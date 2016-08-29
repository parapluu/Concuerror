%% -*- erlang-indent-level: 2 -*-

-module(concuerror_scheduler).

%% User interface
-export([run/1, explain_error/1]).

%%------------------------------------------------------------------------------

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

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

%% =============================================================================
%% DATA STRUCTURES
%% =============================================================================

-record(backtrack_entry, {
          event            :: event(),
          origin = 1       :: integer(),
          wakeup_tree = [] :: event_tree()
         }).

-type event_tree() :: [#backtrack_entry{}].

-type channel_actor() :: {channel(), message_event_queue()}.

-record(trace_state, {
          actors           = []         :: [pid() | channel_actor()],
          clock_map        = dict:new() :: clock_map(),
          done             = []         :: [event()],
          index            = 1          :: index(),
          graph_ref        = make_ref() :: reference(),
          scheduling_bound = infinity   :: bound(),
          sleeping         = []         :: [event()],
          wakeup_tree      = []         :: event_tree()
         }).

-type trace_state() :: #trace_state{}.

-record(scheduler_state, {
          assertions_only              :: boolean(),
          assume_racing                :: boolean(),
          current_graph_ref            :: 'undefined' | reference(),
          depth_bound                  :: pos_integer(),
          dpor                         :: dpor(),
          entry_point                  :: mfargs(),
          exploring            = 1     :: integer(),
          first_process                :: pid(),
          ignore_error                 :: [atom()],
          interleaving_bound           :: pos_integer(),
          keep_going                   :: boolean(),
          logger                       :: pid(),
          last_scheduled               :: pid(),
          need_to_replay       = false :: boolean(),
          non_racing_system            :: [atom()],
          origin               = 1     :: integer(),
          print_depth                  :: pos_integer(),
          processes                    :: processes(),
          scheduling                   :: scheduling(),
          scheduling_bound_type        :: scheduling_bound_type(),
          show_races                   :: boolean(),
          strict_scheduling            :: boolean(),
          system                       :: [pid()],
          timeout                      :: timeout(),
          trace                        :: [trace_state()],
          treat_as_normal              :: [atom()],
          warnings             = []    :: [concuerror_warning_info()]
         }).

%% =============================================================================
%% LOGIC (high level description of the exploration algorithm)
%% =============================================================================

-spec run(concuerror_options:options()) -> ok.

run(Options) ->
  process_flag(trap_exit, true),
  {FirstProcess, System} =
    concuerror_callback:spawn_first_process(Options),
  InitialTrace =
    #trace_state{
       actors = [FirstProcess],
       scheduling_bound = ?opt(scheduling_bound, Options)
      },
  InitialState =
    #scheduler_state{
       assertions_only = ?opt(assertions_only, Options),
       assume_racing = ?opt(assume_racing, Options),
       depth_bound = ?opt(depth_bound, Options) + 1,
       dpor = ?opt(dpor, Options),
       entry_point = EntryPoint = ?opt(entry_point, Options),
       first_process = FirstProcess,
       ignore_error = ?opt(ignore_error, Options),
       interleaving_bound = ?opt(interleaving_bound, Options),
       keep_going = ?opt(keep_going, Options),
       last_scheduled = FirstProcess,
       logger = Logger = ?opt(logger, Options),
       non_racing_system = ?opt(non_racing_system, Options),
       print_depth = ?opt(print_depth, Options),
       processes = ?opt(processes, Options),
       scheduling = ?opt(scheduling, Options),
       scheduling_bound_type = ?opt(scheduling_bound_type, Options),
       show_races = ?opt(show_races, Options),
       strict_scheduling = ?opt(strict_scheduling, Options),
       system = System,
       trace = [InitialTrace],
       treat_as_normal = ?opt(treat_as_normal, Options),
       timeout = Timeout = ?opt(timeout, Options)
      },
  ok = concuerror_callback:start_first_process(FirstProcess, EntryPoint, Timeout),
  concuerror_logger:plan(Logger),
  ?time(Logger, "Exploration start"),
  explore(InitialState).

%%------------------------------------------------------------------------------

