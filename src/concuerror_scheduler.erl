%% -*- erlang-indent-level: 2 -*-

-module(concuerror_scheduler).

%% User interface
-export([run/1]).

%% Process interface
-export([ets_new/3, known_process/2]).

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
          processes = ordsets:new()    :: ordsets:ordset(pid()),
          timeout                      :: non_neg_integer(),
          trace = []                   :: [trace_state()]
         }).

%% =============================================================================
%% LOGIC (high level description of the exploration algorithm)
%% =============================================================================

run(Options) ->
  LoggerPred = fun(O) -> concuerror_options:filter_options('logger', O) end,
  {LoggerOptions, _} = lists:partition(LoggerPred, Options),
  Logger = spawn_link(fun() -> concuerror_logger:run(LoggerOptions) end),
  EtsTables = ets:new(ets_tables, [public]),
  ProcessPred = fun(O) -> concuerror_options:filter_options('process', O) end,
  {ProcessOptions0, _} = lists:partition(ProcessPred, Options),
  ProcessOptions = [{ets_tables, EtsTables}, {logger, Logger}|ProcessOptions0],
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
       processes = [FirstProcess],
       timeout = Timeout,
       trace = [InitialTrace]},
  %%meck:new(file, [unstick, passthrough]),
  ok = concuerror_callback:start_first_process(FirstProcess, Target),
  {Status, FinalState} =
    try
      ?debug(Logger, "Starting exploration...~n",[]),
      concuerror_logger:plan(Logger),
      explore(InitialState)
    catch
      Type:Reason ->
        ?log(Logger, ?lerror,
             "concuerror crashed (~p)~n"
             "Reason: ~p~n"
             "Trace: ~p~n",
             [Type, Reason, erlang:get_stacktrace()]),
        {error, InitialState}
    end,
  cleanup(FinalState),
  concuerror_logger:stop(Logger, Status),
  {exit, Status}.

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

get_next_event(#scheduler_state{trace = [Last|_]} = State) ->
  #trace_state{
     active_processes = ActiveProcesses,
     pending_messages = PendingMessages,
     sleeping         = Sleeping,
     wakeup_tree      = WakeupTree
    } = Last,
  case WakeupTree of
    [] ->
      Event = #event{label = make_ref()},
      {AvailablePendingMessages, AvailableActiveProcesses} =
        filter_sleeping(Sleeping, PendingMessages, ActiveProcesses),
      get_next_event(Event, AvailablePendingMessages, AvailableActiveProcesses,
                     State);
    [{#event{label = Label} = Event, _}|_] ->
      {Status, UpdatedEvent} =
        case Label =/= undefined of
          true -> {_, Event} = get_next_event_backend(Event, State);
          false ->
            %% Last event = Previously racing event = Result may differ.
            ResetEvent = reset_event(Event),
            get_next_event_backend(ResetEvent, State)
        end,
      case Status of
        ok -> update_state(UpdatedEvent, State);
        retry -> error(planned_backtrack_blocked)
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
  %% XXX: Sending to an uninstrumented process should be caught here
  Special = [{message_delivered, MessageEvent}],
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
    retry -> get_next_event(Event, [], ActiveProcesses, State);
    {ok, UpdatedEvent} -> update_state(UpdatedEvent, State)
  end;
get_next_event(_Event, [], [], State) ->
  %% Nothing to do, trace is completely explored
  #scheduler_state{
     current_warnings = Warnings,
     trace = [Last|Prev]
    } = State,
  #trace_state{
     active_processes = ActiveProcesses,
     sleeping         = Sleeping
    } = Last,
  NewWarnings =
    case Sleeping =/= [] of
      true -> [{sleep_set_block, Sleeping}|Warnings];
      false ->
        case ActiveProcesses =/= [] of
          true ->
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
      _ -> {undefined, []}
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

update_special([], State) ->
  State;
