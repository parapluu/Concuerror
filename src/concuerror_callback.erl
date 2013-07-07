%% -*- erlang-indent-level: 2 -*-

-module(concuerror_callback).

%% Interface to concuerror_inspect:
-export([instrumented/4]).

%% Interface to scheduler:
-export([spawn_first_process/1, start_first_process/2, stop/1]).

%% Interface for resetting:
-export([process_top_loop/1]).

%%------------------------------------------------------------------------------

%% DEBUGGING SETTINGS

-define(flag(A), (1 bsl A)).

-define(builtin, ?flag(1)).
-define(non_builtin, ?flag(2)).
-define(receive_, ?flag(3)).
-define(receive_messages, ?flag(4)).
-define(stack, ?flag(5)).
-define(args, ?flag(6)).
-define(result, ?flag(7)).
-define(spawn, ?flag(8)).
-define(short_builtin, ?flag(9)).
-define(wait, ?flag(10)).
-define(undelivered, ?flag(11)).
-define(send, ?flag(12)).
-define(exit, ?flag(13)).
-define(crash, ?flag(14)).
-define(trap, ?flag(15)).

-define(ACTIVE_FLAGS, [?crash, ?undelivered]).

%% -define(DEBUG, true).
%% -define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).

%%------------------------------------------------------------------------------

-include("concuerror.hrl").
-include("concuerror_callback.hrl").

-type concuerror_info() :: #concuerror_info{}.

%%------------------------------------------------------------------------------

-spec spawn_first_process(options()) -> pid().

spawn_first_process(Options) ->
  {ets_tables, EtsTables} = proplists:lookup(ets_tables, Options),
  {logger, Logger} = proplists:lookup(logger, Options),
  {'after-timeout', AfterTimeout} = proplists:lookup('after-timeout', Options),
  InitialInfo =
    #concuerror_info{
       'after-timeout' = AfterTimeout,
       ets_tables = EtsTables,
       logger = Logger,
       scheduler = self()
      },
  spawn_link(fun() -> process_top_loop(InitialInfo) end).

-spec start_first_process(pid(), {atom(), atom(), [term()]}) -> ok.

start_first_process(Pid, {Module, Name, Args}) ->
  Pid ! {start, Module, Name, Args},
  ok.

-spec stop(pid()) -> stop.

stop(Pid) ->
  Pid ! stop.

%%------------------------------------------------------------------------------

-spec instrumented(Tag      :: instrumented_tags(),
                   Args     :: [term()],
                   Location :: term(),
                   Info     :: concuerror_info()) ->
                      {Return :: term(), NewInfo :: concuerror_info()}.

instrumented(call, [Module, Name, Args], Location, Info) ->
  Arity = length(Args),
  instrumented_aux(call, Module, Name, Arity, Args, Location, Info);
instrumented(apply, [Fun, Args], Location, Info) ->
  case is_function(Fun) of
    true ->
      Module = get_fun_info(Fun, module),
      Name = get_fun_info(Fun, name),
      Arity = get_fun_info(Fun, arity),
      case length(Args) =:= Arity of
        true -> instrumented_aux(apply, Module, Name, Arity, Args, Location, Info);
        false -> {doit, Info}
      end;
    false ->
      {doit, Info}
  end;
instrumented('receive', [PatternFun, Timeout], Location, Info) ->
  handle_receive(PatternFun, Timeout, Location, Info).

instrumented_aux(Tag, Module, Name, Arity, Args, Location, Info) ->
  try
    case
      erlang:is_builtin(Module, Name, Arity) andalso
      not lists:member({Module, Name, Arity}, ?RACE_FREE_BIFS)
    of
      true  ->
        built_in(Module, Name, Arity, Args, Location, Info);
      false ->
        _Log = {Tag, Module, Name, Arity, Location},
        ?debug_flag(?non_builtin, _Log),
        ?debug_flag(?args, {args, Args}),
        NewInfo = Info,%append_stack(Log, Info),
        ok = concuerror_loader:load_if_needed(Module),
        {doit, NewInfo}
    end
  catch
    throw:{error, Reason} ->
      {{error, Reason}, Info};
    Type:Reason ->
      #concuerror_info{logger = Logger} = Info,
      ?trace(Logger, "XCEPT ~p:~p/~p: ~p(~p)~n", [Module, Name, Arity, Type, Reason]),
      {doit, Info}
  end.

