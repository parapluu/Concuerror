%% -*- erlang-indent-level: 2 -*-

-module(concuerror_callback).

%% Interface to concuerror_inspect:
-export([instrumented/4]).

%% Interface to scheduler:
-export([spawn_first_process/1, start_first_process/2]).

%% Interface for resetting:
-export([process_top_loop/2]).

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
-define(send, ?flag(11)).
-define(exit, ?flag(12)).
-define(trap, ?flag(13)).
-define(undefined, ?flag(14)).
-define(heir, ?flag(15)).

-define(ACTIVE_FLAGS, [?undefined]).

%% -define(DEBUG, true).
-define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).

%%------------------------------------------------------------------------------

-include("concuerror.hrl").
-include("concuerror_callback.hrl").

-type concuerror_info() :: #concuerror_info{}.

%%------------------------------------------------------------------------------

-spec spawn_first_process(options()) -> pid().

spawn_first_process(Options) ->
  [AfterTimeout, Logger, Processes] =
    get_properties(['after-timeout', logger, processes], Options),
  [Monitors, Links] =
    [ets:new(Name, [bag, public]) || Name <- [monitors, links]],
  EtsTables = ets:new(ets_tables, [public]),
  system_ets_entries(EtsTables),
  InitialInfo =
    #concuerror_info{
       'after-timeout' = AfterTimeout,
       ets_tables = EtsTables,
       links = Links,
       logger = Logger,
       monitors = Monitors,
       processes = Processes,
       scheduler = self()
      },
  spawn_link(fun() -> process_top_loop(InitialInfo, "P") end).

get_properties(Props, PropList) ->
  get_properties(Props, PropList, []).

get_properties([], _, Acc) -> lists:reverse(Acc);
get_properties([Prop|Props], PropList, Acc) ->
  PropVal = proplists:get_value(Prop, PropList),
  get_properties(Props, PropList, [PropVal|Acc]).

-spec start_first_process(pid(), {atom(), atom(), [term()]}) -> ok.

start_first_process(Pid, {Module, Name, Args}) ->
  Pid ! {start, Module, Name, Args},
  ok.

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
  #concuerror_info{'after-timeout' = AfterTimeout} = Info,
  RealTimeout =
    case Timeout =:= infinity orelse Timeout > AfterTimeout of
      false -> Timeout;
      true -> infinity
    end,
  handle_receive(PatternFun, RealTimeout, Location, Info).

instrumented_aux(Tag, Module, Name, Arity, Args, Location, Info) ->
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
  end.

get_fun_info(Fun, Tag) ->
  {Tag, Info} = erlang:fun_info(Fun, Tag),
  Info.

%%------------------------------------------------------------------------------

%% Process dictionary has been restored here. No need to report such ops.
built_in(erlang, get, _Arity, Args, _Location, Info) ->
  {{didit, erlang:apply(erlang,get,Args)}, Info};
