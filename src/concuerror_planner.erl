-module(concuerror_planner).

-include("concuerror.hrl").

-export([run/1]).



%% %% =============================================================================
%% %% DATA STRUCTURES
%% %% =============================================================================

-ifdef(BEFORE_OTP_17).
%% Not supported.
-else.
-ifdef(BEFORE_OTP_18).
-type clock_vector() :: orddict:orddict().
-else.
-type clock_vector() :: orddict:orddict(pid(), index()).
-endif.
-endif.

-ifdef(BEFORE_OTP_17).
-type clock_map()           :: dict().
-type message_event_queue() :: queue().
-else.
-type clock_map()           :: dict:dict(pid(), clock_vector()).
-type message_event_queue() :: queue:queue(#message_event{}).
-endif.


-record(backtrack_entry, {
          conservative = false :: boolean(),
          event                :: event(),
          origin = 1           :: integer(),
          wakeup_tree = []     :: event_tree()
         }).

-type event_tree() :: [#backtrack_entry{}].

-type channel_actor() :: {channel(), message_event_queue()}.

-record(trace_state, {
          actors           = []         :: [pid() | channel_actor()],
          clock_map        = dict:new() :: clock_map(),
          done             = []         :: [event()],
          enabled          = []         :: [pid() | channel_actor()],
          index            = 1          :: index(),
          graph_ref        = make_ref() :: reference(),
          previous_actor   = 'none'     :: 'none' | actor(),
          scheduling_bound = infinity   :: concuerror_options:bound(),
          sleeping         = []         :: [event()],
          wakeup_tree      = []         :: event_tree()
         }).

-type trace_state() :: #trace_state{}.

%% DO NOT ADD A DEFAULT VALUE IF IT WILL ALWAYS BE OVERWRITTEN.
%% Default values for fields should be specified in ONLY ONE PLACE.
%% For e.g., user options this is normally in the _options module.
-record(scheduler_state, {
          assertions_only              :: boolean(),
          assume_racing                :: assume_racing_opt(),
          current_graph_ref            :: 'undefined' | reference(),
          depth_bound                  :: pos_integer(),
          disable_sleep_sets           :: boolean(),
          dpor                         :: concuerror_options:dpor(),
          entry_point                  :: mfargs(),
          exploring            = 1     :: integer(),
          first_process                :: pid(),
          ignore_error                 :: [concuerror_options:ignore_error()],
          interleaving_bound           :: concuerror_options:bound(),
          keep_going                   :: boolean(),
          logger                       :: pid(),
	  planner                      :: pid(),  %%par_added
          last_scheduled               :: pid(),
          need_to_replay       = false :: boolean(),
          non_racing_system            :: [atom()],
          origin               = 1     :: integer(),
          parallel                     :: boolean(),
          print_depth                  :: pos_integer(),
          processes                    :: processes(),
          receive_timeout_total = 0    :: non_neg_integer(),
          scheduling                   :: concuerror_options:scheduling(),
          scheduling_bound_type        :: concuerror_options:scheduling_bound_type(),
          show_races                   :: boolean(),
          strict_scheduling            :: boolean(),
          system                       :: [pid()],
          timeout                      :: timeout(),
          trace                        :: [trace_state()],
          treat_as_normal              :: [atom()],
          unsound_bpor                 :: boolean(),
          use_receive_patterns         :: boolean(),
          warnings             = []    :: [concuerror_warning_info()]
         }).

-record(planner_status, {
	  scheduler       :: pid(),
	  logger          :: pid(),
	  scheduler_state :: concuerror_scheduler:scheduler_state()
	 }).



-spec run(concuerror_options:options()) -> ok.

run(Options) ->
    SchedulerOptions = [{planner, self()}|Options],
    Logger = ?opt(logger, Options),
    process_flag(trap_exit, true),
    Scheduler = 
        spawn_link(concuerror_scheduler, run, [SchedulerOptions]),
    receive 
	{initial, InitialState} -> 
	    InitialStatus = 
		#planner_status{
		   scheduler = Scheduler, 
		   logger = Logger, 
		   scheduler_state = InitialState
		  },
	    loop(InitialStatus);
	{'EXIT', Scheduler, Reason} ->%% will need to fix that to work with many schedulers 
	    case Reason of
		normal ->
		    ok;
		_Else ->
		    exit(Reason)
	    end
    end.


loop(Status) ->
    #planner_status{scheduler = Scheduler, logger = _Logger} = Status,
    receive
	{crash, Class, Reason, Stack} ->
	    Scheduler ! exit,
	    erlang:raise(Class, Reason, Stack);
	{explored, {Trace, Warnings, Exploring, BoundExceeded}}  ->
	    put(bound_exceeded, BoundExceeded),
	    #planner_status{scheduler_state = PreviousState} = Status,
	    State = 
		PreviousState#scheduler_state{
		  trace = Trace,
		  warnings = Warnings, 
		  exploring = Exploring
		 },
	    RacesDetectedState = plan_more_interleavings(State),
	    LogState = concuerror_scheduler:log_trace(RacesDetectedState),
	    {HasMore, NewState} = has_more_to_explore(LogState),
	    case HasMore of
		true -> 
		    #scheduler_state{
		       trace = NewTrace, 
		       warnings = NewWarnings, 
		       exploring = NewExploring
		      } = NewState,
		    Scheduler ! {explore, {NewTrace, NewWarnings, NewExploring, get(bound_exceeded)}},
		    loop(Status#planner_status{scheduler_state = NewState});
		false ->
		    Scheduler ! exit,
		    ok
	    end;
	{'EXIT', Scheduler, Reason} ->%% will need to fix that to work with many schedulers
	    case Reason of
		normal ->
		    ok;
		_Else ->
		    exit(Reason)
	    end
	    %% will need to also cleanup the rest of 
	    %%the schedulers when there are going to be more than one
    end.


%%------------------------------------------------------------------------------
%% THE NEXT 3 FUNCTIONS ARE REPLICATED FROM CONCUERROR_SCHEDULER
%%------------------------------------------------------------------------------ 


next_bound(SchedulingBoundType, Done, PreviousActor, Bound) ->
  case SchedulingBoundType of
    none -> Bound;
    bpor ->
      NonPreemptExplored =
        [E || #event{actor = PA} = E <- Done, PA =:= PreviousActor] =/= [],
      case NonPreemptExplored of
        true -> Bound - 1;
        false -> Bound
      end;
    delay ->
      %% Every reschedule costs.
      Bound - length(Done)
  end.

patch_message_delivery({message_delivered, MessageEvent}, ReceiveInfoDict) ->
  #message_event{message = #message{id = Id}} = MessageEvent,
  ReceiveInfo =
    case dict:find(Id, ReceiveInfoDict) of
      {ok, RI} -> RI;
      error -> not_received
    end,
  {message_delivered, MessageEvent#message_event{receive_info = ReceiveInfo}};
patch_message_delivery(Other, _ReceiveInfoDict) ->
  Other.


msg(after_timeout_tip) ->
  "You can use e.g. '--after_timeout 2000' to treat after"
    " clauses that exceed some threshold (here 2000ms) as 'impossible'.~n";
msg(assertions_only_filter) ->
  "Only assertion failures are considered crashes ('--assertions_only').~n";
msg(assertions_only_use) ->
  "A process crashed with reason '{{assert*,_}, _}'. If you want to see only"
    " this kind of error you can use the '--assertions_only' option.~n";
msg(depth_bound) ->
  "An interleaving reached the depth bound. This can happen if a test has an"
    " infinite execution. Concuerror is not sound for testing programs with"
    " infinite executions. Consider limiting the size of the test or increasing"
    " the bound ('-h depth_bound').~n";
msg(maybe_receive_loop) ->
  "The trace contained more than ~w receive timeout events"
    " (receive statements that executed their 'after' clause). Concuerror by"
    " default treats 'after' clauses as always possible, so a 'receive loop'"
    " using a timeout can lead to an infinite execution. "
    ++ msg(after_timeout_tip);
msg(signal) ->
  "An abnormal exit signal was sent to a process. This is probably the worst"
    " thing that can happen race-wise, as any other side-effecting"
    " operation races with the arrival of the signal. If the test produces"
    " too many interleavings consider refactoring your code.~n";
msg(show_races) ->
  "You can see pairs of racing instructions (in the report and"
    " '--graph') with '--show_races true'~n";
msg(shutdown) ->
  "A process crashed with reason 'shutdown'. This may happen when a"
    " supervisor is terminating its children. You can use '--treat_as_normal"
    " shutdown' if this is expected behaviour.~n";
msg(sleep_set_block) ->
  "Some interleavings were 'sleep-set blocked'. This is expected, since you are"
    " not using '--dpor optimal', but indicates wasted effort.~n";
msg(stop_first_error) ->
  "Stop testing on first error. (Check '-h keep_going').~n";
msg(timeout) ->
  "A process crashed with reason '{timeout, ...}'. This may happen when a"
    " call to a gen_server (or similar) does not receive a reply within some"
    " standard timeout. "
    ++ msg(after_timeout_tip);
msg(treat_as_normal) ->
  "Some abnormal exit reasons were treated as normal ('--treat_as_normal').~n".




%%------------------------------------------------------------------------------

plan_more_interleavings(#scheduler_state{dpor = none} = State) ->
  #scheduler_state{logger = _Logger} = State,
  ?debug(_Logger, "Skipping race detection~n", []),
  State;
plan_more_interleavings(State) ->
  #scheduler_state{
     dpor = DPOR,
     logger = Logger,
     trace = RevTrace,
     use_receive_patterns = UseReceivePatterns
    } = State,
  ?time(Logger, "Assigning happens-before..."),
  {RevEarly, Late} =
    case UseReceivePatterns of
      false ->
        {RE, UntimedLate} = split_trace(RevTrace),
        {RE, assign_happens_before(UntimedLate, RE, State)};
      true ->
        {ObsTrace, _Dict} = fix_receive_info(RevTrace),
        {[], assign_happens_before(ObsTrace, [], State)}
    end,
  ?time(Logger, "Planning more interleavings..."),
  NewRevTrace =
    case DPOR =:= optimal of
      true ->
        plan_more_interleavings(lists:reverse(RevEarly, Late), [], State);
      false ->
        plan_more_interleavings(Late, RevEarly, State)
    end,
  State#scheduler_state{trace = NewRevTrace}.

split_trace(RevTrace) ->
  split_trace(RevTrace, []).

split_trace([], UntimedLate) ->
  {[], UntimedLate};
split_trace([#trace_state{clock_map = ClockMap} = State|RevEarlier] = RevEarly,
            UntimedLate) ->
  case dict:size(ClockMap) =:= 0 of
    true  -> split_trace(RevEarlier, [State|UntimedLate]);
    false -> {RevEarly, UntimedLate}
  end.

assign_happens_before(UntimedLate, RevEarly, State) ->
  assign_happens_before(UntimedLate, [], RevEarly, State).

assign_happens_before([], RevLate, _RevEarly, _State) ->
  lists:reverse(RevLate);
assign_happens_before([TraceState|Later], RevLate, RevEarly, State) ->
  #scheduler_state{logger = _Logger} = State,
  #trace_state{done = [Event|_], index = Index} = TraceState,
  #event{actor = Actor, special = Special} = Event,
  ClockMap = get_base_clock(RevLate, RevEarly),
  OldClock = lookup_clock(Actor, ClockMap),
  ActorClock = orddict:store(Actor, Index, OldClock),
  ?trace(_Logger, "HB: ~s~n", [?pretty_s(Index,Event)]),
  BaseHappenedBeforeClock =
    add_pre_message_clocks(Special, ClockMap, ActorClock),
  HappenedBeforeClock =
    update_clock(RevLate, RevEarly, Event, BaseHappenedBeforeClock, State),
  BaseNewClockMap = dict:store(Actor, HappenedBeforeClock, ClockMap),
  NewClockMap =
    add_new_and_messages(Special, HappenedBeforeClock, BaseNewClockMap),
  StateClock = lookup_clock(state, ClockMap),
  OldActorClock = lookup_clock_value(Actor, StateClock),
  FinalActorClock = orddict:store(Actor, OldActorClock, HappenedBeforeClock),
  FinalStateClock = orddict:store(Actor, Index, StateClock),
  FinalClockMap =
    dict:store(
      Actor, FinalActorClock,
      dict:store(state, FinalStateClock, NewClockMap)),
  NewTraceState = TraceState#trace_state{clock_map = FinalClockMap},
  assign_happens_before(Later, [NewTraceState|RevLate], RevEarly, State).

get_base_clock(RevLate, RevEarly) ->
  case get_base_clock(RevLate) of
    {ok, V} -> V;
    none ->
      case get_base_clock(RevEarly) of
        {ok, V} -> V;
        none -> dict:new()
      end
  end.

get_base_clock([#trace_state{clock_map = ClockMap}|_]) -> {ok, ClockMap};
get_base_clock([]) -> none.

add_pre_message_clocks([], _, Clock) -> Clock;
add_pre_message_clocks([Special|Specials], ClockMap, Clock) ->
  NewClock =
    case Special of
      {message_delivered, #message_event{message = #message{id = Id}}} ->
        max_cv(Clock, lookup_clock({Id, sent}, ClockMap));
      {message_received, Id} ->
        max_cv(Clock, lookup_clock({Id, delivered}, ClockMap));
      _ -> Clock
    end,
  add_pre_message_clocks(Specials, ClockMap, NewClock).

add_new_and_messages([], _Clock, ClockMap) ->
  ClockMap;
add_new_and_messages([Special|Rest], Clock, ClockMap) ->
  NewClockMap =
    case Special of
      {new, SpawnedPid} ->
        dict:store(SpawnedPid, Clock, ClockMap);
      {message, #message_event{message = #message{id = Id}}} ->
        dict:store({Id, sent}, Clock, ClockMap);
      {message_delivered, #message_event{message = #message{id = Id}}} ->
        dict:store({Id, delivered}, Clock, ClockMap);
      _ -> ClockMap
    end,
  add_new_and_messages(Rest, Clock, NewClockMap).

update_clock(RevLate, RevEarly, Event, Clock, State) ->
  Clock1 = update_clock(RevLate, Event, Clock, State),
  update_clock(RevEarly, Event, Clock1, State).

update_clock([], _Event, Clock, _State) ->
  Clock;
update_clock([TraceState|Rest], Event, Clock, State) ->
  #trace_state{
     done = [#event{actor = EarlyActor} = EarlyEvent|_],
     index = EarlyIndex
    } = TraceState,
  EarlyClock = lookup_clock_value(EarlyActor, Clock),
  NewClock =
    case EarlyIndex > EarlyClock of
      false -> Clock;
      true ->
        #scheduler_state{assume_racing = AssumeRacing} = State,
        Dependent =
          concuerror_dependencies:dependent(EarlyEvent, Event, AssumeRacing),
        ?trace(State#scheduler_state.logger,
               "    ~s ~s~n",
               begin
                 Star = fun(false) -> " ";(_) -> "*" end,
                 [Star(Dependent), ?pretty_s(EarlyIndex,EarlyEvent)]
               end),
        case Dependent =:= false of
          true -> Clock;
          false ->
            #trace_state{clock_map = ClockMap} = TraceState,
            EarlyActorClock = lookup_clock(EarlyActor, ClockMap),
            max_cv(
              Clock, orddict:store(EarlyActor, EarlyIndex, EarlyActorClock))
        end
    end,
  update_clock(Rest, Event, NewClock, State).

plan_more_interleavings([], OldTrace, _SchedulerState) ->
  OldTrace;
plan_more_interleavings([TraceState|Rest], OldTrace, State) ->
  #scheduler_state{
     logger = _Logger,
     non_racing_system = NonRacingSystem
    } = State,
  #trace_state{done = [Event|_], index = Index, graph_ref = Ref} = TraceState,
  #event{actor = Actor, event_info = EventInfo, special = Special} = Event,
  Skip =
    case proplists:lookup(system_communication, Special) of
      {system_communication, System} -> lists:member(System, NonRacingSystem);
      none -> false
    end,
  case Skip of
    true ->
      plan_more_interleavings(Rest, [TraceState|OldTrace], State);
    false ->
      ClockMap = get_base_clock(OldTrace, []),
      StateClock = lookup_clock(state, ClockMap),
      ActorLast = lookup_clock_value(Actor, StateClock),
      ActorClock = orddict:store(Actor, ActorLast, lookup_clock(Actor, ClockMap)),
      BaseClock =
        case ?is_channel(Actor) of
          true ->
            #message_event{message = #message{id = Id}} = EventInfo,
            lookup_clock({Id, sent}, ClockMap);
          false -> ActorClock
        end,
      ?debug(_Logger, "~s~n", [?pretty_s(Index, Event)]),
      GState = State#scheduler_state{current_graph_ref = Ref},
      BaseNewOldTrace =
        more_interleavings_for_event(OldTrace, Event, Rest, BaseClock, GState, Index),
      NewOldTrace = [TraceState|BaseNewOldTrace],
      plan_more_interleavings(Rest, NewOldTrace, State)
  end.

more_interleavings_for_event(OldTrace, Event, Later, Clock, State, Index) ->
  more_interleavings_for_event(OldTrace, Event, Later, Clock, State, Index, []).

more_interleavings_for_event([], _Event, _Later, _Clock, _State, _Index,
                             NewOldTrace) ->
  lists:reverse(NewOldTrace);
more_interleavings_for_event([TraceState|Rest], Event, Later, Clock, State,
                             Index, NewOldTrace) ->
  #trace_state{
     clock_map = EarlyClockMap,
     done = [#event{actor = EarlyActor} = EarlyEvent|_],
     index = EarlyIndex
    } = TraceState,
  EarlyClock = lookup_clock_value(EarlyActor, Clock),
  Action =
    case EarlyIndex > EarlyClock of
      false -> none;
      true ->
        Dependent =
          case concuerror_dependencies:dependent_safe(EarlyEvent, Event) of
            true -> {true, no_observer};
            Other -> Other
          end,
        case Dependent of
          false -> none;
          irreversible -> update_clock;
          {true, ObserverInfo} ->
            ?debug(State#scheduler_state.logger,
                   "   races with ~s~n",
                   [?pretty_s(EarlyIndex, EarlyEvent)]),
            case
              update_trace(
                EarlyEvent, Event, Clock, TraceState,
                Later, NewOldTrace, Rest, ObserverInfo, State)
            of
              skip -> update_clock;
              {UpdatedNewOldTrace, ConservativeCandidates} ->
                {update, UpdatedNewOldTrace, ConservativeCandidates}
            end
        end
    end,
  NC =
    orddict:store(
      EarlyActor, EarlyIndex,
      max_cv(lookup_clock(EarlyActor, EarlyClockMap), Clock)),
  {NewClock, NewTrace, NewRest} =
    case Action of
      none -> {Clock, [TraceState|NewOldTrace], Rest};
      update_clock -> {NC, [TraceState|NewOldTrace], Rest};
      {update, S, CI} ->
        maybe_log_race(TraceState, Index, Event, State),
        NR = add_conservative(Rest, EarlyActor, EarlyClock, CI, State),
        {NC, S, NR}
    end,
  more_interleavings_for_event(NewRest, Event, Later, NewClock, State, Index, NewTrace).

update_trace(
  EarlyEvent, Event, Clock, TraceState,
  Later, NewOldTrace, Rest, ObserverInfo, State
 ) ->
  #scheduler_state{
     dpor = DPOR,
     exploring = Exploring,
     logger = Logger,
     scheduling_bound_type = SchedulingBoundType,
     unsound_bpor = UnsoundBPOR,
     use_receive_patterns = UseReceivePatterns
    } = State,
  #trace_state{
     done = [#event{actor = EarlyActor} = EarlyEvent|Done] = AllDone,
     index = EarlyIndex,
     previous_actor = PreviousActor,
     scheduling_bound = BaseBound,
     sleeping = BaseSleeping,
     wakeup_tree = Wakeup
    } = TraceState,
  Bound = next_bound(SchedulingBoundType, AllDone, PreviousActor, BaseBound),
  DPORInfo =
    {DPOR,
     case DPOR =:= persistent of
       true -> Clock;
       false -> {EarlyActor, EarlyIndex}
     end},
  Sleeping = BaseSleeping ++ Done,
  RevEvent = update_context(Event, EarlyEvent),
  {MaybeNewWakeup, ConservativeInfo} =
    case Bound < 0 of
      true ->
        {over_bound,
         case SchedulingBoundType =:= bpor of
           true ->
             NotDep = not_dep(NewOldTrace, Later, DPORInfo, RevEvent),
             get_initials(NotDep);
           false ->
             false
         end};
      false ->
        NotDep = not_dep(NewOldTrace, Later, DPORInfo, RevEvent),
        {Plan, _} = NW =
          case DPOR =:= optimal of
            true ->
              case UseReceivePatterns of
                false ->
                  {insert_wakeup_optimal(Sleeping, Wakeup, NotDep, Bound, Exploring), false};
                true ->
                  V =
                    case ObserverInfo =:= no_observer of
                      true -> NotDep;
                      false ->
                        NotObsRaw =
                          not_obs_raw(NewOldTrace, Later, ObserverInfo, Event),
                        NotObs = NotObsRaw -- NotDep,
                        NotDep ++ [EarlyEvent#event{label = undefined}] ++ NotObs
                    end,
                  RevV = lists:reverse(V),
                  {FixedV, ReceiveInfoDict} = fix_receive_info(RevV),
                  {FixedRest, _} = fix_receive_info(Rest, ReceiveInfoDict),
                  show_plan(v, Logger, 0, FixedV),
                  case has_weak_initial_before(lists:reverse(FixedRest), FixedV, Logger) of
                    true -> {skip, false};
                    false ->
                      {insert_wakeup_optimal(Done, Wakeup, FixedV, Bound, Exploring), false}
                  end
              end;
            false ->
              Initials = get_initials(NotDep),
              AddCons =
                case SchedulingBoundType =:= bpor of
                  true -> Initials;
                  false -> false
                end,
              {insert_wakeup_non_optimal(Sleeping, Wakeup, Initials, false, Exploring), AddCons}
          end,
        case is_atom(Plan) of
          true -> NW;
          false ->
            show_plan(standard, Logger, EarlyIndex, NotDep),
            NW
        end
    end,
  case MaybeNewWakeup of
    skip ->
      ?debug(Logger, "     SKIP~n",[]),
      skip;
    over_bound ->
      concuerror_logger:bound_reached(Logger),
      case UnsoundBPOR of
        true -> ok;
        false -> put(bound_exceeded, true)
      end,
      {[TraceState|NewOldTrace], ConservativeInfo};
    NewWakeup ->
      NS = TraceState#trace_state{wakeup_tree = NewWakeup},
      concuerror_logger:plan(Logger),
      {[NS|NewOldTrace], ConservativeInfo}
  end.

not_dep(Trace, Later, DPORInfo, RevEvent) ->
  NotDep = not_dep1(Trace, Later, DPORInfo, []),
  lists:reverse([RevEvent|NotDep]).

not_dep1([], [], _DPORInfo, NotDep) ->
  NotDep;
not_dep1([], T, {DPOR, _} = DPORInfo, NotDep) ->
  KeepLooking =
    case DPOR =:= optimal of
      true -> T;
      false -> []
    end,
  not_dep1(KeepLooking,  [], DPORInfo, NotDep);
not_dep1([TraceState|Rest], Later, {DPOR, Info} = DPORInfo, NotDep) ->
  #trace_state{
     clock_map = ClockMap,
     done = [#event{actor = LaterActor} = LaterEvent|_],
     index = LateIndex
    } = TraceState,
  NewNotDep =
    case DPOR =:= persistent of
      true ->
        Clock = Info,
        LaterActorClock = lookup_clock_value(LaterActor, Clock),
        case LateIndex > LaterActorClock of
          true -> NotDep;
          false -> [LaterEvent|NotDep]
        end;
      false ->
        {Actor, Index} = Info,
        LaterClock = lookup_clock(LaterActor, ClockMap),
        ActorLaterClock = lookup_clock_value(Actor, LaterClock),
        case Index > ActorLaterClock of
          false -> NotDep;
          true -> [LaterEvent|NotDep]
        end
    end,
  not_dep1(Rest, Later, DPORInfo, NewNotDep).

update_context(Event, EarlyEvent) ->
  NewEventInfo =
    case Event#event.event_info of
      %% A receive statement...
      #receive_event{message = Msg} = Info when Msg =/= 'after' ->
        %% ... in race with a message.
        case is_process_info_related(EarlyEvent) of
          true -> Info;
          false -> Info#receive_event{message = 'after'}
        end;
      Info -> Info
    end,
  %% The racing event's effect should differ, so new label.
  Event#event{
    event_info = NewEventInfo,
    label = undefined
   }.

is_process_info_related(Event) ->
  case Event#event.event_info of
    #builtin_event{mfargs = {erlang, process_info, _}} -> true;
    _ -> false
  end.

not_obs_raw(NewOldTrace, Later, ObserverInfo, Event) ->
  lists:reverse(not_obs_raw(NewOldTrace, Later, ObserverInfo, Event, [])).

not_obs_raw([], [], _ObserverInfo, _Event, _NotObs) ->
  [];
not_obs_raw([], Later, ObserverInfo, Event, NotObs) ->
  not_obs_raw(Later, [], ObserverInfo, Event, NotObs);
not_obs_raw([TraceState|Rest], Later, ObserverInfo, Event, NotObs) ->
  #trace_state{done = [#event{special = Special} = E|_]} = TraceState,
  case [Id || {message_received, Id} <- Special, Id =:= ObserverInfo] =:= [] of
    true ->
      not_obs_raw(Rest, Later, ObserverInfo, Event, [E|NotObs]);
    false ->
      #event{special = NewSpecial} = Event,
      ObsNewSpecial =
        case lists:keyfind(message_delivered, 1, NewSpecial) of
          {message_delivered, #message_event{message = #message{id = NewId}}} ->
            lists:keyreplace(ObserverInfo, 2, Special, {message_received, NewId});
          _ -> exit(impossible)
        end,
      [E#event{label = undefined, special = ObsNewSpecial}|NotObs]
  end.

has_weak_initial_before([], _, _Logger) ->
  ?debug(_Logger, "No weak initial before~n",[]),
  false;
has_weak_initial_before([TraceState|Rest], V, Logger) ->
  #trace_state{done = [EarlyEvent|Done]} = TraceState,
  case has_initial(Done, [EarlyEvent|V]) of
    true ->
      ?debug(Logger, "Check: ~s~n",[string:join([?pretty_s(0,D)||D<-Done],"~n")]),
      show_plan(initial, Logger, 1, [EarlyEvent|V]),
      true;
    false ->
      ?debug(Logger, "Up~n",[]),
      has_weak_initial_before(Rest, [EarlyEvent|V], Logger)
  end.

show_plan(_Type, _Logger, _Index, _NotDep) ->
  ?debug(
     _Logger, "     PLAN (Type: ~p)~n~s",
     begin
       Indices = lists:seq(_Index, _Index + length(_NotDep) - 1),
       IndexedNotDep = lists:zip(Indices, _NotDep),
       [_Type] ++
         [lists:append(
            [io_lib:format("        ~s~n", [?pretty_s(I,S)])
             || {I,S} <- IndexedNotDep])]
     end).

maybe_log_race(TraceState, Index, Event, State) ->
  #scheduler_state{logger = Logger} = State,
  if State#scheduler_state.show_races ->
      #trace_state{done = [EarlyEvent|_], index = EarlyIndex} = TraceState,
      EarlyRef = TraceState#trace_state.graph_ref,
      Ref = State#scheduler_state.current_graph_ref,
      concuerror_logger:graph_race(Logger, EarlyRef, Ref),
      IndexedEarly = {EarlyIndex, EarlyEvent#event{location = []}},
      IndexedLate = {Index, Event#event{location = []}},
      concuerror_logger:race(Logger, IndexedEarly, IndexedLate);
     true ->
      ?unique(Logger, ?linfo, msg(show_races), [])
  end.

insert_wakeup_non_optimal(Sleeping, Wakeup, Initials, Conservative, Exploring) ->
  case existing(Sleeping, Initials) of
    true -> skip;
    false -> add_or_make_compulsory(Wakeup, Initials, Conservative, Exploring)
  end.

add_or_make_compulsory(Wakeup, Initials, Conservative, Exploring) ->
  add_or_make_compulsory(Wakeup, Initials, Conservative, Exploring, []).

add_or_make_compulsory([], [E|_], Conservative, Exploring, Acc) ->
  Entry =
    #backtrack_entry{
       conservative = Conservative,
       event = E, origin = Exploring,
       wakeup_tree = []
      },
  lists:reverse([Entry|Acc]);
add_or_make_compulsory([Entry|Rest], Initials, Conservative, Exploring, Acc) ->
  #backtrack_entry{conservative = C, event = E, wakeup_tree = []} = Entry,
  #event{actor = A} = E,
  Pred = fun(#event{actor = B}) -> A =:= B end,
  case lists:any(Pred, Initials) of
    true ->
      case C andalso not Conservative of
        true ->
          NewEntry = Entry#backtrack_entry{conservative = false},
          lists:reverse(Acc, [NewEntry|Rest]);
        false -> skip
      end;
    false ->
      NewAcc = [Entry|Acc],
      add_or_make_compulsory(Rest, Initials, Conservative, Exploring, NewAcc)
  end.

insert_wakeup_optimal(Sleeping, Wakeup, V, Bound, Exploring) ->
  case has_initial(Sleeping, V) of
    true -> skip;
    false -> insert_wakeup(Wakeup, V, Bound, Exploring)
  end.

has_initial([Event|Rest], V) ->
  case check_initial(Event, V) =:= false of
    true -> has_initial(Rest, V);
    false -> true
  end;
has_initial([], _) -> false.

insert_wakeup(          _, _NotDep,  Bound, _Exploring) when Bound < 0 ->
  over_bound;
insert_wakeup(         [],  NotDep, _Bound,  Exploring) ->
  backtrackify(NotDep, Exploring);
insert_wakeup([Node|Rest],  NotDep,  Bound,  Exploring) ->
  #backtrack_entry{event = Event, origin = M, wakeup_tree = Deeper} = Node,
  case check_initial(Event, NotDep) of
    false ->
      NewBound =
        case is_integer(Bound) of
          true -> Bound - 1;
          false -> Bound
        end,
      case insert_wakeup(Rest, NotDep, NewBound, Exploring) of
        Special
          when
            Special =:= skip;
            Special =:= over_bound -> Special;
        NewTree -> [Node|NewTree]
      end;
    NewNotDep ->
      case Deeper =:= [] of
        true  -> skip;
        false ->
          case insert_wakeup(Deeper, NewNotDep, Bound, Exploring) of
            Special
              when
                Special =:= skip;
                Special =:= over_bound -> Special;
            NewTree ->
              Entry =
                #backtrack_entry{
                   event = Event,
                   origin = M,
                   wakeup_tree = NewTree},
              [Entry|Rest]
          end
      end
  end.

backtrackify(Seq, Cause) ->
  Fold =
    fun(Event, Acc) ->
        [#backtrack_entry{event = Event, origin = Cause, wakeup_tree = Acc}]
    end,
  lists:foldr(Fold, [], Seq).

check_initial(Event, NotDep) ->
  check_initial(Event, NotDep, []).

check_initial(_Event, [], Acc) ->
  lists:reverse(Acc);
check_initial(Event, [E|NotDep], Acc) ->
  #event{actor = EventActor} = Event,
  #event{actor = EActor} = E,
  case EventActor =:= EActor of
    true -> lists:reverse(Acc,NotDep);
    false ->
      case concuerror_dependencies:dependent_safe(E, Event) =:= false of
        true -> check_initial(Event, NotDep, [E|Acc]);
        false -> false
      end
  end.

get_initials(NotDeps) ->
  get_initials(NotDeps, [], []).

get_initials([], Initials, _) -> lists:reverse(Initials);
get_initials([Event|Rest], Initials, All) ->
  Fold =
    fun(Initial, Acc) ->
        Acc andalso
          concuerror_dependencies:dependent_safe(Initial, Event) =:= false
    end,
  NewInitials =
    case lists:foldr(Fold, true, All) of
      true -> [Event|Initials];
      false -> Initials
    end,
  get_initials(Rest, NewInitials, [Event|All]).            

existing([], _) -> false;
existing([#event{actor = A}|Rest], Initials) ->
  Pred = fun(#event{actor = B}) -> A =:= B end,
  lists:any(Pred, Initials) orelse existing(Rest, Initials).

add_conservative(Rest, _Actor, _Clock, false, _State) ->
  Rest;
add_conservative(Rest, Actor, Clock, Candidates, State) ->
  case add_conservative(Rest, Actor, Clock, Candidates, State, []) of
    abort ->
      ?debug(State#scheduler_state.logger, "  aborted~n",[]),
      Rest;
    NewRest -> NewRest
  end.

add_conservative([], _Actor, _Clock, _Candidates, _State, _Acc) ->
  abort;
add_conservative([TraceState|Rest], Actor, Clock, Candidates, State, Acc) ->
  #scheduler_state{
     exploring = Exploring,
     logger = _Logger
    } = State,
  #trace_state{
     done = [#event{actor = EarlyActor} = _EarlyEvent|Done],
     enabled = Enabled,
     index = EarlyIndex,
     previous_actor = PreviousActor,
     sleeping = BaseSleeping,
     wakeup_tree = Wakeup
    } = TraceState,
  ?debug(_Logger,
         "   conservative check with ~s~n",
         [?pretty_s(EarlyIndex, _EarlyEvent)]),
  case EarlyActor =:= Actor of
    false -> abort;
    true ->
      case EarlyIndex < Clock of
        true -> abort;
        false ->
          case PreviousActor =:= Actor of
            true ->
              NewAcc = [TraceState|Acc],
              add_conservative(Rest, Actor, Clock, Candidates, State, NewAcc);
            false ->
              EnabledCandidates =
                [C ||
                  #event{actor = A} = C <- Candidates,
                  lists:member(A, Enabled)],
              case EnabledCandidates =:= [] of
                true -> abort;
                false ->
                  Sleeping = BaseSleeping ++ Done,
                  case
                    insert_wakeup_non_optimal(
                      Sleeping, Wakeup, EnabledCandidates, true, Exploring
                     )
                  of
                    skip -> abort;
                    NewWakeup ->
                      NS = TraceState#trace_state{wakeup_tree = NewWakeup},
                      lists:reverse(Acc, [NS|Rest])
                  end
              end
          end
      end
  end.

%%------------------------------------------------------------------------------

has_more_to_explore(State) ->
  #scheduler_state{
     scheduling_bound_type = SchedulingBoundType,
     trace = Trace
    } = State,
  TracePrefix = find_prefix(Trace, SchedulingBoundType),
  case TracePrefix =:= [] of
    true -> {false, State#scheduler_state{trace = []}};
    false ->
      NewState =
        State#scheduler_state{need_to_replay = true, trace = TracePrefix},
      {true, NewState}
  end.

find_prefix([], _SchedulingBoundType) -> [];
find_prefix(Trace, SchedulingBoundType) ->
  [#trace_state{wakeup_tree = Tree} = TraceState|Rest] = Trace,
  case SchedulingBoundType =/= 'bpor' orelse get(bound_exceeded) of
    false ->
      case [B || #backtrack_entry{conservative = false} = B <- Tree] of
        [] -> find_prefix(Rest, SchedulingBoundType);
        WUT -> [TraceState#trace_state{wakeup_tree = WUT}|Rest]
      end;
    true ->
      case Tree =:= [] of
        true -> find_prefix(Rest, SchedulingBoundType);
        false -> Trace
      end
  end.

fix_receive_info(RevTraceOrEvents) ->
  fix_receive_info(RevTraceOrEvents, dict:new()).

fix_receive_info(RevTraceOrEvents, ReceiveInfoDict) ->
  fix_receive_info(RevTraceOrEvents, ReceiveInfoDict, []).

fix_receive_info([], ReceiveInfoDict, TraceOrEvents) ->
  {TraceOrEvents, ReceiveInfoDict};
fix_receive_info([#trace_state{} = TraceState|RevTrace], ReceiveInfoDict, Trace) ->
  [Event|Rest] = TraceState#trace_state.done,
  {[NewEvent], NewDict} = fix_receive_info([Event], ReceiveInfoDict, []),
  NewTraceState = TraceState#trace_state{done = [NewEvent|Rest]},
  fix_receive_info(RevTrace, NewDict, [NewTraceState|Trace]);
fix_receive_info([#event{} = Event|RevEvents], ReceiveInfoDict, Events) ->
  #event{event_info = EventInfo, special = Special} = Event,
  NewReceiveInfoDict = store_receive_info(EventInfo, Special, ReceiveInfoDict),
  NewSpecial = [patch_message_delivery(S, NewReceiveInfoDict) || S <- Special],
  NewEventInfo =
    case EventInfo of
      #message_event{} ->
        {_, NI} =
          patch_message_delivery({message_delivered, EventInfo}, NewReceiveInfoDict),
        NI;
      _ -> EventInfo
    end,
  NewEvent = Event#event{event_info = NewEventInfo, special = NewSpecial},
  fix_receive_info(RevEvents, NewReceiveInfoDict, [NewEvent|Events]).

store_receive_info(EventInfo, Special, ReceiveInfoDict) ->
  case [ID || {message_received, ID} <- Special] of
    [] -> ReceiveInfoDict;
    IDs ->
      ReceiveInfo =
        case EventInfo of
          #receive_event{receive_info = RI} -> RI;
          _ -> {system, fun(_) -> true end}
        end,
      Fold = fun(ID,Dict) -> dict:store(ID, ReceiveInfo, Dict) end,
      lists:foldl(Fold, ReceiveInfoDict, IDs)
  end.

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

    