get_fun_info(Fun, Tag) ->
  {Tag, Info} = erlang:fun_info(Fun, Tag),
  Info.

%%------------------------------------------------------------------------------

%% XXX: Check if its redundant (e.g. link to already linked)
built_in(Module, Name, Arity, Args, Location, Info) ->
  ?debug_flag(?short_builtin, {'built-in', Module, Name, Arity, Location}),
  %% {Stack, ResetInfo} = reset_stack(Info),
  %% ?debug_flag(?stack, {stack, Stack}),
  LocatedInfo = locate_next_event(Location, Info),%ResetInfo),
  {Value, #concuerror_info{next_event = Event} = UpdatedInfo} =
    run_built_in(Module, Name, Arity, Args, LocatedInfo),
  ?debug_flag(?builtin, {'built-in', Module, Name, Arity, Value, Location}),
  ?debug_flag(?args, {args, Args}),
  ?debug_flag(?result, {args, Value}),
  EventInfo = #builtin_event{mfa = {Module, Name, Args}, result = Value},
  Notification = Event#event{event_info = EventInfo},
  NewInfo = notify(Notification, UpdatedInfo),
  {{didit, Value}, NewInfo}.

%% Special instruction running control (e.g. send to unknown -> wait for reply)
run_built_in(erlang, link, 1, [Recipient], Info) ->
  #concuerror_info{links = Old, scheduler = Scheduler} = Info,
  case concuerror_scheduler:known_process(Scheduler, Recipient) of
    false -> throw({error, external_process});
    true ->
      Recipient ! {link, self(), confirm},
      receive
        success ->
          NewInfo =
            Info#concuerror_info{links = ordsets:add_element(Recipient, Old)},
          {true, NewInfo};
        failed ->
          throw({error, badarg})
      end
  end;
run_built_in(erlang, spawn, 3, [M, F, Args], Info) ->
  run_built_in(erlang, spawn_opt, 1, [{M, F, Args, []}], Info);
run_built_in(erlang, spawn_link, 3, [M, F, Args], Info) ->
  run_built_in(erlang, spawn_opt, 1, [{M, F, Args, [link]}], Info);
run_built_in(erlang, spawn_opt, 1, [{Module, Name, Args, SpawnOpts}],
             #concuerror_info{next_event = Event} = Info) ->
  #event{event_info = EventInfo} = Event,
  {Result, NewInfo} =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} -> {OldResult, Info};
      %% New event...
      undefined ->
        PassedInfo = init_concuerror_info(Info),
        ?debug_flag(?spawn, {self(), spawning_new, PassedInfo}),
        P = spawn_link(fun() -> process_top_loop(PassedInfo) end),
        NewResult =
          case lists:member(monitor, SpawnOpts) of
            true -> {P, make_ref()};
            false -> P
          end,
        NewEvent = Event#event{special = [{new, P}]},
        {NewResult, Info#concuerror_info{next_event = NewEvent}}
    end,
  case lists:member(monitor, SpawnOpts) of
    true ->
      {Pid, Ref} = Result,
      Pid ! {start, Module, Name, Args},
      Pid ! {monitor, {Ref, self()}, no_confirm};
    false ->
      Pid = Result,
      Pid ! {start, Module, Name, Args}
  end,
  case lists:member(link, SpawnOpts) of
    true ->
      Pid ! {link, self(), no_confirm},
      self() ! {link, Pid, no_confirm};
    false ->
      ok
  end,
  {Result, NewInfo};
run_built_in(erlang, Send, 2, [Recipient, Message], Info)
  when Send =:= '!'; Send =:= 'send' ->
  run_built_in(erlang, send, 3, [Recipient, Message, []], Info);
run_built_in(erlang, send, 3, [Recipient, Message, _Options],
             #concuerror_info{
                next_event = #event{event_info = EventInfo} = Event
               } = Info) ->
  case EventInfo of
    %% Replaying...
    #builtin_event{result = OldResult} -> {OldResult, Info};
    %% New event...
    undefined ->
      ?debug_flag(?send, {send, Recipient, Message}),
      Pid =
        case Recipient of
          P when is_pid(P) -> P;
          A when is_atom(A) -> whereis(A);
          _ -> undefined
        end,
      %% XXX: Make sure that the pid is local or abort.
      case is_pid(Pid) of
        true ->
          MessageEvent =
            #message_event{
               cause_label = Event#event.label,
               message = #message{data = Message, message_id = make_ref()},
               recipient = Pid},
          NewEvent = Event#event{special = [{messages, [MessageEvent]}]},
          ?debug_flag(?send, {send, successful}),
          {Message, Info#concuerror_info{next_event = NewEvent}};
        false -> error(non_local_process)
      end
  end;
run_built_in(erlang, process_flag, 2, [trap_exit, Value],
             #concuerror_info{trap_exit = OldValue} = Info) ->
  ?debug_flag(?trap, {trap_exit_set, Value}),
  {OldValue, Info#concuerror_info{trap_exit = Value}};
run_built_in(ets, new, 2, [Name, Options], Info) ->
  #concuerror_info{
     ets_tables = EtsTables,
     next_event = #event{event_info = EventInfo},
     scheduler = Scheduler
    } = Info,
  Tid =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} -> OldResult;
      %% New event...
      undefined ->
        case concuerror_scheduler:ets_new(Scheduler, Name, Options) of
          {error, Reason} -> throw({error, Reason});
          {ok, Reply} -> Reply
        end
    end,
  Heir =
    case proplists:lookup(heir, Options) of
      none -> {heir, none};
      Other -> Other
    end,
  Update = [{?ets_heir, Heir}, {?ets_owner, self()}],
  ets:update_element(EtsTables, Tid, Update),
  ets:delete_all_objects(Tid),
  {Tid, Info};
run_built_in(ets, insert, 2, [Tid, _] = Args, Info) ->
  #concuerror_info{ets_tables = EtsTables} = Info,
  Owner = ets:lookup_element(EtsTables, Tid, ?ets_owner),
  case
    is_pid(Owner) andalso
    (Owner =:= self()
     orelse ets:lookup_element(EtsTables, Tid, ?ets_protection) =:= public)
  of
    true -> ok;
    false -> throw({error, badarg})
  end,
  {erlang:apply(ets, insert, Args), Info};
run_built_in(ets, lookup, 2, [Tid, _] = Args, Info) ->
  #concuerror_info{ets_tables = EtsTables} = Info,
  Owner = ets:lookup_element(EtsTables, Tid, ?ets_owner),
  case
    is_pid(Owner) andalso
    (Owner =:= self()
     orelse ets:lookup_element(EtsTables, Tid, ?ets_protection) =/= private)
  of
    true -> ok;
    false -> throw({error, badarg})
  end,
  {erlang:apply(ets, insert, Args), Info};
run_built_in(ets, delete, 1, [Tid], Info) ->
  #concuerror_info{ets_tables = EtsTables} = Info,
  Owner = ets:lookup_element(EtsTables, Tid, ?ets_owner),
  case
    Owner =:= self()
  of
    true -> ok;
    false -> throw({error, badarg})
  end,
  Update = [{?ets_owner, none}],
  ets:update_element(EtsTables, Tid, Update),
  ets:delete_all_objects(Tid),
  {true, Info};
run_built_in(Module, Name, Arity, Args, Info)
  when
    {Module, Name, Arity} =:= {erlang, exit, 1};
    {Module, Name, Arity} =:= {erlang, register, 2};
    {Module, Name, Arity} =:= {erlang, throw, 1};
    {Module, Name, Arity} =:= {erlang, unregister, 1};
    false
    ->
  {erlang:apply(Module, Name, Args), Info};
run_built_in(Module, Name, _Arity, Args, Info) ->
   #concuerror_info{logger = Logger} = Info,
  ?debug(Logger, "default built-in: ~p:~p/~p~n", [Module, Name, _Arity]),
  {erlang:apply(Module, Name, Args), Info}.

%%------------------------------------------------------------------------------

handle_receive(PatternFun, Timeout, Location, Info) ->
  %% No distinction between replaying/new as we have to clear the message from
  %% the queue anyway...
  {Match, ReceiveInfo} = has_matching_or_after(PatternFun, Timeout, Info),
  case Match of
    {true, MessageOrAfter} ->
      #concuerror_info{
         next_event = NextEvent,
         trap_exit = Trapping
        } = UpdatedInfo =
        locate_next_event(Location, ReceiveInfo),
      ReceiveEvent =
        #receive_event{
           message = MessageOrAfter,
           patterns = PatternFun,
           timeout = Timeout,
           trapping = Trapping},
      {Special, CreateMessage} =
        case MessageOrAfter of
          #message{data = Data, message_id = Id} ->
            {[{message_received, Id, PatternFun}], {ok, Data}};
          'after' -> {[], false}
        end,
      Notification =
        NextEvent#event{event_info = ReceiveEvent, special = Special},
      NewInfo = notify(Notification, UpdatedInfo),
      case CreateMessage of
        {ok, D} ->
          ?debug_flag(?receive_, {deliver, D}),
          self() ! D;
        false -> ok
      end,
      {doit, NewInfo};
    false ->
      NewInfo = notify({blocked, Location}, ReceiveInfo),
      handle_receive(PatternFun, Timeout, Location, NewInfo)
  end.