update_special([Special|Rest],
               #scheduler_state{
                  message_info = MessageInfo,
                  processes = Processes,
                  trace = [Next|Trace]
                 } = State) ->
  NewState =
    case Special of
      {messages, Messages} ->
        #trace_state{pending_messages = PendingMessages} = Next,
        NewPendingMessages =
          process_messages(Messages, PendingMessages, MessageInfo),
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
        State#scheduler_state{
          processes = ordsets:add_element(SpawnedPid, Processes),
          trace = [NewNext|Trace]
         };
      {exit, ExitedPid} ->
        #trace_state{active_processes = ActiveProcesses} = Next,
        NewNext =
          Next#trace_state{
            active_processes = ordsets:del_element(ExitedPid, ActiveProcesses)
           },
        State#scheduler_state{
          trace = [NewNext|Trace]
         }
    end,
  update_special(Rest, NewState).

process_messages(Messages, PendingMessages, MessageInfo) ->
  Fold =
    fun(#message_event{
           message = #message{message_id = Id},
           recipient = Recipient,
           sender = Sender
          } = MessageEvent,
        PendingAcc) ->
        Key = {Sender, Recipient},
        Update = fun(Queue) -> queue:in(MessageEvent, Queue) end,
        Initial = queue:from_list([MessageEvent]),
        ets:insert(MessageInfo, ?new_message_info(Id)),
        orddict:update(Key, Update, Initial, PendingAcc)
    end,
  lists:foldl(Fold, PendingMessages, Messages).

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
  BaseClock = get_base_clock(OldTrace),
  FinalTrace =
    plan_more_interleavings(NewTrace, OldTrace, BaseClock, State),
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

