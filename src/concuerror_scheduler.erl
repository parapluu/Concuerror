%% -*- erlang-indent-level: 2 -*-

-module(concuerror_scheduler).

%% User interface
-export([run/1]).

%% Process interface
-export([ets_new/3]).

%%------------------------------------------------------------------------------

%%-define(DEBUG, true).
-define(CHECK_ASSERTIONS, true).
-include("concuerror.hrl").

%%------------------------------------------------------------------------------

%% -type clock_vector() :: orddict:orddict(). %% orddict(pid(), index()).
-type clock_map()    :: dict(). %% dict(pid(), clock_vector()).

%%------------------------------------------------------------------------------

%% =============================================================================
%% DATA STRUCTURES
%% =============================================================================

-type event_tree() :: [{event(), event_tree()}].

-record(trace_state, {
          active_processes = ordsets:new() :: ordsets:ordset(pid()),
          clock_map        = dict:new()    :: clock_map(),
          done             = []            :: [event()],
          index            = 1             :: index(),
          pending_messages = orddict:new() :: orddict:orddict(),
          preemptions      = 0             :: non_neg_integer(),
          sleeping         = []            :: [event()],
          wakeup_tree      = []            :: event_tree()
         }).

-type trace_state() :: #trace_state{}.
%% -type dpor_algorithm() :: 'none' | 'classic' | 'source' | 'optimal'.
%% -type preemption_bound() :: non_neg_integer() | 'inf'.

-record(scheduler_state, {
          current_warnings = []        :: [concuerror_warning_info()],
          ets_tables                   :: ets_tables(),
          first_process                :: {pid(), mfargs()},
          logger                       :: pid(),
          message_info                 :: message_info(),
          options = []                 :: proplists:proplist(),
          processes                    :: processes(),
          timeout                      :: non_neg_integer(),
          trace = []                   :: [trace_state()]
         }).

%% =============================================================================
%% LOGIC (high level description of the exploration algorithm)
%% =============================================================================

run(Options) ->
  {Pid, Ref} = spawn_monitor(fun() -> backend_run(Options) end),
  Quit = proplists:get_value(quit, Options, false),
  receive
    {'DOWN', Ref, process, Pid, Reason} ->
      QuitStatus =
        case Reason =:= normal of
          true -> 0;
          false ->
            io:format(standard_error, "Concuerror crashed!~nReason:~n~p~n",
                      [Reason]),
            1
        end,
      case Quit of
        true  -> erlang:halt(QuitStatus);
        false -> ok
      end
  end.

backend_run(Options) ->
  true = code:add_pathz(code:root_dir()++"/erts/preloaded/ebin"),
  EtsTables = ets:new(ets_tables, [public]),
  Processes = ets:new(processes, [public]),
  system_processes_wrappers(Processes),
  system_ets_entries(EtsTables),
  LoggerOptions =
    [{processes, Processes} |
     [O || O <- Options, concuerror_options:filter_options('logger', O)]
    ],
  Logger = spawn_link(fun() -> concuerror_logger:run(LoggerOptions) end),
  ProcessOptions0 =
    [O || O <- Options, concuerror_options:filter_options('process', O)],
  ProcessOptions =
    [{ets_tables, EtsTables},
     {logger, Logger},
     {processes, Processes}|
     ProcessOptions0],
  ?debug(Logger, "Starting first process...~n",[]),
  FirstProcess = concuerror_callback:spawn_first_process(ProcessOptions),
  {target, Target} = proplists:lookup(target, Options),
  {timeout, Timeout} = proplists:lookup(timeout, Options),
  InitialTrace = #trace_state{active_processes = [FirstProcess]},
  InitialState =
    #scheduler_state{
       ets_tables = EtsTables,
       first_process = {FirstProcess, Target},
       logger = Logger,
       message_info = ets:new(message_info, [private]),
       options = Options,
       processes = Processes,
       timeout = Timeout,
       trace = [InitialTrace]},
  %%meck:new(file, [unstick, passthrough]),
  ok = concuerror_callback:start_first_process(FirstProcess, Target),
  assert_no_messages(),
  {Status, FinalState} =
    try
      ?debug(Logger, "Starting exploration...~n",[]),
      concuerror_logger:plan(Logger),
      explore(InitialState)
    catch
      Type:Reason ->
        ?log(Logger, ?lerror,
             "Concuerror scheduler crashed (~p)~n"
             "Reason: ~p~n"
             "Trace: ~p~n",
             [Type, Reason, erlang:get_stacktrace()]),
        {error, InitialState}
    end,
  cleanup(FinalState),
  concuerror_logger:stop(Logger, Status).