has_matching_or_after(PatternFun, Timeout,
                      #concuerror_info{messages_new = NewMessages,
                                       messages_old = OldMessages} = Info) ->
  ?debug_flag(?receive_, {matching_or_after, [NewMessages, OldMessages]}),
  {Result, NewOldMessages} =
    fold_with_patterns(PatternFun, NewMessages, OldMessages),
  case Result =:= false of
    false ->
      {Result,
       Info#concuerror_info{
         messages_new = NewOldMessages,
         messages_old = queue:new()
        }
      };
    true ->
      case Timeout =/= infinity of
        true ->
          {{true, 'after'},
           Info#concuerror_info{
             messages_new = NewOldMessages,
             messages_old = queue:new()
            }
          };
        false ->
          {false,
           Info#concuerror_info{
             messages_new = queue:new(),
             messages_old = NewOldMessages}
          }
      end
  end.

fold_with_patterns(PatternFun, NewMessages, OldMessages) ->
  {Value, NewNewMessages} = queue:out(NewMessages),
  ?debug_flag(?receive_, {inspect, Value}),
  case Value of
    {value, #message{data = Data} = Message} ->
      case PatternFun(Data) of
        true  -> {{true, Message}, queue:join(OldMessages, NewNewMessages)};
        false ->
          NewOldMessages = queue:in(Message, OldMessages),
          fold_with_patterns(PatternFun, NewNewMessages, NewOldMessages)
      end;
    empty ->
      {false, OldMessages}
  end.

%%------------------------------------------------------------------------------

notify(Notification, #concuerror_info{scheduler = Scheduler} = Info) ->
  Scheduler ! Notification,
  process_loop(Info).

process_top_loop(Info) ->
  ?debug_flag(?wait, {top_waiting, self()}),
  receive
    {start, Module, Name, Args} ->
      ?debug_flag(?wait, {start, Module, Name, Args}),
      Running = Info#concuerror_info{status = running},
      %% Wait for 1st event (= 'run') signal, accepting messages,
      %% links and monitors in the meantime.
      StartInfo = process_loop(Running),
      %% It is ok for this load to fail
      concuerror_loader:load_if_needed(Module),
      put(concuerror_info, StartInfo),
      try
        erlang:apply(Module, Name, Args),
        exit(normal)
      catch
        Class:Reason ->
          #concuerror_info{escaped = Escaped} = EndInfo = get(concuerror_info),
          case Escaped =:= nonexisting of
            true  -> erase(concuerror_info);
            false -> put(concuerror_info, Escaped)
          end,
          Stacktrace = lists:keydelete(?MODULE, 1, erlang:get_stacktrace()),
          ?debug_flag(?crash, {crash, Class, Reason, Stacktrace}),
          NewReason =
            case Class of
              throw -> {{nocatch, Reason}, Stacktrace};
              error -> {Reason, Stacktrace};
              exit  -> Reason
            end,
          exiting(NewReason, Stacktrace, EndInfo)
      end;
    stop ->
      ?debug_flag(?wait, {waiting, stop}),
      ok
  end.

process_loop(Info) ->
  ?debug_flag(?wait, {waiting, self()}),
  receive
    #event{event_info = EventInfo} = Event ->
      case Info#concuerror_info.status =:= dead of
        true ->
          notify(unavailable, Info);
        false ->
          NewInfo = Info#concuerror_info{next_event = Event},
          case EventInfo of
            undefined ->
              ?debug_flag(?wait, {waiting, exploring}),
              NewInfo;
            _OtherReplay ->
              ?debug_flag(?wait, {waiting, replaying}),
              NewInfo
          end
      end;
    {exit_signal, #message{data = {'EXIT', _From, Reason}} = Message} ->
      Scheduler = Info#concuerror_info.scheduler,
      Trapping = Info#concuerror_info.trap_exit,
      case Info#concuerror_info.status =:= running of
        true ->
          %% XXX: Verify that this is the correct behaviour
          %% NewInfo =
          %%   Info#concuerror_info{
          %%     links = ordsets:del_element(From, Info#concuerror_info.links)
          %%    },
          case Reason =:= kill of
            true ->
              ?debug_flag(?wait, {waiting, kill_signal}),
              Scheduler ! {trapping, Trapping},
              exiting(killed, [], Info);
            false ->
              case Trapping of
                true ->
                  ?debug_flag(?trap, {waiting, signal_trapped}),
                  self() ! {message, Message},
                  process_loop(Info);
                false ->
                  Scheduler ! {trapping, Trapping},
                  case Reason =:= normal of
                    true ->
                      ?debug_flag(?wait, {waiting, normal_signal_ignored}),
                      process_loop(Info);
                    false ->
                      ?debug_flag(?wait, {waiting, exiting_signal}),
                      exiting(Reason, [], Info)
                  end
              end
          end;
        false ->
          Scheduler ! {trapping, Trapping},
          process_loop(Info)
      end;
    {link, Pid, Confirm} ->
      ?debug_flag(?wait, {waiting, got_link}),
      NewInfo =
        case Info#concuerror_info.status =:= running of
          true ->
            case Confirm =:= confirm of
              true -> Pid ! success;
              false -> ok
            end,
            Old = Info#concuerror_info.links,
            Info#concuerror_info{links = ordsets:add_element(Pid, Old)};
          false ->
            Pid ! failed,
            Info
        end,
      process_loop(NewInfo);
    {message, Message} ->
      ?debug_flag(?wait, {waiting, got_message}),
      Scheduler = Info#concuerror_info.scheduler,
      Trapping = Info#concuerror_info.trap_exit,
      case Info#concuerror_info.status =:= running of
        true ->
          ?debug_flag(?receive_, {message_enqueued, Message}),
          Old = Info#concuerror_info.messages_new,
          NewInfo =
            Info#concuerror_info{
              messages_new = queue:in(Message, Old)
             },
          Scheduler ! {trapping, Trapping},
          process_loop(NewInfo);
        false ->
          Scheduler ! {trapping, Trapping},
          process_loop(Info)
      end;
    {monitor, {_Ref, Pid} = Monitor, Confirm} ->
      ?debug_flag(?wait, {waiting, got_monitor}),
      NewInfo =
        case Info#concuerror_info.status =:= running of
          true ->
            case Confirm =:= confirm of
              true -> Pid ! success;
              false -> ok
            end,
            Old = Info#concuerror_info.monitors,
            Info#concuerror_info{monitors = ordsets:add_element(Monitor, Old)};
          false ->
            Pid ! failed,
            Info
        end,
      process_loop(NewInfo);
    reset ->
      ?debug_flag(?wait, {waiting, reset}),
      NewInfo = init_concuerror_info(Info),
      case erlang:process_info(self(), registered_name) of
        [] -> ok;
        {registered_name, Name} -> unregister(Name)
      end,
      erase(),
      erlang:hibernate(concuerror_callback, process_top_loop, [NewInfo]);
    deadlock_poll ->
      Info
    %% {system, #event{actor = {_, Recipient}, event_info = EventInfo} = Event} ->
    %%   #message_event{message = Message, type = Type} = EventInfo,
    %%   #message{data = Data} = Message,
    %%   Recipient ! Data,
    %%   receive
    %%     ReplyData ->
    %%       ReplyMessage = #message{data = ReplyData, message_id = make_ref()},
    %%         MessageEvent =
    %%           #message_event{
    %%              cause_label = Label,
    %%              message = Message,
    %%              recipient = P},
    %%         add_message(MessageEvent, Acc)
  end.

%%------------------------------------------------------------------------------

exiting(Reason, Stacktrace, Info) ->
  %% XXX: The ordering of the following events has to be determined:
  %% XXX:  - new messages are not delivered
  %% XXX:  - send link signals
  %% XXX:  - send monitor messages
  %% XXX:  - transfer ets ownership and send message
  %% XXX:  - unregister name
  ?debug_flag(?exit, {going_to_exit, Reason, Info#concuerror_info.next_event}),
  case erlang:process_info(self(), registered_name) of
    [] -> ok;
    {registered_name, Name} -> unregister(Name)
  end,
  LocatedInfo = locate_next_event(exit, Info#concuerror_info{status = exiting}),
  ExitInfo = #concuerror_info{next_event = Event} =
    add_exiting_events(Reason, LocatedInfo),
  Notification =
    Event#event{
      event_info =
        #exit_event{
           reason = Reason,
           stacktrace = Stacktrace
          }
     },
  notify(Notification, ExitInfo),
  ?debug_flag(?exit, complete_exit).

add_exiting_events(Reason,
                   #concuerror_info{
                      next_event = #event{event_info = EventInfo} = Event
                     } = Info) ->
  case EventInfo =/= undefined of
    %% Replaying...
    true -> Info;
    false ->
      MessagesInfo =
        Info#concuerror_info{
          next_event = Event#event{special = [{messages, []}]}
         },
      LinksInfo = add_links_events(Reason, MessagesInfo),
      MonitorInfo =
        #concuerror_info{
           next_event = #event{special = InitSpecial}
          } = add_monitor_events(Reason, LinksInfo),
      FinalSpecial = [{exit, self()}|InitSpecial],
      MonitorInfo#concuerror_info{
        next_event = Event#event{special = FinalSpecial},
        status = dead
       }
  end.