%% XXX: Check if its redundant (e.g. link to already linked)
built_in(Module, Name, Arity, Args, Location, Info) ->
  ?debug_flag(?short_builtin, {'built-in', Module, Name, Arity, Location}),
  %% {Stack, ResetInfo} = reset_stack(Info),
  %% ?debug_flag(?stack, {stack, Stack}),
  LocatedInfo = add_location_info(Location, Info),%ResetInfo),
  try
    %% XXX: TODO If replaying, inspect if original crashed and replay crash
    {Value, #concuerror_info{next_event = Event} = UpdatedInfo} =
      run_built_in(Module, Name, Arity, Args, LocatedInfo),
    ?debug_flag(?builtin, {'built-in', Module, Name, Arity, Value, Location}),
    ?debug_flag(?args, {args, Args}),
    ?debug_flag(?result, {args, Value}),
    EventInfo = #builtin_event{mfa = {Module, Name, Args}, result = Value},
    Notification = Event#event{event_info = EventInfo},
    NewInfo = notify(Notification, UpdatedInfo),
    {{didit, Value}, NewInfo}
  catch
    throw:Reason ->
      #concuerror_info{scheduler = Scheduler} = Info,
      exit(Scheduler, {Reason, Module, Name, Arity, Args, Location}),
      receive after infinity -> ok end;
    error:Reason ->
      #concuerror_info{next_event = FEvent} = LocatedInfo,
      FEventInfo = #builtin_event{mfa = {Module, Name, Args}, status = crashed},
      FNotification = FEvent#event{event_info = FEventInfo},
      FNewInfo = notify(FNotification, LocatedInfo),
      FinalInfo =
        FNewInfo#concuerror_info{stacktop = {Module, Name, Args, Location}},
      {{error, Reason}, FinalInfo}
  end.

%% Special instruction running control (e.g. send to unknown -> wait for reply)
run_built_in(erlang, exit, 2, [Pid, Reason],
             #concuerror_info{
                next_event = #event{event_info = EventInfo} = Event
               } = Info) ->
  case EventInfo of
    %% Replaying...
    #builtin_event{result = OldResult} -> {OldResult, Info};
    %% New event...
    undefined ->
      Message =
        #message{data = {'EXIT', self(), Reason}, message_id = make_ref()},
      MessageEvent =
        #message_event{
           cause_label = Event#event.label,
           message = Message,
           recipient = Pid,
           type = exit_signal},
      NewEvent = Event#event{special = {message, MessageEvent}},
      {true, Info#concuerror_info{next_event = NewEvent}}
  end;

run_built_in(erlang, link, 1, [Pid], Info) ->
  #concuerror_info{links = Links, processes = Processes} = Info,
  case ets:lookup(Processes, Pid) of
    [] ->
      ?debug_flag(?undefined, {link_to_external, Pid}),
      error(badarg);
    [?process_pat_pid_status(Pid, Status)] ->
      case is_active(Status) of
        true ->
          Self = self(),
          true = ets:insert(Links, [{Self, Pid}, {Pid, Self}]),
          {true, Info};
        false ->
          error(badarg)
      end
  end;
run_built_in(erlang, monitor, 2, [Type, Pid], Info) ->
  #concuerror_info{
     monitors = Monitors,
     next_event = #event{event_info = EventInfo} = Event,
     processes = Processes} = Info,
  case Type =:= process andalso is_pid(Pid) of
    true -> ok;
    false -> error(badarg)
  end,
  Ref =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} -> OldResult;
      %% New event...
      undefined -> make_ref()
    end,
  NewInfo =
    case ets:lookup(Processes, Pid) of
      [] -> throw(monitoring_non_concuerror_process);
      [?process_pat_pid_status(Pid, Status)] ->
        IsActive = is_active(Status),
        case IsActive of
          true -> true = ets:insert(Monitors, {Pid, {Ref, self()}});
          false -> ok
        end,
        case EventInfo of
          %% Replaying...
          #builtin_event{} -> Info;
          %% New event...
          undefined ->
            case IsActive of
              false ->
                Message =
                  #message{data = {'DOWN', Ref, process, Pid, noproc},
                           message_id = make_ref()},
                MessageEvent =
                  #message_event{
                  cause_label = Event#event.label,
                  message = Message,
                  recipient = self()},
                NewEvent = Event#event{special = {message, MessageEvent}},
                Info#concuerror_info{next_event = NewEvent};
              true -> Info
            end
        end
    end,
  {Ref, NewInfo};