%%------------------------------------------------------------------------------

explore(State) ->
  receive
    cl_exit -> {interrupted, State}
  after 0 ->
      {Status, UpdatedState} = get_next_event(State),
      case Status of
        ok -> explore(UpdatedState);
        none ->
          RacesDetectedState = plan_more_interleavings(UpdatedState),
          LogState = log_trace(RacesDetectedState),
          {HasMore, NewState} = has_more_to_explore(LogState),
          case HasMore of
            true -> explore(NewState);
            false -> {ok, NewState}
          end
      end
  end.

%%------------------------------------------------------------------------------

log_trace(State) ->
  #scheduler_state{logger = Logger, current_warnings = Warnings} = State,
  Log =
    case Warnings =:= [] of
      true -> none;
      false ->
        #scheduler_state{trace = Trace} = State,
        %%io:format("~p~n",[Trace]),
        Fold =
          fun(#trace_state{done = [A|_], index = I}, Acc) -> [{I, A}|Acc] end,
        TraceInfo = lists:foldl(Fold, [], Trace),
        {Warnings, TraceInfo}
    end,
  concuerror_logger:complete(Logger, Log),
  State#scheduler_state{current_warnings = []}.

get_next_event(#scheduler_state{logger = Logger, trace = [Last|_]} = State) ->
  #trace_state{
     active_processes = ActiveProcesses,
     pending_messages = PendingMessages,
     sleeping         = Sleeping,
     wakeup_tree      = WakeupTree
    } = Last,
  assert_no_messages(),
  case WakeupTree of
    [] ->
      Event = #event{label = make_ref()},
      {AvailablePendingMessages, AvailableActiveProcesses} =
        filter_sleeping(Sleeping, PendingMessages, ActiveProcesses),
      get_next_event(Event, AvailablePendingMessages, AvailableActiveProcesses,
                     State);
    [{#event{label = Label} = Event, _}|_] ->
      try
        {ok, UpdatedEvent} =
          case Label =/= undefined of
            true -> NewEvent = get_next_event_backend(Event, State),
                    try {ok, Event} = NewEvent
                    catch
                      _:_ ->
                        error({{new, element(2, NewEvent)}, {old, Event}})
                    end;
            false ->
              %% Last event = Previously racing event = Result may differ.
              ResetEvent = reset_event(Event),
              get_next_event_backend(ResetEvent, State)
        end,
        update_state(UpdatedEvent, State)
      catch
        error:What ->
          ?debug(Logger, "Expected:~n~p~n", [Event]),
          error(What)
      end
  end.

filter_sleeping([], PendingMessages, ActiveProcesses) ->
  {PendingMessages, ActiveProcesses};
filter_sleeping([#event{actor = {_, _} = Pair}|Sleeping],
                PendingMessages, ActiveProcesses) ->
  NewPendingMessages = orddict:erase(Pair, PendingMessages),
  filter_sleeping(Sleeping, NewPendingMessages, ActiveProcesses);
filter_sleeping([#event{actor = Pid}|Sleeping],
                PendingMessages, ActiveProcesses) ->
  NewActiveProcesses = ordsets:del_element(Pid, ActiveProcesses),
  filter_sleeping(Sleeping, PendingMessages, NewActiveProcesses).

get_next_event(Event, [{Pair, Queue}|_], _ActiveProcesses, State) ->
  %% Pending messages can always be sent
  MessageEvent = queue:get(Queue),
  Special = {message_delivered, MessageEvent},
  UpdatedEvent =
    Event#event{
      actor = Pair,
      event_info = MessageEvent,
      special = Special},
  {ok, FinalEvent} = get_next_event_backend(UpdatedEvent, State),
  update_state(FinalEvent, State);
get_next_event(Event, [], [P|ActiveProcesses], State) ->
  Result = get_next_event_backend(Event#event{actor = P}, State),
  case Result of
    exited ->
      #scheduler_state{trace = [Top|Rest]} = State,
      #trace_state{active_processes = Active} = Top,
      NewActive = ordsets:del_element(P, Active),
      NewTop = Top#trace_state{active_processes = NewActive},
      NewState = State#scheduler_state{trace = [NewTop|Rest]},
      get_next_event(Event, [], ActiveProcesses, NewState);
    retry -> get_next_event(Event, [], ActiveProcesses, State);
    {ok, UpdatedEvent} -> update_state(UpdatedEvent, State)
  end;
get_next_event(_Event, [], [], State) ->
  %% Nothing to do, trace is completely explored
  #scheduler_state{
     current_warnings = Warnings,
     logger = Logger,
     trace = [Last|Prev]
    } = State,
  #trace_state{
     active_processes = ActiveProcesses,
     sleeping         = Sleeping
    } = Last,
  NewWarnings =
    case Sleeping =/= [] of
      true ->
        ?debug(Logger, "Sleep set block:~n ~p~n", [Sleeping]),
        [{sleep_set_block, Sleeping}|Warnings];
      false ->
        case ActiveProcesses =/= [] of
          true ->
            ?debug(Logger, "Deadlock: ~p~n~n", [ActiveProcesses]),
            [{deadlock, collect_deadlock_info(ActiveProcesses)}|Warnings];
          false -> Warnings
        end
    end,
  {none, State#scheduler_state{current_warnings = NewWarnings, trace = Prev}}.

reset_event(#event{actor = Actor} = Event) ->
  {ResetEventInfo, ResetSpecial} =
    case Actor of
      {_, _} ->
        #event{event_info = EventInfo, special = Special} = Event,
        {EventInfo#message_event{patterns = none}, Special};
      _ -> {undefined, none}
    end,
  #event{
     actor = Actor,
     event_info = ResetEventInfo,
     label = make_ref(),
     special = ResetSpecial
    }.

%%------------------------------------------------------------------------------

update_state(#event{actor = Actor, special = Special} = Event,
             #scheduler_state{logger = Logger, trace = [Last|Prev]} = State) ->
  #trace_state{
     active_processes = ActiveProcesses,
     done             = Done,
     index            = Index,
     pending_messages = PendingMessages,
     preemptions      = Preemptions,
     sleeping         = Sleeping,
     wakeup_tree      = WakeupTree
    } = Last,
  ?trace(Logger, "+++ ~s~n", [concuerror_printer:pretty_s({Index, Event})]),
  AllSleeping = ordsets:union(ordsets:from_list(Done), Sleeping),
  NextSleeping = update_sleeping(Event, AllSleeping, State),
  {NewLastWakeupTree, NextWakeupTree} =
    case WakeupTree of
      [] -> {[], []};
      [{_, NWT}|Rest] -> {Rest, NWT}
    end,
  NewLastDone = [Event|Done],
  NextPreemptions =
    update_preemptions(Actor, ActiveProcesses, Prev, Preemptions),
  InitNextTrace =
    #trace_state{
       active_processes = ActiveProcesses,
       index            = Index + 1,
       pending_messages = PendingMessages,
       preemptions      = NextPreemptions,
       sleeping         = NextSleeping,
       wakeup_tree      = NextWakeupTree
      },
  NewLastTrace =
    Last#trace_state{done = NewLastDone, wakeup_tree = NewLastWakeupTree},
  InitNewState =
    State#scheduler_state{trace = [InitNextTrace, NewLastTrace|Prev]},
  NewState =
    case Event#event.event_info of
      #exit_event{reason = Reason} = Exit when Reason =/= normal ->
        Warnings = InitNewState#scheduler_state.current_warnings,
        Stacktrace = Exit#exit_event.stacktrace,
        NewWarnings = [{crash, {Index, Actor, Reason, Stacktrace}}|Warnings],
        InitNewState#scheduler_state{current_warnings = NewWarnings};
      _ -> InitNewState
    end,
  {ok, update_special(Special, NewState)}.

update_sleeping(#event{event_info = NewInfo}, Sleeping, State) ->
  #scheduler_state{logger = Logger} = State,
  Pred =
    fun(#event{event_info = OldInfo}) ->
        V = concuerror_dependencies:dependent(OldInfo, NewInfo),
        ?trace(Logger, "AWAKE (~p):~n~p~nvs~n~p~n", [V, OldInfo, NewInfo]),
        not V
    end,
  lists:filter(Pred, Sleeping).

%% XXX: Stub.
update_preemptions(_Pid, _ActiveProcesses, _Prev, Preemptions) ->
  Preemptions.

update_special(none, State) ->
  State;
update_special(Special, State) ->
  #scheduler_state{message_info = MessageInfo, trace = [Next|Trace]} = State,
  case Special of
    {message, Message} ->
      #trace_state{pending_messages = PendingMessages} = Next,
      NewPendingMessages =
        process_message(Message, PendingMessages, MessageInfo),
      NewNext = Next#trace_state{pending_messages = NewPendingMessages},
      State#scheduler_state{trace = [NewNext|Trace]};
    {message_delivered, MessageEvent} ->
      #trace_state{pending_messages = PendingMessages} = Next,
      NewPendingMessages =
        remove_pending_message(MessageEvent, PendingMessages),
      NewNext = Next#trace_state{pending_messages = NewPendingMessages},
      State#scheduler_state{trace = [NewNext|Trace]};
    {message_received, Message, PatternFun} ->
      Update = {?message_pattern, PatternFun},
      true = ets:update_element(MessageInfo, Message, Update),
      State;
    {new, SpawnedPid} ->
      #trace_state{active_processes = ActiveProcesses} = Next,
      NewNext =
        Next#trace_state{
          active_processes = ordsets:add_element(SpawnedPid, ActiveProcesses)
         },
      State#scheduler_state{trace = [NewNext|Trace]};
    List when is_list(List) ->
      lists:foldl(fun update_special/2, State, Special)
  end.

process_message(MessageEvent, PendingMessages, MessageInfo) ->
  #message_event{
     message = #message{message_id = Id},
     recipient = Recipient,
     sender = Sender
    } = MessageEvent,
  Key = {Sender, Recipient},
  Update = fun(Queue) -> queue:in(MessageEvent, Queue) end,
  Initial = queue:from_list([MessageEvent]),
  ets:insert(MessageInfo, ?new_message_info(Id)),
  orddict:update(Key, Update, Initial, PendingMessages).

remove_pending_message(#message_event{recipient = Recipient, sender = Sender},
                       PendingMessages) ->
  Key = {Sender, Recipient},
  Queue = orddict:fetch(Key, PendingMessages),
  NewQueue = queue:drop(Queue),
  case queue:is_empty(NewQueue) of
    true  -> orddict:erase(Key, PendingMessages);
    false -> orddict:store(Key, NewQueue, PendingMessages)
  end.

%%------------------------------------------------------------------------------

plan_more_interleavings(State) ->
  #scheduler_state{logger = Logger, trace = Trace} = State,
  ?trace(Logger, "Plan more interleavings:~n", []),
  {OldTrace, NewTrace} = split_trace(Trace),
  TimedNewTrace = assign_happens_before(NewTrace, OldTrace, State),
  FinalTrace =
    plan_more_interleavings(lists:reverse(OldTrace, TimedNewTrace), [], State),
  State#scheduler_state{trace = FinalTrace}.

split_trace(Trace) ->
  split_trace(Trace, []).

split_trace([], NewTrace) ->
  {[], NewTrace};
split_trace([#trace_state{clock_map = ClockMap} = State|Rest] = OldTrace,
            NewTrace) ->
  case dict:size(ClockMap) =:= 0 of
    true  -> split_trace(Rest, [State|NewTrace]);
    false -> {OldTrace, NewTrace}
  end.

assign_happens_before(NewTrace, OldTrace, State) ->
  assign_happens_before(NewTrace, [], OldTrace, State).

assign_happens_before([], TimedNewTrace, _OldTrace, _State) ->
  lists:reverse(TimedNewTrace);
assign_happens_before([TraceState|Rest], TimedNewTrace, OldTrace, State) ->
  #scheduler_state{logger = Logger, message_info = MessageInfo} = State,
  #trace_state{done = [Event|RestEvents], index = Index} = TraceState,
  #event{actor = Actor, event_info = EventInfo, special = Special} = Event,
  ClockMap = get_base_clock(OldTrace),
  ActorClock = lookup_clock(Actor, ClockMap),
  {BaseTraceState, BaseClock} =
    case Actor of
      {_, _} ->
        #message_event{message = #message{message_id = Id}} = EventInfo,
        SentClock = message_clock(Id, MessageInfo, ActorClock),
        Patterns = ets:lookup_element(MessageInfo, Id, ?message_pattern),
        UpdatedEventInfo = EventInfo#message_event{patterns = Patterns},
        UpdatedEvent = Event#event{event_info = UpdatedEventInfo},
        UpdatedTraceState =
          TraceState#trace_state{done = [UpdatedEvent|RestEvents]},
        {UpdatedTraceState, SentClock};
      _ -> {TraceState, ActorClock}
    end,
  #trace_state{done = [BaseEvent|_]} = BaseTraceState,
  BaseNewClock = update_clock(OldTrace, BaseEvent, BaseClock, State),
  ActorNewClock = orddict:store(Actor, Index, BaseNewClock),
  NewClock =
    case Actor of
      {_, _} -> ActorNewClock;
      _ ->
        case EventInfo of
          #receive_event{message = #message{message_id = RId}} ->
            RMessageClock =
              ets:lookup_element(MessageInfo, RId, ?message_delivered),
            max_cv(ActorNewClock, RMessageClock);
          _Other ->
            ActorNewClock
        end
    end,
  ?trace_nl(Logger, "~p: ~w:~w~n", [Index, Actor, NewClock]),
  BaseNewClockMap = dict:store(Actor, NewClock, ClockMap),
  NewClockMap =
    case Special of
      {new, SpawnedPid} -> dict:store(SpawnedPid, NewClock, BaseNewClockMap);
      _ -> BaseNewClockMap
    end,
  case Actor of
    {_, _} ->
      #message_event{message = #message{message_id = IdB}} = EventInfo,
      ets:update_element(MessageInfo, IdB, {?message_delivered, NewClock});
    _ -> ok
  end,
  maybe_mark_sent_message(Special, NewClock, MessageInfo),
  NewTraceState = BaseTraceState#trace_state{clock_map = NewClockMap},
  NewOldTrace = [NewTraceState|OldTrace],
  NewTimedNewTrace = [NewTraceState|TimedNewTrace],
  assign_happens_before(Rest, NewTimedNewTrace, NewOldTrace, State).

get_base_clock([]) -> dict:new();
get_base_clock([#trace_state{clock_map = ClockMap}|_]) -> ClockMap.

message_clock(Id, MessageInfo, ActorClock) ->
  MessageClock = ets:lookup_element(MessageInfo, Id, ?message_sent),
  max_cv(ActorClock, MessageClock).

update_clock([], _Event, Clock, _State) ->
  Clock;
update_clock([TraceState|Rest], Event, Clock, State) ->
  #trace_state{
     done =
       [#event{actor = EarlyActor, event_info = EarlyInfo} = _EarlyEvent|_],
     index = EarlyIndex
    } = TraceState,
  EarlyClock = lookup_clock_value(EarlyActor, Clock),
  NewClock =
    case EarlyIndex > EarlyClock of
      false -> Clock;
      true ->
        #event{event_info = EventInfo} = Event,
        Dependent =
          concuerror_dependencies:dependent(EarlyInfo, EventInfo),
        case Dependent of
          false -> Clock;
          true ->
            #trace_state{clock_map = ClockMap} = TraceState,
            EarlyActorClock = lookup_clock(EarlyActor, ClockMap),
            max_cv(Clock, EarlyActorClock)
        end
    end,
  update_clock(Rest, Event, NewClock, State).

maybe_mark_sent_message({message, Message}, Clock, MessageInfo) ->
  #message_event{message = #message{message_id = Id}} = Message,
  ets:update_element(MessageInfo, Id, {?message_sent, Clock});
maybe_mark_sent_message(Special, Clock, MessageInfo) ->
  case is_list(Special) of
    false -> true;
    true ->
      Message = proplists:lookup(message, Special),
      maybe_mark_sent_message(Message, Clock, MessageInfo)
  end.

plan_more_interleavings([], OldTrace, _SchedulerState) ->
  OldTrace;
plan_more_interleavings([TraceState|Rest], OldTrace, State) ->
  #scheduler_state{logger = Logger, message_info = MessageInfo} = State,
  #trace_state{done = [Event|_], index = Index} = TraceState,
  #event{actor = Actor, event_info = EventInfo} = Event,
  ClockMap = get_base_clock(OldTrace),
  ActorClock = lookup_clock(Actor, ClockMap),
  BaseClock =
    case Actor of
      {_, _} ->
        #message_event{message = #message{message_id = Id}} = EventInfo,
        message_clock(Id, MessageInfo, ActorClock);
      _ -> ActorClock
    end,
  ?trace_nl(Logger, "===~nRaces ~s~n",
            [concuerror_printer:pretty_s({Index, Event})]),
  BaseNewOldTrace =
    more_interleavings_for_event(OldTrace, Event, Rest, BaseClock, State),
  NewOldTrace = [TraceState|BaseNewOldTrace],
  plan_more_interleavings(Rest, NewOldTrace, State).

more_interleavings_for_event(OldTrace, Event, Later, Clock, State) ->
  more_interleavings_for_event(OldTrace, Event, Later, Clock, State, []).

more_interleavings_for_event([], _Event, _Later, _Clock, _State, NewOldTrace) ->
  lists:reverse(NewOldTrace);
more_interleavings_for_event([TraceState|Rest], Event, Later, Clock, State,
                             NewOldTrace) ->
  #scheduler_state{logger = Logger} = State,
  #trace_state{
     done =
       [#event{actor = EarlyActor, event_info = EarlyInfo} = _EarlyEvent|Done],
     index = EarlyIndex,
     sleeping = Sleeping
    } = TraceState,
  EarlyClock = lookup_clock_value(EarlyActor, Clock),
  Action =
    case EarlyIndex > EarlyClock of
      false -> none;
      true ->
        #event{event_info = EventInfo} = Event,
        Dependent =
          concuerror_dependencies:dependent(EarlyInfo, EventInfo),
        case Dependent of
          false -> none;
          true ->
            ?trace_nl(Logger, "   with ~s~n",
                      [concuerror_printer:pretty_s({EarlyIndex, _EarlyEvent})]),
            %% XXX: Why is this line needed?
            NC = orddict:store(EarlyActor, EarlyIndex, Clock),
            NotDep =
              not_dep(NewOldTrace ++ Later, EarlyActor, EarlyIndex, Event, Logger),
            #trace_state{wakeup_tree = WakeupTree} = TraceState,
            case insert_wakeup(Sleeping ++ Done, WakeupTree, NotDep) of
              skip -> {update_clock, NC};
              NewWakeupTree ->
                concuerror_logger:plan(Logger),
                ?trace_nl(Logger,
                          "PLAN~n~s",
                          [lists:append(
                             [io_lib:format(
                                "        ~s~n",
                                [concuerror_printer:pretty_s(S)]) ||
                               S <- NotDep])]),
                NS = TraceState#trace_state{wakeup_tree = NewWakeupTree},
                {update, NS, NC}
            end
        end
    end,
  {NewTrace, NewClock} =
    case Action of
      none -> {[TraceState|NewOldTrace], Clock};
      {update_clock, C} ->
        ?trace_nl(Logger, "SKIP~n",[]),
        {[TraceState|NewOldTrace], C};
      {update, S, C} -> {[S|NewOldTrace], C}
    end,
  more_interleavings_for_event(Rest, Event, Later, NewClock, State, NewTrace).

not_dep(Trace, Actor, Index, Event, Logger) ->
  not_dep(Trace, Actor, Index, Event, Logger, []).

not_dep([], _Actor, _Index, Event, Logger, NotDep) ->
  %% The racing event's effect may differ, so new label.
  ?trace_nl(Logger, "      not_dep: last:~p ~n", [Event#event.actor]),
  lists:reverse([Event#event{label = undefined}|NotDep]);
not_dep([TraceState|Rest], Actor, Index, Event, Logger, NotDep) ->
  #trace_state{
     clock_map = ClockMap,
     done = [#event{actor = LaterActor} = LaterEvent|_],
     index = LaterIndex
    } = TraceState,
  LaterClock = lookup_clock(LaterActor, ClockMap),
  ActorLaterClock = lookup_clock_value(Actor, LaterClock),
  NewNotDep =
    case Index > ActorLaterClock of
      false -> NotDep;
      true ->
        ?trace_nl(Logger, "      not_dep: ~p:~p ~n", [LaterIndex, LaterActor]),
        [LaterEvent|NotDep]
    end,
  not_dep(Rest, Actor, Index, Event, Logger, NewNotDep).

insert_wakeup([Sleeping|Rest], Wakeup, NotDep) ->
  case check_initial(Sleeping, NotDep) =:= false of
    true  -> insert_wakeup(Rest, Wakeup, NotDep);
    false -> skip
  end;
insert_wakeup([], Wakeup, NotDep) ->
  insert_wakeup(Wakeup, NotDep).

insert_wakeup([], NotDep) ->
  Fold = fun(Event, Acc) -> [{Event, Acc}] end,
  lists:foldr(Fold, [], NotDep);
insert_wakeup([{Event, Deeper} = Node|Rest], NotDep) ->
  case check_initial(Event, NotDep) of
    false ->
      case insert_wakeup(Rest, NotDep) of
        skip -> skip;
        NewTree -> [Node|NewTree]
      end;
    NewNotDep ->
      case Deeper =:= [] of
        true  -> skip;
        false ->
          case insert_wakeup(Deeper, NewNotDep) of
            skip -> skip;
            NewTree -> [{Event, NewTree}|Rest]
          end
      end
  end.

check_initial(Event, NotDep) ->
  check_initial(Event, NotDep, []).

check_initial(_Event, [], Acc) ->
  lists:reverse(Acc);
check_initial(Event, [E|NotDep], Acc) ->
  #event{actor = EventActor, event_info = EventInfo} = Event,
  #event{actor = EActor, event_info = EInfo} = E,
  case EventActor =:= EActor of
    true -> lists:reverse(Acc,NotDep);
    false ->
      case concuerror_dependencies:dependent(EventInfo, EInfo) of
        true -> false;
        false -> check_initial(Event, NotDep, [E|Acc])
      end
  end.

%%------------------------------------------------------------------------------

has_more_to_explore(State) ->
  #scheduler_state{logger = Logger, trace = Trace} = State,
  TracePrefix = find_prefix(Trace, State),
  case TracePrefix =:= [] of
    true -> {false, State#scheduler_state{trace = []}};
    false ->
      ?debug(Logger, "New interleaving, replaying...~n", []),
      ok = replay_prefix(TracePrefix, State),
      ?debug(Logger, "~s~n",["Replay done...!"]),
      NewState = State#scheduler_state{trace = TracePrefix},
      {true, NewState}
  end.

find_prefix([], _State) -> [];
find_prefix([#trace_state{done = Done, wakeup_tree = []}|Rest],
            State) ->
  lists:foreach(fun(E) -> reset_receive(E, State) end, Done),
  find_prefix(Rest, State);
find_prefix([#trace_state{} = Other|Rest], _State) ->
  [Other#trace_state{clock_map = dict:new()}|Rest].

reset_receive(Last, State) ->
  %% Reset receive info
  case Last of
    #message_event{message = #message{message_id = Id}} ->
      #scheduler_state{logger = Logger, message_info = MessageInfo} = State,
      ?trace(Logger, "Reset: ~p~n", [Id]),
      Update = {?message_pattern, undefined},
      true = ets:update_element(MessageInfo, Id, Update);
    _Other -> true
  end.

%% =============================================================================
%% ENGINE (manipulation of the Erlang processes under the scheduler)
%% =============================================================================

replay_prefix(Trace, State) ->
  #scheduler_state{
     first_process = {FirstProcess, Target},
     processes = Processes
    } = State,
  Fold =
    fun(?process_pat_pid_kind(P, Kind), _) ->
        case Kind =:= regular of
          true -> P ! reset;
          false -> ok
        end,
        ok
    end,
  ok = ets:foldl(Fold, ok, Processes),
  ok = concuerror_callback:start_first_process(FirstProcess, Target),
  assert_no_messages(),
  ok = replay_prefix_aux(lists:reverse(Trace), State).

replay_prefix_aux([_], _State) ->
  %% Last state has to be properly replayed.
  ok;
replay_prefix_aux([#trace_state{done = [Event|_], index = I}|Rest], State) ->
  #scheduler_state{logger = Logger} = State,
  ?trace_nl(Logger, "~s~n", [concuerror_printer:pretty_s({I, Event})]),
  {ok, NewEvent} = get_next_event_backend(Event, State),
  try
    Event = NewEvent
  catch
    A:B ->
      ?debug(Logger,
             "replay mismatch (~p):~n"
             "~p~n"
             "  original: ~p~n"
             "  new     : ~p~n",
             [A, B, Event, NewEvent]),
      error(replay_crashed)
  end,
  replay_prefix_aux(Rest, State).

%% XXX: Stub
cleanup(#scheduler_state{logger = Logger, processes = Processes} = State) ->
  %% Kill still running processes, deallocate tables, etc...
  Fold = fun(?process_pat_pid(P), true) -> unlink(P), exit(P, kill) end,
  true = ets:foldl(Fold, true, Processes),
  ?trace(Logger, "Reached the end!~n",[]),
  State.

%% =============================================================================
%% INTERNAL INTERFACES
%% =============================================================================

%% Between scheduler and an instrumented process
%%------------------------------------------------------------------------------

get_next_event_backend(#event{actor = {_Sender, Recipient}} = Event, _State) ->
  #event{event_info = EventInfo} = Event,
  #message_event{message = Message, type = Type} = EventInfo,
  %% Message delivery always succeeds
  Recipient ! {Type, Message},
  UpdatedEvent =
    receive
      {trapping, Trapping} ->
        NewEventInfo = EventInfo#message_event{trapping = Trapping},
        Event#event{event_info = NewEventInfo};
      {system_reply, From, Id, Reply} ->
        #event{special = Special} = Event,
        case is_list(Special) of
          true ->
            #message_event{message = #message{data = OldReply}} =
              proplists:get_value(message, Special),
            case OldReply =:= Reply of
              true -> Event;
              false ->
                error({system_reply_differs, OldReply, Reply})
            end;
          false ->
            MessageEvent =
              #message_event{
                 cause_label = Event#event.label,
                 message = #message{data = Reply, message_id = make_ref()},
                 sender = Recipient,
                 recipient = From},
            Specials =
              [{message_received, Id, fun(_) -> true end},
               {message, MessageEvent}],
            Event#event{special = [Special|Specials]}
        end
    after
      2000 ->
        error(too_late)
    end,
  {ok, UpdatedEvent};
get_next_event_backend(#event{actor = Pid} = Event, State) when is_pid(Pid) ->
  Pid ! Event,
  get_next_event_backend_loop(Event, State).

get_next_event_backend_loop(Trigger, State) ->
  #scheduler_state{timeout = Timeout} = State,
  receive
    exited -> exited;
    {blocked, _} -> retry;
    #event{} = Event -> {ok, Event};
    {ets_new, Pid, Name, Options} ->
      #scheduler_state{ets_tables = EtsTables} = State,
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
      Reply =
        try
          Tid = ets:new(Name, Options ++ [public]),
          ets:insert(EtsTables, ?new_ets_table(Tid, Protection)),
          {ok, Tid}
        catch
          error:Reason ->
            #scheduler_state{logger = Logger} = State,
            ?trace(Logger, "ets:new crash scheduler: ~p~n", [Reason]),
            {error, Reason}
        end,
      Pid ! {ets_new, Reply},
      get_next_event_backend_loop(Trigger, State)
  after
    Timeout -> error({timeout, Trigger})
  end.

ets_new(Scheduler, Name, Options) ->
  Scheduler ! {ets_new, self(), Name, Options},
  receive
    {ets_new, Reply} -> Reply
  end.

collect_deadlock_info(ActiveProcesses) ->
  Map =
    fun(P) ->
        P ! deadlock_poll,
        receive
          {blocked, Location} -> {P, Location}
        end
    end,
  [Map(P) || P <- ActiveProcesses].

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

lookup_clock(P, ClockMap) ->
  case dict:find(P, ClockMap) of
    {ok, Clock} -> Clock;
    error -> orddict:new()
  end.

lookup_clock_value(P, CV) ->
  case orddict:find(P, CV) of
    {ok, Value} -> Value;
    error -> 0
  end.

max_cv(D1, D2) ->
  Merger = fun(_Key, V1, V2) -> max(V1, V2) end,
  orddict:merge(Merger, D1, D2).

system_processes_wrappers(Processes) ->
  Scheduler = self(),
  Map =
    fun(Name) ->
        Fun = fun() -> system_wrapper_loop(Name, whereis(Name), Scheduler) end,
        Pid = spawn_link(Fun),
        ?new_system_process(Pid, Name)
    end,
  ets:insert(Processes, [Map(Name) || Name <- registered()]).

system_wrapper_loop(Name, Wrapped, Scheduler) ->
  receive
    {message,
     #message{data = Data, message_id = Id}} ->
      case Name of
        init ->
          {From, Request} = Data,
          erlang:send(Wrapped, {self(), Request}),
          receive
            Msg -> Scheduler ! {system_reply, From, Id, Msg}
          end;
        error_logger ->
          erlang:send(Wrapped, Data),
          Scheduler ! {trapping, false}
      end
  end,
  system_wrapper_loop(Name, Wrapped, Scheduler).

system_ets_entries(EtsTables) ->
  Map = fun(Tid) -> ?new_system_ets_table(Tid, ets:info(Tid, protection)) end,
  ets:insert(EtsTables, [Map(Tid) || Tid <- ets:all(), is_atom(Tid)]).

assert_no_messages() ->
  receive
    Msg -> error({pending_message, Msg})
  after
    0 -> ok
  end.
