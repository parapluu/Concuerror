%% -*- erlang-indent-level: 2 -*-

-module(concuerror_callback).

%% Interface to concuerror_inspect:
-export([instrumented/4, hijack_backend/1]).

%% Interface to scheduler:
-export([spawn_first_process/1, start_first_process/3,
         deliver_message/3, wait_actor_reply/2, collect_deadlock_info/1,
         enabled/1, reset_processes/1, cleanup_processes/1]).

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

-define(crash_instr(Reason), exit(self(), {?MODULE, Reason})).
-define(crash(Reason), exit({?MODULE, Reason})).

-ifdef(BEFORE_OTP_17).
-type ref_queue() :: queue().
-type message_queue() :: queue().
-else.
-type ref_queue() :: queue:queue(reference()).
-type message_queue() :: queue:queue(#message{}).
-endif.

-type ref_queue_2() :: {ref_queue(), ref_queue()}.

-type status() :: 'running' | 'waiting' | 'exiting' | 'exited'.

-record(process_flags, {
          trap_exit = false  :: boolean(),
          priority  = normal :: 'low' | 'normal' | 'high' | 'max'
         }).

-record(concuerror_info, {
          after_timeout               :: 'infinite' | integer(),
          delayed_notification = none :: 'none' | {'true', term()},
          demonitors = []             :: [reference()],
          ets_tables                  :: ets_tables(),
          exit_by_signal = false      :: boolean(),
          exit_reason = normal        :: term(),
          extra                       :: term(),
          flags = #process_flags{}    :: #process_flags{},
          instant_delivery            :: boolean(),
          is_timer = false            :: 'false' | reference(),
          links                       :: links(),
          logger                      :: pid(),
          message_counter = 1         :: pos_integer(),
          messages_new = queue:new()  :: message_queue(),
          messages_old = queue:new()  :: message_queue(),
          monitors                    :: monitors(),
          event = none                :: 'none' | event(),
          notify_when_ready           :: {pid(), boolean()},
          processes                   :: processes(),
          ref_queue = new_ref_queue() :: ref_queue_2(),
          scheduler                   :: pid(),
          stacktop = 'none'           :: 'none' | tuple(),
          status = 'running'          :: status(),
          system_ets_entries          :: ets:tid(),
          timeout                     :: timeout(),
          timers                      :: timers()
         }).

-type concuerror_info() :: #concuerror_info{}.

%%------------------------------------------------------------------------------

-spec spawn_first_process(concuerror_options:options()) -> {pid(), [pid()]}.

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
       monitors       = ets:new(monitors, [bag, public]),
       notify_when_ready = {self(), true},
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
  {DefLeader, _} = run_built_in(erlang, whereis, 1, [user], Info),
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
  concuerror_inspect:start_inspection({logger, Processes}).

-spec hijack_backend(concuerror_info()) -> ok.

hijack_backend(#concuerror_info{processes = Processes} = Info) ->
  true = group_leader() =:= whereis(user),
  {GroupLeader, _} = run_built_in(erlang,whereis,1,[user], Info),
  {registered_name, Name} = process_info(self(), registered_name),
  true = ets:insert(Processes, ?new_system_process(self(), Name, hijacked)),
  {true, Info} =
    run_built_in(erlang, group_leader, 2, [GroupLeader, self()], Info),
  concuerror_inspect:start_inspection(Info),
  ok.

%%------------------------------------------------------------------------------

-type instrumented_return() :: 'doit' |
                               {'didit', term()} |
                               {'error', term()} |
                               {'skip_timeout', 'false' | {'true', term()}} |
                               'unhijack'.

-spec instrumented(Tag      :: instrumented_tag(),
                   Args     :: [term()],
                   Location :: term(),
                   Info     :: concuerror_info()) ->
                      {instrumented_return(), concuerror_info()}.

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
instrumented('receive', [PatternFun, RealTimeout], Location, Info) ->
  case Info of
    #concuerror_info{after_timeout = AfterTimeout} ->
      Timeout =
        case RealTimeout =:= infinity orelse RealTimeout >= AfterTimeout of
          false -> RealTimeout;
          true -> infinity
        end,
      handle_receive(PatternFun, Timeout, Location, Info);
    _Logger ->
      {doit, Info}
  end.

instrumented_aux(Module, Name, Arity, Args, _Location,
                 {logger, Processes} = Info) ->
  case {Module, Name, Arity} of
    {erlang, pid_to_list, 1} ->
      [Term] = Args,
      try
        Symbol = ets:lookup_element(Processes, Term, ?process_symbolic),
        {{didit, Symbol}, Info}
      catch
        _:_ -> {doit, Info}
      end;
    {erlang, fun_to_list, 1} ->
      %% Slightly prettier printer than the default...
      [Fun] = Args,
      [M, F, A] =
        [I ||
          {_, I} <-
            [erlang:fun_info(Fun, T) || T <- [module, name, arity]]],
      String = lists:flatten(io_lib:format("#Fun<~p.~p.~p>", [M, F, A])),
      {{didit, String}, Info};
    _ ->
      {doit, Info}
  end;
instrumented_aux(erlang, apply, 3, [Module, Name, Args], Location, Info) ->
  instrumented_aux(Module, Name, length(Args), Args, Location, Info);
instrumented_aux(Module, Name, Arity, Args, Location, Info)
  when is_atom(Module) ->
  case
    erlang:is_builtin(Module, Name, Arity) andalso
    concuerror_instrumenter:is_unsafe({Module, Name, Arity})
  of
    true ->
      built_in(Module, Name, Arity, Args, Location, Info);
    false ->
      case Info of
        #concuerror_info{logger = Logger} ->
          ?debug_flag(?non_builtin,{Module,Name,Arity,Location}),
          ?autoload_and_log(Module, Logger);
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

built_in(erlang, Display, 1, [Term], _Location, Info)
  when Display =:= display; Display =:= display_string ->
  ?debug_flag(?builtin, {'built-in', erlang, Display, 1, [Term], _Location}),
  Chars =
    case Display of
      display -> io_lib:format("~w~n",[Term]);
      display_string ->
        _ = erlang:list_to_atom(Term), % Will throw badarg if not string.
        Term
    end,
  concuerror_logger:print(Info#concuerror_info.logger, standard_io, Chars),
  {{didit, true}, Info};
%% Process dictionary has been restored here. No need to report such ops.
built_in(erlang, Name, _Arity, Args, _Location, Info)
  when Name =:= get; Name =:= get_keys; Name =:= put; Name =:= erase ->
  try
    {{didit, erlang:apply(erlang, Name, Args)}, Info}
  catch
    error:Reason -> {{error, Reason}, Info}
  end;
%% XXX: Temporary
built_in(erlang, get_stacktrace, 0, [], _Location, Info) ->
  #concuerror_info{logger = Logger} = Info,
  Msg =
    "Concuerror does not fully support erlang:get_stacktrace/0, returning an"
    " empty list instead. If you need proper support, notify the developers to"
    " add this feature.~n",
  ?unique(Logger, ?lwarning, Msg, []),
  {{didit, []}, Info};
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
  SaneOptions =
    try
      [] =:= [O || O <- Options, O =/= flush, O =/= info]
    catch
      _:_ -> false
    end,
  ?badarg_if_not(SaneOptions),
  #concuerror_info{demonitors = Demonitors, monitors = Monitors} = Info,
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
  FinalInfo = NewInfo#concuerror_info{demonitors = [Ref|Demonitors]},
  case lists:member(info, Options) of
    true -> {Result, FinalInfo};
    false -> {true, FinalInfo}
  end;
run_built_in(erlang, exit, 2, [Pid, Reason],
             #concuerror_info{
                event = #event{event_info = EventInfo} = Event
               } = Info) ->
  ?badarg_if_not(is_pid(Pid)),
  case EventInfo of
    %% Replaying...
    #builtin_event{result = OldResult} ->
      {_, MsgInfo} = get_message_cnt(Info),
      {OldResult, MsgInfo};
    %% New event...
    undefined ->
      Content =
        case Event#event.location =/= exit andalso Reason =:= kill of
          true -> kill;
          false ->
            #concuerror_info{flags = #process_flags{trap_exit = Trapping}} = Info,
            case Pid =/= self() orelse Reason =/= normal orelse Trapping of
              true -> ok;
              false ->
                Message = msg(exit_normal_self_abnormal),
                Logger = Info#concuerror_info.logger,
                ?unique(Logger, ?lwarning, Message, [Pid])
            end,
            make_exit_signal(Reason)
        end,
      MsgInfo = make_message(Info, exit_signal, Content, Pid),
      {true, MsgInfo}
  end;

run_built_in(erlang, group_leader, 0, [], Info) ->
  Leader = get_leader(Info, self()),
  {Leader, Info};

run_built_in(erlang, group_leader, 2, [GroupLeader, Pid],
             #concuerror_info{processes = Processes} = Info) ->
  try
    {true, Info} = run_built_in(erlang, is_process_alive, 1, [Pid], Info),
    {true, Info} = run_built_in(erlang, is_process_alive, 1, [GroupLeader], Info),
    ok
  catch
    _:_ -> error(badarg)
  end,
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
      [] -> ?crash_instr({checking_system_process, Pid});
      [?process_pat_pid_status(Pid, Status)] -> is_active(Status)
    end,
  {Return, Info};

run_built_in(erlang, link, 1, [Pid], Info) ->
  #concuerror_info{
     flags = #process_flags{trap_exit = TrapExit},
     links = Links,
     event = #event{event_info = EventInfo}
    } = Info,
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
              #builtin_event{} ->
                {_, MsgInfo} = get_message_cnt(Info),
                MsgInfo;
              %% New event...
              undefined ->
                Signal = make_exit_signal(Pid, noproc),
                make_message(Info, message, Signal, self())
            end,
          {true, NewInfo}
      end
  end;

run_built_in(erlang, make_ref, 0, [], Info) ->
  #concuerror_info{event = #event{event_info = EventInfo}} = Info,
  {MaybeRef, NewInfo} = get_ref(Info),
  case EventInfo of
    %% Replaying...
    #builtin_event{result = MaybeRef} -> ok;
    %% New event...
    undefined -> ok
  end,
  {MaybeRef, NewInfo};
run_built_in(erlang, monitor, 2, [Type, InTarget], Info) ->
  #concuerror_info{
     monitors = Monitors,
     event = #event{event_info = EventInfo}
    } = Info,
  ?badarg_if_not(Type =:= process),
  {Target, As} =
    case InTarget of
      P when is_pid(P) -> {InTarget, InTarget};
      A when is_atom(A) -> {InTarget, {InTarget, node()}};
      {Name, Node} = Local when is_atom(Name), Node =:= node() ->
        {Name, Local};
      {Name, Node} when is_atom(Name) -> ?crash_instr({not_local_node, Node});
      _ -> error(badarg)
    end,
  {Ref, NewInfo} = get_ref(Info),
  case EventInfo of
    %% Replaying...
    #builtin_event{result = Ref} -> ok;
    %% New event...
    undefined -> ok
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
  FinalInfo =
    case IsActive of
      true -> NewInfo;
      false ->
        case EventInfo of
          %% Replaying...
          #builtin_event{} ->
            {_, MsgInfo} = get_message_cnt(NewInfo),
            MsgInfo;
          %% New event...
          undefined ->
            Data = {'DOWN', Ref, process, As, noproc},
            make_message(NewInfo, message, Data, self())
        end
    end,
  {Ref, FinalInfo};
run_built_in(erlang, process_info, 2, [Pid, Item], Info) when is_atom(Item) ->
  {Alive, _} = run_built_in(erlang, is_process_alive, 1, [Pid], Info),
  case Alive of
    false -> {undefined, Info};
    true ->
      {TheirInfo, TheirDict} =
        case Pid =:= self() of
          true -> {Info, get()};
          false -> get_their_info(Pid)
        end,
      Res =
        case Item of
          dictionary ->
            TheirDict;
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
          message_queue_len ->
            #concuerror_info{messages_new = Queue} = TheirInfo,
            queue:len(Queue);
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
run_built_in(erlang, register, 2, [Name, Pid], Info) ->
  #concuerror_info{
     logger = Logger,
     processes = Processes
    } = Info,
  case Name of
    eunit_server ->
      ?unique(Logger, ?lwarning, msg(register_eunit_server), []);
    _ -> ok
  end,
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
          Pid ! {exit_signal, #message{data = kill, id = hidden}, self()},
          {false, true, false} = receive_message_ack(),
          ok
      end,
      {1, Info}
  end;

run_built_in(erlang, SendAfter, 3, [0, Dest, Msg], Info)
  when
    SendAfter =:= send_after;
    SendAfter =:= start_timer ->
  #concuerror_info{
     event = #event{event_info = EventInfo}} = Info,
  {Ref, NewInfo} = get_ref(Info),
  case EventInfo of
    %% Replaying...
    #builtin_event{result = Ref} -> ok;
    %% New event...
    undefined -> ok
  end,
  ActualMessage =
    case SendAfter of
      send_after -> Msg;
      start_timer -> {timeout, Ref, Msg}
    end,
  {_, FinalInfo} = run_built_in(erlang, send, 2, [Dest, ActualMessage], NewInfo),
  {Ref, FinalInfo};

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
  {Ref, NewInfo} = get_ref(Info),
  {Pid, FinalInfo} =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = Ref, extra = OldPid} ->
        {OldPid, NewInfo#concuerror_info{extra = OldPid}};
      %% New event...
      undefined ->
        Symbol = "Timer " ++ erlang:ref_to_list(Ref),
        P =
          case
            ets:match(Processes, ?process_match_symbol_to_pid(Symbol))
          of
            [] ->
              PassedInfo = reset_concuerror_info(NewInfo),
              TimerInfo =
                PassedInfo#concuerror_info{
                  instant_delivery = true,
                  is_timer = Ref
                 },
              NewP = new_process(TimerInfo),
              true = ets:insert(Processes, ?new_process(NewP, Symbol)),
              NewP;
            [[OldP]] -> OldP
          end,
        NewEvent = Event#event{special = [{new, P}]},
        {P, NewInfo#concuerror_info{event = NewEvent, extra = P}}
    end,
  ActualMessage =
    case SendAfter of
      send_after -> Msg;
      start_timer -> {timeout, Ref, Msg}
    end,
  ets:insert(Timers, {Ref, Pid, Dest}),
  TimerFun =
    fun() ->
        catch concuerror_inspect:inspect(call, [erlang, send, [Dest, ActualMessage]], foo)
    end,
  Pid ! {start, erlang, apply, [TimerFun, []]},
  wait_process(Pid, Wait),
  {Ref, FinalInfo};

run_built_in(erlang, SendAfter, 4, [Timeout, Dest, Msg, []], Info)
  when
    SendAfter =:= send_after;
    SendAfter =:= start_timer ->
  run_built_in(erlang, SendAfter, 3, [Timeout, Dest, Msg], Info);

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
  {HasMonitor, NewInfo} =
    case lists:member(monitor, SpawnOpts) of
      false -> {false, Info};
      true -> get_ref(Info)
    end,
  {Result, FinalInfo} =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} ->
        case HasMonitor of
          false -> ok;
          Mon ->
            {_, Mon} = OldResult,
            ok
        end,
        {OldResult, NewInfo};
      %% New event...
      undefined ->
        PassedInfo = reset_concuerror_info(NewInfo),
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
          case HasMonitor of
            false -> P;
            Mon -> {P, Mon}
          end,
        NewEvent = Event#event{special = [{new, P}]},
        {NewResult, NewInfo#concuerror_info{event = NewEvent}}
    end,
  Pid =
    case HasMonitor of
      false ->
        Result;
      Ref ->
        {P1, Ref} = Result,
        #concuerror_info{monitors = Monitors} = FinalInfo,
        true = ets:insert(Monitors, ?monitor(Ref, P1, P1, active)),
        P1
    end,
  case lists:member(link, SpawnOpts) of
    true ->
      #concuerror_info{links = Links} = FinalInfo,
      true = ets:insert(Links, ?links(Parent, Pid));
    false -> ok
  end,
  {GroupLeader, _} = run_built_in(erlang, group_leader, 0, [], FinalInfo),
  true = ets:update_element(Processes, Pid, {?process_leader, GroupLeader}),
  Pid ! {start, Module, Name, Args},
  wait_process(Pid, Timeout),
  {Result, FinalInfo};
run_built_in(erlang, Send, 2, [Recipient, Message], Info)
  when Send =:= '!'; Send =:= 'send' ->
  run_built_in(erlang, send, 3, [Recipient, Message, []], Info);
run_built_in(erlang, send, 3, [Recipient, Message, _Options], Info) ->
  #concuerror_info{event = #event{event_info = EventInfo}} = Info,
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
  ?badarg_if_not(is_pid(Pid)),
  Extra =
    case Info#concuerror_info.is_timer of
      false -> undefined;
      Timer ->
        ets:delete(Info#concuerror_info.timers, Timer),
        Timer
    end,
  case EventInfo of
    %% Replaying...
    #builtin_event{result = OldResult} ->
      {_, MsgInfo} = get_message_cnt(Info),
      {OldResult, MsgInfo#concuerror_info{extra = Extra}};
    %% New event...
    undefined ->
      ?debug_flag(?send, {send, Recipient, Message}),
      MsgInfo = make_message(Info, message, Message, Pid),
      ?debug_flag(?send, {send, successful}),
      {Message, MsgInfo#concuerror_info{extra = Extra}}
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
run_built_in(erlang, whereis, 1, [Name], Info) ->
  #concuerror_info{
     logger = Logger,
     processes = Processes
    } = Info,
  case Name of
    application_controller ->
      ?unique(Logger, ?lwarning, msg(whereis_application_controller), []);
    _ -> ok
  end,
  case ets:match(Processes, ?process_match_name_to_pid(Name)) of
    [] ->
      case whereis(Name) =:= undefined of
        true -> {undefined, Info};
        false ->
          Stacktrace = fix_stacktrace(Info),
          ?crash_instr({registered_process_not_wrapped, Name, Stacktrace})
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
run_built_in(ets, info, _, [Name|Rest] = Args, Info) ->
  try
    {Tid, _} = check_ets_access_rights(Name, {info, length(Args)}, Info),
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
  #concuerror_info{event = #event{event_info = EventInfo}} = Info,
  {Tid, _} = check_ets_access_rights(Name, {give_away,3}, Info),
  #concuerror_info{ets_tables = EtsTables} = Info,
  {Alive, Info} = run_built_in(erlang, is_process_alive, 1, [Pid], Info),
  Self = self(),
  ?badarg_if_not(is_pid(Pid) andalso Pid =/= Self andalso Alive),
  NewInfo =
    case EventInfo of
      %% Replaying. Keep original message
      #builtin_event{} ->
        {_Id, MsgInfo} = get_message_cnt(Info),
        MsgInfo;
      %% New event...
      undefined ->
        Data = {'ETS-TRANSFER', Tid, Self, GiftData},
        make_message(Info, message, Data, Pid)
    end,
  Update = [{?ets_owner, Pid}],
  true = ets:update_element(EtsTables, Tid, Update),
  {true, NewInfo#concuerror_info{extra = Tid}};

run_built_in(Module, Name, Arity, Args, Info)
  when
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
              ?crash_instr({inconsistent_builtin,
                      [Module, Name, Arity, Args, OldResult, NewResult, Location]});
            false ->
              ?crash_instr({unexpected_builtin_change,
                      [Module, Name, Arity, Args, M, F, OArgs, Location]})
          end
      end;
    undefined ->
      {NewResult, Info}
  end;

run_built_in(erlang = Module, Name, Arity, Args, Info)
  when
    {Name, Arity} =:= {date, 0};
    {Name, Arity} =:= {monotonic_time, 0};
    {Name, Arity} =:= {monotonic_time, 1};
    {Name, Arity} =:= {now, 0};
    {Name, Arity} =:= {system_time, 0};
    {Name, Arity} =:= {system_time, 1};
    {Name, Arity} =:= {time, 0};
    {Name, Arity} =:= {time_offset, 0};
    {Name, Arity} =:= {time_offset, 0};
    {Name, Arity} =:= {time_offset, 1};
    {Name, Arity} =:= {timestamp, 0};
    {Name, Arity} =:= {unique_integer, 0};
    {Name, Arity} =:= {unique_integer, 1}
    ->
  maybe_reuse_old(Module, Name, Arity, Args, Info);

run_built_in(os = Module, Name, Arity, Args, Info)
  when
    {Name, Arity} =:= {timestamp, 0}
    ->
  maybe_reuse_old(Module, Name, Arity, Args, Info);

run_built_in(Module, Name, Arity, _Args,
             #concuerror_info{event = #event{location = Location}}) ->
  Clean = clean_stacktrace(),
  ?crash_instr({unknown_built_in, {Module, Name, Arity, Location, Clean}}).

clean_stacktrace() ->
  Trace = try throw(foo) catch throw:_ -> erlang:get_stacktrace() end,
  [T || {M,_,_,_} = T <- Trace, not_concuerror_module(M)].

not_concuerror_module(Atom) ->
  case atom_to_list(Atom) of
    "concuerror" ++ _ -> false;
    _ -> true
  end.

maybe_reuse_old(Module, Name, _Arity, Args, Info) ->
  #concuerror_info{event = #event{event_info = EventInfo}} = Info,
  Res =
    case EventInfo of
      %% Replaying...
      #builtin_event{result = OldResult} -> OldResult;
      %% New event...
      undefined -> erlang:apply(Module, Name, Args)
    end,
  {Res, Info}.

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
        {true, SelfTrapping} = Instant,
        SelfKilling = Type =:= exit_signal,
        send_message_ack(Self, SelfTrapping, SelfKilling, false),
        ?notify_none;
      false -> Self
    end,
  Recipient ! {Type, Message, Notify},
  receive
    {message_ack, Trapping, Killing, Ignored} ->
      NewMessageEvent =
        MessageEvent#message_event{
          killing = Killing,
          trapping = Trapping,
          ignored = Ignored
         },
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
               message = #message{data = Reply, id = {System, Id}},
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
    Timeout ->
      Pid = Event#event.actor,
      ?crash({process_did_not_respond, Timeout, Pid})
  end.

%%------------------------------------------------------------------------------

-spec reset_processes(processes()) -> ok.

reset_processes(Processes) ->
  Procs = ets:tab2list(Processes),
  Fold =
    fun(?process_pat_pid_kind(P, Kind), _) ->
        case Kind =:= regular of
          true ->
            P ! reset,
            receive reset_done -> ok end;
          false -> ok
        end,
        ok
    end,
  ok = lists:foldl(Fold, ok, Procs).

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
  after
    5000 -> ?crash({process_did_not_respond_system, P})
  end.

%%------------------------------------------------------------------------------

handle_receive(PatternFun, Timeout, Location, Info) ->
  %% No distinction between replaying/new as we have to clear the message from
  %% the queue anyway...
  case has_matching_or_after(PatternFun, Timeout, Location, Info, blocking) of
    unhijack ->
      {unhijack, Info};
    {MessageOrAfter, NewInfo} ->
      handle_receive(MessageOrAfter, PatternFun, Timeout, Location, NewInfo)
  end.

handle_receive(MessageOrAfter, PatternFun, Timeout, Location, Info) ->
  #concuerror_info{
     event = NextEvent,
     flags = #process_flags{trap_exit = Trapping}
    } = UpdatedInfo =
    add_location_info(Location, Info),
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
  AddMessage =
    case CreateMessage of
      {ok, D} ->
        ?debug_flag(?receive_, {deliver, D}),
        {true, D};
      false ->
        false
    end,
  {{skip_timeout, AddMessage}, delay_notify(Notification, UpdatedInfo)}.


has_matching_or_after(_, _, _, unhijack, _) ->
  unhijack;
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

delay_notify(Notification, Info) ->
  Info#concuerror_info{delayed_notification = {true, Notification}}.

-spec process_top_loop(concuerror_info()) -> no_return().

process_top_loop(Info) ->
  ?debug_flag(?loop, top_waiting),
  receive
    reset ->
      process_top_loop(notify(reset_done, Info));
    reset_system ->
      reset_system(Info),
      process_top_loop(notify(reset_system_done, Info));
    {start, Module, Name, Args} ->
      ?debug_flag(?loop, {start, Module, Name, Args}),
      concuerror_inspect:start_inspection(set_status(Info, running)),
      try
        concuerror_inspect:inspect(call, [Module, Name, Args], start),
        exit(normal)
      catch
        Class:Reason ->
          case concuerror_inspect:stop_inspection() of
            {true, EndInfo} ->
              Stacktrace = fix_stacktrace(EndInfo),
              ?debug_flag(?exit, {exit, Class, Reason, Stacktrace}),
              NewReason =
                case Class of
                  throw -> {{nocatch, Reason}, Stacktrace};
                  error -> {Reason, Stacktrace};
                  exit  -> Reason
                end,
              exiting(NewReason, Stacktrace, EndInfo);
            false -> exit(Reason)
          end
      end
  end.

request_system_reset(Pid) ->
  Pid ! reset_system,
  receive
    reset_system_done -> ok
  end.

reset_system(Info) ->
  #concuerror_info{system_ets_entries = SystemEtsEntries} = Info,
  Entries = ets:tab2list(SystemEtsEntries),
  lists:foldl(fun delete_system_entries/2, true, Entries),
  ets:delete_all_objects(SystemEtsEntries).

delete_system_entries({T, Objs}, true) when is_list(Objs) ->
  lists:foldl(fun delete_system_entries/2, true, [{T, O} || O <- Objs]);
delete_system_entries({T, O}, true) ->
  ets:delete_object(T, O).

new_process(ParentInfo) ->
  Info = ParentInfo#concuerror_info{notify_when_ready = {self(), true}},
  spawn_link(?MODULE, process_top_loop, [Info]).

wait_process(Pid, Timeout) ->
  %% Wait for the new process to instrument any code.
  receive
    ready -> ok
  after
    Timeout ->
      ?crash({process_did_not_respond, Timeout, Pid})
  end.


process_loop(#concuerror_info{delayed_notification = {true, Notification},
                              scheduler = Scheduler} = Info) ->
  Scheduler ! Notification,
  process_loop(Info#concuerror_info{delayed_notification = none});
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
              send_message_ack(Notify, Trapping, true, false),
              exiting(killed, [], Info#concuerror_info{exit_by_signal = true});
            false ->
              case Trapping of
                true ->
                  ?debug_flag(?loop, signal_trapped),
                  self() ! {message, Message, Notify},
                  process_loop(Info);
                false ->
                  {'EXIT', From, Reason} = Data,
                  send_message_ack(Notify, Trapping, Reason =/= normal, false),
                  case Reason =:= normal andalso From =/= self() of
                    true ->
                      ?debug_flag(?loop, ignore_normal_signal),
                      process_loop(Info);
                    false ->
                      ?debug_flag(?loop, error_signal),
                      NewInfo = Info#concuerror_info{exit_by_signal = true},
                      exiting(Reason, [], NewInfo)
                  end
              end
          end;
        false ->
          ?debug_flag(?loop, ignoring_signal),
          send_message_ack(Notify, Trapping, false, false),
          process_loop(Info)
      end;
    {message, Message, Notify} ->
      ?debug_flag(?loop, message),
      Trapping = Info#concuerror_info.flags#process_flags.trap_exit,
      NotDemonitored = not_demonitored(Message, Info),
      send_message_ack(Notify, Trapping, false, not NotDemonitored),
      case is_active(Info) andalso NotDemonitored of
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
      ResetInfo =
        #concuerror_info{
           ets_tables = EtsTables,
           links = Links,
           monitors = Monitors,
           processes = Processes} = reset_concuerror_info(Info),
      NewInfo = set_status(ResetInfo, exited),
      _ = erase(),
      Symbol = ets:lookup_element(Processes, self(), ?process_symbolic),
      ets:insert(Processes, ?new_process(self(), Symbol)),
      {DefLeader, _} = run_built_in(erlang,whereis,1,[user],Info),
      true = ets:update_element(Processes, self(), {?process_leader, DefLeader}),
      ets:match_delete(EtsTables, ?ets_match_mine()),
      ets:match_delete(Links, ?links_match_mine()),
      ets:match_delete(Monitors, ?monitors_match_mine()),
      FinalInfo = NewInfo#concuerror_info{ref_queue = reset_ref_queue(Info)},
      _ = notify(reset_done, FinalInfo),
      erlang:hibernate(concuerror_callback, process_top_loop, [FinalInfo]);
    deadlock_poll ->
      ?debug_flag(?loop, deadlock_poll),
      Status = Info#concuerror_info.status,
      case Status =:= exited of
        true -> process_loop(notify(exited, Info));
        false -> Info
      end;
    enabled ->
      Status = Info#concuerror_info.status,
      Reply = Status =:= running orelse Status =:= exiting,
      process_loop(notify({enabled, Reply}, Info));
    {get_info, To} ->
      To ! {info, {Info, get()}},
      process_loop(Info);
    unhijack ->
      unhijack;
    quit ->
      exit(normal)
  end.

get_their_info(Pid) ->
  Pid ! {get_info, self()},
  receive
    {info, Info} -> Info
  end.

send_message_ack(Notify, Trapping, Killing, Ignored) ->
  case Notify =/= ?notify_none of
    true ->
      Notify ! {message_ack, Trapping, Killing, Ignored},
      ok;
    false -> ok
  end.

receive_message_ack() ->
  receive
    {message_ack, Trapping, Killing, Ignored} -> {Trapping, Killing, Ignored}
  end.

get_leader(#concuerror_info{processes = Processes}, P) ->
  ets:lookup_element(Processes, P, ?process_leader).

not_demonitored(Message, Info) ->
  case Message of
    #message{data = {'DOWN', Ref, _, _, _}} ->
      #concuerror_info{demonitors = Demonitors} = Info,
      not lists:member(Ref, Demonitors);
    _ -> true
  end.

%%------------------------------------------------------------------------------

exiting(Reason, _,
        #concuerror_info{is_timer = Timer} = InfoIn) when Timer =/= false ->
  Info =
    case Reason of
      killed ->
        #concuerror_info{event = Event} = WaitInfo = process_loop(InfoIn),
        EventInfo = #exit_event{actor = Timer, reason = normal},
        Notification = Event#event{event_info = EventInfo},
        add_location_info(exit, notify(Notification, WaitInfo));
      normal ->
        InfoIn
    end,
  process_loop(set_status(Info, exited));
exiting(Reason, Stacktrace, InfoIn) ->
  %% XXX: The ordering of the following events has to be verified (e.g. R16B03):
  %% XXX:  - process marked as exiting, new messages are not delivered, name is
  %%         unregistered
  %% XXX:  - cancel timers
  %% XXX:  - transfer ets ownership and send message or delete table
  %% XXX:  - send link signals
  %% XXX:  - send monitor messages
  #concuerror_info{
     exit_by_signal = ExitBySignal,
     status = Status
    } = InfoIn,
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
           exit_by_signal = ExitBySignal,
           last_status = Status,
           links = [L || {L, _} <- Links],
           monitors = [M || {M, _} <- Monitors],
           name = Name,
           reason = Reason,
           stacktrace = Stacktrace,
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

-spec cleanup_processes(processes()) -> ok.

cleanup_processes(ProcessesTable) ->
  Processes = ets:tab2list(ProcessesTable),
  Foreach =
    fun(?process_pat_pid_kind(P,Kind)) ->
        case Kind =:= hijacked of
          true -> P ! unhijack;
          false ->
            unlink(P),
            P ! quit
        end
    end,
  lists:foreach(Foreach, Processes).

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
hijack_or_wrap_system(Name, #concuerror_info{timeout = Timeout} = Info)
  when Name =:= application_controller ->
  Pid = whereis(Name),
  link(Pid),
  _ = concuerror_loader:load(gen_server),
  ok = sys:suspend(Name),
  Notify =
    reset_concuerror_info(
      Info#concuerror_info{notify_when_ready = {self(), true}}),
  concuerror_inspect:hijack(Name, Notify),
  ok = sys:resume(Name),
  wait_process(Name, Timeout),
  hijacked;  
hijack_or_wrap_system(Name, Info) ->
  #concuerror_info{processes = Processes} = Info,
  Wrapped = whereis(Name),
  Fun = fun() -> system_wrapper_loop(Name, Wrapped, Info) end,
  Pid = spawn_link(Fun),
  ets:insert(Processes, ?new_system_process(Pid, Name, wrapper)),
  wrapped.

system_wrapper_loop(Name, Wrapped, Info) ->
  receive
    quit -> exit(normal);
    Message ->
      case Message of
        {message,
         #message{data = Data, id = Id}, Report} ->
          try
            {F, R} =
              case Name of
                code_server ->
		  {Call, From, Request} = Data,
		  check_request(Name, Request),
		  erlang:send(Wrapped, {Call, self(), Request}),
		  receive
		    Msg -> {From, Msg}
		  end;
                erl_prim_loader ->
		  {From, Request} = Data,
		  check_request(Name, Request),
		  erlang:send(Wrapped, {self(), Request}),
		  receive
		    {_, Msg} -> {From, {self(), Msg}}
                  end;
                error_logger ->
                  %% erlang:send(Wrapped, Data),
                  throw(no_reply);
                file_server_2 ->
		  {Call, {From, Ref}, Request} = Data,
		  check_request(Name, Request),
		  erlang:send(Wrapped, {Call, {self(), Ref}, Request}),
		  receive
		    Msg -> {From, Msg}
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
                  throw({unknown_protocol_for_system, Else})
              end,
            Report ! {system_reply, F, Id, R, Name},
            ok
          catch
            no_reply -> send_message_ack(Report, false, false, false);
            {unknown_protocol_for_system, _} = Reason -> ?crash(Reason);
            Class:Reason ->
              Stacktrace = erlang:get_stacktrace(),
              ?crash({system_wrapper_error, Name, Class, Reason, Stacktrace})
          end;
        {get_info, _} ->
          ?crash({wrapper_asked_for_status, Name})
      end,
      system_wrapper_loop(Name, Wrapped, Info)
  end.

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
  Request =
    try
      element(1, Other)
    catch
      _:_ ->
        Other
    end,
  ?crash({unsupported_request, Name, Request}).

reset_concuerror_info(Info) ->
  #concuerror_info{
     after_timeout = AfterTimeout,
     ets_tables = EtsTables,
     instant_delivery = InstantDelivery,
     is_timer = IsTimer,
     links = Links,
     logger = Logger,
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

new_ref_queue() ->
  {queue:new(), queue:new()}.

reset_ref_queue(#concuerror_info{ref_queue = {_, Stored}}) ->
  {Stored, Stored}.

get_ref(#concuerror_info{ref_queue = {Active, Stored}} = Info) ->
  {Result, NewActive} = queue:out(Active),
  case Result of
    {value, Ref} ->
      {Ref, Info#concuerror_info{ref_queue = {NewActive, Stored}}};
    empty ->
      Ref = make_ref(),
      NewStored = queue:in(Ref, Stored),
      {Ref, Info#concuerror_info{ref_queue = {NewActive, NewStored}}}
  end.

make_exit_signal(Reason) ->
  make_exit_signal(self(), Reason).

make_exit_signal(From, Reason) ->
  {'EXIT', From, Reason}.

make_message(Info, Type, Data, Recipient) ->
  #concuerror_info{event = #event{label = Label} = Event} = Info,
  {Id, MsgInfo} = get_message_cnt(Info),
  MessageEvent =
    #message_event{
       cause_label = Label,
       message = #message{data = Data, id = Id},
       recipient = Recipient,
       type = Type},
  NewEvent = Event#event{special = [{message, MessageEvent}]},
  MsgInfo#concuerror_info{event = NewEvent}.

get_message_cnt(#concuerror_info{message_counter = Counter} = Info) ->
  {{self(), Counter}, Info#concuerror_info{message_counter = Counter + 1}}.

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

is_active(#concuerror_info{exit_by_signal = ExitBySignal, status = Status}) ->
  not ExitBySignal andalso is_active(Status);
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
  true = is_atom(Tag),
  Logger = Data,
  concuerror_logger:print(Logger, Tag, Chars),
  {ok, IOState};
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

msg(exit_normal_self_abnormal) ->
  "A process that is not trapping exits (~w) sent a 'normal' exit"
    " signal to itself. This shouldn't make it exit, but in the current"
    " OTP it does, unless it's trapping exit signals. Concuerror respects the"
    " implementation.~n";
msg(register_eunit_server) ->
  "Your test seems to try to set up an EUnit server. This is a bad"
    " idea, for at least two reasons:"
    " 1) you probably don't want to test all of EUnit's boilerplate"
    " code systematically and"
    " 2) the default test function generated by EUnit runs all tests,"
    " one after another; as a result, systematic testing will have to"
    " explore a number of schedulings that is the product of every"
    " individual test's schedulings! You should use Concuerror on single tests"
    " instead.~n";
msg(whereis_application_controller) ->
  "Your test communicates with the 'application_controller' process. This"
    " can be problematic, as this process is not under Concuerror's"
    " control. You may want to try to start the test from a top-level"
    " supervisor (or even better a top level gen_server).~n".

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
    " increase the '--timeout' limit and/or ensure that there are no infinite"
    " loops in your test. (Process: ~p)",
    [Timeout, Actor]
   );
explain_error({process_did_not_respond_system, Actor}) ->
  io_lib:format(
    "A process did not respond to a control signal. Ensure that"
    " there are no infinite loops in your test. (Process: ~p)",
    [Actor]
   );
explain_error({registered_process_not_wrapped, Name, Location}) ->
  io_lib:format(
    "The test tries to communicate with a process registered as '~w' that is"
    " not under Concuerror's control. If your test cannot avoid this"
    " communication please open an issue to consider adding support.~n"
    "  Location:~p~n", [Name, Location]);
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
explain_error({unknown_built_in, {Module, Name, Arity, Location, Stack}}) ->
  LocationString =
    case Location of
      [Line, {file, File}] -> location(File, Line);
      _ -> ""
    end,
  io_lib:format(
    "Concuerror does not support calls to built-in ~p:~p/~p~s.~n  If you cannot"
    " avoid its use, please contact the developers.~n  Stacktrace:~n    ~p",
    [Module, Name, Arity, LocationString, Stack]);
explain_error({unsupported_request, Name, Type}) ->
  io_lib:format(
    "A process send a request of type '~p' to ~p. Concuerror does not yet support"
    " this type of request to this process.~n"
    ?notify_us_msg,
    [Type, Name]);
explain_error({wrapper_asked_for_status, Name}) ->
  io_lib:format(
    "A process attempted to request process_info for a system process (~p)."
    " Concuerror cannot track and restore the state of system processes, so"
    " this information may change between interleavings, leading to errors in"
    " the exploration. It should be possible to refactor your test to avoid"
    " this problem.",
    [Name]).

location(F, L) ->
  Basename = filename:basename(F),
  io_lib:format(" (found in ~s line ~w)", [Basename, L]).