run_built_in(erlang, process_info, 2, [Pid, Item], Info) when is_atom(Item) ->
  TheirInfo =
    case Pid =:= self() of
      true -> Info;
      false ->
        case process_info(Pid, dictionary) of
          [] -> throw(inspecting_the_process_dictionary_of_a_system_process);
          {dictionary, [{concuerror_info, Dict}]} -> Dict
        end
    end,
  Res =
    case Item of
      dictionary ->
        #concuerror_info{escaped_pdict = Escaped} = TheirInfo,
        Escaped;
      links ->
        #concuerror_info{links = Links} = TheirInfo,
        try ets:lookup_element(Links, Pid, 2)
        catch error:badarg -> []
        end;
      messages ->
        #concuerror_info{messages_new = Queue} = TheirInfo,
        [M || #message{data = M} <- queue:to_list(Queue)];
      registered_name ->
        #concuerror_info{processes = Processes} = TheirInfo,
        [?process_pat_pid_name(Pid, Name)] = ets:lookup(Processes, Pid),
        case Name =:= ?process_name_none of
          true -> [];
          false -> {Item, Name}
        end;
      status ->
        #concuerror_info{status = Status} = TheirInfo,
        Status;
      trap_exit ->
        #concuerror_info{trap_exit = TrapExit} = TheirInfo,
        TrapExit;
      ExpectsANumber when
          ExpectsANumber =:= heap_size;
          ExpectsANumber =:= reductions;
          ExpectsANumber =:= stack_size;
          false ->
        42;
      _ ->
        throw({process_info_sucks, Item})
    end,
  {Res, Info};
run_built_in(erlang, register, 2, [Name, Pid],
             #concuerror_info{processes = Processes} = Info) ->
  try
    true = is_atom(Name),
    true = is_pid(Pid) orelse is_port(Pid),
    [] = ets:match(Processes, ?process_match_name_to_pid(Name)),
    ?process_name_none = ets:lookup_element(Processes, Pid, ?process_name),
    false = undefined =:= Name,
    true = ets:update_element(Processes, Pid, {?process_name, Name}),
    {true, Info}
  catch
    _:_ -> error(badarg)
  end;
run_built_in(erlang, spawn, 3, [M, F, Args], Info) ->
  run_built_in(erlang, spawn_opt, 1, [{M, F, Args, []}], Info);
run_built_in(erlang, spawn_link, 3, [M, F, Args], Info) ->
  run_built_in(erlang, spawn_opt, 1, [{M, F, Args, [link]}], Info);
run_built_in(erlang, spawn_opt, 1, [{Module, Name, Args, SpawnOpts}], Info) ->
  #concuerror_info{next_event = Event, processes = Processes} = Info,
  #event{event_info = EventInfo} = Event,
  Parent = self(),
  {Result, NewInfo} =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} -> {OldResult, Info};
      %% New event...
      undefined ->
        PassedInfo = init_concuerror_info(Info),
        ?debug_flag(?spawn, {Parent, spawning_new, PassedInfo}),
        ParentSymbol = ets:lookup_element(Processes, Parent, ?process_symbolic),
        ChildId = ets:update_counter(Processes, Parent, {?process_children, 1}),
        ChildSymbol = io_lib:format("~s.~w",[ParentSymbol, ChildId]),
        P = spawn_link(fun() -> process_top_loop(PassedInfo, ChildSymbol) end),
        NewResult =
          case lists:member(monitor, SpawnOpts) of
            true -> {P, make_ref()};
            false -> P
          end,
        NewEvent = Event#event{special = {new, P}},
        {NewResult, Info#concuerror_info{next_event = NewEvent}}
    end,
  case lists:member(monitor, SpawnOpts) of
    true ->
      {Pid, Ref} = Result,
      #concuerror_info{monitors = Monitors} = Info,
      true = ets:insert(Monitors, {Pid, {Ref, Parent}});
    false ->
      Pid = Result
  end,
  case lists:member(link, SpawnOpts) of
    true ->
      #concuerror_info{monitors = Links} = Info,
      true = ets:insert(Links, [{Parent, Pid}, {Pid, Parent}]);
    false -> ok
  end,
  Pid ! {start, Module, Name, Args},
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
        case is_pid(Recipient) of
          true -> Recipient;
          false ->
            {P, Info} = run_built_in(erlang, whereis, 1, [Recipient], Info),
            P
        end,
      case is_pid(Pid) of
        true ->
          MessageEvent =
            #message_event{
               cause_label = Event#event.label,
               message = #message{data = Message, message_id = make_ref()},
               recipient = Pid},
          NewEvent = Event#event{special = {message, MessageEvent}},
          ?debug_flag(?send, {send, successful}),
          {Message, Info#concuerror_info{next_event = NewEvent}};
        false -> error(badarg)
      end
  end;
run_built_in(erlang, process_flag, 2, [trap_exit, Value],
             #concuerror_info{trap_exit = OldValue} = Info) ->
  ?debug_flag(?trap, {trap_exit_set, Value}),
  {OldValue, Info#concuerror_info{trap_exit = Value}};
run_built_in(erlang, unregister, 1, [Name],
             #concuerror_info{processes = Processes} = Info) ->
  try
    [[Pid]] = ets:match(Processes, ?process_match_name_to_pid(Name)),
    true =
      ets:update_element(Processes, Pid, {?process_name, ?process_name_none}),
    {true, Info}
  catch
    _:_ -> error(badarg)
  end;
run_built_in(erlang, whereis, 1, [Name],
             #concuerror_info{processes = Processes} = Info) ->
  case ets:match(Processes, ?process_match_name_to_pid(Name)) of
    [] ->
      case whereis(Name) =:= undefined of
        true -> {undefined, Info};
        false -> throw({system_process_not_wrapped, Name})
      end;
    [[Pid]] -> {Pid, Info}
  end;
run_built_in(ets, new, 2, [Name, Options], Info) ->
  #concuerror_info{
     ets_tables = EtsTables,
     next_event = #event{event_info = EventInfo},
     scheduler = Scheduler
    } = Info,
  %% XXX: Allow dead named tables
  Tid =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} -> OldResult;
      %% New event...
      undefined ->
        %% Looks like the last option is the one actually used.
        ProtectFold =
          fun(Option, Selected) ->
              case Option of
                O when O =:= 'private';
                       O =:= 'protected';
                       O =:= 'public' -> O;
                _ -> Selected
              end
          end,
        Protection = lists:foldl(ProtectFold, protected, Options),
        T = ets:new(Name, Options ++ [public]),
        true = ets:insert(EtsTables, ?new_ets_table(T, Protection)),
        true = ets:give_away(T, Scheduler, given_to_scheduler),
        T
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
  ok = check_ets_access_rights(Tid, self(), insert, EtsTables),
  {erlang:apply(ets, insert, Args), Info};
run_built_in(ets, lookup, 2, [Tid, _] = Args, Info) ->
  #concuerror_info{ets_tables = EtsTables} = Info,
  ok = check_ets_access_rights(Tid, self(), lookup, EtsTables),
  {erlang:apply(ets, lookup, Args), Info};
run_built_in(ets, delete, 1, [Tid], Info) ->
  #concuerror_info{ets_tables = EtsTables} = Info,
  ok = check_ets_access_rights(Tid, self(), delete, EtsTables),
  Update = [{?ets_owner, none}],
  ets:update_element(EtsTables, Tid, Update),
  ets:delete_all_objects(Tid),
  {true, Info};
run_built_in(ets, give_away, 3, [Tid, Pid, GiftData],
             #concuerror_info{
                next_event = #event{event_info = EventInfo} = Event,
                processes = Processes
               } = Info) ->
  #concuerror_info{ets_tables = EtsTables} = Info,
  Owner = ets:lookup_element(EtsTables, Tid, ?ets_owner),
  Self = self(),
  case
    is_pid(Pid) andalso Owner =:= Self andalso Pid =/= Self
  of
    true -> ok;
    false -> error(badarg)
  end,
  case ets:lookup(Processes, Pid) of
    [?process_pat_pid_status(Pid, Status)]
      when Status =/= exiting andalso Status =/= exited -> ok;
    _ -> error(badarg)
  end,
  NewInfo =
    case EventInfo of
      %% Replaying. Keep original Message reference.
      #builtin_event{} -> Info;
      %% New event...
      undefined ->
        MessageEvent =
          #message_event{
             cause_label = Event#event.label,
             message =
               #message{
                  data = {'ETS-TRANSFER', Tid, Self, GiftData},
                  message_id = make_ref()},
             recipient = Pid},
        NewEvent = Event#event{special = {message, MessageEvent}},
        Info#concuerror_info{next_event = NewEvent}
    end,
  Update = [{?ets_owner, Pid}],
  true = ets:update_element(EtsTables, Tid, Update),
  {true, NewInfo};

%% For other built-ins check whether replaying has the same result:
run_built_in(Module, Name, Arity, Args, Info) ->
  #concuerror_info{next_event =
                     #event{event_info = EventInfo,
                            location = Location}
                  } = Info,
  NewResult = erlang:apply(Module, Name, Args),
  case EventInfo of
    %% Replaying...
    #builtin_event{mfa = {M,F,OArgs}, result = OldResult} ->
      case OldResult =:= NewResult of
        true  -> {OldResult, Info};
        false ->
          #concuerror_info{logger = Logger} = Info,
          case M =:= Module andalso F =:= Name andalso Args =:= OArgs of
            true ->
              ?log(Logger, ?lerror,
                   "~nWhile re-running the program, a call to ~p:~p/~p with"
                   " arguments:~n  ~p~nreturned a different result:~n"
                   "Earlier result: ~p~n"
                   "  Later result: ~p~n"
                   "Concuerror cannot explore behaviours that depend on~n"
                   "data that may differ on separate runs of the program.~n"
                   "Location: ~p~n~n",
                   [Module, Name, Arity, Args, OldResult, NewResult, Location]),
              throw(inconsistent_builtin_behaviour);
            false ->
              ?log(Logger, ?lerror,
                   "~nWhile re-running the program, a call to ~p:~p/~p with"
                   " arguments:~n  ~p~nwas found instead of the original call~n"
                   "to ~p:~p/~p with args:~n  ~p~n"
                   "Concuerror cannot explore behaviours that depend on~n"
                   "data that may differ on separate runs of the program.~n"
                   "Location: ~p~n~n",
                   [Module, Name, Arity, Args, M, F,
                    length(OArgs), OArgs, Location]),
              throw(inconsistent_builtin_behaviour)
          end
      end;
    undefined ->
      {NewResult, Info}
  end.

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
        add_location_info(Location, ReceiveInfo),
      ReceiveEvent =
        #receive_event{
        message = MessageOrAfter,
        patterns = PatternFun,
        timeout = Timeout,
        trapping = Trapping},
      {Special, CreateMessage} =
        case MessageOrAfter of
          #message{data = Data, message_id = Id} ->
            {{message_received, Id, PatternFun}, {ok, Data}};
          'after' -> {none, false}
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
      {skip_timeout, set_status(NewInfo, running)};
    false ->
      WaitingInfo = set_status(ReceiveInfo, waiting),
      NewInfo = notify({blocked, Location}, WaitingInfo),
      handle_receive(PatternFun, Timeout, Location, NewInfo)
  end.