get_base_clock([]) -> dict:new();
get_base_clock([#trace_state{clock_map = ClockMap}|_]) -> ClockMap.

plan_more_interleavings([], OldTrace, _ClockMap, _SchedulerState) ->
  OldTrace;
plan_more_interleavings([TraceState|Rest], OldTrace, ClockMap, State) ->
  #scheduler_state{logger = Logger, message_info = MessageInfo} = State,
  #trace_state{done = [Event|RestEvents], index = Index} = TraceState,
  #event{actor = Actor, event_info = EventInfo, special = Special} = Event,
  ActorClock = lookup_clock(Actor, ClockMap),
  {BaseTraceState, BaseClock} =
    case Actor of
      {_, _} ->
        #message_event{message = #message{message_id = Id}} = EventInfo,
        MessageClock = ets:lookup_element(MessageInfo, Id, ?message_sent),
        Patterns = ets:lookup_element(MessageInfo, Id, ?message_pattern),
        UpdatedEventInfo = EventInfo#message_event{patterns = Patterns},
        UpdatedEvent = Event#event{event_info = UpdatedEventInfo},
        UpdatedTraceState =
          TraceState#trace_state{done = [UpdatedEvent|RestEvents]},
        {UpdatedTraceState, max_cv(ActorClock, MessageClock)};
      _ -> {TraceState, ActorClock}
    end,
  {BaseNewOldTrace, BaseNewClock} =
    more_interleavings_for_event(OldTrace, BaseTraceState, BaseClock, State),
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
  ?trace_nl(Logger, "NewClock :~w~n", [NewClock]),
  BaseNewClockMap = dict:store(Actor, NewClock, ClockMap),
  NewClockMap =
    case Special of
      [{new, SpawnedPid}] -> dict:store(SpawnedPid, NewClock, BaseNewClockMap);
      _ -> BaseNewClockMap
    end,
  case Actor of
    {_, _} ->
      #message_event{message = #message{message_id = IdB}} = EventInfo,
      ets:update_element(MessageInfo, IdB, {?message_delivered, NewClock});
    _ ->
      maybe_mark_sent_messages(Special, NewClock, MessageInfo)
  end,
  NewTraceState = BaseTraceState#trace_state{clock_map = NewClockMap},
  NewOldTrace = [NewTraceState|BaseNewOldTrace],
  plan_more_interleavings(Rest, NewOldTrace, NewClockMap, State).

more_interleavings_for_event(OldTrace, TraceState, Clock, State) ->
  #trace_state{done = [Event|_], index = _Index} = TraceState,
  #scheduler_state{logger = Logger} = State,
  ?trace_nl(Logger, "===~nRaces ~s~n",
            [concuerror_printer:pretty_s({_Index, Event})]),
  ?trace_nl(Logger, "BaseClock:~w~n", [Clock]),
  more_interleavings_for_event(OldTrace, [TraceState], Event, Clock, State).

more_interleavings_for_event([], Trace, _Event, Clock, _State) ->
  [_|NewTrace] = lists:reverse(Trace),
  {NewTrace, Clock};
more_interleavings_for_event([TraceState|Rest], Trace, Event, Clock, State) ->
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
            AllSleeping = extract_actors(Sleeping, Done),
            NotDep = not_dep(Trace, EarlyActor, EarlyIndex, AllSleeping),
            case NotDep =:= skip of
              true ->
                {update_clock, NC};
              false ->
                #trace_state{wakeup_tree = WakeupTree} = TraceState,
                case insert_wakeup(WakeupTree, NotDep) of
                  skip ->
                    {update_clock, NC};
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
        end
    end,
  {NewTrace, NewClock} =
    case Action of
      none -> {[TraceState|Trace], Clock};
      {update_clock, C} ->
        ?trace_nl(Logger, "SKIP~n",[]),
        {[TraceState|Trace], C};
      {update, S, C} -> {[S|Trace], C}
    end,
  more_interleavings_for_event(Rest, NewTrace, Event, NewClock, State).

maybe_mark_sent_messages([], _Clock, _MessageI) -> true;
maybe_mark_sent_messages([{messages, Messages}|Rest], Clock, MessageInfo) ->
  Foreach =
    fun(#message_event{message = #message{message_id = Id}}) ->
        ets:update_element(MessageInfo, Id, {?message_sent, Clock})
    end,
  lists:foreach(Foreach, Messages),
  maybe_mark_sent_messages(Rest, Clock, MessageInfo);
maybe_mark_sent_messages([_|Rest], Clock, MessageInfo) ->
  maybe_mark_sent_messages(Rest, Clock, MessageInfo).

extract_actors(EventsA, EventsB) ->
  extract_actors(EventsA, EventsB, ordsets:new()).

extract_actors([], [], Acc) -> Acc;
extract_actors([], [#event{actor = Actor}|Rest], Acc) ->
  extract_actors([], Rest, ordsets:add_element(Actor, Acc));
extract_actors([#event{actor = Actor}|Rest], Events, Acc) ->
  extract_actors(Rest, Events, ordsets:add_element(Actor, Acc)).

not_dep(Trace, Actor, Index, Sleeping) ->
  not_dep(Trace, Actor, Index, Sleeping, orddict:new(), []).

not_dep([], _Actor, _Index, _Sleeping, _WIClock, NotDep) ->
  lists:reverse(NotDep);
not_dep([TraceState|Rest], Actor, Index, Sleeping, WIClock, NotDep) ->
  #trace_state{
     clock_map = ClockMap,
     done = [#event{actor = LaterActor} = Event|_],
     index = LaterIndex
    } = TraceState,
  LaterClock = lookup_clock(LaterActor, ClockMap),
  ActorLaterClock = lookup_clock_value(Actor, LaterClock),
  Result =
    case Index > ActorLaterClock of
      false -> {WIClock, NotDep};
      true ->
        ND =
          case Rest =/= [] of
            true -> [Event|NotDep];
            false ->
              %% The racing event's effect may have differ, so new label.
              [Event#event{label = undefined}|NotDep]
          end,
        case is_weak_initial(WIClock, LaterClock) of
          false -> {WIClock, ND};
          true ->
            case ordsets:is_element(LaterActor, Sleeping) of
              true -> skip;
              false ->
                {orddict:store(LaterActor, LaterIndex, WIClock), ND}
            end
        end
    end,
  case Result of
    skip -> skip;
    {NewWIClock, NewNotDep} ->
      not_dep(Rest, Actor, Index, Sleeping, NewWIClock, NewNotDep)
  end.

is_weak_initial(WIClock, Clock) ->
  Fold =
    fun(Key, Value, Acc) ->
        Acc andalso (lookup_clock_value(Key, Clock) < Value)
    end,
  orddict:fold(Fold, true, WIClock).

insert_wakeup([], NotDep) ->
  Fold = fun(Event, Acc) -> [{Event, Acc}] end,
  lists:foldr(Fold, [], NotDep);
insert_wakeup([{Event, Deeper} = Node|Rest], NotDep) ->
  case check_initial(Event, NotDep) of
    skip -> skip;
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
    true -> skip;
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
      ?debug(Logger, "New interleaving~n", []),
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
  Foreach = fun(P) -> P ! reset end,
  lists:foreach(Foreach, Processes),
  ok = concuerror_callback:start_first_process(FirstProcess, Target),
  ok = replay_prefix_aux(lists:reverse(Trace), State).

replay_prefix_aux([_], _State) ->
  %% Last state has to be properly replayed.
  ok;
replay_prefix_aux([#trace_state{done = [Event|_], index = I}|Rest], State) ->
  #scheduler_state{logger = Logger} = State,
  ?trace(Logger, "replay~n~s~n", [concuerror_printer:pretty_s({I, Event})]),
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
  Foreach = fun(P) -> P ! reset, P ! stop end,
  lists:foreach(Foreach, Processes),
  ?trace(Logger, "Reached the end!~n",[]),
  State.

%% =============================================================================
%% INTERNAL INTERFACES
%% =============================================================================

%% Between scheduler and an instrumented process
%%------------------------------------------------------------------------------

get_next_event_backend(#event{actor = {_Sender, Recipient}} = Event, State) ->
  #scheduler_state{processes = Processes, timeout = _Timeout} = State,
  case ordsets:is_element(Recipient, Processes) of
    true ->
      #event{event_info = EventInfo} = Event,
      #message_event{message = Message, type = Type} = EventInfo,
      %% Message delivery always succeeds
      Recipient ! {Type, Message},
      UpdatedEvent =
        receive
          {trapping, Trapping} ->
            NewEventInfo = EventInfo#message_event{trapping = Trapping},
            Event#event{event_info = NewEventInfo}
        end,
      {ok, UpdatedEvent}
    %% false ->
    %%   %% Sending to system process. Sender must wait for immediate reply!
    %%   Sender ! {system, Event},
    %%   receive
    %%     {system_reply, UpdatedEvent} -> UpdatedEvent
    %%   after
    %%     Timeout -> error(timeout)
    %%   end
  end;
get_next_event_backend(#event{actor = Pid} = Event, State) when is_pid(Pid) ->
  Pid ! Event,
  get_next_event_backend_loop(State).

get_next_event_backend_loop(#scheduler_state{timeout = Timeout} = State) ->
  receive
    {blocked, _} -> retry;
    unavailable -> error(process_has_exited);
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
      get_next_event_backend_loop(State);
    {known_process, Pid, Query} ->
      #scheduler_state{processes = Procs} = State,
      Pid ! {known_process, ordsets:is_element(Query, Procs)},
      get_next_event_backend_loop(State)
  after
    Timeout -> error(timeout)
  end.

ets_new(Scheduler, Name, Options) ->
  Scheduler ! {ets_new, self(), Name, Options},
  receive
    {ets_new, Reply} -> Reply
  end.

known_process(Scheduler, Pid) ->
  Scheduler ! {known_process, self(), Pid},
  receive
    {known_process, Reply} -> Reply
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
