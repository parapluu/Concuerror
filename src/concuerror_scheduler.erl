%% -*- erlang-indent-level: 2 -*-

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

%%% The logic of the exploration goes through `explore/1`, which is
%%% fairly clean: as long as there are more processes that can be
%%% executed and yield events, `get_next_event/1` will be returning
%%% `ok`, after executing one of them and doing all necessary updates
%%% to the state (adding new `#trace_state`s, etc).  If
%%% `get_next_event/1` returns `none`, we are at the end of an
%%% interleaving (either due to no more enabled processes or due to
%%% "sleep set blocking") and can do race analysis and report any
%%% errors found in the interleaving.  Race analysis is contained in
%%% `plan_more_interleavings/1`, reporting whether the current
%%% interleaving was buggy is contained in `log_trace/1` and resetting
%%% most parts to continue exploration is contained in
%%% `has_more_to_explore/1`.

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
-export([run/1, log_trace/1, explain_error/1]).

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

-type scheduler_state() :: #scheduler_state{}.

%% =============================================================================
%% LOGIC (high level description of the exploration algorithm)
%% =============================================================================

-spec run(concuerror_options:options()) -> ok.

run(Options) ->
  process_flag(trap_exit, true),
  put(bound_exceeded, false),
  {FirstProcess, System} =
    concuerror_callback:spawn_first_process(Options),
  EntryPoint = ?opt(entry_point, Options),
  Timeout = ?opt(timeout, Options),
  ok =
    concuerror_callback:start_first_process(FirstProcess, EntryPoint, Timeout),
  InitialTrace =
    #trace_state{
       actors = [FirstProcess],
       enabled = [E || E <- [FirstProcess], enabled(E)],
       scheduling_bound = ?opt(scheduling_bound, Options)
      },
  Logger = ?opt(logger, Options),
  Planner = ?opt(planner, Options),
  {SchedulingBoundType, UnsoundBPOR} =
    case ?opt(scheduling_bound_type, Options) of
      ubpor -> {bpor, true};
      Else -> {Else, false}
    end,
  InitialState =
    #scheduler_state{
       assertions_only = ?opt(assertions_only, Options),
       assume_racing = {?opt(assume_racing, Options), Logger},
       depth_bound = ?opt(depth_bound, Options) + 1,
       disable_sleep_sets = ?opt(disable_sleep_sets, Options),
       dpor = ?opt(dpor, Options),
       entry_point = EntryPoint,
       first_process = FirstProcess,
       ignore_error = ?opt(ignore_error, Options),
       interleaving_bound = ?opt(interleaving_bound, Options),
       keep_going = ?opt(keep_going, Options),
       last_scheduled = FirstProcess,
       logger = Logger,
       planner = Planner,
       non_racing_system = ?opt(non_racing_system, Options),
       parallel = ?opt(parallel, Options),
       print_depth = ?opt(print_depth, Options),
       processes = Processes = ?opt(processes, Options),
       scheduling = ?opt(scheduling, Options),
       scheduling_bound_type = SchedulingBoundType,
       show_races = ?opt(show_races, Options),
       strict_scheduling = ?opt(strict_scheduling, Options),
       system = System,
       trace = [InitialTrace],
       treat_as_normal = ?opt(treat_as_normal, Options),
       timeout = Timeout,
       unsound_bpor = UnsoundBPOR,
       use_receive_patterns = ?opt(use_receive_patterns, Options)
      },
  concuerror_logger:plan(Logger),
  Planner ! {initial, InitialState},
  ?time(Logger, "Exploration start"),
  Ret = explore(InitialState),
  concuerror_callback:cleanup_processes(Processes),
  Ret.

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
      #scheduler_state{
	 trace = UpdatedTrace, 
	 warnings = Warnings, 
	 exploring = Exploring,
	 planner = Planner
	} = UpdatedState,
      Planner ! {explored, {UpdatedTrace, Warnings, Exploring, get(bound_exceeded)}},
      loop(UpdatedState);
    {crash, Class, Reason, Stack} ->
      #scheduler_state{
	 trace = [_|Trace],
	 planner = Planner
	} = UpdatedState,
      FatalCrashState = add_warning(fatal, Trace, UpdatedState),
      catch log_trace(FatalCrashState),
      Planner ! {crash, Class, Reason, Stack},
      loop(FatalCrashState)
  end.

loop(State) ->
  receive
    {explore, {NewTrace, Warnings, Exploring, BoundExceeded}} ->
      put(bound_exceeded, BoundExceeded),
      NewState = 
	State#scheduler_state{
	  trace = NewTrace,
	  warnings = Warnings,
	  exploring = Exploring,
	  need_to_replay = true
	 },
      explore(NewState);
    exit ->
      ok
  end.