explore(State) ->
  {Status, UpdatedState} =
    try
      get_next_event(State)
    catch
      C:R ->
        S = erlang:get_stacktrace(),
        {{crash, C, R, S}, State}
    end,
  case Status of
    ok -> explore(UpdatedState);
    none ->
      RacesDetectedState = plan_more_interleavings(UpdatedState),
      LogState = log_trace(RacesDetectedState),
      {HasMore, NewState} = has_more_to_explore(LogState),
      case HasMore of
        true -> explore(NewState);
        false -> ok
      end;
    {crash, Class, Reason, Stack} ->
      #scheduler_state{trace = [_|Trace]} = UpdatedState,
      FatalCrashState = add_warning(fatal, Trace, UpdatedState),
      catch log_trace(FatalCrashState),
      erlang:raise(Class, Reason, Stack)
  end.

%%------------------------------------------------------------------------------

log_trace(#scheduler_state{exploring = N, logger = Logger} = State) ->
  Log =
    case filter_warnings(State) of
      [] -> none;
      Warnings ->
        case proplists:get_value(sleep_set_block, Warnings) of
          {Origin, Sleep} ->
            case State#scheduler_state.dpor =:= optimal of
              false ->
                ?unique(Logger, ?lwarning, msg(sleep_set_block), []);
              true ->
                ?crash({optimal_sleep_set_block, Origin, Sleep})
            end,
            sleep_set_block;
          undefined ->
            #scheduler_state{trace = Trace} = State,
            Fold =
              fun(#trace_state{done = [A|_], index = I}, Acc) ->
                  [{I, A}|Acc]
              end,
            TraceInfo = lists:foldl(Fold, [], Trace),
            {lists:reverse(Warnings), TraceInfo}
        end
    end,
  concuerror_logger:complete(Logger, Log),
  case Log =/= none andalso Log =/= sleep_set_block of
    true when not State#scheduler_state.keep_going ->
      ?unique(Logger, ?lerror, msg(stop_first_error), []),
      State#scheduler_state{trace = []};
    Other ->
      case Other of
        true ->
          ?unique(Logger, ?linfo, "Continuing after error (-k)~n", []);
        false ->
          ok
      end,
      NextExploring = N + 1,
      NextState = State#scheduler_state{exploring = N + 1, warnings = []},
      case NextExploring =< State#scheduler_state.interleaving_bound of
        true -> NextState;
        false ->
          UniqueMsg = "Reached interleaving bound (~p)~n",
          ?unique(Logger, ?lwarning, UniqueMsg, [N]),
          NextState#scheduler_state{trace = []}
      end
  end.

filter_warnings(State) ->
  #scheduler_state{
     ignore_error = Ignored,
     logger = Logger,
     warnings = UnfilteredWarnings
    } = State,
  filter_warnings(UnfilteredWarnings, Ignored, Logger).

filter_warnings(Warnings, [], _) -> Warnings;
filter_warnings(Warnings, [Ignore|Rest] = Ignored, Logger) ->
  case lists:keytake(Ignore, 1, Warnings) of
    false -> filter_warnings(Warnings, Rest, Logger);
    {value, _, NewWarnings} ->
      UniqueMsg = "Some errors were ignored ('--ignore_error').~n",
      ?unique(Logger, ?lwarning, UniqueMsg, []),
      filter_warnings(NewWarnings, Ignored, Logger)
  end.

add_warning(Warning, #scheduler_state{trace = Trace} = State) ->
  add_warning(Warning, Trace, State).

add_warning(Warning, Trace, State) ->
  add_warnings([Warning], Trace, State).

add_warnings(Warnings, Trace, State) ->
  #scheduler_state{warnings = OldWarnings} = State,
  State#scheduler_state{
    warnings = Warnings ++ OldWarnings,
    trace = Trace
   }.

%%------------------------------------------------------------------------------

get_next_event(
  #scheduler_state{
     depth_bound = Bound,
     logger = Logger,
     trace = [#trace_state{index = Bound}|Old]} = State) ->
  UniqueMsg =
    "An interleaving reached the depth bound (~p). Consider limiting the size"
    " of the test or increasing the bound ('-d').~n",
  ?unique(Logger, ?lwarning, UniqueMsg, [Bound - 1]),
  NewState = add_warning({depth_bound, Bound - 1}, Old, State),
  {none, NewState};
get_next_event(#scheduler_state{logger = _Logger, trace = [Last|_]} = State) ->
  #trace_state{wakeup_tree = WakeupTree} = Last,
  case WakeupTree of
    [] ->
      Event = #event{label = make_ref()},
      get_next_event(Event, State);
    [#backtrack_entry{event = Event, origin = N}|_] ->
      ?debug(_Logger, "New interleaving detected in ~p~n", [N]),
      get_next_event(Event, State#scheduler_state{origin = N})
  end.

get_next_event(Event, MaybeNeedsReplayState) ->
  State = replay(MaybeNeedsReplayState),
  #scheduler_state{system = System, trace = [Last|_]} = State,
  #trace_state{actors = Actors, sleeping = Sleeping} = Last,
  SortedActors = schedule_sort(Actors, State),
  #event{actor = Actor, label = Label} = Event,
  case Actor =:= undefined of
    true ->
      AvailableActors = filter_sleeping(Sleeping, SortedActors),
      free_schedule(Event, System ++ AvailableActors, State);
    false ->
      false = lists:member(Actor, Sleeping),
      {ok, UpdatedEvent} =
        case Label =/= undefined of
          true ->
            NewEvent = get_next_event_backend(Event, State),
            try {ok, Event} = NewEvent
            catch
              _:_ ->
                #scheduler_state{print_depth = PrintDepth} = State,
                #trace_state{index = I} = Last,
                New =
                  case NewEvent of
                    {ok, E} -> E;
                    _ -> NewEvent
                  end,
                Reason =
                  {replay_mismatch, I, Event, New, PrintDepth},
                ?crash(Reason)
            end;
          false ->
            %% Last event = Previously racing event = Result may differ.
            ResetEvent = reset_event(Event),
            get_next_event_backend(ResetEvent, State)
        end,
      update_state(UpdatedEvent, State)
  end.

filter_sleeping([], AvailableActors) -> AvailableActors;
filter_sleeping([#event{actor = Actor}|Sleeping], AvailableActors) ->
  NewAvailableActors =
    case ?is_channel(Actor) of
      true -> lists:keydelete(Actor, 1, AvailableActors);
      false -> lists:delete(Actor, AvailableActors)
    end,
  filter_sleeping(Sleeping, NewAvailableActors).

schedule_sort([], _State) -> [];
schedule_sort(Actors, State) ->
  #scheduler_state{
     last_scheduled = LastScheduled,
     scheduling = Scheduling,
     strict_scheduling = StrictScheduling
    } = State,
  Sorted =
    case Scheduling of
      oldest -> Actors;
      newest -> lists:reverse(Actors);
      round_robin ->
        Split = fun(E) -> E =/= LastScheduled end,    
        {Pre, Post} = lists:splitwith(Split, Actors),
        Post ++ Pre
    end,
  case StrictScheduling of
    true when Scheduling =:= round_robin ->
      [LastScheduled|Rest] = Sorted,
      Rest ++ [LastScheduled];
    false when Scheduling =/= round_robin ->
      [LastScheduled|lists:delete(LastScheduled, Sorted)];
    _ -> Sorted
  end.

free_schedule(Event, Actors, State) ->
  #scheduler_state{dpor = DPOR, logger = Logger, trace = [Last|Prev]} = State,
  case DPOR =/= none of
    true -> free_schedule_1(Event, Actors, State);
    false ->
      Enabled = [A || A <- Actors, enabled(A)],
      Eventify = [#event{actor = E} || E <- Enabled],
      FullBacktrack = [#backtrack_entry{event = Ev} || Ev <- Eventify],
      case FullBacktrack of
        [] -> ok;
        [_|L] ->
          _ = [concuerror_logger:plan(Logger) || _ <- L],
          ok
      end,
      NewLast = Last#trace_state{wakeup_tree = FullBacktrack},
      NewTrace = [NewLast|Prev],
      NewState = State#scheduler_state{trace = NewTrace},
      free_schedule_1(Event, Actors, NewState)
  end.

enabled({_,_}) -> true;
enabled(P) -> concuerror_callback:enabled(P).

free_schedule_1(Event, [{Channel, Queue}|_], State) ->
  %% Pending messages can always be sent
  MessageEvent = queue:get(Queue),
  UpdatedEvent = Event#event{actor = Channel, event_info = MessageEvent},
  {ok, FinalEvent} = get_next_event_backend(UpdatedEvent, State),
  update_state(FinalEvent, State);
free_schedule_1(Event, [P|ActiveProcesses], State) ->
  case get_next_event_backend(Event#event{actor = P}, State) of
    retry -> free_schedule_1(Event, ActiveProcesses, State);
    {ok, UpdatedEvent} -> update_state(UpdatedEvent, State)
  end;
free_schedule_1(_Event, [], State) ->
  %% Nothing to do, trace is completely explored
  #scheduler_state{logger = _Logger, trace = [Last|Prev]} = State,
  #trace_state{actors = Actors, sleeping = Sleeping} = Last,
  NewWarnings =
    case Sleeping =/= [] of
      true ->
        ?debug(_Logger, "Sleep set block:~n ~p~n", [Sleeping]),
        [{sleep_set_block, {State#scheduler_state.origin, Sleeping}}];
      false ->
        case concuerror_callback:collect_deadlock_info(Actors) of
          [] -> [];
          Info ->
            ?debug(_Logger, "Deadlock: ~p~n", [[P || {P,_} <- Info]]),
            [{deadlock, Info}]
        end
    end,
  {none, add_warnings(NewWarnings, Prev, State)}.

reset_event(#event{actor = Actor, event_info = EventInfo}) ->
  ResetEventInfo =
    case ?is_channel(Actor) of
      true -> EventInfo;
      false -> undefined
    end,
  #event{
     actor = Actor,
     event_info = ResetEventInfo,
     label = make_ref()
    }.

%%------------------------------------------------------------------------------

update_state(#event{special = Special} = Event, State) ->
  #scheduler_state{
     logger = Logger,
     scheduling_bound_type = SchedulingBoundType,
     trace  = [Last|Prev]
    } = State,
  #trace_state{
     actors      = Actors,
     done        = Done,
     index       = Index,
     graph_ref   = Ref,
     scheduling_bound = SchedulingBound,
     sleeping    = Sleeping,
     wakeup_tree = WakeupTree
    } = Last,
  ?trace(Logger, "~s~n", [?pretty_s(Index, Event)]),
  concuerror_logger:graph_new_node(Logger, Ref, Index, Event, 0),
  AllSleeping = ordsets:union(ordsets:from_list(Done), Sleeping),
  NextSleeping = update_sleeping(Event, AllSleeping, State),
  {NewLastWakeupTree, NextWakeupTree} =
    case WakeupTree of
      [] -> {[], []};
      [#backtrack_entry{wakeup_tree = NWT}|Rest] -> {Rest, NWT}
    end,
  NewSchedulingBound =
    case SchedulingBoundType of
      none -> SchedulingBound;
      simple ->
        %% First reschedule costs one point, otherwise nothing.
        case Done of
          [_] -> SchedulingBound - 1;
          _ -> SchedulingBound
        end
    end,
  NewLastDone = [Event|Done],
  InitNextTrace =
    #trace_state{
       actors      = Actors,
       index       = Index + 1,
       scheduling_bound = NewSchedulingBound,
       sleeping    = NextSleeping,
       wakeup_tree = NextWakeupTree
      },
  NewLastTrace =
    Last#trace_state{
      done = NewLastDone,
      scheduling_bound = NewSchedulingBound,
      wakeup_tree = NewLastWakeupTree
     },
  InitNewState =
    State#scheduler_state{trace = [InitNextTrace, NewLastTrace|Prev]},
  NewState = maybe_log(Event, InitNewState, Index),
  {ok, update_special(Special, NewState)}.

maybe_log(#event{actor = P} = Event, State0, Index) ->
  #scheduler_state{
     assertions_only = AssertionsOnly,
     logger = Logger,
     treat_as_normal = Normal
    } = State0,
  State = 
    case is_pid(P) of
      true -> State0#scheduler_state{last_scheduled = P};
      false -> State0
    end,
  case Event#event.event_info of
    #exit_event{reason = Reason} = Exit when Reason =/= normal ->
      {Tag, WasTimeout} =
        if tuple_size(Reason) > 0 ->
            T = element(1, Reason),
            {T, T =:= timeout};
           true -> {Reason, false}
        end,
      case is_atom(Tag) andalso lists:member(Tag, Normal) of
        true ->
          ?unique(Logger, ?lwarning, msg(treat_as_normal), []),
          State;
        false ->
          if WasTimeout -> ?unique(Logger, ?ltip, msg(timeout), []);
             Tag =:= shutdown -> ?unique(Logger, ?ltip, msg(shutdown), []);
             true -> ok
          end,
          IsAssertLike =
            case Tag of
              {MaybeAssert, _} when is_atom(MaybeAssert) ->
                case atom_to_list(MaybeAssert) of
                  "assert"++_ -> true;
                  _ -> false
                end;
              _ -> false
            end,
          Report =
            case {IsAssertLike, AssertionsOnly} of
              {false, true} ->
                ?unique(Logger, ?lwarning, msg(assertions_only_filter), []),
                false;
              {true, false} ->
                ?unique(Logger, ?ltip, msg(assertions_only_use), []),
                true;
              _ -> true
            end,
          if Report ->
              #event{actor = Actor} = Event,
              Stacktrace = Exit#exit_event.stacktrace,
              add_warning({crash, {Index, Actor, Reason, Stacktrace}}, State);
             true -> State
          end
      end;
    #builtin_event{mfargs = {erlang, exit, [_,Reason]}}
      when Reason =/= normal ->
      ?unique(Logger, ?ltip, msg(signal), []),
      State;
    _ -> State
  end.

update_sleeping(NewEvent, Sleeping, State) ->
  #scheduler_state{logger = _Logger} = State,
  Pred =
    fun(OldEvent) ->
        V = concuerror_dependencies:dependent_safe(OldEvent, NewEvent),
        ?trace(_Logger, "     Awaking (~p): ~s~n", [V,?pretty_s(OldEvent)]),
        V =:= false
    end,
  lists:filter(Pred, Sleeping).

update_special(List, State) when is_list(List) ->
  lists:foldl(fun update_special/2, State, List);
update_special(Special, State) ->
  #scheduler_state{trace = [#trace_state{actors = Actors} = Next|Trace]} = State,
  NewActors =
    case Special of
      halt -> [];
      {message, Message} ->
        add_message(Message, Actors);
      {message_delivered, MessageEvent} ->
        remove_message(MessageEvent, Actors);
      {message_received, _Message} ->
        Actors;
      {new, SpawnedPid} ->
        Actors ++ [SpawnedPid];
      {system_communication, _} ->
        Actors
    end,
  NewNext = Next#trace_state{actors = NewActors},
  State#scheduler_state{trace = [NewNext|Trace]}.

add_message(MessageEvent, Actors) ->
  #message_event{recipient = Recipient, sender = Sender} = MessageEvent,
  Channel = {Sender, Recipient},
  Update = fun(Queue) -> queue:in(MessageEvent, Queue) end,
  Initial = queue:from_list([MessageEvent]),
  insert_message(Channel, Update, Initial, Actors).

insert_message(Channel, Update, Initial, Actors) ->
  insert_message(Channel, Update, Initial, Actors, false, []).

insert_message(Channel, _Update, Initial, [], Found, Acc) ->
  case Found of
    true -> lists:reverse(Acc, [{Channel, Initial}]);
    false -> [{Channel, Initial}|lists:reverse(Acc)]
  end;
insert_message(Channel, Update, _Initial, [{Channel, Queue}|Rest], true, Acc) ->
  NewQueue = Update(Queue),
  lists:reverse(Acc, [{Channel, NewQueue}|Rest]);
insert_message({From, _} = Channel, Update, Initial, [Other|Rest], Found, Acc) ->
  case Other of
    {{_,_},_} ->
      insert_message(Channel, Update, Initial, Rest, Found, [Other|Acc]);
    From ->
      insert_message(Channel, Update, Initial, Rest,  true, [Other|Acc]);
    _ ->
      case Found of
        false ->
          insert_message(Channel, Update, Initial, Rest, Found, [Other|Acc]);
        true ->
          lists:reverse(Acc, [{Channel, Initial},Other|Rest])
      end
  end.

remove_message(#message_event{recipient = Recipient, sender = Sender}, Actors) ->
  Channel = {Sender, Recipient},
  remove_message(Channel, Actors, []).

remove_message(Channel, [{Channel, Queue}|Rest], Acc) ->
  NewQueue = queue:drop(Queue),
  case queue:is_empty(NewQueue) of
    true  -> lists:reverse(Acc, Rest);
    false -> lists:reverse(Acc, [{Channel, NewQueue}|Rest])
  end;
remove_message(Channel, [Other|Rest], Acc) ->
  remove_message(Channel, Rest, [Other|Acc]).

%%------------------------------------------------------------------------------

plan_more_interleavings(#scheduler_state{dpor = none} = State) ->
  #scheduler_state{logger = _Logger} = State,
  ?debug(_Logger, "Skipping race detection~n", []),
  State;
plan_more_interleavings(State) ->
  #scheduler_state{logger = Logger, trace = RevTrace} = State,
  ?time(Logger, "Assigning happens-before..."),
  {RevEarly, UntimedLate} = split_trace(RevTrace),
  Late = assign_happens_before(UntimedLate, RevEarly, State),
  ?time(Logger, "Planning more interleavings..."),
  NewRevTrace = plan_more_interleavings(lists:reverse(RevEarly, Late), [], State),
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
        case Dependent of
          false -> Clock;
          True when True =:= true; True =:= irreversible ->
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
  #scheduler_state{logger = Logger} = State,
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
          concuerror_dependencies:dependent_safe(EarlyEvent, Event),
        case Dependent of
          false -> none;
          irreversible -> update_clock;
          true ->
            ?debug(Logger, "   races with ~s~n",
                   [?pretty_s(EarlyIndex, EarlyEvent)]),
            case
              update_trace(Event, TraceState, Later, NewOldTrace, State)
            of
              skip -> update_clock;
              UpdatedNewOldTrace ->
                concuerror_logger:plan(Logger),
                {update, UpdatedNewOldTrace}
            end
        end
    end,
  NC =
    orddict:store(
      EarlyActor, EarlyIndex,
      max_cv(lookup_clock(EarlyActor, EarlyClockMap), Clock)),
  {NewClock, NewTrace} =
    case Action of
      none -> {Clock, [TraceState|NewOldTrace]};
      update_clock -> {NC, [TraceState|NewOldTrace]};
      {update, S} ->
        maybe_log_race(TraceState, Index, Event, State),
        {NC, S}
    end,
  more_interleavings_for_event(Rest, Event, Later, NewClock, State, Index, NewTrace).

update_trace(Event, TraceState, Later, NewOldTrace, State) ->
  #scheduler_state{
     dpor = DPOR,
     exploring = Exploring,
     logger = Logger,
     scheduling_bound_type = SchedulingBoundType
    } = State,
  #trace_state{
     done = [#event{actor = EarlyActor}|Done],
     scheduling_bound = BaseBound,
     index = EarlyIndex,
     sleeping = BaseSleeping,
     wakeup_tree = Wakeup
    } = TraceState,
  Bound =
    case SchedulingBoundType of
      none -> BaseBound;
      simple ->
        case Done =:= [] of
          true -> BaseBound - 1;
          false -> BaseBound
        end
    end,
  MaybeNewWakeup =
    case Bound =:= -1 of
      true -> over_bound;
      false ->
        NotDep = not_dep(NewOldTrace, Later, EarlyActor, EarlyIndex, Event),
        Sleeping = BaseSleeping ++ Done,
        NW = insert_wakeup(Sleeping, Wakeup, NotDep, DPOR, Bound, Exploring),
        show_plan(NW, Logger, EarlyIndex, NotDep),
        NW
    end,
  case MaybeNewWakeup of
    skip ->
      ?debug(Logger, "     SKIP~n",[]),
      skip;
    over_bound ->
      concuerror_logger:bound_reached(Logger),
      skip;
    NewWakeup ->
      NS = TraceState#trace_state{wakeup_tree = NewWakeup},
      [NS|NewOldTrace]
  end.

not_dep(Trace, Later, Actor, Index, Event) ->
  not_dep(Trace, Later, Actor, Index, Event, []).

not_dep([], [], _Actor, _Index, Event, NotDep) ->
  %% The racing event's effect may differ, so new label.
  lists:reverse([Event#event{label = undefined}|NotDep]);
not_dep([], T, Actor, Index, Event, NotDep) ->
  not_dep(T,  [], Actor, Index, Event, NotDep);
%% %% This is a reasonable (but unproven) optimisation for filtering the wakeup
%% %% sequence...
%% not_dep([], [#trace_state{sleeping=S} = H|T], Actor, Index, Event, NotDep) ->
%%   case S =:= [] of
%%     true  -> not_dep( [], [], Actor, Index, Event, NotDep);
%%     false -> not_dep([H],  T, Actor, Index, Event, NotDep)
%%   end;
not_dep([TraceState|Rest], Later, Actor, Index, Event, NotDep) ->
  #trace_state{
     clock_map = ClockMap,
     done = [#event{actor = LaterActor} = LaterEvent|_]
    } = TraceState,
  LaterClock = lookup_clock(LaterActor, ClockMap),
  ActorLaterClock = lookup_clock_value(Actor, LaterClock),
  NewNotDep =
    case Index > ActorLaterClock of
      false -> NotDep;
      true -> [LaterEvent|NotDep]
    end,
  not_dep(Rest, Later, Actor, Index, Event, NewNotDep).

show_plan(Atom, _, _, _) when is_atom(Atom) ->
  ok;
show_plan(_NW, _Logger, _Index, _NotDep) ->
  ?debug(
     _Logger, "     PLAN~n~s",
     begin
       Indices = lists:seq(_Index, _Index + length(_NotDep) - 1),
       IndexedNotDep = lists:zip(Indices, _NotDep),
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

insert_wakeup(Sleeping, Wakeup, NotDep, DPOR, Bound, Exploring) ->
  case DPOR =:= optimal of
    true -> insert_wakeup_1(Sleeping, Wakeup, NotDep, Bound, Exploring);
    false ->
      Initials = get_initials(NotDep),
      All =
        Sleeping ++
        [W || #backtrack_entry{event = W, wakeup_tree = []} <- Wakeup],
      case existing(All, Initials) of
        true -> skip;
        false ->
          [E|_] = NotDep,
          Entry =
            #backtrack_entry{event = E, origin = Exploring, wakeup_tree = []},
          Wakeup ++ [Entry]
      end
  end.      

insert_wakeup_1(Sleeping, Wakeup, NotDep, Bound, Exploring) ->
  case has_sleeping_initial(Sleeping, NotDep) of
    true -> skip;
    false -> insert_wakeup(Wakeup, NotDep, Bound, true, Exploring)
  end.

has_sleeping_initial([Sleeping|Rest], NotDep) ->
  case check_initial(Sleeping, NotDep) =:= false of
    true -> has_sleeping_initial(Rest, NotDep);
    false -> true
  end;
has_sleeping_initial([], _) -> false.

insert_wakeup(          _, _NotDep,     -1, _Paid, _Exploring) ->
  over_bound;
insert_wakeup(         [],  NotDep, _Bound, _Paid,  Exploring) ->
  backtrackify(NotDep, Exploring);
insert_wakeup([Node|Rest],  NotDep,  Bound,  Paid,  Exploring) ->
  #backtrack_entry{event = Event, origin = M, wakeup_tree = Deeper} = Node,
  case check_initial(Event, NotDep) of
    false ->
      {NewBound, NewPaid} =
        case {is_integer(Bound), Paid} of
          {true, false} -> {Bound - 1, true};
          _ -> {Bound, Paid}
        end,
      case insert_wakeup(Rest, NotDep, NewBound, NewPaid, Exploring) of
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
          case insert_wakeup(Deeper, NewNotDep, Bound, false, Exploring) of
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
      case concuerror_dependencies:dependent_safe(Event, E) of
        True when True =:= true; True =:= irreversible -> false;
        false -> check_initial(Event, NotDep, [E|Acc])
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

%%------------------------------------------------------------------------------

has_more_to_explore(#scheduler_state{trace = Trace} = State) ->
  TracePrefix = find_prefix(Trace, State),
  case TracePrefix =:= [] of
    true -> {false, State#scheduler_state{trace = []}};
    false ->
      NewState =
        State#scheduler_state{need_to_replay = true, trace = TracePrefix},
      {true, NewState}
  end.

find_prefix([#trace_state{wakeup_tree = []}|Rest], State) ->
  find_prefix(Rest, State);
find_prefix(Trace, _State) -> Trace.

replay(#scheduler_state{need_to_replay = false} = State) ->
  State;
replay(State) ->
  #scheduler_state{exploring = N, logger = Logger, trace = Trace} = State,
  [#trace_state{graph_ref = Sibling} = Last|
   [#trace_state{graph_ref = Parent}|_] = Rest] = Trace,
  concuerror_logger:graph_set_node(Logger, Parent, Sibling),
  NewTrace =
    [Last#trace_state{graph_ref = make_ref(), clock_map = dict:new()}|Rest],
  S = io_lib:format("New interleaving ~p. Replaying...", [N]),
  ?time(Logger, S),
  NewState = replay_prefix(NewTrace, State#scheduler_state{trace = NewTrace}),
  ?debug(Logger, "~s~n",["Replay done."]),
  NewState#scheduler_state{need_to_replay = false}.

%% =============================================================================
%% ENGINE (manipulation of the Erlang processes under the scheduler)
%% =============================================================================

replay_prefix(Trace, State) ->
  #scheduler_state{
     entry_point = EntryPoint,
     first_process = FirstProcess,
     processes = Processes,
     timeout = Timeout
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
  ok =
    concuerror_callback:start_first_process(FirstProcess, EntryPoint, Timeout),
  NewState = State#scheduler_state{last_scheduled = FirstProcess},
  replay_prefix_aux(lists:reverse(Trace), NewState).

replay_prefix_aux([_], State) ->
  %% Last state has to be properly replayed.
  State;
replay_prefix_aux([#trace_state{done = [Event|_], index = I}|Rest], State) ->
  #scheduler_state{logger = _Logger, print_depth = PrintDepth} = State,
  ?trace(_Logger, "~s~n", [?pretty_s(I, Event)]),
  {ok, #event{actor = Actor} = NewEvent} = get_next_event_backend(Event, State),
  try
    true = Event =:= NewEvent
  catch
    _:_ ->
      #scheduler_state{print_depth = PrintDepth} = State,
      ?crash({replay_mismatch, I, Event, NewEvent, PrintDepth})
  end,
  NewLastScheduled =
    case is_pid(Actor) of
      true -> Actor;
      false -> State#scheduler_state.last_scheduled
    end,
  NewState = State#scheduler_state{last_scheduled = NewLastScheduled},
  replay_prefix_aux(Rest, maybe_log(Event, NewState, I)).

%% =============================================================================
%% INTERNAL INTERFACES
%% =============================================================================

%% Between scheduler and an instrumented process
%%------------------------------------------------------------------------------

get_next_event_backend(#event{actor = Channel} = Event, State)
  when ?is_channel(Channel) ->
  #scheduler_state{timeout = Timeout} = State,
  #event{event_info = MessageEvent} = Event,
  assert_no_messages(),
  UpdatedEvent =
    concuerror_callback:deliver_message(Event, MessageEvent, Timeout),
  {ok, UpdatedEvent};
get_next_event_backend(#event{actor = Pid} = Event, State) when is_pid(Pid) ->
  #scheduler_state{timeout = Timeout} = State,
  assert_no_messages(),
  Pid ! Event,
  concuerror_callback:wait_actor_reply(Event, Timeout).

assert_no_messages() ->
  receive
    Msg -> error({pending_message, Msg})
  after
    0 -> ok
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

%% =============================================================================

-spec explain_error(term()) -> string().

explain_error({optimal_sleep_set_block, Origin, Who}) ->
  io_lib:format(
    "During a run of the optimal algorithm, the following events were left in~n"
    "a sleep set (the race was detected at interleaving #~p)~n~n"
    "  ~p~n"
    ?notify_us_msg,
    [Origin, Who]
   );
explain_error({replay_mismatch, I, Event, NewEvent, Depth}) ->
  [EString, NEString] =
    [concuerror_printer:pretty_s(E, Depth) || E <- [Event, NewEvent]],
  [Original, New] =
    case EString =/= NEString of
      true -> [EString, NEString];
      false ->
        [io_lib:format("~p",[E]) || E <- [Event, NewEvent]]
    end,
  io_lib:format(
    "On step ~p, replaying a built-in returned a different result than"
    " expected:~n"
    "  original:~n"
    "    ~s~n"
    "  new:~n"
    "    ~s~n"
    ?notify_us_msg,
    [I,Original,New]
   ).

%%==============================================================================

msg(assertions_only_filter) ->
  "Only assertion failures are considered crashes ('--assertions_only').~n";
msg(assertions_only_use) ->
  "A process crashed with reason '{{assert*,_}, _}'. If you want to see only"
    " this kind of error you can use the '--assertions_only' option.~n";
msg(signal) ->
  "An abnormal exit signal was sent to a process. This is probably the worst"
    " thing that can happen race-wise, as any other side-effecting"
    " operation races with the arrival of the signal. If the test produces"
    " too many interleavings consider refactoring your code.~n";
msg(show_races) ->
  "You can see pairs of racing instructions (in the report and"
    " --graph) with '--show_races true'~n";
msg(shutdown) ->
  "A process crashed with reason 'shutdown'. This may happen when a"
    " supervisor is terminating its children. You can use '--treat_as_normal"
    " shutdown' if this is expected behaviour.~n";
msg(sleep_set_block) ->
  "Some interleavings were 'sleep-set blocked'. This is expected, since you are"
    " not using '--dpor optimal', but reveals wasted effort.~n";
msg(stop_first_error) ->
  "Stop testing on first error. (Check '-h keep_going').~n";
msg(timeout) ->
  "A process crashed with reason '{timeout, ...}'. This may happen when a"
    " call to a gen_server (or similar) does not receive a reply within some"
    " standard timeout. Use the '--after_timeout' option to treat after clauses"
    " that exceed some threshold as 'impossible'.~n";
msg(treat_as_normal) ->
  "Some abnormal exit reasons were treated as normal ('--treat_as_normal').~n".
