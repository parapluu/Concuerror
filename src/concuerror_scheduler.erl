%%% @private
%%% @doc Concuerror's scheduler component
%%%
%%% concuerror_scheduler is the main driver of interleaving
%%% exploration.  A rough trace through it is the following:

%%% The entry point is `concuerror_scheduler:run/1` which takes the
%%% options and initializes the exploration, spawning the main
%%% process.  There are plenty of state info that are kept in the
%%% `#scheduler_state` record the most important of which being a list
%%% of `#trace_state` records, recording events in the exploration.
%%% This list corresponds more or less to "E" in the various DPOR
%%% papers (representing the execution trace).

%%% The logic of the exploration goes through `explore_scheduling/1`,
%%% which in turn calls 'explore/1'. Both functions are fairly clean:
%%% as long as there are more processes that can be executed and yield
%%% events, `get_next_event/1` will be returning `ok`, after executing
%%% one of them and doing all necessary updates to the state (adding
%%% new `#trace_state`s, etc).  If `get_next_event/1` returns `none`,
%%% we are at the end of an interleaving (either due to no more
%%% enabled processes or due to "sleep set blocking") and can do race
%%% analysis and report any errors found in the interleaving.  Race
%%% analysis is contained in `plan_more_interleavings/1`, reporting
%%% whether the current interleaving was buggy is contained in
%%% `log_trace/1` and resetting most parts to continue exploration is
%%% contained in `has_more_to_explore/1`.

%%% Focusing on `plan_more_interleavings`, it is composed out of two
%%% steps: first (`assign_happens_before/3`) we assign a
%%% happens-before relation to all events to be able to detect when
%%% races are reversible or not (if two events are dependent not only
%%% directly but also via a chain of dependent events then the race is
%%% not reversible) and then (`plan_more_interleavings/3`) for each
%%% event (`more_interleavings_for_event/6`) we do an actual race
%%% analysis, adding initials or wakeup sequences in appropriate
%%% places in the list of `#trace_state`s.

-module(concuerror_scheduler).

%% User interface
-export([run/1, explain_error/1]).

-export_type([ interleaving_error/0,
               interleaving_error_tag/0,
               interleaving_result/0,
               unique_id/0
             ]).

%% =============================================================================
%% DATA STRUCTURES & TYPES
%% =============================================================================

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-type interleaving_id() :: pos_integer().

-ifdef(BEFORE_OTP_17).
-type clock_map()           :: dict().
-type message_event_queue() :: queue().
-else.
-type vector_clock()        :: #{actor() => index()}.
-type clock_map()           :: #{actor() => vector_clock()}.
-type message_event_queue() :: queue:queue(#message_event{}).
-endif.

-record(backtrack_entry, {
          conservative = false :: boolean(),
          event                :: event(),
          origin = 1           :: interleaving_id(),
          wakeup_tree = []     :: event_tree()
         }).

-type event_tree() :: [#backtrack_entry{}].

-type channel_actor() :: {channel(), message_event_queue()}.

-type unique_id() :: {interleaving_id(), index()}.

-record(trace_state, {
          actors                        :: [pid() | channel_actor()],
          clock_map        = empty_map():: clock_map(),
          done             = []         :: [event()],
          enabled          = []         :: [pid() | channel_actor()],
          index                         :: index(),
          unique_id                     :: unique_id(),
          previous_actor   = 'none'     :: 'none' | actor(),
          scheduling_bound              :: concuerror_options:bound(),
          sleep_set        = []         :: [event()],
          wakeup_tree      = []         :: event_tree()
         }).

-type trace_state() :: #trace_state{}.

-type interleaving_result() ::
        'ok' | 'sleep_set_block' | {[interleaving_error()], [event()]}.

-type interleaving_error_tag() ::
        'abnormal_exit' |
        'abnormal_halt' |
        'deadlock' |
        'depth_bound'.

-type interleaving_error() ::
        {'abnormal_exit', {index(), pid(), term(), [term()]}} |
        {'abnormal_halt', {index(), pid(), term()}} |
        {'deadlock', [pid()]} |
        {'depth_bound', concuerror_options:bound()} |
        'fatal'.

-type scope() :: 'all' | [pid()].

%% DO NOT ADD A DEFAULT VALUE IF IT WILL ALWAYS BE OVERWRITTEN.
%% Default values for fields should be specified in ONLY ONE PLACE.
%% For e.g., user options this is normally in the _options module.
-record(scheduler_state, {
          assertions_only :: boolean(),
          assume_racing :: assume_racing_opt(),
          depth_bound :: pos_integer(),
          dpor :: concuerror_options:dpor(),
          entry_point :: mfargs(),
          estimator :: concuerror_estimator:estimator(),
          first_process :: pid(),
          ignore_error :: [{interleaving_error_tag(), scope()}],
          interleaving_bound :: concuerror_options:bound(),
          interleaving_errors :: [interleaving_error()],
          interleaving_id :: interleaving_id(),
          keep_going :: boolean(),
          logger :: pid(),
          last_scheduled :: pid(),
          need_to_replay :: boolean(),
          non_racing_system :: [atom()],
          origin :: interleaving_id(),
          print_depth :: pos_integer(),
          processes :: processes(),
          receive_timeout_total :: non_neg_integer(),
          report_error :: [{interleaving_error_tag(), scope()}],
          scheduling :: concuerror_options:scheduling(),
          scheduling_bound_type :: concuerror_options:scheduling_bound_type(),
          show_races :: boolean(),
          strict_scheduling :: boolean(),
          timeout :: timeout(),
          trace :: [trace_state()],
          treat_as_normal :: [atom()],
          use_receive_patterns :: boolean(),
          use_sleep_sets :: boolean(),
          use_unsound_bpor :: boolean()
         }).

%% =============================================================================
%% LOGIC (high level description of the exploration algorithm)
%% =============================================================================

-spec run(concuerror_options:options()) -> ok.

run(Options) ->
  process_flag(trap_exit, true),
  put(bound_exceeded, false),
  FirstProcess = concuerror_callback:spawn_first_process(Options),
  EntryPoint = ?opt(entry_point, Options),
  Timeout = ?opt(timeout, Options),
  ok =
    concuerror_callback:start_first_process(FirstProcess, EntryPoint, Timeout),
  SchedulingBound = ?opt(scheduling_bound, Options, infinity),
  InitialTrace =
    #trace_state{
       actors = [FirstProcess],
       enabled = [E || E <- [FirstProcess], enabled(E)],
       index = 1,
       scheduling_bound = SchedulingBound,
       unique_id = {1, 1}
      },
  Logger = ?opt(logger, Options),
  {SchedulingBoundType, UnsoundBPOR} =
    case ?opt(scheduling_bound_type, Options) of
      ubpor -> {bpor, true};
      Else -> {Else, false}
    end,
  {IgnoreError, ReportError} =
    generate_filtering_rules(Options, FirstProcess),
  InitialState =
    #scheduler_state{
       assertions_only = ?opt(assertions_only, Options),
       assume_racing = {?opt(assume_racing, Options), Logger},
       depth_bound = ?opt(depth_bound, Options) + 1,
       dpor = ?opt(dpor, Options),
       entry_point = EntryPoint,
       estimator = ?opt(estimator, Options),
       first_process = FirstProcess,
       ignore_error = IgnoreError,
       interleaving_bound = ?opt(interleaving_bound, Options),
       interleaving_errors = [],
       interleaving_id = 1,
       keep_going = ?opt(keep_going, Options),
       last_scheduled = FirstProcess,
       logger = Logger,
       need_to_replay = false,
       non_racing_system = ?opt(non_racing_system, Options),
       origin = 1,
       print_depth = ?opt(print_depth, Options),
       processes = Processes = ?opt(processes, Options),
       receive_timeout_total = 0,
       report_error = ReportError,
       scheduling = ?opt(scheduling, Options),
       scheduling_bound_type = SchedulingBoundType,
       show_races = ?opt(show_races, Options),
       strict_scheduling = ?opt(strict_scheduling, Options),
       trace = [InitialTrace],
       treat_as_normal = ?opt(treat_as_normal, Options),
       timeout = Timeout,
       use_receive_patterns = ?opt(use_receive_patterns, Options),
       use_sleep_sets = not ?opt(disable_sleep_sets, Options),
       use_unsound_bpor = UnsoundBPOR
      },
  case SchedulingBound =:= infinity of
    true ->
      ?unique(Logger, ?ltip, msg(scheduling_bound_tip), []);
    false ->
      ok
  end,
  concuerror_logger:plan(Logger),
  ?time(Logger, "Exploration start"),
  Ret = explore_scheduling(InitialState),
  concuerror_callback:cleanup_processes(Processes),
  Ret.

