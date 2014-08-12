%% -*- erlang-indent-level: 2 -*-

-module(concuerror_callback).

%% Interface to concuerror_inspect:
-export([instrumented_top/4, hijack_backend/1]).

%% Interface to scheduler:
-export([spawn_first_process/1, start_first_process/3,
         deliver_message/3, wait_actor_reply/2, collect_deadlock_info/1,
         enabled/1]).

%% Interface to logger:
-export([setup_logger/1]).

%% Interface for resetting:
-export([process_top_loop/1]).

-export([explain_error/1]).

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
-define(loop, ?flag(10)).
-define(send, ?flag(11)).
-define(exit, ?flag(12)).
-define(trap, ?flag(13)).
-define(undefined, ?flag(14)).
-define(heir, ?flag(15)).
-define(notify, ?flag(16)).

-define(ACTIVE_FLAGS, [?undefined,?short_builtin,?loop,?notify, ?non_builtin]).

%%-define(DEBUG, true).
%%-define(DEBUG_FLAGS, lists:foldl(fun erlang:'bor'/2, 0, ?ACTIVE_FLAGS)).

-define(badarg_if_not(A), case A of true -> ok; false -> error(badarg) end).
%%------------------------------------------------------------------------------

-include("concuerror.hrl").

-record(process_flags, {
          trap_exit = false  :: boolean(),
          priority  = normal :: 'low' | 'normal' | 'high' | 'max'
         }).

-record(concuerror_info, {
          after_timeout              :: infinite | integer(),
          caught_signal = false      :: boolean(),
          escaped_pdict = []         :: term(),
          ets_tables                 :: ets_tables(),
          exit_reason = normal       :: term(),
          extra                      :: term(),
          flags = #process_flags{}   :: #process_flags{},
          instant_delivery = false   :: boolean(),
          is_timer = false           :: 'false' | reference(),
          links                      :: links(),
          logger                     :: pid(),
          messages_new = queue:new() :: queue(),
          messages_old = queue:new() :: queue(),
          modules                    :: modules(),
          monitors                   :: monitors(),
          event = none               :: 'none' | event(),
          notify_when_ready          :: {pid(), boolean()},
          processes                  :: processes(),
          scheduler                  :: pid(),
          stacktop = 'none'          :: 'none' | tuple(),
          status = running           :: 'exited'| 'exiting' | 'running' | 'waiting',
          system_ets_entries         :: ets:tid(),
          timeout                    :: timeout(),
          timers                     :: timers()
         }).

-type concuerror_info() :: #concuerror_info{}.

%%------------------------------------------------------------------------------

-spec spawn_first_process(options()) -> {pid(), [pid()]}.

spawn_first_process(Options) ->
  EtsTables = ets:new(ets_tables, [public]),
  ets:insert(EtsTables, {tid,1}),
  Info =
    #concuerror_info{
       after_timeout = ?opt(after_timeout, Options),
       ets_tables = EtsTables,
       instant_delivery = ?opt(instant_delivery, Options),
       links          = ets:new(links, [bag, public]),
       logger         = ?opt(logger, Options),
       modules        = ?opt(modules, Options),
       monitors       = ets:new(monitors, [bag, public]),
       processes      = Processes = ?opt(processes, Options),
       scheduler      = self(),
       system_ets_entries = ets:new(system_ets_entries, [bag, public]),
       timeout        = ?opt(timeout, Options),
       timers         = ets:new(timers, [public])
      },
  System = system_processes_wrappers(Info),
  system_ets_entries(Info),
  P = new_process(Info),
  true = ets:insert(Processes, ?new_process(P, "P")),
  {DefLeader, _} = run_built_in(erlang,whereis,1,[user],Info),
  true = ets:update_element(Processes, P, {?process_leader, DefLeader}),
  {P, System}.

-spec start_first_process(pid(), {atom(), atom(), [term()]}, timeout()) -> ok.

start_first_process(Pid, {Module, Name, Args}, Timeout) ->
  request_system_reset(Pid),
  Pid ! {start, Module, Name, Args},
  wait_process(Pid, Timeout),
  ok.

-spec setup_logger(processes()) -> ok.

setup_logger(Processes) ->
  put(concuerror_info, {logger, Processes}),
  ok.

-spec hijack_backend(concuerror_info()) -> ok.