add_links_events(Reason, #concuerror_info{links = Links} = Info) ->
  case Links =:= [] of
    true -> Info;
    false ->
      #concuerror_info{next_event = #event{label = Label, actor = Pid}} = Info,
      Message = #message{data = {'EXIT', Pid, Reason}, message_id = make_ref()},
      Signal =
        #message_event{
           cause_label = Label,
           message = Message,
           type = exit_signal},
      Fold =
        fun(P, Acc) ->
            ?debug_flag(?exit, {link_event, P}),
            add_message(Signal#message_event{recipient = P}, Acc)
        end,
      lists:foldl(Fold, Info, Links)
  end.

add_monitor_events(Reason, #concuerror_info{monitors = Monitors} = Info) ->
  case Monitors =:= [] of
    true -> Info;
    false ->
      #concuerror_info{next_event = #event{label = Label, actor = Pid}} = Info,
      Fold =
        fun({Ref, P}, Acc) ->
            ?debug_flag(?exit, {monitor_event, Ref, P}),
            Message =
              #message{
                 data = {'DOWN', Ref, process, Pid, Reason},
                 message_id = make_ref()
                },
            MessageEvent =
              #message_event{
                 cause_label = Label,
                 message = Message,
                 recipient = P},
            add_message(MessageEvent, Acc)
        end,
      lists:foldl(Fold, Info, Monitors)
  end.

add_message(Message, #concuerror_info{
                      next_event =
                          #event{special = [{messages, Messages}]} = Event
                       } = Info) ->
  Info#concuerror_info{
    next_event = Event#event{special = [{messages, [Message|Messages]}]}
   }.

%%------------------------------------------------------------------------------

init_concuerror_info(Info) ->
  #concuerror_info{
     'after-timeout' = AfterTimeout,
     ets_tables = EtsTables,
     logger = Logger,
     scheduler = Scheduler
    } = Info,
  #concuerror_info{
     'after-timeout' = AfterTimeout,
     ets_tables = EtsTables,
     logger = Logger,
     scheduler = Scheduler
    }.

%% reset_stack(#concuerror_info{stack = Stack} = Info) ->
%%   {Stack, Info#concuerror_info{stack = []}}.

%% append_stack(Value, #concuerror_info{stack = Stack} = Info) ->
%%   Info#concuerror_info{stack = [Value|Stack]}.

%%------------------------------------------------------------------------------

locate_next_event(Location, #concuerror_info{next_event = Event} = Info) ->
  Info#concuerror_info{next_event = Event#event{location = Location}}.