%%------------------------------------------------------------------------------

explore_scheduling(State) ->
  UpdatedState = explore(State),
  LogState = log_trace(UpdatedState),
  RacesDetectedState = plan_more_interleavings(LogState),
  {HasMore, NewState} = has_more_to_explore(RacesDetectedState),
  case HasMore of
    true -> explore_scheduling(NewState);
    false -> ok
  end.

explore(State) ->
  {Status, UpdatedState} =
    try
      get_next_event(State)
    catch
      C:R ->
        S = [],
        {{crash, C, R, S}, State}
    end,
  case Status of
    ok -> explore(UpdatedState);
    none -> UpdatedState;
    {crash, Class, Reason, Stack} ->
      FatalCrashState =
        add_error(fatal, discard_last_trace_state(UpdatedState)),
      catch log_trace(FatalCrashState),
      erlang:raise(Class, Reason, Stack)
  end.

%%------------------------------------------------------------------------------

log_trace(#scheduler_state{logger = Logger} = State) ->
  Log =
    case filter_errors(State) of
      [] -> none;
      Errors ->
        case proplists:get_value(sleep_set_block, Errors) of
          {Origin, Sleep} ->
            case State#scheduler_state.dpor =:= optimal of
              true -> ?crash({optimal_sleep_set_block, Origin, Sleep});
              false -> ok
            end,
            sleep_set_block;
          undefined ->
            #scheduler_state{trace = Trace} = State,
            Fold =
              fun(#trace_state{done = [A|_], index = I}, Acc) ->
                  [{I, A}|Acc]
              end,
            TraceInfo = lists:foldl(Fold, [], Trace),
            {lists:reverse(Errors), TraceInfo}
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
      InterleavingId = State#scheduler_state.interleaving_id,
      NextInterleavingId = InterleavingId + 1,
      case NextInterleavingId =< State#scheduler_state.interleaving_bound of
        true -> State;
        false ->
          UniqueMsg = "Reached interleaving bound (~p)~n",
          ?unique(Logger, ?lwarning, UniqueMsg, [InterleavingId]),
          State#scheduler_state{trace = []}
      end
  end.

%%------------------------------------------------------------------------------

generate_filtering_rules(Options, FirstProcess) ->
  IgnoreErrors = ?opt(ignore_error, Options),
  OnlyFirstProcessErrors = ?opt(first_process_errors_only, Options),
  case OnlyFirstProcessErrors of
    false -> {[{IE, all} || IE <- IgnoreErrors], []};
    true ->
      AllCategories = [abnormal_exit, abnormal_halt, deadlock],
      Ignored = [{IE, all} || IE <- AllCategories],
      Reported = [{IE, [FirstProcess]} || IE <- AllCategories -- IgnoreErrors],
      {Ignored, Reported}
  end.

filter_errors(State) ->
  #scheduler_state{
     ignore_error = Ignored,
     interleaving_errors = UnfilteredErrors,
     logger = Logger,
     report_error = Reported
    } = State,
  TaggedErrors = [{true, E} || E <- UnfilteredErrors],
  IgnoredErrors = update_all_tags(TaggedErrors, Ignored, false),
  ReportedErrors = update_all_tags(IgnoredErrors, Reported, true),
  FinalErrors = [E || {true, E} <- ReportedErrors],
  case FinalErrors =/= UnfilteredErrors of
    true ->
      UniqueMsg = "Some errors were ignored ('--ignore_error').~n",
      ?unique(Logger, ?lwarning, UniqueMsg, []);
    false -> ok
  end,
  FinalErrors.

update_all_tags([], _, _) -> [];
update_all_tags(TaggedErrors, [], _) -> TaggedErrors;
update_all_tags(TaggedErrors, Rules, Value) ->
  [update_tag(E, Rules, Value) || E <- TaggedErrors].

update_tag({OldTag, Error}, Rules, NewTag) ->
  RuleAppliesPred = fun(Rule) -> rule_applies(Rule, Error) end,
  case lists:any(RuleAppliesPred, Rules) of
    true -> {NewTag, Error};
    false -> {OldTag, Error}
  end.

rule_applies({Tag, Scope}, {Tag, _} = Error) ->
  scope_applies(Scope, Error);
rule_applies(_, _) -> false.

scope_applies(all, _) -> true;
scope_applies(Pids, ErrorInfo) ->
  case ErrorInfo of
    {deadlock, Deadlocked} ->
      DPids = [element(1, D) || D <- Deadlocked],
      DPids -- Pids =/= DPids;
    {abnormal_exit, {_, Pid, _, _}} -> lists:member(Pid, Pids);
    {abnormal_halt, {_, Pid, _}} -> lists:member(Pid, Pids);
    _ -> false
  end.

discard_last_trace_state(State) ->
  #scheduler_state{trace = [_|Trace]} = State,
  State#scheduler_state{trace = Trace}.

add_error(Error, State) ->
  add_errors([Error], State).

add_errors(Errors, State) ->
  #scheduler_state{interleaving_errors = OldErrors} = State,
  State#scheduler_state{interleaving_errors = Errors ++ OldErrors}.

%%------------------------------------------------------------------------------

get_next_event(
  #scheduler_state{
     depth_bound = Bound,
     logger = Logger,
     trace = [#trace_state{index = Bound}|_]} = State) ->
  ?unique(Logger, ?lwarning, msg(depth_bound_reached), []),
  NewState =
    add_error({depth_bound, Bound - 1}, discard_last_trace_state(State)),
  {none, NewState};
get_next_event(#scheduler_state{logger = _Logger, trace = [Last|_]} = State) ->
  #trace_state{index = _I, wakeup_tree = WakeupTree} = Last,
  case WakeupTree of
    [] ->
      Event = #event{label = make_ref()},
      get_next_event(Event, State);
    [#backtrack_entry{event = Event, origin = N}|_] ->
      ?debug(
         _Logger,
         "New interleaving detected in ~p (diverge @ ~p)~n",
         [N, _I]),
      get_next_event(Event, State#scheduler_state{origin = N})
  end.

get_next_event(Event, MaybeNeedsReplayState) ->
  State = replay(MaybeNeedsReplayState),
  #scheduler_state{trace = [Last|_]} = State,
  #trace_state{actors = Actors, sleep_set = SleepSet} = Last,
  SortedActors = schedule_sort(Actors, State),
  #event{actor = Actor, label = Label} = Event,
  case Actor =:= undefined of
    true ->
      AvailableActors = filter_sleep_set(SleepSet, SortedActors),
      free_schedule(Event, AvailableActors, State);
    false ->
      #scheduler_state{print_depth = PrintDepth} = State,
      #trace_state{index = I} = Last,
      false = lists:member(Actor, SleepSet),
      OkUpdatedEvent =
        case Label =/= undefined of
          true ->
            NewEvent = get_next_event_backend(Event, State),
            try {ok, Event} = NewEvent
            catch
              _:_ ->
                New =
                  case NewEvent of
                    {ok, E} -> E;
                    _ -> NewEvent
                  end,
                Reason = {replay_mismatch, I, Event, New, PrintDepth},
                ?crash(Reason)
            end;
          false ->
            %% Last event = Previously racing event = Result may differ.
            ResetEvent = reset_event(Event),
            get_next_event_backend(ResetEvent, State)
        end,
      case OkUpdatedEvent of
        {ok, UpdatedEvent} ->
          update_state(UpdatedEvent, State);
        retry ->
          BReason = {blocked_mismatch, I, Event, PrintDepth},
          ?crash(BReason)
      end
  end.

filter_sleep_set([], AvailableActors) -> AvailableActors;
filter_sleep_set([#event{actor = Actor}|SleepSet], AvailableActors) ->
  NewAvailableActors =
    case ?is_channel(Actor) of
      true -> lists:keydelete(Actor, 1, AvailableActors);
      false -> lists:delete(Actor, AvailableActors)
    end,
  filter_sleep_set(SleepSet, NewAvailableActors).

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
  #scheduler_state{
     dpor = DPOR,
     estimator = Estimator,
     logger = Logger,
     scheduling_bound_type = SchedulingBoundType,
     trace = [Last|Prev]
    } = State,
  case DPOR =/= none of
    true -> free_schedule_1(Event, Actors, State);
    false ->
      Enabled = [A || A <- Actors, enabled(A)],
      ToBeExplored =
        case SchedulingBoundType =:= delay of
          false -> Enabled;
          true ->
            #trace_state{scheduling_bound = SchedulingBound} = Last,
            ?debug(Logger, "Select ~p of ~p~n", [SchedulingBound, Enabled]),
            lists:sublist(Enabled, SchedulingBound + 1)
        end,
      case ToBeExplored < Enabled of
        true -> bound_reached(Logger);
        false -> ok
      end,
      Eventify =
        [maybe_prepare_channel_event(E, #event{}) || E <- ToBeExplored],
      FullBacktrack = [#backtrack_entry{event = Ev} || Ev <- Eventify],
      case FullBacktrack of
        [] -> ok;
        [_|L] ->
          _ = [concuerror_logger:plan(Logger) || _ <- L],
          Index = Last#trace_state.index,
          _ = [concuerror_estimator:plan(Estimator, Index) || _ <- L],
          ok
      end,
      NewLast = Last#trace_state{wakeup_tree = FullBacktrack},
      NewTrace = [NewLast|Prev],
      NewState = State#scheduler_state{trace = NewTrace},
      free_schedule_1(Event, Actors, NewState)
  end.

enabled({_, _}) -> true;
enabled(P) -> concuerror_callback:enabled(P).

free_schedule_1(Event, [Actor|_], State) when ?is_channel(Actor) ->
  %% Pending messages can always be sent
  PrepEvent = maybe_prepare_channel_event(Actor, Event),
  {ok, FinalEvent} = get_next_event_backend(PrepEvent, State),
  update_state(FinalEvent, State);
free_schedule_1(Event, [P|ActiveProcesses], State) ->
  case get_next_event_backend(Event#event{actor = P}, State) of
    retry -> free_schedule_1(Event, ActiveProcesses, State);
    {ok, UpdatedEvent} -> update_state(UpdatedEvent, State)
  end;
free_schedule_1(_Event, [], State) ->
  %% Nothing to do, trace is completely explored
  #scheduler_state{logger = _Logger, trace = [Last|_]} = State,
  #trace_state{actors = Actors, sleep_set = SleepSet} = Last,
  NewErrors =
    case SleepSet =/= [] of
      true ->
        ?debug(_Logger, "Sleep set block:~n ~p~n", [SleepSet]),
        [{sleep_set_block, {State#scheduler_state.origin, SleepSet}}];
      false ->
        case concuerror_callback:collect_deadlock_info(Actors) of
          [] -> [];
          Info ->
            ?debug(_Logger, "Deadlock: ~p~n", [[element(1, I) || I <- Info]]),
            [{deadlock, Info}]
        end
    end,
  {none, add_errors(NewErrors, discard_last_trace_state(State))}.

maybe_prepare_channel_event(Actor, Event) ->
  case ?is_channel(Actor) of
    false -> Event#event{actor = Actor};
    true ->
      {Channel, Queue} = Actor,
      MessageEvent = queue:get(Queue),
      Event#event{actor = Channel, event_info = MessageEvent}
  end.

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

update_state(#event{actor = Actor} = Event, State) ->
  #scheduler_state{
     estimator = Estimator,
     logger = Logger,
     scheduling_bound_type = SchedulingBoundType,
     trace = [Last|Prev],
     use_sleep_sets = UseSleepSets
    } = State,
  #trace_state{
     actors      = Actors,
     done        = RawDone,
     index       = Index,
     previous_actor = PreviousActor,
     scheduling_bound = SchedulingBound,
     sleep_set   = SleepSet,
     unique_id   = {InterleavingId, Index} = UID,
     wakeup_tree = WakeupTree
    } = Last,
  ?debug(Logger, "~s~n", [?pretty_s(Index, Event)]),
  concuerror_logger:graph_new_node(Logger, UID, Index, Event),
  Done = reset_receive_done(RawDone, State),
  NextSleepSet =
    case UseSleepSets of
      true ->
        AllSleepSet =
          case WakeupTree of
            [#backtrack_entry{conservative = true}|_] ->
              concuerror_logger:plan(Logger),
              concuerror_estimator:plan(Estimator, Index),
              SleepSet;
            _ -> ordsets:union(ordsets:from_list(Done), SleepSet)
          end,
        update_sleep_set(Event, AllSleepSet, State);
      false -> []
    end,
  {NewLastWakeupTree, NextWakeupTree} =
    case WakeupTree of
      [] -> {[], []};
      [#backtrack_entry{wakeup_tree = NWT}|Rest] -> {Rest, NWT}
    end,
  NewSchedulingBound =
    next_bound(SchedulingBoundType, Done, PreviousActor, SchedulingBound),
  ?trace(Logger, "  Next bound: ~p~n", [NewSchedulingBound]),
  NewLastDone = [Event|Done],
  NextIndex = Index + 1,
  InitNextTrace =
    #trace_state{
       actors      = Actors,
       index       = NextIndex,
       previous_actor = Actor,
       scheduling_bound = NewSchedulingBound,
       sleep_set   = NextSleepSet,
       unique_id   = {InterleavingId, NextIndex},
       wakeup_tree = NextWakeupTree
      },
  NewLastTrace =
    Last#trace_state{
      done = NewLastDone,
      wakeup_tree = NewLastWakeupTree
     },
  UpdatedSpecialNextTrace =
    update_special(Event#event.special, InitNextTrace),
  NextTrace =
    maybe_update_enabled(SchedulingBoundType, UpdatedSpecialNextTrace),
  InitNewState =
    State#scheduler_state{trace = [NextTrace, NewLastTrace|Prev]},
  NewState = maybe_log(Event, InitNewState, Index),
  {ok, NewState}.

maybe_log(#event{actor = P} = Event, State0, Index) ->
  #scheduler_state{
     assertions_only = AssertionsOnly,
     logger = Logger,
     receive_timeout_total = ReceiveTimeoutTotal,
     treat_as_normal = Normal
    } = State0,
  State =
    case is_pid(P) of
      true -> State0#scheduler_state{last_scheduled = P};
      false -> State0
    end,
  case Event#event.event_info of
    #builtin_event{mfargs = {erlang, halt, [Status|_]}}
      when Status =/= 0 ->
      #event{actor = Actor} = Event,
      add_error({abnormal_halt, {Index, Actor, Status}}, State);
    #exit_event{reason = Reason} = Exit when Reason =/= normal ->
      {Tag, WasTimeout} =
        case is_tuple(Reason) andalso (tuple_size(Reason) > 0) of
          true ->
            T = element(1, Reason),
            {T, T =:= timeout};
          false -> {Reason, false}
        end,
      case is_atom(Tag) andalso lists:member(Tag, Normal) of
        true ->
          ?unique(Logger, ?lwarning, msg(treat_as_normal), []),
          State;
        false ->
          case {WasTimeout, Tag} of
            {true, _} -> ?unique(Logger, ?ltip, msg(timeout), []);
            {_, shutdown} -> ?unique(Logger, ?ltip, msg(shutdown), []);
            _ -> ok
          end,
          IsAssertLike =
            case Tag of
              {MaybeAssert, _} when is_atom(MaybeAssert) ->
                case atom_to_list(MaybeAssert) of
                  "assert" ++ _ -> true;
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
          case Report of
            true ->
              #event{actor = Actor} = Event,
              Stacktrace = Exit#exit_event.stacktrace,
              Error = {abnormal_exit, {Index, Actor, Reason, Stacktrace}},
              add_error(Error, State);
            false -> State
          end
      end;
    #receive_event{message = 'after'} ->
      NewReceiveTimeoutTotal = ReceiveTimeoutTotal + 1,
      Threshold = 50,
      case NewReceiveTimeoutTotal =:= Threshold of
        true ->
          ?unique(Logger, ?ltip, msg(maybe_receive_loop), [Threshold]);
        false -> ok
      end,
      State#scheduler_state{receive_timeout_total = NewReceiveTimeoutTotal};
    _ -> State
  end.

update_sleep_set(NewEvent, SleepSet, State) ->
  #scheduler_state{logger = _Logger} = State,
  Pred =
    fun(OldEvent) ->
        V = concuerror_dependencies:dependent_safe(NewEvent, OldEvent),
        ?debug(_Logger, "     Awaking (~p): ~s~n", [V, ?pretty_s(OldEvent)]),
        V =:= false
    end,
  lists:filter(Pred, SleepSet).

update_special(List, TraceState) when is_list(List) ->
  lists:foldl(fun update_special/2, TraceState, List);
update_special(Special, #trace_state{actors = Actors} = TraceState) ->
  NewActors =
    case Special of
      halt -> [];
      {message, Message} ->
        add_message(Message, Actors);
      {message_delivered, MessageEvent} ->
        remove_message(MessageEvent, Actors);
      {new, SpawnedPid} ->
        Actors ++ [SpawnedPid];
      _ ->
        Actors
    end,
  TraceState#trace_state{actors = NewActors}.

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
insert_message(Channel, Update, Initial, [Other|Rest], Found, Acc) ->
  {From, _} = Channel,
  case Other of
    {{_, _}, _} ->
      insert_message(Channel, Update, Initial, Rest, Found, [Other|Acc]);
    From ->
      insert_message(Channel, Update, Initial, Rest,  true, [Other|Acc]);
    _ ->
      case Found of
        false ->
          insert_message(Channel, Update, Initial, Rest, Found, [Other|Acc]);
        true ->
          lists:reverse(Acc, [{Channel, Initial}, Other|Rest])
      end
  end.

remove_message(MessageEvent, Actors) ->
  #message_event{recipient = Recipient, sender = Sender} = MessageEvent,
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

maybe_update_enabled(bpor, TraceState) ->
  #trace_state{actors = Actors} = TraceState,
  Enabled = [E || E <- Actors, enabled(E)],
  TraceState#trace_state{enabled = Enabled};
maybe_update_enabled(_, TraceState) ->
  TraceState.

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
  {RE, UntimedLate} = split_trace(RevTrace),
  {RevEarly, Late} =
    case UseReceivePatterns of
      false ->
        {RE, lists:reverse(assign_happens_before(UntimedLate, RE, State))};
      true ->
        RevUntimedLate = lists:reverse(UntimedLate),
        {ObsLate, Dict} = fix_receive_info(RevUntimedLate),
        {ObsEarly, _} = fix_receive_info(RE, Dict),
        case lists:reverse(ObsEarly) =:= RE of
          true ->
            {RE, lists:reverse(assign_happens_before(ObsLate, RE, State))};
          false ->
            RevHBEarly = assign_happens_before(ObsEarly, [], State),
            RevHBLate = assign_happens_before(ObsLate, RevHBEarly, State),
            {[], lists:reverse(RevHBLate ++ RevHBEarly)}
        end
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

%%------------------------------------------------------------------------------

split_trace(RevTrace) ->
  split_trace(RevTrace, []).

split_trace([], UntimedLate) ->
  {[], UntimedLate};
split_trace([#trace_state{clock_map = ClockMap} = State|RevEarlier] = RevEarly,
            UntimedLate) ->
  case is_empty_map(ClockMap) of
    true  -> split_trace(RevEarlier, [State|UntimedLate]);
    false -> {RevEarly, UntimedLate}
  end.

%%------------------------------------------------------------------------------

assign_happens_before(UntimedLate, RevEarly, State) ->
  assign_happens_before(UntimedLate, [], RevEarly, State).

assign_happens_before([], RevLate, _RevEarly, _State) ->
  RevLate;
assign_happens_before([TraceState|Later], RevLate, RevEarly, State) ->
  %% We will calculate two separate clocks for each state:
  %% - ops unavoidably needed to reach the state will make up the 'state' clock
  %% - ops that happened before the state, will make up the 'Actor' clock
  #trace_state{done = [Event|_], index = Index} = TraceState,
  #scheduler_state{logger = _Logger} = State,
  #event{actor = Actor, special = Special} = Event,
  ?debug(_Logger, "HB: ~s~n", [?pretty_s(Index, Event)]),
  %% Start from the latest vector clock of the actor itself
  ClockMap = get_base_clock_map(RevLate, RevEarly),
  ActorLastClock = lookup_clock(Actor, ClockMap),
  %% Add the step itself:
  ActorNewClock = clock_store(Actor, Index, ActorLastClock),
  %% And add all irreversible edges
  IrreversibleClock =
    add_pre_message_clocks(Special, ClockMap, ActorNewClock),
  %% Apart from those, for the Actor clock we need all the ops that
  %% affect the state. That is, anything dependent with the step:
  HappenedBeforeClock =
    update_clock(RevLate ++ RevEarly, Event, IrreversibleClock, State),
  %% The 'state' clock contains the irreversible clock or
  %% 'independent' if no other dependencies were found
  StateClock =
    case IrreversibleClock =:= HappenedBeforeClock of
      true -> independent;
      false -> IrreversibleClock
    end,
  BaseNewClockMap = map_store(state, StateClock, ClockMap),
  NewClockMap = map_store(Actor, HappenedBeforeClock, BaseNewClockMap),
  %% The HB clock should also be added to anything else stemming
  %% from the step (spawns, sends and deliveries)
  FinalClockMap =
    add_new_and_messages(Special, HappenedBeforeClock, NewClockMap),
  ?trace(_Logger, "       SC: ~w~n", [StateClock]),
  ?trace(_Logger, "       AC: ~w~n", [HappenedBeforeClock]),
  NewTraceState = TraceState#trace_state{clock_map = FinalClockMap},
  assign_happens_before(Later, [NewTraceState|RevLate], RevEarly, State).

get_base_clock_map(RevLate, RevEarly) ->
  case get_base_clock_map(RevLate) of
    {ok, V} -> V;
    none ->
      case get_base_clock_map(RevEarly) of
        {ok, V} -> V;
        none -> empty_map()
      end
  end.

get_base_clock_map([#trace_state{clock_map = ClockMap}|_]) -> {ok, ClockMap};
get_base_clock_map([]) -> none.

add_pre_message_clocks([], _, Clock) -> Clock;
add_pre_message_clocks([Special|Specials], ClockMap, Clock) ->
  NewClock =
    case Special of
      {message_delivered, #message_event{message = #message{id = Id}}} ->
        max_cv(Clock, lookup_clock({Id, sent}, ClockMap));
      _ -> Clock
    end,
  add_pre_message_clocks(Specials, ClockMap, NewClock).

add_new_and_messages([], _Clock, ClockMap) ->
  ClockMap;
add_new_and_messages([Special|Rest], Clock, ClockMap) ->
  NewClockMap =
    case Special of
      {new, SpawnedPid} ->
        map_store(SpawnedPid, Clock, ClockMap);
      {message, #message_event{message = #message{id = Id}}} ->
        map_store({Id, sent}, Clock, ClockMap);
      _ -> ClockMap
    end,
  add_new_and_messages(Rest, Clock, NewClockMap).

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
        ?debug(State#scheduler_state.logger,
               "   ~s ~s~n",
               begin
                 Star = fun(false) -> "  "; (_) -> "->" end,
                 [Star(Dependent), ?pretty_s(EarlyIndex, EarlyEvent)]
               end),
        case Dependent =:= false of
          true -> Clock;
          false ->
            #trace_state{clock_map = ClockMap} = TraceState,
            EarlyActorClock = lookup_clock(EarlyActor, ClockMap),
            max_cv(Clock, clock_store(EarlyActor, EarlyIndex, EarlyActorClock))
        end
    end,
  update_clock(Rest, Event, NewClock, State).

%%------------------------------------------------------------------------------

plan_more_interleavings([], RevEarly, _State) ->
  ?trace(_State#scheduler_state.logger, "Finished checking races~n", []),
  RevEarly;
plan_more_interleavings([TraceState|Later], RevEarly, State) ->
  case skip_planning(TraceState, State) of
    true ->
      plan_more_interleavings(Later, [TraceState|RevEarly], State);
    false ->
      #scheduler_state{logger = _Logger} = State,
      #trace_state{
         clock_map = ClockMap,
         done = [#event{actor = Actor} = _Event|_],
         index = _Index
        } = TraceState,
      StateClock = lookup_clock(state, ClockMap),
      %% If no dependencies were found skip this altogether
      case StateClock =:= independent of
        true ->
          plan_more_interleavings(Later, [TraceState|RevEarly], State);
        false ->
          ?debug(_Logger, "~s~n", [?pretty_s(_Index, _Event)]),
          ActorClock = lookup_clock(Actor, ClockMap),
          %% Otherwise we zero-down to the latest op that happened before
          LatestHBIndex = find_latest_hb_index(ActorClock, StateClock),
          ?trace(_Logger, "    SC: ~w~n", [StateClock]),
          ?trace(_Logger, "    AC: ~w~n", [ActorClock]),
          ?debug(_Logger, "    Nearest race @ ~w~n", [LatestHBIndex]),
          NewRevEarly =
            more_interleavings_for_event(
              TraceState, RevEarly, LatestHBIndex, StateClock, Later, State),
          plan_more_interleavings(Later, NewRevEarly, State)
      end
  end.

skip_planning(TraceState, State) ->
  #scheduler_state{non_racing_system = NonRacingSystem} = State,
  #trace_state{done = [Event|_]} = TraceState,
  #event{special = Special} = Event,
  case proplists:lookup(system_communication, Special) of
    {system_communication, System} -> lists:member(System, NonRacingSystem);
    none -> false
  end.

more_interleavings_for_event(TraceState, RevEarly, NextIndex, Clock,
                             Later, State) ->
  more_interleavings_for_event(
    TraceState, RevEarly, NextIndex, Clock, Later, State, []
   ).

more_interleavings_for_event(TraceState, RevEarly, -1, _Clock, _Later,
                             State, UpdEarly) ->
  _Logger = State#scheduler_state.logger,
  ?trace(_Logger, "    Finished checking races for event~n", []),
  [TraceState|lists:reverse(UpdEarly, RevEarly)];
more_interleavings_for_event(TraceState, [], _NextIndex, _Clock, _Later,
                             _State, UpdEarly) ->
  ?trace(
     _State#scheduler_state.logger,
     "    Finished checking races for event (NOT FAST)~n",
     []),
  [TraceState|lists:reverse(UpdEarly)];
more_interleavings_for_event(TraceState, [EarlyTraceState|RevEarly], NextIndex,
                             Clock, Later, State, UpdEarly) ->
  #trace_state{
     clock_map = ClockMap,
     done = [#event{actor = Actor} = Event|_]
    } = TraceState,
  #trace_state{
     clock_map = EarlyClockMap,
     done = [#event{actor = EarlyActor} = EarlyEvent|_],
     index = EarlyIndex
    } = EarlyTraceState,
  Action =
    case NextIndex =:= EarlyIndex of
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
                EarlyEvent, Event, Clock, EarlyTraceState,
                Later, UpdEarly, RevEarly, ObserverInfo, State)
            of
              skip -> update_clock;
              {UpdatedNewEarly, ConservativeCandidates} ->
                {update, UpdatedNewEarly, ConservativeCandidates}
            end
        end
    end,
  {NewClock, NewNextIndex} =
    case Action =:= none of
      true -> {Clock, NextIndex};
      false ->
        NC = max_cv(lookup_clock(EarlyActor, EarlyClockMap), Clock),
        ActorClock = lookup_clock(Actor, ClockMap),
        NI = find_latest_hb_index(ActorClock, NC),
        _Logger = State#scheduler_state.logger,
        ?debug(_Logger, "    Next nearest race @ ~w~n", [NI]),
        {NC, NI}
    end,
  {NewUpdEarly, NewRevEarly} =
    case Action of
      none -> {[EarlyTraceState|UpdEarly], RevEarly};
      update_clock -> {[EarlyTraceState|UpdEarly], RevEarly};
      {update, S, CC} ->
        maybe_log_race(EarlyTraceState, TraceState, State),
        EarlyClock = lookup_clock_value(EarlyActor, Clock),
        NRE = add_conservative(RevEarly, EarlyActor, EarlyClock, CC, State),
        {S, NRE}
    end,
  more_interleavings_for_event(TraceState, NewRevEarly, NewNextIndex, NewClock,
                               Later, State, NewUpdEarly).

update_trace(
  EarlyEvent, Event, Clock, TraceState,
  Later, NewOldTrace, Rest, ObserverInfo, State
 ) ->
  #scheduler_state{
     dpor = DPOR,
     estimator = Estimator,
     interleaving_id = Origin,
     logger = Logger,
     scheduling_bound_type = SchedulingBoundType,
     use_unsound_bpor = UseUnsoundBPOR,
     use_receive_patterns = UseReceivePatterns
    } = State,
  #trace_state{
     done = [#event{actor = EarlyActor} = EarlyEvent|Done] = AllDone,
     index = EarlyIndex,
     previous_actor = PreviousActor,
     scheduling_bound = BaseBound,
     sleep_set = BaseSleepSet,
     wakeup_tree = Wakeup
    } = TraceState,
  Bound = next_bound(SchedulingBoundType, AllDone, PreviousActor, BaseBound),
  DPORInfo =
    {DPOR,
     case DPOR =:= persistent of
       true -> Clock;
       false -> {EarlyActor, EarlyIndex}
     end},
  RevEvent = update_context(Event, EarlyEvent),
  FastSkip =
    case Bound < 0 of
      true ->
        CI =
          case SchedulingBoundType =:= bpor of
            true ->
              ND = not_dep(NewOldTrace, Later, DPORInfo, RevEvent),
              get_initials(ND);
            false ->
              false
          end,
        {true, {over_bound, [], CI}};
      false -> false
    end,
  {MaybeNewWakeup, VSeq, ConservativeInfo} =
    case FastSkip of
      {true, FastSkipReason} -> FastSkipReason;
      false ->
        SleepSet = BaseSleepSet ++ Done,
        NotDep = not_dep(NewOldTrace, Later, DPORInfo, RevEvent),
        case DPOR =:= optimal of
          true ->
            case UseReceivePatterns of
              false ->
                V = NotDep,
                NW = insert_wakeup_optimal(SleepSet, Wakeup, V, Bound, Origin),
                {NW, V, false};
              true ->
                ExtV =
                  case ObserverInfo =:= no_observer of
                    true -> NotDep;
                    false ->
                      NotObsRaw =
                        not_obs_raw(NewOldTrace, Later, ObserverInfo, Event),
                      NotObs = NotObsRaw -- NotDep,
                      ResetEvent = EarlyEvent#event{label = undefined},
                      NotDep ++ [ResetEvent] ++ NotObs
                  end,
                RevExtV = lists:reverse(ExtV),
                {V, ReceiveInfoDict} = fix_receive_info(RevExtV),
                {FixedRest, _} = fix_receive_info(Rest, ReceiveInfoDict),
                debug_show_sequence("v sequence", Logger, 1, V),
                RevFixedRest = lists:reverse(FixedRest),
                case has_weak_initial_before(RevFixedRest, V, Logger) of
                  true -> {skip, V, false};
                  false ->
                    NW = insert_wakeup_optimal(Done, Wakeup, V, Bound, Origin),
                    {NW, V, false}
                end
            end;
          false ->
            Initials = get_initials(NotDep),
            V = Initials,
            AddCons =
              case SchedulingBoundType =:= bpor of
                true -> Initials;
                false -> false
              end,
            NW = insert_wakeup_non_optimal(SleepSet, Wakeup, V, false, Origin),
            {NW, V, AddCons}
        end
    end,
  case MaybeNewWakeup of
    skip ->
      ?debug(Logger, "     SKIP~n", []),
      skip;
    over_bound ->
      bound_reached(Logger),
      case UseUnsoundBPOR of
        true -> ok;
        false -> put(bound_exceeded, true)
      end,
      {[TraceState|NewOldTrace], ConservativeInfo};
    NewWakeup ->
      debug_show_sequence("PLAN", Logger, EarlyIndex, VSeq),
      NS = TraceState#trace_state{wakeup_tree = NewWakeup},
      concuerror_logger:plan(Logger),
      concuerror_estimator:plan(Estimator, EarlyIndex),
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
            NewReceived = {message_received, NewId},
            lists:keyreplace(ObserverInfo, 2, Special, NewReceived);
          _ -> exit(impossible)
        end,
      [E#event{label = undefined, special = ObsNewSpecial}|NotObs]
  end.

has_weak_initial_before([], _, _Logger) ->
  ?debug(_Logger, "    No earlier weak initials found~n", []),
  false;
has_weak_initial_before([TraceState|Rest], V, Logger) ->
  #trace_state{done = [EarlyEvent|Done]} = TraceState,
  case has_initial(Done, [EarlyEvent|V]) of
    true ->
      ?debug(
         Logger,
         "    Has weak initial in: ~s~n",
         [?join([?pretty_s(0, D) || D <- Done], "~n")]
        ),
      debug_show_sequence("if seen as", Logger, 1, [EarlyEvent|V]),
      true;
    false ->
      has_weak_initial_before(Rest, [EarlyEvent|V], Logger)
  end.

debug_show_sequence(_Type, _Logger, _Index, _NotDep) ->
  ?debug(
     _Logger, "     ~s:~n~s",
     begin
       Indices = lists:seq(_Index, _Index + length(_NotDep) - 1),
       IndexedNotDep = lists:zip(Indices, _NotDep),
       Format = "                                       ~s~n",
       [_Type] ++
         [lists:append(
            [io_lib:format(Format, [?pretty_s(I, S)])
             || {I, S} <- IndexedNotDep])]
     end).

maybe_log_race(EarlyTraceState, TraceState, State) ->
  #scheduler_state{logger = Logger} = State,
  case State#scheduler_state.show_races of
    true ->
      #trace_state{
         done = [EarlyEvent|_],
         index = EarlyIndex,
         unique_id = EarlyUID
        } = EarlyTraceState,
      #trace_state{
         done = [Event|_],
         index = Index,
         unique_id = UID
        } = TraceState,
      concuerror_logger:graph_race(Logger, EarlyUID, UID),
      IndexedEarly = {EarlyIndex, EarlyEvent#event{location = []}},
      IndexedLate = {Index, Event#event{location = []}},
      concuerror_logger:race(Logger, IndexedEarly, IndexedLate);
    false ->
      ?unique(Logger, ?linfo, msg(show_races), [])
  end.

insert_wakeup_non_optimal(SleepSet, Wakeup, Initials, Conservative, Origin) ->
  case existing(SleepSet, Initials) of
    true -> skip;
    false -> add_or_make_compulsory(Wakeup, Initials, Conservative, Origin)
  end.

add_or_make_compulsory(Wakeup, Initials, Conservative, Origin) ->
  add_or_make_compulsory(Wakeup, Initials, Conservative, Origin, []).

add_or_make_compulsory([], [E|_], Conservative, Origin, Acc) ->
  Entry =
    #backtrack_entry{
       conservative = Conservative,
       event = E, origin = Origin,
       wakeup_tree = []
      },
  lists:reverse([Entry|Acc]);
add_or_make_compulsory([Entry|Rest], Initials, Conservative, Origin, Acc) ->
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
      add_or_make_compulsory(Rest, Initials, Conservative, Origin, NewAcc)
  end.

insert_wakeup_optimal(SleepSet, Wakeup, V, Bound, Origin) ->
  case has_initial(SleepSet, V) of
    true -> skip;
    false -> insert_wakeup(Wakeup, V, Bound, Origin)
  end.

has_initial([Event|Rest], V) ->
  case check_initial(Event, V) =:= false of
    true -> has_initial(Rest, V);
    false -> true
  end;
has_initial([], _) -> false.

insert_wakeup(          _, _NotDep,  Bound, _Origin) when Bound < 0 ->
  over_bound;
insert_wakeup(         [],  NotDep, _Bound,  Origin) ->
  backtrackify(NotDep, Origin);
insert_wakeup([Node|Rest],  NotDep,  Bound,  Origin) ->
  #backtrack_entry{event = Event, origin = M, wakeup_tree = Deeper} = Node,
  case check_initial(Event, NotDep) of
    false ->
      NewBound =
        case is_integer(Bound) of
          true -> Bound - 1;
          false -> Bound
        end,
      case insert_wakeup(Rest, NotDep, NewBound, Origin) of
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
          case insert_wakeup(Deeper, NewNotDep, Bound, Origin) of
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
    true -> lists:reverse(Acc, NotDep);
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
      ?debug(State#scheduler_state.logger, "  aborted~n", []),
      Rest;
    NewRest -> NewRest
  end.

add_conservative([], _Actor, _Clock, _Candidates, _State, _Acc) ->
  abort;
add_conservative([TraceState|Rest], Actor, Clock, Candidates, State, Acc) ->
  #scheduler_state{
     interleaving_id = Origin,
     logger = _Logger
    } = State,
  #trace_state{
     done = [#event{actor = EarlyActor} = _EarlyEvent|Done],
     enabled = Enabled,
     index = EarlyIndex,
     previous_actor = PreviousActor,
     sleep_set = BaseSleepSet,
     wakeup_tree = Wakeup
    } = TraceState,
  ?debug(_Logger,
         "   conservative check with ~s~n",
         [?pretty_s(EarlyIndex, _EarlyEvent)]),
  case (EarlyActor =/= Actor) orelse (EarlyIndex < Clock) of
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
              SleepSet = BaseSleepSet ++ Done,
              case
                insert_wakeup_non_optimal(
                  SleepSet, Wakeup, EnabledCandidates, true, Origin
                 )
              of
                skip -> abort;
                NewWakeup ->
                  NS = TraceState#trace_state{wakeup_tree = NewWakeup},
                  lists:reverse(Acc, [NS|Rest])
              end
          end
      end
  end.

%%------------------------------------------------------------------------------

has_more_to_explore(State) ->
  #scheduler_state{
     estimator = Estimator,
     scheduling_bound_type = SchedulingBoundType,
     trace = Trace
    } = State,
  TracePrefix = find_prefix(Trace, SchedulingBoundType),
  case TracePrefix =:= [] of
    true -> {false, State#scheduler_state{trace = []}};
    false ->
      InterleavingId = State#scheduler_state.interleaving_id,
      NextInterleavingId = InterleavingId + 1,
      NewState =
        State#scheduler_state{
          interleaving_errors = [],
          interleaving_id = NextInterleavingId,
          need_to_replay = true,
          receive_timeout_total = 0,
          trace = TracePrefix
         },
      [Last|_] = TracePrefix,
      TopIndex = Last#trace_state.index,
      concuerror_estimator:restart(Estimator, TopIndex),
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

replay(#scheduler_state{need_to_replay = false} = State) ->
  State;
replay(State) ->
  #scheduler_state{interleaving_id = N, logger = Logger, trace = Trace} = State,
  [#trace_state{index = I, unique_id = Sibling} = Last|
   [#trace_state{unique_id = Parent}|_] = Rest] = Trace,
  concuerror_logger:graph_set_node(Logger, Parent, Sibling),
  NewTrace =
    [Last#trace_state{unique_id = {N, I}, clock_map = empty_map()}|Rest],
  S = io_lib:format("New interleaving ~p. Replaying...", [N]),
  ?time(Logger, S),
  NewState = replay_prefix(NewTrace, State#scheduler_state{trace = NewTrace}),
  ?debug(Logger, "~s~n", ["Replay done."]),
  NewState#scheduler_state{need_to_replay = false}.

%% =============================================================================

reset_receive_done([Event|Rest], State)
  when State#scheduler_state.use_receive_patterns =:= true ->
  NewSpecial =
    [patch_message_delivery(S, empty_map()) || S <- Event#event.special],
  [Event#event{special = NewSpecial}|Rest];
reset_receive_done(Done, _) ->
  Done.

fix_receive_info(RevTraceOrEvents) ->
  fix_receive_info(RevTraceOrEvents, empty_map()).

fix_receive_info(RevTraceOrEvents, ReceiveInfoDict) ->
  D = collect_demonitor_info(RevTraceOrEvents, ReceiveInfoDict),
  fix_receive_info(RevTraceOrEvents, D, []).

collect_demonitor_info([], ReceiveInfoDict) ->
  ReceiveInfoDict;
collect_demonitor_info([#trace_state{} = TS|RevTrace], ReceiveInfoDict) ->
  [Event|_] = TS#trace_state.done,
  NewDict = collect_demonitor_info([Event], ReceiveInfoDict),
  collect_demonitor_info(RevTrace, NewDict);
collect_demonitor_info([#event{} = Event|RevEvents], ReceiveInfoDict) ->
  case Event#event.event_info of
    #builtin_event{mfargs = {erlang, demonitor, _}} ->
      #event{special = Special} = Event,
      NewDict = store_demonitor_info(Special, ReceiveInfoDict),
      collect_demonitor_info(RevEvents, NewDict);
    _ ->
      collect_demonitor_info(RevEvents, ReceiveInfoDict)
  end.

store_demonitor_info(Special, ReceiveInfoDict) ->
  case [D || {demonitor, D} <- Special] of
    [{Ref, ReceiveInfo}] ->
      map_store({demonitor, Ref}, ReceiveInfo, ReceiveInfoDict);
    [] -> ReceiveInfoDict
  end.

fix_receive_info([], ReceiveInfoDict, TraceOrEvents) ->
  {TraceOrEvents, ReceiveInfoDict};
fix_receive_info([#trace_state{} = TS|RevTrace], ReceiveInfoDict, Trace) ->
  [Event|Rest] = TS#trace_state.done,
  {[NewEvent], NewDict} = fix_receive_info([Event], ReceiveInfoDict, []),
  NewTS = TS#trace_state{done = [NewEvent|Rest]},
  fix_receive_info(RevTrace, NewDict, [NewTS|Trace]);
fix_receive_info([#event{} = Event|RevEvents], ReceiveInfoDict, Events) ->
  case has_delivery_or_receive(Event#event.special) of
    true ->
      #event{event_info = EventInfo, special = Special} = Event,
      NewReceiveInfoDict =
        store_receive_info(EventInfo, Special, ReceiveInfoDict),
      NewSpecial =
        [patch_message_delivery(S, NewReceiveInfoDict) || S <- Special],
      NewEventInfo =
        case EventInfo of
          #message_event{} ->
            DeliverySpecial = {message_delivered, EventInfo},
            {_, NI} =
              patch_message_delivery(DeliverySpecial, NewReceiveInfoDict),
            NI;
          _ -> EventInfo
        end,
      NewEvent = Event#event{event_info = NewEventInfo, special = NewSpecial},
      fix_receive_info(RevEvents, NewReceiveInfoDict, [NewEvent|Events]);
    false ->
      fix_receive_info(RevEvents, ReceiveInfoDict, [Event|Events])
  end.

has_delivery_or_receive([]) -> false;
has_delivery_or_receive([{M, _}|_])
  when M =:= message_delivered; M =:= message_received ->
  true;
has_delivery_or_receive([_|R]) -> has_delivery_or_receive(R).

store_receive_info(EventInfo, Special, ReceiveInfoDict) ->
  case [ID || {message_received, ID} <- Special] of
    [] -> ReceiveInfoDict;
    IDs ->
      ReceiveInfo =
        case EventInfo of
          #receive_event{receive_info = RI} -> RI;
          _ -> {system, fun(_) -> true end}
        end,
      Fold = fun(ID, Dict) -> map_store(ID, ReceiveInfo, Dict) end,
      lists:foldl(Fold, ReceiveInfoDict, IDs)
  end.

patch_message_delivery({message_delivered, MessageEvent}, ReceiveInfoDict) ->
  #message_event{message = #message{id = Id, data = Data}} = MessageEvent,
  ReceiveInfo =
    case map_find(Id, ReceiveInfoDict) of
      {ok, RI} -> RI;
      error ->
        case Data of
          {'DOWN', Ref, process, _, _} ->
            case map_find({demonitor, Ref}, ReceiveInfoDict) of
              {ok, RI} -> RI;
              error -> not_received
            end;
          _ -> not_received
        end
    end,
  {message_delivered, MessageEvent#message_event{receive_info = ReceiveInfo}};
patch_message_delivery(Other, _ReceiveInfoDict) ->
  Other.

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
  concuerror_callback:reset_processes(Processes),
  ok =
    concuerror_callback:start_first_process(FirstProcess, EntryPoint, Timeout),
  NewState = State#scheduler_state{last_scheduled = FirstProcess},
  replay_prefix_aux(lists:reverse(Trace), NewState).

replay_prefix_aux([_], State) ->
  %% Last state has to be properly replayed.
  State;
replay_prefix_aux([#trace_state{done = [Event|_], index = I}|Rest], State) ->
  #scheduler_state{logger = _Logger, print_depth = PrintDepth} = State,
  ?debug(_Logger, "~s~n", [?pretty_s(I, Event)]),
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
  UpdatedEvent =
    concuerror_callback:deliver_message(Event, MessageEvent, Timeout),
  {ok, UpdatedEvent};
get_next_event_backend(#event{actor = Pid} = Event, State) when is_pid(Pid) ->
  #scheduler_state{timeout = Timeout} = State,
  concuerror_callback:wait_actor_reply(Event, Timeout).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

-ifdef(BEFORE_OTP_17).

empty_map() ->
  dict:new().

map_store(K, V, Map) ->
  dict:store(K, V, Map).

map_find(K, Map) ->
  dict:find(K, Map).

is_empty_map(Map) ->
  dict:size(Map) =:= 0.

lookup_clock(P, ClockMap) ->
  case dict:find(P, ClockMap) of
    {ok, Clock} -> Clock;
    error -> clock_new()
  end.

clock_new() ->
  orddict:new().

clock_store(_, 0, VectorClock) ->
  VectorClock;
clock_store(Actor, Index, VectorClock) ->
  orddict:store(Actor, Index, VectorClock).

lookup_clock_value(Actor, VectorClock) ->
  case orddict:find(Actor, VectorClock) of
    {ok, Value} -> Value;
    error -> 0
  end.

max_cv(D1, D2) ->
  Merger = fun(_Key, V1, V2) -> max(V1, V2) end,
  orddict:merge(Merger, D1, D2).

find_latest_hb_index(ActorClock, StateClock) ->
  %% This is the max index that is in the Actor clock but not in the
  %% corresponding state clock.
  Fold =
    fun(K, V, Next) ->
        case orddict:find(K, StateClock) =:= {ok, V} of
          true -> Next;
          false -> max(V, Next)
        end
    end,
  orddict:fold(Fold, -1, ActorClock).

-else.

empty_map() ->
  #{}.

map_store(K, V, Map) ->
  maps:put(K, V, Map).

map_find(K, Map) ->
  maps:find(K, Map).

is_empty_map(Map) ->
  maps:size(Map) =:= 0.

lookup_clock(P, ClockMap) ->
  maps:get(P, ClockMap, clock_new()).

clock_new() ->
  #{}.

clock_store(_, 0, VectorClock) ->
  VectorClock;
clock_store(Actor, Index, VectorClock) ->
  maps:put(Actor, Index, VectorClock).

lookup_clock_value(Actor, VectorClock) ->
  maps:get(Actor, VectorClock, 0).

max_cv(VC1, VC2) ->
  ODVC1 = orddict:from_list(maps:to_list(VC1)),
  ODVC2 = orddict:from_list(maps:to_list(VC2)),
  Merger = fun(_Key, V1, V2) -> max(V1, V2) end,
  MaxVC = orddict:merge(Merger, ODVC1, ODVC2),
  maps:from_list(MaxVC).

find_latest_hb_index(ActorClock, StateClock) ->
  %% This is the max index that is in the Actor clock but not in the
  %% corresponding state clock.
  Fold =
    fun(K, V, Next) ->
        case maps:find(K, StateClock) =:= {ok, V} of
          true -> Next;
          false -> max(V, Next)
        end
    end,
  maps:fold(Fold, -1, ActorClock).

-endif.

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

bound_reached(Logger) ->
  ?unique(Logger, ?lwarning, msg(scheduling_bound_warning), []),
  ?debug(Logger, "OVER BOUND~n", []),
  concuerror_logger:bound_reached(Logger).

%% =============================================================================

-spec explain_error(term()) -> string().

explain_error({blocked_mismatch, I, Event, Depth}) ->
  EString = concuerror_io_lib:pretty_s(Event, Depth),
  io_lib:format(
    "On step ~p, replaying a built-in returned a different result than"
    " expected:~n"
    "  original:~n"
    "    ~s~n"
    "  new:~n"
    "    blocked~n"
    ?notify_us_msg,
    [I, EString]
   );
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
    [concuerror_io_lib:pretty_s(E, Depth) || E <- [Event, NewEvent]],
  [Original, New] =
    case EString =/= NEString of
      true -> [EString, NEString];
      false ->
        [io_lib:format("~p", [E]) || E <- [Event, NewEvent]]
    end,
  io_lib:format(
    "On step ~p, replaying a built-in returned a different result than"
    " expected:~n"
    "  original:~n"
    "    ~s~n"
    "  new:~n"
    "    ~s~n"
    ?notify_us_msg,
    [I, Original, New]
   ).

%%==============================================================================

msg(after_timeout_tip) ->
  "You can use e.g. '--after_timeout 5000' to treat after timeouts that exceed"
    " some threshold (here 4999ms) as 'infinity'.~n";
msg(assertions_only_filter) ->
  "Only assertion failures are considered abnormal exits"
    " ('--assertions_only').~n";
msg(assertions_only_use) ->
  "A process exited with reason '{{assert*,_}, _}'. If you want to see only"
    " this kind of error you can use the '--assertions_only' option.~n";
msg(depth_bound_reached) ->
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
msg(scheduling_bound_tip) ->
  "Running without a scheduling_bound corresponds to verification and"
    " may take a long time.~n";
msg(scheduling_bound_warning) ->
  "Some interleavings will not be explored because they exceed the scheduling"
    " bound.~n";
msg(show_races) ->
  "You can see pairs of racing instructions (in the report and"
    " '--graph') with '--show_races true'~n";
msg(shutdown) ->
  "A process exited with reason 'shutdown'. This may happen when a"
    " supervisor is terminating its children. You can use '--treat_as_normal"
    " shutdown' if this is expected behaviour.~n";
msg(stop_first_error) ->
  "Stop testing on first error. (Check '-h keep_going').~n";
msg(timeout) ->
  "A process exited with reason '{timeout, ...}'. This may happen when a"
    " call to a gen_server (or similar) does not receive a reply within some"
    " timeout (5000ms by default). "
    ++ msg(after_timeout_tip);
msg(treat_as_normal) ->
  "Some abnormal exit reasons were treated as normal ('--treat_as_normal').~n".