%%------------------------------------------------------------------------------
-spec log_trace(scheduler_state()) -> scheduler_state().

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
      NextState =
        State#scheduler_state{
          exploring = N + 1,
          receive_timeout_total = 0,
          warnings = []
         },
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
     trace = [#trace_state{index = Bound}|Trace]} = State) ->
  ?unique(Logger, ?lwarning, msg(depth_bound), []),
  NewState = add_warning({depth_bound, Bound - 1}, Trace, State),
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
  #scheduler_state{system = System, trace = [Last|_]} = State,
  #trace_state{actors = Actors, sleeping = Sleeping} = Last,
  SortedActors = schedule_sort(Actors, State),
  #event{actor = Actor, label = Label} = Event,
  case Actor =:= undefined of
    true ->
      AvailableActors = filter_sleeping(Sleeping, SortedActors),
      free_schedule(Event, System ++ AvailableActors, State);
    false ->
      #scheduler_state{print_depth = PrintDepth} = State,
      #trace_state{index = I} = Last,
      false = lists:member(Actor, Sleeping),
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
  #scheduler_state{
     dpor = DPOR,
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
        true -> concuerror_logger:bound_reached(Logger);
        false -> ok
      end,
      Eventify = [maybe_prepare_channel_event(E, #event{}) || E <- ToBeExplored],
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
     disable_sleep_sets = DisableSleepSets,
     logger = Logger,
     scheduling_bound_type = SchedulingBoundType,
     trace  = [Last|Prev]
    } = State,
  #trace_state{
     actors      = Actors,
     done        = RawDone,
     index       = Index,
     graph_ref   = Ref,
     previous_actor = PreviousActor,
     scheduling_bound = SchedulingBound,
     sleeping    = Sleeping,
     wakeup_tree = WakeupTree
    } = Last,
  ?trace(Logger, "~s~n", [?pretty_s(Index, Event)]),
  concuerror_logger:graph_new_node(Logger, Ref, Index, Event, 0),
  Done = reset_receive_done(RawDone, State),
  NextSleeping =
    case DisableSleepSets of
      true -> [];
      false ->
        AllSleeping =
          case WakeupTree of
            [#backtrack_entry{conservative = true}|_] ->
              concuerror_logger:plan(Logger),
              Sleeping;
            _ -> ordsets:union(ordsets:from_list(Done), Sleeping)
          end,
        update_sleeping(Event, AllSleeping, State)
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
  InitNextTrace =
    #trace_state{
       actors      = Actors,
       index       = Index + 1,
       previous_actor = Actor,
       scheduling_bound = NewSchedulingBound,
       sleeping    = NextSleeping,
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
    #builtin_event{mfargs = {erlang, exit, [_,Reason]}}
      when Reason =/= normal ->
      ?unique(Logger, ?ltip, msg(signal), []),
      State;
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

update_sleeping(NewEvent, Sleeping, State) ->
  #scheduler_state{logger = _Logger} = State,
  Pred =
    fun(OldEvent) ->
        V = concuerror_dependencies:dependent_safe(NewEvent, OldEvent),
        ?trace(_Logger, "     Awaking (~p): ~s~n", [V,?pretty_s(OldEvent)]),
        V =:= false
    end,
  lists:filter(Pred, Sleeping).

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
      {message_received, _Message} ->
        Actors;
      {new, SpawnedPid} ->
        Actors ++ [SpawnedPid];
      {system_communication, _} ->
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

maybe_update_enabled(bpor, TraceState) ->
  #trace_state{actors = Actors} = TraceState,
  Enabled = [E || E <- Actors, enabled(E)],
  TraceState#trace_state{enabled = Enabled};
maybe_update_enabled(_, TraceState) ->
  TraceState.


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

reset_receive_done([Event|Rest], #scheduler_state{use_receive_patterns = true}) ->
  NewSpecial =
    [patch_message_delivery(S, dict:new()) || S <- Event#event.special],
  [Event#event{special = NewSpecial}|Rest];
reset_receive_done(Done, _) ->
  Done.


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
    [I,EString]
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

msg(after_timeout_tip) ->
  "You can use e.g. '--after_timeout 5000' to treat after timeouts that exceed"
    " some threshold (here 4999ms) as 'infinity'.~n";
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
    " timeout (5000ms by default). "
    ++ msg(after_timeout_tip);
msg(treat_as_normal) ->
  "Some abnormal exit reasons were treated as normal ('--treat_as_normal').~n".