has_matching_or_after(PatternFun, Timeout, Info) ->
  #concuerror_info{messages_new = NewMessages,
                   messages_old = OldMessages} = Info,
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
      case Timeout =:= infinity of
        false ->
          {{true, 'after'},
           Info#concuerror_info{
             messages_new = NewOldMessages,
             messages_old = queue:new()
            }
          };
        true ->
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
        true  ->
          ?debug_flag(?receive_, matches),
          {{true, Message}, queue:join(OldMessages, NewNewMessages)};
        false ->
          ?debug_flag(?receive_, doesnt_match),
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

process_top_loop(Info, Symbolic) ->
  #concuerror_info{
     links = Links,
     monitors = Monitors,
     processes = Processes} = Info,
  true = ets:insert(Processes, ?new_process(self(), Symbolic)),
  true = ets:delete(Links, self()),
  true = ets:delete(Monitors, self()),
  ?debug_flag(?wait, top_waiting),
  receive
    {start, Module, Name, Args} ->
      ?debug_flag(?wait, {start, Module, Name, Args}),
      Running = set_status(Info, running),
      %% Wait for 1st event (= 'run') signal, accepting messages
      StartInfo = process_loop(Running),
      %% It is ok for this load to fail
      concuerror_loader:load_if_needed(Module),
      put(concuerror_info, StartInfo),
      try
        erlang:apply(Module, Name, Args),
        exit(normal)
      catch
        Class:Reason ->
          case get(concuerror_info) of
            #concuerror_info{escaped_pdict = Escaped} = EndInfo ->
              erase(),
              [put(K,V) || {K,V} <- Escaped],
              Stacktrace = fix_stacktrace(EndInfo),
              ?debug_flag(?exit, {exit, Class, Reason, Stacktrace}),
              NewReason =
                case Class of
                  throw -> {{nocatch, Reason}, Stacktrace};
                  error -> {Reason, Stacktrace};
                  exit  -> Reason
                end,
              exiting(NewReason, Stacktrace, EndInfo);
            _ -> exit({process_crashed, Class, Reason})
          end
      end
  end.