hijack_backend(#concuerror_info{processes = Processes} = Info) ->
  Escaped = erase(),
  true = group_leader() =:= whereis(user),
  {GroupLeader, _} = run_built_in(erlang,whereis,1,[user], Info),
  {registered_name, Name} = process_info(self(), registered_name),
  true = ets:insert(Processes, ?new_system_process(self(), Name, hijacked)),
  {true, Info} =
    run_built_in(erlang, group_leader, 2, [GroupLeader, self()], Info),
  NewInfo = Info#concuerror_info{escaped_pdict = Escaped},
  put(concuerror_info, NewInfo),
  ok.

%%------------------------------------------------------------------------------

-spec instrumented_top(Tag      :: instrumented_tag(),
                       Args     :: [term()],
                       Location :: term(),
                       Info     :: concuerror_info()) ->
                          'doit' |
                          {'didit', term()} |
                          {'error', term()} |
                          'skip_timeout'.

instrumented_top(Tag, Args, Location, #concuerror_info{} = Info) ->
  #concuerror_info{escaped_pdict = Escaped} = Info,
  lists:foreach(fun({K,V}) -> put(K,V) end, Escaped),
  {Result, #concuerror_info{} = NewInfo} =
    instrumented(Tag, Args, Location, Info),
  NewEscaped = erase(),
  FinalInfo = NewInfo#concuerror_info{escaped_pdict = NewEscaped},
  put(concuerror_info, FinalInfo),
  Result;
instrumented_top(Tag, Args, Location, {logger, _} = Info) ->
  {Result, _} = instrumented(Tag, Args, Location, Info),
  put(concuerror_info, Info),
  Result.

instrumented(call, [Module, Name, Args], Location, Info) ->
  Arity = length(Args),
  instrumented_aux(Module, Name, Arity, Args, Location, Info);
instrumented(apply, [Fun, Args], Location, Info) ->
  case is_function(Fun) of
    true ->
      Module = get_fun_info(Fun, module),
      Name = get_fun_info(Fun, name),
      Arity = get_fun_info(Fun, arity),
      case length(Args) =:= Arity of
        true -> instrumented_aux(Module, Name, Arity, Args, Location, Info);
        false -> {doit, Info}
      end;
    false ->
      {doit, Info}
  end;
instrumented('receive', [PatternFun, Timeout], Location, Info) ->
  case Info of
    #concuerror_info{after_timeout = AfterTimeout} ->
      RealTimeout =
        case Timeout =:= infinity orelse Timeout > AfterTimeout of
          false -> Timeout;
          true -> infinity
        end,
      handle_receive(PatternFun, RealTimeout, Location, Info);
    _Logger ->
      {doit, Info}
  end.

instrumented_aux(erlang, apply, 3, [Module, Name, Args], Location, Info) ->
  instrumented_aux(Module, Name, length(Args), Args, Location, Info);
instrumented_aux(Module, Name, Arity, Args, Location, Info)
  when is_atom(Module) ->
  case
    erlang:is_builtin(Module, Name, Arity) andalso
    not lists:member({Module, Name, Arity}, ?RACE_FREE_BIFS)
  of
    true ->
      case Info of
        #concuerror_info{} ->
          built_in(Module, Name, Arity, Args, Location, Info);
        {logger, Processes} ->
          case {Module, Name, Arity} =:= {erlang, pid_to_list, 1} of
            true ->
              [Term] = Args,
              try
                Symbol = ets:lookup_element(Processes, Term, ?process_symbolic),
                {{didit, Symbol}, Info}
              catch
                _:_ -> {doit, Info}
              end;
            false ->
              {doit, Info}
          end
      end;
    false ->
      case Info of
        #concuerror_info{modules = M} ->
          ?debug_flag(?non_builtin,{Module,Name,Arity,Location}),
          concuerror_loader:load(Module, M);
        _ -> ok
      end,
      {doit, Info}
  end;
instrumented_aux({Module, _} = Tuple, Name, Arity, Args, Location, Info) ->
  instrumented_aux(Module, Name, Arity + 1, Args ++ Tuple, Location, Info);
instrumented_aux(_, _, _, _, _, Info) ->
  {doit, Info}.

get_fun_info(Fun, Tag) ->
  {Tag, Info} = erlang:fun_info(Fun, Tag),
  Info.

%%------------------------------------------------------------------------------

built_in(erlang, display, 1, [Term], _Location, Info) ->
  ?debug_flag(?builtin, {'built-in', erlang, display, 1, [Term], _Location}),
  #concuerror_info{logger = Logger} = Info,
  Chars = io_lib:format("~w~n",[Term]),
  concuerror_logger:print(Logger, standard_io, Chars),
  {{didit, true}, Info};
%% Process dictionary has been restored here. No need to report such ops.
built_in(erlang, get, _Arity, Args, _Location, Info) ->
  ?debug_flag(?builtin, {'built-in', erlang, get, _Arity, Args, _Location}),
  Res = erlang:apply(erlang,get,Args),
  {{didit, Res}, Info};
%% Instrumented processes may just call pid_to_list (we instrument this builtin
%% for the logger)
built_in(erlang, pid_to_list, _Arity, _Args, _Location, Info) ->
  {doit, Info};
built_in(erlang, system_info, 1, [A], _Location, Info)
  when A =:= os_type;
       A =:= schedulers;
       A =:= logical_processors_available
       ->
  {doit, Info};
%% XXX: Check if its redundant (e.g. link to already linked)
built_in(Module, Name, Arity, Args, Location, InfoIn) ->
  Info = process_loop(InfoIn),
  ?debug_flag(?short_builtin, {'built-in', Module, Name, Arity, Location}),
  %% {Stack, ResetInfo} = reset_stack(Info),
  %% ?debug_flag(?stack, {stack, Stack}),
  #concuerror_info{flags = #process_flags{trap_exit = Trapping}} = LocatedInfo =
    add_location_info(Location, Info#concuerror_info{extra = undefined}),%ResetInfo),
  try
    {Value, UpdatedInfo} = run_built_in(Module, Name, Arity, Args, LocatedInfo),
    #concuerror_info{extra = Extra, event = MaybeMessageEvent} = UpdatedInfo,
    Event = maybe_deliver_message(MaybeMessageEvent, UpdatedInfo),
    ?debug_flag(?builtin, {'built-in', Module, Name, Arity, Value, Location}),
    ?debug_flag(?args, {args, Args}),
    ?debug_flag(?result, {args, Value}),
    EventInfo =
      #builtin_event{
         exiting = Location =:= exit,
         extra = Extra,
         mfargs = {Module, Name, Args},
         result = Value,
         trapping = Trapping
        },
    Notification = Event#event{event_info = EventInfo},
    NewInfo = notify(Notification, UpdatedInfo),
    {{didit, Value}, NewInfo}
  catch
    throw:Reason ->
      #concuerror_info{scheduler = Scheduler} = Info,
      ?debug_flag(?loop, crashing),
      exit(Scheduler, {Reason, Module, Name, Arity, Args, Location}),
      receive after infinity -> ok end;
    error:Reason ->
      #concuerror_info{event = FEvent} = LocatedInfo,
      FEventInfo =
        #builtin_event{
           mfargs = {Module, Name, Args},
           status = {crashed, Reason},
           trapping = Trapping
          },
      FNotification = FEvent#event{event_info = FEventInfo},
      FNewInfo = notify(FNotification, LocatedInfo),
      FinalInfo =
        FNewInfo#concuerror_info{stacktop = {Module, Name, Args, Location}},
      {{error, Reason}, FinalInfo}
  end.

%% Special instruction running control (e.g. send to unknown -> wait for reply)
run_built_in(erlang, demonitor, 1, [Ref], Info) ->
  run_built_in(erlang, demonitor, 2, [Ref, []], Info);
run_built_in(erlang, demonitor, 2, [Ref, Options], Info) ->
  ?badarg_if_not(is_reference(Ref)),
  #concuerror_info{monitors = Monitors} = Info,
  {Result, NewInfo} =
    case ets:match(Monitors, ?monitor_match_to_target_source_as(Ref)) of
      [] ->
        PatternFun =
          fun(M) ->
              case M of
                {'DOWN', Ref, process, _, _} -> true;
                _ -> false
              end
          end,
        case lists:member(flush, Options) of
          true ->
            {Match, FlushInfo} =
              has_matching_or_after(PatternFun, infinity, foo, Info, non_blocking),
            {Match =/= false, FlushInfo};
          false ->
            {false, Info}
        end;
      [[Target, Source, As]] ->
        ?badarg_if_not(Source =:= self()),
        true = ets:delete_object(Monitors, ?monitor(Ref, Target, As, active)),
        true = ets:insert(Monitors, ?monitor(Ref, Target, As, inactive)),
        {not lists:member(flush, Options), Info}
    end,
  case lists:member(info, Options) of
    true -> {Result, NewInfo};
    false -> {true, NewInfo}
  end;
run_built_in(erlang, exit, 2, [Pid, Reason],
             #concuerror_info{
                event = #event{event_info = EventInfo} = Event
               } = Info) ->
  ?badarg_if_not(is_pid(Pid)),
  case EventInfo of
    %% Replaying...
    #builtin_event{result = OldResult} -> {OldResult, Info};
    %% New event...
    undefined ->
      Content =
        case Event#event.location =/= exit andalso Reason =:= kill of
          true -> kill;
          false -> {'EXIT', self(), Reason}
        end,
      MessageEvent =
        #message_event{
           cause_label = Event#event.label,
           message = #message{data = Content},
           recipient = Pid,
           type = exit_signal},
      NewEvent = Event#event{special = [{message, MessageEvent}]},
      {true, Info#concuerror_info{event = NewEvent}}
  end;

%% XXX: Temporary
run_built_in(erlang, get_stacktrace, 0, [], Info) ->
  #concuerror_info{logger = Logger} = Info,
  Msg =
    "Concuerror does not fully support erlang:get_stacktrace/0, returning an"
    " empty list instead. If you need proper support, notify the developers to"
    " add this feature.~n",
  ?unique(Logger, ?lwarning, Msg, []),
  {[], Info};

run_built_in(erlang, group_leader, 0, [], Info) ->
  Leader = get_leader(Info, self()),
  {Leader, Info};

run_built_in(erlang, group_leader, 2, [GroupLeader, Pid],
             #concuerror_info{processes = Processes} = Info) ->
  ?badarg_if_not(is_pid(GroupLeader) andalso is_pid(Pid)),
  true = ets:update_element(Processes, Pid, {?process_leader, GroupLeader}),
  {true, Info};

run_built_in(erlang, halt, _, _, Info) ->
  #concuerror_info{event = Event} = Info,
  NewEvent = Event#event{special = [halt]},
  {no_return, Info#concuerror_info{event = NewEvent}};

run_built_in(erlang, is_process_alive, 1, [Pid], Info) ->
  ?badarg_if_not(is_pid(Pid)),
  #concuerror_info{processes = Processes} = Info,
  Return =
    case ets:lookup(Processes, Pid) of
      [] -> ?crash({checking_system_process, Pid});
      [?process_pat_pid_status(Pid, Status)] -> is_active(Status)
    end,
  {Return, Info};

run_built_in(erlang, link, 1, [Pid], Info) ->
  #concuerror_info{
     flags = #process_flags{trap_exit = TrapExit},
     links = Links,
     event = #event{event_info = EventInfo} = Event} = Info,
  case run_built_in(erlang, is_process_alive, 1, [Pid], Info) of
    {true, Info}->
      Self = self(),
      true = ets:insert(Links, ?links(Self, Pid)),
      {true, Info};
    {false, _} ->
      case TrapExit of
        false -> error(noproc);
        true ->
          NewInfo =
            case EventInfo of
              %% Replaying...
              #builtin_event{} -> Info;
              %% New event...
              undefined ->
                MessageEvent =
                  #message_event{
                     cause_label = Event#event.label,
                     message = #message{data = {'EXIT', Pid, noproc}},
                     recipient = self()},
                NewEvent = Event#event{special = [{message, MessageEvent}]},
                Info#concuerror_info{event = NewEvent}
            end,
          {true, NewInfo}
      end
  end;

run_built_in(erlang, Name, 0, [], Info)
  when
    Name =:= date;
    Name =:= make_ref;
    Name =:= now;
    Name =:= time
    ->
  #concuerror_info{event = #event{event_info = EventInfo}} = Info,
  Ref =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} -> OldResult;
      %% New event...
      undefined -> erlang:apply(erlang,Name,[])
    end,
  {Ref, Info};
run_built_in(erlang, monitor, 2, [Type, InTarget], Info) ->
  #concuerror_info{
     monitors = Monitors,
     event = #event{event_info = EventInfo} = Event} = Info,
  ?badarg_if_not(Type =:= process),
  {Target, As} =
    case InTarget of
      P when is_pid(P) -> {InTarget, InTarget};
      A when is_atom(A) -> {InTarget, {InTarget, node()}};
      {Name, Node} = Local when is_atom(Name), Node =:= node() ->
        {Name, Local};
      {Name, Node} when is_atom(Name) -> ?crash({not_local_node, Node});
      _ -> error(badarg)
    end,
  Ref =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} -> OldResult;
      %% New event...
      undefined -> make_ref()
    end,
  {IsActive, Pid} =
    case is_pid(Target) of
      true ->
        {IA, _} = run_built_in(erlang, is_process_alive, 1, [Target], Info),
        {IA, Target};
      false ->
        {P1, _} = run_built_in(erlang, whereis, 1, [Target], Info),
        case P1 =:= undefined of
          true -> {false, foo};
          false ->
            {IA, _} = run_built_in(erlang, is_process_alive, 1, [P1], Info),
            {IA, P1}
        end
    end,
  case IsActive of
    true -> true = ets:insert(Monitors, ?monitor(Ref, Pid, As, active));
    false -> ok
  end,
  NewInfo =
    case EventInfo of
      %% Replaying...
      #builtin_event{} -> Info;
      %% New event...
      undefined ->
        case IsActive of
          false ->
            Message = #message{data = {'DOWN', Ref, process, As, noproc}},
            MessageEvent =
              #message_event{
                 cause_label = Event#event.label,
                 message = Message,
                 recipient = self()},
            NewEvent = Event#event{special = [{message, MessageEvent}]},
            Info#concuerror_info{event = NewEvent};
          true -> Info
        end
    end,
  {Ref, NewInfo};