process_loop(Info) ->
  ?debug_flag(?wait, waiting),
  receive
    #event{event_info = EventInfo} = Event ->
      Status = Info#concuerror_info.status,
      case Status =:= exited of
        true ->
          notify(exited, Info);
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
      case is_active(Info) of
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
              NewInfo = process_loop(Info),
              exiting(killed, [], NewInfo);
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
                      NewInfo = process_loop(Info),
                      exiting(Reason, [], NewInfo)
                  end
              end
          end;
        false ->
          Scheduler ! {trapping, Trapping},
          process_loop(Info)
      end;
    {message, Message} ->
      ?debug_flag(?wait, {waiting, got_message}),
      Scheduler = Info#concuerror_info.scheduler,
      Trapping = Info#concuerror_info.trap_exit,
      Scheduler ! {trapping, Trapping},
      case is_active(Info) of
        true ->
          ?debug_flag(?receive_, {message_enqueued, Message}),
          Old = Info#concuerror_info.messages_new,
          NewInfo =
            Info#concuerror_info{
              messages_new = queue:in(Message, Old)
             },
          process_loop(NewInfo);
        false ->
          ?debug_flag(?receive_, {message_ignored, Info#concuerror_info.status}),
          process_loop(Info)
      end;
    reset ->
      ?debug_flag(?wait, {waiting, reset}),
      NewInfo = #concuerror_info{processes = Processes} =
        init_concuerror_info(Info),
      erase(),
      Symbol = ets:lookup_element(Processes, self(), ?process_symbolic),
      erlang:hibernate(concuerror_callback, process_top_loop, [NewInfo, Symbol])
  end.

%%------------------------------------------------------------------------------

exiting(Reason, Stacktrace, Info) ->
  %% XXX: The ordering of the following events has to be verified (e.g. R16B03):
  %% XXX:  - process marked as exiting, new messages are not delivered, name is
  %%         unregistered
  %% XXX:  - cancel timers
  %% XXX:  - transfer ets ownership and send message or delete table
  %% XXX:  - send link signals
  %% XXX:  - send monitor messages
  ?debug_flag(?exit, {going_to_exit, Reason}),
  Self = self(),
  LocatedInfo = #concuerror_info{next_event = Event} =
    add_location_info(exit, set_status(Info, exiting)),
  [{MaybeName, Info}, {Links, Info}] =
    [run_built_in(erlang, process_info, 2, [Self, Type], Info) ||
      Type <- [registered_name, links]],
  #concuerror_info{monitors = MonitorsTable} = Info,
  Monitors =
    try ets:lookup_element(MonitorsTable, Self, 2)
    catch error:badarg -> []
    end,
  Name =
    case MaybeName of
      [] -> ?process_name_none;
      {registered_name, N} -> N
    end,
  Notification =
    Event#event{
      event_info =
        #exit_event{
           links = Links,
           monitors = Monitors,
           name = Name,
           reason = Reason,
           stacktrace = Stacktrace
          }
     },
  ExitInfo = add_location_info(exit, notify(Notification, LocatedInfo)),
  FunFold = fun(Fun, Acc) -> Fun(Acc) end,
  FunList =
    [fun ets_ownership_exiting_events/1,
     links_exiting_events(Links),
     monitors_exiting_events(Monitors)],
  FinalInfo = #concuerror_info{next_event = FinalEvent} =
    lists:foldl(FunFold, ExitInfo#concuerror_info{exit_reason = Reason}, FunList),
  self() ! FinalEvent,
  process_loop(set_status(FinalInfo, exited)).

ets_ownership_exiting_events(Info) ->
  %% XXX:  - transfer ets ownership and send message or delete table
  %% XXX: Mention that order of deallocation/transfer is not monitored.
  #concuerror_info{ets_tables = EtsTables} = Info,
  case ets:match(EtsTables, ?ets_match_owner_to_tid_heir(self())) of
    [] -> Info;
    Tables ->
      Fold =
        fun([Tid, HeirSpec], InfoIn) ->
            MFArgs =
              case HeirSpec of
                {heir, none} ->
                  ?debug_flag(?heir, no_heir),
                  [ets, delete, [Tid]];
                {heir, Pid, Data} ->
                  ?debug_flag(?heir, {using_heir, Tid, HeirSpec}),
                  [ets, give_away, [Tid, Pid, Data]]
              end,
            case instrumented(call, MFArgs, exit, InfoIn) of
              {{didit, true}, NewInfo} -> NewInfo;
              _ ->
                ?debug_flag(?heir, {problematic_heir, Tid, HeirSpec}),
                {{didit, true}, NewInfo} =
                  instrumented(call, [ets, delete, [Tid]], exit, InfoIn),
                NewInfo
            end
        end,
      lists:foldl(Fold, Info, Tables)
  end.

links_exiting_events(Links) ->
  fun(Info) ->
      case Links =:= [] of
        true -> Info;
        false ->
          #concuerror_info{exit_reason = Reason} = Info,
          Fold =
            fun(Link, InfoIn) ->
                MFArgs = [erlang, exit, [Link, Reason]],
                {{didit, true}, NewInfo} =
                  instrumented(call, MFArgs, exit, InfoIn),
                NewInfo
            end,
          lists:foldl(Fold, Info, Links)
      end
  end.

monitors_exiting_events(Monitors) ->
  fun(Info) ->
      case Monitors =:= [] of
        true -> Info;
        false ->
          #concuerror_info{exit_reason = Reason} = Info,
          Fold =
            fun({Ref, P}, InfoIn) ->
                Msg = {'DOWN', Ref, process, self(), Reason},
                MFArgs = [erlang, send, [P, Msg]],
                {{didit, Msg}, NewInfo} =
                  instrumented(call, MFArgs, exit, InfoIn),
                NewInfo
            end,
          lists:foldl(Fold, Info, Monitors)
      end
  end.

%%------------------------------------------------------------------------------

check_ets_access_rights(Tid, Pid, Op, EtsTables) ->
  Owner = ets:lookup_element(EtsTables, Tid, ?ets_owner),
  case
    is_pid(Owner)
    andalso
    (Owner =:= Pid
     orelse
     case ets_ops_access_rights_map(Op) of
       write -> ets:lookup_element(EtsTables, Tid, ?ets_protection) =:= public;
       read -> ets:lookup_element(EtsTables, Tid, ?ets_protection) =/= private;
       delete -> false;
       _ -> throw(specify_ets_rights)
     end)
  of
    true -> ok;
    false -> error(badarg)
  end.

ets_ops_access_rights_map(Op) ->
  case Op of
    insert -> write;
    lookup -> read;
    delete -> delete
  end.

%%------------------------------------------------------------------------------

system_ets_entries(EtsTables) ->
  Map = fun(Tid) -> ?new_system_ets_table(Tid, ets:info(Tid, protection)) end,
  ets:insert(EtsTables, [Map(Tid) || Tid <- ets:all(), is_atom(Tid)]).

init_concuerror_info(Info) ->
  #concuerror_info{
     'after-timeout' = AfterTimeout,
     ets_tables = EtsTables,
     links = Links,
     logger = Logger,
     monitors = Monitors,
     processes = Processes,
     scheduler = Scheduler
    } = Info,
  #concuerror_info{
     'after-timeout' = AfterTimeout,
     ets_tables = EtsTables,
     links = Links,
     logger = Logger,
     monitors = Monitors,
     processes = Processes,
     scheduler = Scheduler
    }.

%% reset_stack(#concuerror_info{stack = Stack} = Info) ->
%%   {Stack, Info#concuerror_info{stack = []}}.

%% append_stack(Value, #concuerror_info{stack = Stack} = Info) ->
%%   Info#concuerror_info{stack = [Value|Stack]}.

%%------------------------------------------------------------------------------

add_location_info(Location, #concuerror_info{next_event = Event} = Info) ->
  Info#concuerror_info{next_event = Event#event{location = Location}}.

set_status(#concuerror_info{processes = Processes} = Info, Status) ->
  MaybeDropName =
    case Status =:= exiting of
      true -> [{?process_name, ?process_name_none}];
      false -> []
    end,
  Updates = [{?process_status, Status}|MaybeDropName],
  true = ets:update_element(Processes, self(), Updates),
  Info#concuerror_info{status = Status}.

is_active(#concuerror_info{status = Status}) ->
  is_active(Status);
is_active(Status) when is_atom(Status) ->
  (Status =:= running) orelse (Status =:= waiting).

fix_stacktrace(#concuerror_info{stacktop = Top}) ->
  RemoveSelf = lists:keydelete(?MODULE, 1, erlang:get_stacktrace()),
  case lists:keyfind(concuerror_inspect, 1, RemoveSelf) of
    false -> RemoveSelf;
    _ ->
      RemoveInspect = lists:keydelete(concuerror_inspect, 1, RemoveSelf),
      [Top|RemoveInspect]
  end.