run_built_in(erlang, process_info, 2, [Pid, Item], Info) when is_atom(Item) ->
  {Alive, _} = run_built_in(erlang, is_process_alive, 1, [Pid], Info),
  case Alive of
    false -> {undefined, Info};
    true ->
      TheirInfo =
        case Pid =:= self() of
          true -> Info;
          false -> get_their_info(Pid)
        end,
      Res =
        case Item of
          dictionary ->
            #concuerror_info{escaped_pdict = Escaped} = TheirInfo,
            Escaped;
          group_leader ->
            get_leader(Info, Pid);
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
            TheirInfo#concuerror_info.flags#process_flags.trap_exit;
          ExpectsANumber when
              ExpectsANumber =:= heap_size;
              ExpectsANumber =:= reductions;
              ExpectsANumber =:= stack_size;
              false ->
            42;
          _ ->
            throw({unsupported_process_info, Item})
        end,
      {Res, Info}
  end;
run_built_in(erlang, register, 2, [Name, Pid],
             #concuerror_info{processes = Processes} = Info) ->
  try
    true = is_atom(Name),
    {true, Info} = run_built_in(erlang, is_process_alive, 1, [Pid], Info),
    [] = ets:match(Processes, ?process_match_name_to_pid(Name)),
    ?process_name_none = ets:lookup_element(Processes, Pid, ?process_name),
    false = undefined =:= Name,
    true = ets:update_element(Processes, Pid, {?process_name, Name}),
    {true, Info}
  catch
    _:_ -> error(badarg)
  end;

run_built_in(erlang, ReadorCancelTimer, 1, [Ref], Info)
  when
    ReadorCancelTimer =:= read_timer;
    ReadorCancelTimer =:= cancel_timer
    ->
  #concuerror_info{timers = Timers} = Info,
  case ets:lookup(Timers, Ref) of
    [] -> {false, Info};
    [{Ref,Pid,_Dest}] ->
      case ReadorCancelTimer of
        read_timer -> ok;
        cancel_timer ->
          ?debug_flag(?loop, sending_kill_to_cancel),
          ets:delete(Timers, Ref),
          Pid ! {exit_signal, #message{data = kill}, self()},
          receive {trapping, false} -> ok end
      end,
      {1, Info}
  end;

run_built_in(erlang, SendAfter, 3, [0, Dest, Msg], Info)
  when
    SendAfter =:= send_after;
    SendAfter =:= start_timer ->
  #concuerror_info{
     event = #event{event_info = EventInfo}} = Info,
  Ref =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldRef} -> OldRef;
      %% New event...
      undefined -> make_ref()
    end,
  ActualMessage =
    case SendAfter of
      send_after -> Msg;
      start_timer -> {timeout, Ref, Msg}
    end,
  {_, NewInfo} = run_built_in(erlang, send, 2, [Dest, ActualMessage], Info),
  {Ref, NewInfo};

run_built_in(erlang, SendAfter, 3, [Timeout, Dest, Msg], Info)
  when
    SendAfter =:= send_after;
    SendAfter =:= start_timer ->
  ?badarg_if_not(
    (is_pid(Dest) orelse is_atom(Dest)) andalso
     is_integer(Timeout) andalso
     Timeout >= 0),
  #concuerror_info{
     event = Event, processes = Processes, timeout = Wait, timers = Timers
    } = Info,
  #event{event_info = EventInfo} = Event,
  %Parent = self(),
  {Ref, Pid, NewInfo} =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldRef, extra = OldPid} ->
        true = ets:update_element(Processes, OldPid, {?process_name, OldRef}),
        {OldRef, OldPid, Info#concuerror_info{extra = OldPid}};
      %% New event...
      undefined ->
        NewRef = make_ref(),
        PassedInfo = reset_concuerror_info(Info),
        P =
          new_process(
            PassedInfo#concuerror_info{
              instant_delivery = true, is_timer = NewRef}),
        Symbol = "Timer " ++ erlang:ref_to_list(NewRef),
        true = ets:insert(Processes, ?new_process(P, Symbol)),
        NewEvent = Event#event{special = [{new, P}]},
        {NewRef, P, Info#concuerror_info{event = NewEvent, extra = P}}
    end,
  ActualMessage =
    case SendAfter of
      send_after -> Msg;
      start_timer -> {timeout, Ref, Msg}
    end,
  ets:insert(Timers, {Ref, Pid, Dest}),
  Pid ! {start, erlang, send, [Dest, ActualMessage]},
  wait_process(Pid, Wait),
  {Ref, NewInfo};

run_built_in(erlang, spawn, 3, [M, F, Args], Info) ->
  run_built_in(erlang, spawn_opt, 1, [{M, F, Args, []}], Info);
run_built_in(erlang, spawn_link, 3, [M, F, Args], Info) ->
  run_built_in(erlang, spawn_opt, 1, [{M, F, Args, [link]}], Info);
run_built_in(erlang, spawn_opt, 1, [{Module, Name, Args, SpawnOpts}], Info) ->
  #concuerror_info{
     event = Event,
     processes = Processes,
     timeout = Timeout} = Info,
  #event{event_info = EventInfo} = Event,
  Parent = self(),
  ParentSymbol = ets:lookup_element(Processes, Parent, ?process_symbolic),
  ChildId = ets:update_counter(Processes, Parent, {?process_children, 1}),
  {Result, NewInfo} =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} -> {OldResult, Info};
      %% New event...
      undefined ->
        PassedInfo = reset_concuerror_info(Info),
        ?debug_flag(?spawn, {Parent, spawning_new, PassedInfo}),
        ChildSymbol = io_lib:format("~s.~w",[ParentSymbol, ChildId]),
        P =
          case
            ets:match(Processes, ?process_match_symbol_to_pid(ChildSymbol))
          of
            [] ->
              NewP = new_process(PassedInfo),
              true = ets:insert(Processes, ?new_process(NewP, ChildSymbol)),
              NewP;
            [[OldP]] -> OldP
          end,
        NewResult =
          case lists:member(monitor, SpawnOpts) of
            true -> {P, make_ref()};
            false -> P
          end,
        NewEvent = Event#event{special = [{new, P}]},
        {NewResult, Info#concuerror_info{event = NewEvent}}
    end,
  Pid =
    case lists:member(monitor, SpawnOpts) of
      true ->
        {P1, Ref} = Result,
        #concuerror_info{monitors = Monitors} = Info,
        true = ets:insert(Monitors, ?monitor(Ref, P1, P1, active)),
        P1;
      false ->
        Result
    end,
  case lists:member(link, SpawnOpts) of
    true ->
      #concuerror_info{links = Links} = Info,
      true = ets:insert(Links, ?links(Parent, Pid));
    false -> ok
  end,
  {GroupLeader, _} = run_built_in(erlang, group_leader, 0, [], Info),
  true = ets:update_element(Processes, Pid, {?process_leader, GroupLeader}),
  Pid ! {start, Module, Name, Args},
  wait_process(Pid, Timeout),
  {Result, NewInfo};
run_built_in(erlang, Send, 2, [Recipient, Message], Info)
  when Send =:= '!'; Send =:= 'send' ->
  run_built_in(erlang, send, 3, [Recipient, Message, []], Info);
run_built_in(erlang, send, 3, [Recipient, Message, _Options],
             #concuerror_info{
                event = #event{event_info = EventInfo} = Event
               } = Info) ->
  Pid =
    case is_pid(Recipient) of
      true -> Recipient;
      false ->
        T =
          case Recipient of
            A when is_atom(A) -> Recipient;
            {A, N} when is_atom(A), N =:= node() -> A
          end,            
        {P, Info} = run_built_in(erlang, whereis, 1, [T], Info),
        P
    end,
  Extra =
    case Info#concuerror_info.is_timer of
      false -> undefined;
      Timer ->
        ets:delete(Info#concuerror_info.timers, Timer),
        Timer
    end,
  ?badarg_if_not(is_pid(Pid)),
  case EventInfo of
    %% Replaying...
    #builtin_event{result = OldResult} ->
      {OldResult, Info#concuerror_info{extra = Extra}};
    %% New event...
    undefined ->
      ?debug_flag(?send, {send, Recipient, Message}),
      MessageEvent =
        #message_event{
           cause_label = Event#event.label,
           message = #message{data = Message},
           recipient = Pid},
      NewEvent = Event#event{special = [{message, MessageEvent}]},
      ?debug_flag(?send, {send, successful}),
      {Message, Info#concuerror_info{event = NewEvent, extra = Extra}}
  end;

run_built_in(erlang, process_flag, 2, [Flag, Value],
             #concuerror_info{flags = Flags} = Info) ->
  case Flag of
    trap_exit ->
      ?badarg_if_not(is_boolean(Value)),
      {Flags#process_flags.trap_exit,
       Info#concuerror_info{flags = Flags#process_flags{trap_exit = Value}}};
    priority ->
      ?badarg_if_not(lists:member(Value, [low,normal,high,max])),
      {Flags#process_flags.priority,
       Info#concuerror_info{flags = Flags#process_flags{priority = Value}}}
  end;

run_built_in(erlang, processes, 0, [], Info) ->
  #concuerror_info{processes = Processes} = Info,
  {?active_processes(Processes), Info};

run_built_in(erlang, unlink, 1, [Pid], #concuerror_info{links = Links} = Info) ->
  Self = self(),
  [true,true] = [ets:delete_object(Links, L) || L <- ?links(Self, Pid)],
  {true, Info};
run_built_in(erlang, unregister, 1, [Name],
             #concuerror_info{processes = Processes} = Info) ->
  try
    [[Pid]] = ets:match(Processes, ?process_match_name_to_pid(Name)),
    true =
      ets:update_element(Processes, Pid, {?process_name, ?process_name_none}),
    NewInfo = Info#concuerror_info{extra = Pid},
    {true, NewInfo}
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
  ?badarg_if_not(is_atom(Name)),
  NoNameOptions = [O || O <- Options, O =/= named_table],
  #concuerror_info{
     ets_tables = EtsTables,
     event = #event{event_info = EventInfo},
     scheduler = Scheduler
    } = Info,
  Named =
    case Options =/= NoNameOptions of
      true ->
        ?badarg_if_not(ets:match(EtsTables, ?ets_match_name(Name)) =:= []),
        true;
      false -> false
    end,
  Tid =
    case EventInfo of
      %% Replaying...
      #builtin_event{extra = Extra} -> Extra;
      %% New event...
      undefined ->
        %% Looks like the last option is the one actually used.
        T = ets:new(Name, NoNameOptions ++ [public]),
        true = ets:give_away(T, Scheduler, given_to_scheduler),
        T
    end,
  ProtectFold =
    fun(Option, Selected) ->
        case Option of
          O when O =:= 'private';
                 O =:= 'protected';
                 O =:= 'public' -> O;
          _ -> Selected
        end
    end,
  Protection = lists:foldl(ProtectFold, protected, NoNameOptions),
  true = ets:insert(EtsTables, ?new_ets_table(Tid, Protection)),
  Ret =
    case Named of
      true -> Name;
      false ->
        case EventInfo of
          %% Replaying...
          #builtin_event{result = R} -> R;
          %% New event...
          undefined ->
            ets:update_counter(EtsTables, tid, 1)
        end
    end,
  Heir =
    case proplists:lookup(heir, Options) of
      none -> {heir, none};
      Other -> Other
    end,
  Update =
    [{?ets_alive, true},
     {?ets_heir, Heir},
     {?ets_owner, self()},
     {?ets_name, Ret}],
  ets:update_element(EtsTables, Tid, Update),
  ets:delete_all_objects(Tid),
  {Ret, Info#concuerror_info{extra = Tid}};
run_built_in(ets, info, _, [Name|Rest], Info) ->
  try
    {Tid, _} = check_ets_access_rights(Name, info, Info),
    {erlang:apply(ets, info, [Tid|Rest]), Info#concuerror_info{extra = Tid}}
  catch
    error:badarg -> {undefined, Info}
  end;
run_built_in(ets, F, N, [Name|Args], Info)
  when
    false
    ;{F,N} =:= {delete, 2}
    ;{F,N} =:= {delete_object,2}
    ;{F,N} =:= {first, 1}
    ;{F,N} =:= {insert, 2}
    ;{F,N} =:= {insert_new, 2}
    ;{F,N} =:= {lookup, 2}
    ;{F,N} =:= {lookup_element, 3}
    ;{F,N} =:= {match, 2}
    ;{F,N} =:= {match_object, 2}
    ;{F,N} =:= {member, 2}
    ;{F,N} =:= {next,   2}
    ;{F,N} =:= {select, 2}
    ;{F,N} =:= {select, 3}
    ;{F,N} =:= {select_delete, 2}
    ;{F,N} =:= {update_counter, 3}
    ->
  {Tid, System} = check_ets_access_rights(Name, {F,N}, Info),
  case System of
    true ->
      #concuerror_info{system_ets_entries = SystemEtsEntries} = Info,
      ets:insert(SystemEtsEntries, {Tid, Args});
    false ->
      true
  end,
  {erlang:apply(ets, F, [Tid|Args]), Info#concuerror_info{extra = Tid}};
run_built_in(ets, delete, 1, [Name], Info) ->
  {Tid, _} = check_ets_access_rights(Name, {delete,1}, Info),
  #concuerror_info{ets_tables = EtsTables} = Info,
  ets:update_element(EtsTables, Tid, [{?ets_alive, false}]),
  ets:delete_all_objects(Tid),
  {true, Info#concuerror_info{extra = Tid}};
run_built_in(ets, give_away, 3, [Name, Pid, GiftData], Info) ->
  #concuerror_info{event = #event{event_info = EventInfo} = Event} = Info,
  {Tid, _} = check_ets_access_rights(Name, {give_away,3}, Info),
  #concuerror_info{ets_tables = EtsTables} = Info,
  {Alive, Info} = run_built_in(erlang, is_process_alive, 1, [Pid], Info),
  Self = self(),
  ?badarg_if_not(is_pid(Pid) andalso Pid =/= Self andalso Alive),
  NewInfo =
    case EventInfo of
      %% Replaying. Keep original Message reference.
      #builtin_event{} -> Info;
      %% New event...
      undefined ->
        MessageEvent =
          #message_event{
             cause_label = Event#event.label,
             message = #message{data = {'ETS-TRANSFER', Tid, Self, GiftData}},
             recipient = Pid},
        NewEvent = Event#event{special = [{message, MessageEvent}]},
        Info#concuerror_info{event = NewEvent}
    end,
  Update = [{?ets_owner, Pid}],
  true = ets:update_element(EtsTables, Tid, Update),
  {true, NewInfo#concuerror_info{extra = Tid}};

run_built_in(Module, Name, Arity, Args, Info)
  when
    {Module, Name, Arity} =:= {erlang, put, 2};
    {Module, Name, Arity} =:= {os, getenv, 1}
    ->
  #concuerror_info{event = Event} = Info,
  #event{event_info = EventInfo, location = Location} = Event,
  NewResult = erlang:apply(Module, Name, Args),
  case EventInfo of
    %% Replaying...
    #builtin_event{mfargs = {M,F,OArgs}, result = OldResult} ->
      case OldResult =:= NewResult of
        true  -> {OldResult, Info};
        false ->
          case M =:= Module andalso F =:= Name andalso Args =:= OArgs of
            true ->
              ?crash({inconsistent_builtin,
                      [Module, Name, Arity, Args, OldResult, NewResult, Location]});
            false ->
              ?crash({unexpected_builtin_change,
                      [Module, Name, Arity, Args, M, F, OArgs, Location]})
          end
      end;
    undefined ->
      {NewResult, Info}
  end;

%% For other built-ins check whether replaying has the same result:
run_built_in(Module, Name, Arity, _Args,
             #concuerror_info{
                event = #event{location = Location},
                scheduler = Scheduler}) ->
  ?crash({unknown_built_in, {Module, Name, Arity, Location}}, Scheduler).

%%------------------------------------------------------------------------------

maybe_deliver_message(#event{special = Special} = Event, Info) ->
  case proplists:lookup(message, Special) of
    none -> Event;
    {message, MessageEvent} ->
      #concuerror_info{instant_delivery = InstantDelivery} = Info,
      #message_event{recipient = Recipient, instant = Instant} = MessageEvent,
      case (InstantDelivery orelse Recipient =:= self()) andalso Instant of
        false -> Event;
        true ->
          #concuerror_info{timeout = Timeout} = Info,
          TrapExit = Info#concuerror_info.flags#process_flags.trap_exit,
          deliver_message(Event, MessageEvent, Timeout, {true, TrapExit})
      end
  end.

-spec deliver_message(event(), message_event(), timeout()) -> event().

deliver_message(Event, MessageEvent, Timeout) ->
  deliver_message(Event, MessageEvent, Timeout, false).

deliver_message(Event, MessageEvent, Timeout, Instant) ->
  #event{special = Special} = Event,
  #message_event{
     message = Message,
     recipient = Recipient,
     type = Type} = MessageEvent,
  ?debug_flag(?loop, {deliver_message, Message, Instant}),
  Self = self(),
  Notify =
    case Recipient =:= Self of
      true ->
        %% Instant delivery to self
        Self ! {trapping, element(2, Instant)},
        ?notify_none;
      false -> Self
    end,
  Recipient ! {Type, Message, Notify},
  receive
    {trapping, Trapping} ->
      NewMessageEvent = MessageEvent#message_event{trapping = Trapping},
      NewSpecial =
        case already_known_delivery(Message, Special) of
          true -> Special;
          false -> Special ++ [{message_delivered, NewMessageEvent}]
        end,
      Event#event{special = NewSpecial};
    {system_reply, From, Id, Reply, System} ->
      ?debug_flag(?loop, got_system_message),
      case proplists:lookup(message_received, Special) =:= none of
        true ->
          SystemReply =
            #message_event{
               cause_label = Event#event.label,
               message = #message{data = Reply},
               sender = Recipient,
               recipient = From},
          SystemSpecials =
            [{message_delivered, MessageEvent},
             {message_received, Id},
             {system_communication, System},
             {message, SystemReply}],
          NewEvent = Event#event{special = Special ++ SystemSpecials},
          case Instant =:= false of
            true -> NewEvent;
            false -> deliver_message(NewEvent, SystemReply, Timeout, Instant)
          end;
        false ->
          SystemReply = find_system_reply(Recipient, Special),
          case Instant =:= false of
            true -> Event;
            false -> deliver_message(Event, SystemReply, Timeout, Instant)
          end
      end;
    {'EXIT', _, What} ->
      exit(What)
  after
    Timeout ->
      ?crash({no_response_for_message, Timeout, Recipient})
  end.

already_known_delivery(_, []) -> false;
already_known_delivery(Message, [{message_delivered, Event}|Special]) ->
  #message{id = Id} = Message,
  #message_event{message = #message{id = Del}} = Event,
  Id =:= Del orelse already_known_delivery(Message, Special);
already_known_delivery(Message, [_|Special]) ->
  already_known_delivery(Message, Special).

find_system_reply(System, [{message, #message_event{sender = System} = Message}|_]) ->
  Message;
find_system_reply(System, [_|Special]) ->
  find_system_reply(System, Special).

%%------------------------------------------------------------------------------

-spec wait_actor_reply(event(), timeout()) -> 'retry' | {'ok', event()}.

wait_actor_reply(Event, Timeout) ->
  receive
    exited -> retry;
    {blocked, _} -> retry;
    #event{} = NewEvent -> {ok, NewEvent};
    {'ETS-TRANSFER', _, _, given_to_scheduler} ->
      wait_actor_reply(Event, Timeout);
    {'EXIT', _, What} ->
      exit(What)
  after
    Timeout -> ?crash({process_did_not_respond, Timeout, Event#event.actor})
  end.

%%------------------------------------------------------------------------------

-spec collect_deadlock_info([pid()]) -> [{pid(), location()}].

collect_deadlock_info(Actors) ->
  Fold =
    fun(P, Acc) ->
        P ! deadlock_poll,
        receive
          {blocked, Location} -> [{P, Location}|Acc];
          exited -> Acc
        end
    end,
  lists:foldr(Fold, [], Actors).

-spec enabled(pid()) -> boolean().

enabled(P) ->
  P ! enabled,
  receive
    {enabled, Answer} -> Answer
  end.

%%------------------------------------------------------------------------------

handle_receive(PatternFun, Timeout, Location, Info) ->
  %% No distinction between replaying/new as we have to clear the message from
  %% the queue anyway...
  {MessageOrAfter, ReceiveInfo} =
    has_matching_or_after(PatternFun, Timeout, Location, Info, blocking),
  #concuerror_info{
     event = NextEvent,
     flags = #process_flags{trap_exit = Trapping}
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
      #message{data = Data, id = Id} ->
        {[{message_received, Id}], {ok, Data}};
      'after' -> {[], false}
    end,
  Notification =
    NextEvent#event{event_info = ReceiveEvent, special = Special},
  case CreateMessage of
    {ok, D} ->
      ?debug_flag(?receive_, {deliver, D}),
      self() ! D;
    false -> ok
  end,
  {skip_timeout, notify(Notification, UpdatedInfo)}.

has_matching_or_after(PatternFun, Timeout, Location, InfoIn, Mode) ->
  {Result, NewOldMessages} = has_matching_or_after(PatternFun, Timeout, InfoIn),
  UpdatedInfo = update_messages(Result, NewOldMessages, InfoIn),
  case Mode of
    non_blocking -> {Result, UpdatedInfo};
    blocking ->
      case Result =:= false of
        true ->
          ?debug_flag(?loop, blocked),
          NewInfo =
            case InfoIn#concuerror_info.status =:= waiting of
              true ->
                process_loop(notify({blocked, Location}, UpdatedInfo));
              false ->
                process_loop(set_status(UpdatedInfo, waiting))
            end,
          has_matching_or_after(PatternFun, Timeout, Location, NewInfo, Mode);
        false ->
          ?debug_flag(?loop, ready_to_receive),
          NewInfo = process_loop(InfoIn),
          {FinalResult, FinalNewOldMessages} =
            has_matching_or_after(PatternFun, Timeout, NewInfo),
          FinalInfo = update_messages(Result, FinalNewOldMessages, NewInfo),
          {FinalResult, FinalInfo}
      end
  end.

update_messages(Result, NewOldMessages, Info) ->
  case Result =:= false of
    true ->
      Info#concuerror_info{
        messages_new = queue:new(),
        messages_old = NewOldMessages};
    false ->
      Info#concuerror_info{
        messages_new = NewOldMessages,
        messages_old = queue:new()}
  end.      

has_matching_or_after(PatternFun, Timeout, Info) ->
  #concuerror_info{messages_new = NewMessages,
                   messages_old = OldMessages} = Info,
  {Result, NewOldMessages} =
    fold_with_patterns(PatternFun, NewMessages, OldMessages),
  AfterOrMessage =
    case Result =:= false of
      false -> Result;
      true ->
        case Timeout =:= infinity of
          false -> 'after';
          true -> false
        end
    end,
  {AfterOrMessage, NewOldMessages}.

fold_with_patterns(PatternFun, NewMessages, OldMessages) ->
  {Value, NewNewMessages} = queue:out(NewMessages),
  ?debug_flag(?receive_, {inspect, Value}),
  case Value of
    {value, #message{data = Data} = Message} ->
      case PatternFun(Data) of
        true  ->
          ?debug_flag(?receive_, matches),
          {Message, queue:join(OldMessages, NewNewMessages)};
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
  ?debug_flag(?notify, {notify, Notification}),
  Scheduler ! Notification,
  Info.

-spec process_top_loop(concuerror_info()) -> no_return().

process_top_loop(Info) ->
  ?debug_flag(?loop, top_waiting),
  receive
    reset -> process_top_loop(Info);
    reset_system ->
      reset_system(Info),
      Info#concuerror_info.scheduler ! reset_system,
      process_top_loop(Info);
    {start, Module, Name, Args} ->
      ?debug_flag(?loop, {start, Module, Name, Args}),
      put(concuerror_info, Info),
      try
        concuerror_inspect:instrumented(call, [Module,Name,Args], start),
        exit(normal)
      catch
        exit:{?MODULE, _} = Reason -> exit(Reason);
        Class:Reason ->
          case erase(concuerror_info) of
            #concuerror_info{escaped_pdict = Escaped} = EndInfo ->
              lists:foreach(fun({K,V}) -> put(K,V) end, Escaped),
              Stacktrace = fix_stacktrace(EndInfo),
              ?debug_flag(?exit, {exit, Class, Reason, Stacktrace}),
              NewReason =
                case Class of
                  throw -> {{nocatch, Reason}, Stacktrace};
                  error -> {Reason, Stacktrace};
                  exit  -> Reason
                end,
              exiting(NewReason, Stacktrace, EndInfo);
            _ -> exit({process_crashed, Class, Reason, erlang:get_stacktrace()})
          end
      end
  end.

request_system_reset(Pid) ->
  Pid ! reset_system,
  receive
    reset_system -> ok
  end.

reset_system(Info) ->
  #concuerror_info{system_ets_entries = SystemEtsEntries} = Info,
  ets:foldl(fun delete_system_entries/2, true, SystemEtsEntries),
  ets:delete_all_objects(SystemEtsEntries).

delete_system_entries({T, Objs}, true) when is_list(Objs) ->
  lists:foldl(fun delete_system_entries/2, true, [{T, O} || O <- Objs]);
delete_system_entries({T, O}, true) ->
  ets:delete_object(T, O).

new_process(ParentInfo) ->
  Info = ParentInfo#concuerror_info{notify_when_ready = {self(), true}},
  spawn_link(fun() -> process_top_loop(Info) end).

wait_process(Pid, Timeout) ->
  %% Wait for the new process to instrument any code.
  receive
    ready -> ok
  after
    Timeout ->
      ?crash({process_did_not_respond, Timeout, Pid})
  end.

process_loop(#concuerror_info{notify_when_ready = {Pid, true}} = Info) ->
  ?debug_flag(?loop, notifying_parent),
  Pid ! ready,
  process_loop(Info#concuerror_info{notify_when_ready = {Pid, false}});
process_loop(Info) ->
  ?debug_flag(?loop, process_loop),
  receive
    #event{event_info = EventInfo} = Event ->
      ?debug_flag(?loop, got_event),
      Status = Info#concuerror_info.status,
      case Status =:= exited of
        true ->
          ?debug_flag(?loop, exited),
          process_loop(notify(exited, Info));
        false ->
          NewInfo = Info#concuerror_info{event = Event},
          case EventInfo of
            undefined ->
              ?debug_flag(?loop, exploring),
              NewInfo;
            _OtherReplay ->
              ?debug_flag(?loop, replaying),
              NewInfo
          end
      end;
    {exit_signal, #message{data = Data} = Message, Notify} ->
      Trapping = Info#concuerror_info.flags#process_flags.trap_exit,
      case is_active(Info) of
        true ->
          case Data =:= kill of
            true ->
              ?debug_flag(?loop, kill_signal),
              send_message_ack(Notify, Trapping),
              exiting(killed, [], Info#concuerror_info{caught_signal = true});
            false ->
              case Trapping of
                true ->
                  ?debug_flag(?loop, signal_trapped),
                  self() ! {message, Message, Notify},
                  process_loop(Info);
                false ->
                  send_message_ack(Notify, Trapping),
                  {'EXIT', _From, Reason} = Data,
                  case Reason =:= normal of
                    true ->
                      ?debug_flag(?loop, ignore_normal_signal),
                      process_loop(Info);
                    false ->
                      ?debug_flag(?loop, error_signal),
                      exiting(Reason, [], Info#concuerror_info{caught_signal = true})
                  end
              end
          end;
        false ->
          ?debug_flag(?loop, ignoring_signal),
          send_message_ack(Notify, Trapping),
          process_loop(Info)
      end;
    {message, Message, Notify} ->
      ?debug_flag(?loop, message),
      Trapping = Info#concuerror_info.flags#process_flags.trap_exit,
      send_message_ack(Notify, Trapping),
      case is_active(Info) of
        true ->
          ?debug_flag(?loop, enqueueing_message),
          Old = Info#concuerror_info.messages_new,
          NewInfo =
            Info#concuerror_info{
              messages_new = queue:in(Message, Old)
             },
          ?debug_flag(?loop, enqueued_msg),
          case NewInfo#concuerror_info.status =:= waiting of
            true -> NewInfo#concuerror_info{status = running};
            false -> process_loop(NewInfo)
          end;
        false ->
          ?debug_flag(?loop, ignoring_message),
          process_loop(Info)
      end;
    reset ->
      ?debug_flag(?loop, reset),
      NewInfo =
        #concuerror_info{
           ets_tables = EtsTables,
           links = Links,
           monitors = Monitors,
           processes = Processes} = reset_concuerror_info(Info),
      _ = erase(),
      Symbol = ets:lookup_element(Processes, self(), ?process_symbolic),
      ets:insert(Processes, ?new_process(self(), Symbol)),
      {DefLeader, _} = run_built_in(erlang,whereis,1,[user],Info),
      true = ets:update_element(Processes, self(), {?process_leader, DefLeader}),
      ets:match_delete(EtsTables, ?ets_match_mine()),
      ets:match_delete(Links, ?links_match_mine()),
      ets:match_delete(Monitors, ?monitors_match_mine()),
      erlang:hibernate(concuerror_callback, process_top_loop, [NewInfo]);
    deadlock_poll ->
      ?debug_flag(?loop, deadlock_poll),
      Status = Info#concuerror_info.status,
      case Status =:= exited of
        true -> process_loop(notify(exited, Info));
        false -> Info
      end;
    enabled ->
      Status = Info#concuerror_info.status,
      process_loop(notify({enabled, Status =:= running}, Info));
    {get_info, To} ->
      To ! {info, Info},
      process_loop(Info)
  end.

get_their_info(Pid) ->
  Pid ! {get_info, self()},
  receive
    {info, Info} -> Info
  end.

send_message_ack(Notify, Trapping) ->
  case Notify =/= ?notify_none of
    true ->
      Notify ! {trapping, Trapping},
      ok;
    false -> ok
  end.

get_leader(#concuerror_info{processes = Processes}, P) ->
  ets:lookup_element(Processes, P, ?process_leader).

%%------------------------------------------------------------------------------

exiting(Reason, _,
        #concuerror_info{is_timer = Timer} = InfoIn) when Timer =/= false ->
  Info =
    case Reason of
      killed ->
        #concuerror_info{event = Event} = WaitInfo = process_loop(InfoIn),
        EventInfo =
          #exit_event{
             actor = Timer,
             reason = normal,
             status = running
            },
        Notification = Event#event{event_info = EventInfo},
        add_location_info(exit, notify(Notification, WaitInfo));
      normal ->
        InfoIn
    end,
  process_loop(set_status(Info, exited));
exiting(Reason, Stacktrace, #concuerror_info{status = Status} = InfoIn) ->
  %% XXX: The ordering of the following events has to be verified (e.g. R16B03):
  %% XXX:  - process marked as exiting, new messages are not delivered, name is
  %%         unregistered
  %% XXX:  - cancel timers
  %% XXX:  - transfer ets ownership and send message or delete table
  %% XXX:  - send link signals
  %% XXX:  - send monitor messages
  ?debug_flag(?loop, {going_to_exit, Reason}),
  Info = process_loop(InfoIn),
  Self = self(),
  {MaybeName, Info} =
    run_built_in(erlang, process_info, 2, [Self, registered_name], Info),
  LocatedInfo = #concuerror_info{event = Event} =
    add_location_info(exit, set_status(Info, exiting)),
  #concuerror_info{
     links = LinksTable,
     monitors = MonitorsTable,
     flags = #process_flags{trap_exit = Trapping}} = Info,
  FetchFun =
    fun(Table) ->
        [begin ets:delete_object(Table, E), {D, S} end ||
          {_, D, S} = E <- ets:lookup(Table, Self)]
    end,
  Links = FetchFun(LinksTable),
  Monitors = FetchFun(MonitorsTable),
  Name =
    case MaybeName of
      [] -> ?process_name_none;
      {registered_name, N} -> N
    end,
  Notification =
    Event#event{
      event_info =
        #exit_event{
           links = [L || {L, _} <- Links],
           monitors = [M || {M, _} <- Monitors],
           name = Name,
           reason = Reason,
           stacktrace = Stacktrace,
           status = Status,
           trapping = Trapping
          }
     },
  ExitInfo = add_location_info(exit, notify(Notification, LocatedInfo)),
  FunFold = fun(Fun, Acc) -> Fun(Acc) end,
  FunList =
    [fun ets_ownership_exiting_events/1,
     link_monitor_handlers(fun handle_link/3, Links),
     link_monitor_handlers(fun handle_monitor/3, Monitors)],
  FinalInfo =
    lists:foldl(FunFold, ExitInfo#concuerror_info{exit_reason = Reason}, FunList),
  ?debug_flag(?loop, exited),
  process_loop(set_status(FinalInfo, exited)).

ets_ownership_exiting_events(Info) ->
  %% XXX:  - transfer ets ownership and send message or delete table
  %% XXX: Mention that order of deallocation/transfer is not monitored.
  #concuerror_info{ets_tables = EtsTables} = Info,
  case ets:match(EtsTables, ?ets_match_owner_to_name_heir(self())) of
    [] -> Info;
    UnsortedTables ->
      Tables = lists:sort(UnsortedTables),
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
              {_, OtherInfo} ->
                ?debug_flag(?heir, {problematic_heir, Tid, HeirSpec}),
                {{didit, true}, NewInfo} =
                  instrumented(call, [ets, delete, [Tid]], exit, OtherInfo),
                NewInfo
            end
        end,
      lists:foldl(Fold, Info, Tables)
  end.

handle_link(Link, Reason, InfoIn) ->
  MFArgs = [erlang, exit, [Link, Reason]],
  {{didit, true}, NewInfo} =
    instrumented(call, MFArgs, exit, InfoIn),
  NewInfo.

handle_monitor({Ref, P, As}, Reason, InfoIn) ->
  Msg = {'DOWN', Ref, process, As, Reason},
  MFArgs = [erlang, send, [P, Msg]],
  {{didit, Msg}, NewInfo} =
    instrumented(call, MFArgs, exit, InfoIn),
  NewInfo.

link_monitor_handlers(Handler, LinksOrMonitors) ->
  fun(Info) ->
      #concuerror_info{exit_reason = Reason} = Info,
      HandleActive =
        fun({LinkOrMonitor, S}, InfoIn) ->
            case S =:= active of
              true -> Handler(LinkOrMonitor, Reason, InfoIn);
              false -> InfoIn
            end
        end,
      lists:foldl(HandleActive, Info, LinksOrMonitors)
  end.

%%------------------------------------------------------------------------------

check_ets_access_rights(Name, Op, Info) ->
  #concuerror_info{ets_tables = EtsTables, scheduler = Scheduler} = Info,
  case ets:match(EtsTables, ?ets_match_name(Name)) of
    [] -> error(badarg);
    [[Tid,Owner,Protection]] ->
      Test =
        (Owner =:= self()
         orelse
         case ets_ops_access_rights_map(Op) of
           none  -> true;
           own   -> false;
           read  -> Protection =/= private;
           write -> Protection =:= public
         end),
      ?badarg_if_not(Test),
      System =
        (Owner =:= Scheduler) andalso
        case element(1, Op) of
          insert -> true;
          insert_new -> true;
          _ -> false
        end,
      {Tid, System}
  end.

ets_ops_access_rights_map(Op) ->
  case Op of
    {delete        ,1} -> own;
    {delete        ,2} -> write;
    {delete_object ,2} -> write;
    {first         ,_} -> read;
    {give_away     ,_} -> own;
    {info          ,_} -> none;
    {insert        ,_} -> write;
    {insert_new    ,_} -> write;
    {lookup        ,_} -> read;
    {lookup_element,_} -> read;
    {match         ,_} -> read;
    {match_object  ,_} -> read;
    {member        ,_} -> read;
    {next          ,_} -> read;
    {select        ,_} -> read;
    {select_delete ,_} -> write;
    {update_counter,3} -> write                            
  end.

%%------------------------------------------------------------------------------

system_ets_entries(#concuerror_info{ets_tables = EtsTables}) ->
  Map = fun(Tid) -> ?new_system_ets_table(Tid, ets:info(Tid, protection)) end,
  ets:insert(EtsTables, [Map(Tid) || Tid <- ets:all(), is_atom(Tid)]).

system_processes_wrappers(Info) ->
  Ordered = [user],
  Registered =
    Ordered ++ (lists:sort(registered() -- Ordered)),
  [whereis(Name) ||
    Name <- Registered,
    hijacked =:= hijack_or_wrap_system(Name, Info)].

%% XXX: Application controller support needs to be checked
hijack_or_wrap_system(Name, Info)
  when Name =:= application_controller_disabled ->
  #concuerror_info{
     logger = Logger,
     modules = Modules,
     timeout = Timeout} = Info,
  Pid = whereis(Name),
  link(Pid),
  ok = concuerror_loader:load(gen_server, Modules),
  ok = sys:suspend(Name),
  Notify =
    reset_concuerror_info(
      Info#concuerror_info{notify_when_ready = {self(), true}}),
  concuerror_inspect:hijack(Name, Notify),
  ok = sys:resume(Name),
  wait_process(Name, Timeout),
  ?log(Logger, ?linfo, "Hijacked ~p~n", [Name]),
  hijacked;  
hijack_or_wrap_system(Name, Info) ->
  #concuerror_info{processes = Processes} = Info,
  Fun = fun() -> system_wrapper_loop(Name, whereis(Name), Info) end,
  Pid = spawn_link(Fun),
  ets:insert(Processes, ?new_system_process(Pid, Name, wrapper)),
  wrapped.

system_wrapper_loop(Name, Wrapped, Info) ->
  receive
    Message ->
      case Message of
        {message,
         #message{data = Data, id = Id}, Report} ->
          try
            {F, R} =
              case Name of
                code_server ->
                  case Data of
                    {Call, From, Request} ->
                      check_request(Name, Request),
                      erlang:send(Wrapped, {Call, self(), Request}),
                      receive
                        Msg -> {From, Msg}
                      end
                  end;
                erl_prim_loader ->
                  case Data of
                    {From, Request} ->
                      check_request(Name, Request),
                      erlang:send(Wrapped, {self(), Request}),
                      receive
                        {_, Msg} -> {From, {self(), Msg}}
                      end
                  end;
                error_logger ->
                  %% erlang:send(Wrapped, Data),
                  throw(no_reply);
                file_server_2 ->
                  case Data of
                    {Call, {From, Ref}, Request} ->
                      check_request(Name, Request),
                      erlang:send(Wrapped, {Call, {self(), Ref}, Request}),
                      receive
                        Msg -> {From, Msg}
                      end
                  end;
                init ->
                  {From, Request} = Data,
                  check_request(Name, Request),
                  erlang:send(Wrapped, {self(), Request}),
                  receive
                    Msg -> {From, Msg}
                  end;
                standard_error ->
                  #concuerror_info{logger = Logger} = Info,
                  {From, Reply, _} = handle_io(Data, {standard_error, Logger}),
                  Msg =
                    "Your test sends messages to the 'standard_error' process to"
                    " write output. Such messages from different processes may"
                    " race, producing spurious interleavings. Consider using"
                    " '--non_racing_system standard_error' to avoid them.~n",
                  ?unique(Logger, ?ltip, Msg, []),
                  {From, Reply};
                user ->
                  #concuerror_info{logger = Logger} = Info,
                  {From, Reply, _} = handle_io(Data, {standard_io, Logger}),
                  Msg =
                    "Your test sends messages to the 'user' process to write"
                    " output. Such messages from different processes may race,"
                    " producing spurious interleavings. Consider using"
                    " '--non_racing_system user' to avoid them.~n",
                  ?unique(Logger, ?ltip, Msg, []),
                  {From, Reply};
                Else ->
                  ?crash({unknown_protocol_for_system, Else})
              end,
            Report ! {system_reply, F, Id, R, Name},
            ok
          catch
            exit:{?MODULE, _} = Reason -> exit(Reason);
            throw:no_reply ->
              Report ! {trapping, false},
              ok;
            Type:Reason ->
              Stacktrace = erlang:get_stacktrace(),
              ?crash({system_wrapper_error, Name, Type, Reason, Stacktrace})
          end
      end
  end,
  system_wrapper_loop(Name, Wrapped, Info).

check_request(code_server, get_path) -> ok;
check_request(code_server, {ensure_loaded, _}) -> ok;
check_request(code_server, {is_cached, _}) -> ok;
check_request(code_server, {is_loaded, _}) -> ok;
check_request(erl_prim_loader, {get_file, _}) -> ok;
check_request(erl_prim_loader, {list_dir, _}) -> ok;
check_request(file_server_2, {get_cwd}) -> ok;
check_request(file_server_2, {read_file_info, _}) -> ok;
check_request(init, {get_argument, _}) -> ok;
check_request(init, get_arguments) -> ok;
check_request(Name, Other) ->
  ?crash({unsupported_request, Name, try element(1,Other) catch _:_ -> Other end}).

reset_concuerror_info(Info) ->
  #concuerror_info{
     after_timeout = AfterTimeout,
     ets_tables = EtsTables,
     instant_delivery = InstantDelivery,
     is_timer = IsTimer,
     links = Links,
     logger = Logger,
     modules = Modules,
     monitors = Monitors,
     notify_when_ready = {Pid, _},
     processes = Processes,
     scheduler = Scheduler,
     system_ets_entries = SystemEtsEntries,
     timeout = Timeout,
     timers = Timers
    } = Info,
  #concuerror_info{
     after_timeout = AfterTimeout,
     ets_tables = EtsTables,
     instant_delivery = InstantDelivery,
     is_timer = IsTimer,
     links = Links,
     logger = Logger,
     modules = Modules,
     monitors = Monitors,
     notify_when_ready = {Pid, true},
     processes = Processes,
     scheduler = Scheduler,
     system_ets_entries = SystemEtsEntries,
     timeout = Timeout,
     timers = Timers
    }.

%% reset_stack(#concuerror_info{stack = Stack} = Info) ->
%%   {Stack, Info#concuerror_info{stack = []}}.

%% append_stack(Value, #concuerror_info{stack = Stack} = Info) ->
%%   Info#concuerror_info{stack = [Value|Stack]}.

%%------------------------------------------------------------------------------

add_location_info(Location, #concuerror_info{event = Event} = Info) ->
  Info#concuerror_info{event = Event#event{location = Location}}.

set_status(#concuerror_info{processes = Processes} = Info, Status) ->
  MaybeDropName =
    case Status =:= exiting of
      true -> [{?process_name, ?process_name_none}];
      false -> []
    end,
  Updates = [{?process_status, Status}|MaybeDropName],
  true = ets:update_element(Processes, self(), Updates),
  Info#concuerror_info{status = Status}.

is_active(#concuerror_info{caught_signal = CaughtSignal, status = Status}) ->
  not CaughtSignal andalso is_active(Status);
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

%%------------------------------------------------------------------------------

handle_io({io_request, From, ReplyAs, Req}, IOState) ->
  {Reply, NewIOState} = io_request(Req, IOState),
  {From, {io_reply, ReplyAs, Reply}, NewIOState};
handle_io(_, _) ->
  throw(no_reply).

io_request({put_chars, Chars}, {Tag, Data} = IOState) ->
  case is_atom(Tag) of
    true ->
      Logger = Data,
      concuerror_logger:print(Logger, Tag, Chars),
      {ok, IOState}
  end;
io_request({put_chars, M, F, As}, IOState) ->
  try apply(M, F, As) of
      Chars -> io_request({put_chars, Chars}, IOState)
  catch
    _:_ -> {{error, request}, IOState}
  end;
io_request({put_chars, _Enc, Chars}, IOState) ->
    io_request({put_chars, Chars}, IOState);
io_request({put_chars, _Enc, Mod, Func, Args}, IOState) ->
    io_request({put_chars, Mod, Func, Args}, IOState);
%% io_request({get_chars, _Enc, _Prompt, _N}, IOState) ->
%%     {eof, IOState};
%% io_request({get_chars, _Prompt, _N}, IOState) ->
%%     {eof, IOState};
%% io_request({get_line, _Prompt}, IOState) ->
%%     {eof, IOState};
%% io_request({get_line, _Enc, _Prompt}, IOState) ->
%%     {eof, IOState};
%% io_request({get_until, _Prompt, _M, _F, _As}, IOState) ->
%%     {eof, IOState};
%% io_request({setopts, _Opts}, IOState) ->
%%     {ok, IOState};
%% io_request(getopts, IOState) ->
%%     {error, {error, enotsup}, IOState};
%% io_request({get_geometry,columns}, IOState) ->
%%     {error, {error, enotsup}, IOState};
%% io_request({get_geometry,rows}, IOState) ->
%%     {error, {error, enotsup}, IOState};
%% io_request({requests, Reqs}, IOState) ->
%%     io_requests(Reqs, {ok, IOState});
io_request(_, IOState) ->
    {{error, request}, IOState}.

%% io_requests([R | Rs], {ok, IOState}) ->
%%     io_requests(Rs, io_request(R, IOState));
%% io_requests(_, Result) ->
%%     Result.

%%------------------------------------------------------------------------------

-spec explain_error(term()) -> string().

explain_error({checking_system_process, Pid}) ->
  io_lib:format(
    "A process tried to link/monitor/inspect process ~p which was not"
    " started by Concuerror and has no suitable wrapper to work with"
    " Concuerror.~n"
    ?notify_us_msg,
    [Pid]);
explain_error({inconsistent_builtin,
               [Module, Name, Arity, Args, OldResult, NewResult, Location]}) ->
  io_lib:format(
    "While re-running the program, a call to ~p:~p/~p with"
    " arguments:~n  ~p~nreturned a different result:~n"
    "Earlier result: ~p~n"
    "  Later result: ~p~n"
    "Concuerror cannot explore behaviours that depend on~n"
    "data that may differ on separate runs of the program.~n"
    "Location: ~p~n~n",
    [Module, Name, Arity, Args, OldResult, NewResult, Location]);
explain_error({no_response_for_message, Timeout, Recipient}) ->
  io_lib:format(
    "A process took more than ~pms to send an acknowledgement for a message"
    " that was sent to it. (Process: ~p)~n"
    ?notify_us_msg,
    [Timeout, Recipient]);
explain_error({not_local_node, Node}) ->
  io_lib:format(
    "A built-in tried to use ~p as a remote node. Concuerror does not support"
    " remote nodes yet.",
    [Node]);
explain_error({process_did_not_respond, Timeout, Actor}) ->
  io_lib:format( 
    "A process took more than ~pms to report a built-in event. You can try to"
    " increase the --timeout limit and/or ensure that there are no infinite"
    " loops in your test. (Process: ~p)",
    [Timeout, Actor]
   );
explain_error({system_wrapper_error, Name, Type, Reason, Stacktrace}) ->
  io_lib:format(
    "Concuerror's wrapper for system process ~p crashed (~p):~n"
    "  Reason: ~p~n"
    "Stacktrace:~n"
    " ~p~n"
    ?notify_us_msg,
    [Name, Type, Reason, Stacktrace]);
explain_error({unexpected_builtin_change,
               [Module, Name, Arity, Args, M, F, OArgs, Location]}) ->
  io_lib:format(
    "While re-running the program, a call to ~p:~p/~p with"
    " arguments:~n  ~p~nwas found instead of the original call~n"
    "to ~p:~p/~p with args:~n  ~p~n"
    "Concuerror cannot explore behaviours that depend on~n"
    "data that may differ on separate runs of the program.~n"
    "Location: ~p~n~n",
    [Module, Name, Arity, Args, M, F, length(OArgs), OArgs, Location]);
explain_error({unknown_protocol_for_system, System}) ->
  io_lib:format(
    "A process tried to send a message to system process ~p. Concuerror does"
    " not currently support communication with this process. Please contact the"
    " developers for more information.",[System]);
explain_error({unknown_built_in, {Module, Name, Arity, Location}}) ->
  LocationString =
    case Location of
      [Line, {file, File}] -> location(File, Line);
      _ -> ""
    end,
  io_lib:format(
    "Concuerror does not currently support calls to built-in ~p:~p/~p~s."
    " Please notify the developers.",
    [Module, Name, Arity, LocationString]);
explain_error({unsupported_request, Name, Type}) ->
  io_lib:format(
    "A process send a request of type '~p' to ~p. Concuerror does not yet support"
    " this type of request to this process.~n"
    ?notify_us_msg,
    [Type, Name]).

location(F, L) ->
  Basename = filename:basename(F),
  io_lib:format(" (found in ~s line ~w)", [Basename, L]).
