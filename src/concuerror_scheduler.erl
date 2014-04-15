%% -*- erlang-indent-level: 2 -*-

-module(concuerror_scheduler).

%% User interface
-export([run/1, explain_error/1]).

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
          ignore_first_crash = true :: boolean(),
          assume_racing     = true :: boolean(),
          current_warnings  = []   :: [concuerror_warning_info()],
          depth_bound              :: pos_integer(),
          first_process            :: {pid(), mfargs()},
          ignore_error      = []   :: [atom()],
          logger                   :: pid(),
          message_info             :: message_info(),
          non_racing_system = []   :: [atom()],
          print_depth              :: pos_integer(),
          processes                :: processes(),
          timeout                  :: timeout(),
          trace             = []   :: [trace_state()],
          treat_as_normal   = []   :: [atom()]
         }).

%% =============================================================================
%% LOGIC (high level description of the exploration algorithm)
%% =============================================================================

-spec run(options()) -> ok.

run(Options) ->
  process_flag(trap_exit, true),
  case code:get_object_code(erlang) =:= error of
    true ->
      true =
        code:add_pathz(filename:join(code:root_dir(), "erts/preloaded/ebin"));
    false ->
      ok
  end,
  FirstProcess = concuerror_callback:spawn_first_process(Options),
  InitialTrace = #trace_state{active_processes = [FirstProcess]},
  InitialState =
    #scheduler_state{
       ignore_first_crash = ?opt(ignore_first_crash,Options),
       assume_racing = ?opt(assume_racing,Options),
       depth_bound = ?opt(depth_bound, Options),
       first_process = {FirstProcess, EntryPoint = ?opt(entry_point, Options)},
       ignore_error = ?opt(ignore_error, Options),
       logger = Logger = ?opt(logger, Options),
       message_info = ets:new(message_info, [private]),
       non_racing_system = ?opt(non_racing_system, Options),
       print_depth = ?opt(print_depth, Options),
       processes = ?opt(processes, Options),
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
      exit:Reason -> {{crash, Reason}, State}
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
    {crash, Why} ->
      #scheduler_state{
         current_warnings = Warnings,
         trace = [_|Trace]
        } = UpdatedState,
      FatalCrashState =
        UpdatedState#scheduler_state{
          current_warnings = [fatal|Warnings],
          trace = Trace
         },
      catch log_trace(FatalCrashState),
      exit(Why)
  end.

%%------------------------------------------------------------------------------

log_trace(State) ->
  #scheduler_state{
     current_warnings = UnfilteredWarnings,
     ignore_error = Ignored,
     logger = Logger} = State,
  Warnings =  filter_warnings(UnfilteredWarnings, Ignored),
  case UnfilteredWarnings =/= Warnings of
    true ->
      Message = "Some errors were silenced (--ignore_error).~n",
      ?unique(Logger, ?linfo, Message, []);
    false ->
      ok
  end,
  Log =
    case Warnings =:= [] of
      true -> none;
      false ->
        #scheduler_state{trace = Trace} = State,
        %%io:format("~p~n",[Trace]),
        Fold =
          fun(#trace_state{done = [A|_], index = I}, Acc) -> [{I, A}|Acc] end,
        TraceInfo = lists:foldl(Fold, [], Trace),
        {lists:reverse(Warnings), TraceInfo}
    end,
  concuerror_logger:complete(Logger, Log),
  case (not State#scheduler_state.ignore_first_crash) andalso (Log =/= none) of
    true -> ?crash(first_interleaving_crashed);
    false ->
      State#scheduler_state{ignore_first_crash = true, current_warnings = []}
  end.

filter_warnings(Warnings, []) -> Warnings;
filter_warnings(Warnings, [Ignore|Rest] = Ignored) ->
  case lists:keytake(Ignore, 1, Warnings) of
    false -> filter_warnings(Warnings, Rest);
    {value, _, NewWarnings} -> filter_warnings(NewWarnings, Ignored)
  end.

get_next_event(
  #scheduler_state{
     current_warnings = Warnings,
     depth_bound = Bound,
     trace = [#trace_state{index = I}|Old]} = State) when I =:= Bound + 1->
  NewState =
    State#scheduler_state{
      current_warnings = [{depth_bound, Bound}|Warnings],
      trace = Old},
  {none, NewState};
get_next_event(#scheduler_state{trace = [Last|_]} = State) ->
  #trace_state{
     active_processes = ActiveProcesses,
     index            = I,
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
      {ok, UpdatedEvent} =
        case Label =/= undefined of
          true ->
            NewEvent = get_next_event_backend(Event, State),
            try {ok, Event} = NewEvent
            catch
              _:_ ->
                #scheduler_state{print_depth = PrintDepth} = State,
                ?crash({replay_mismatch, I, Event, element(2, NewEvent), PrintDepth})
            end;
          false ->
            %% Last event = Previously racing event = Result may differ.
            ResetEvent = reset_event(Event),
            get_next_event_backend(ResetEvent, State)
        end,
      update_state(UpdatedEvent, State)
  end.

filter_sleeping([], PendingMessages, ActiveProcesses) ->
  {PendingMessages, ActiveProcesses};
filter_sleeping([#event{actor = Channel}|Sleeping],
                PendingMessages, ActiveProcesses) when ?is_channel(Channel) ->
  NewPendingMessages = orddict:erase(Channel, PendingMessages),
  filter_sleeping(Sleeping, NewPendingMessages, ActiveProcesses);
filter_sleeping([#event{actor = Pid}|Sleeping],
                PendingMessages, ActiveProcesses) ->
  NewActiveProcesses = ordsets:del_element(Pid, ActiveProcesses),
  filter_sleeping(Sleeping, PendingMessages, NewActiveProcesses).

get_next_event(Event, [{Channel, Queue}|_], _ActiveProcesses, State) ->
  %% Pending messages can always be sent
  MessageEvent = queue:get(Queue),
  UpdatedEvent = Event#event{actor = Channel, event_info = MessageEvent},
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
            Info = concuerror_callback:collect_deadlock_info(ActiveProcesses),
            [{deadlock, Info}|Warnings];
          false -> Warnings
        end
    end,
  {none, State#scheduler_state{current_warnings = NewWarnings, trace = Prev}}.

reset_event(#event{actor = Actor, event_info = EventInfo}) ->
  ResetEventInfo =
    case ?is_channel(Actor) of
      true -> EventInfo#message_event{patterns = none};
      false -> undefined
    end,
  #event{
     actor = Actor,
     event_info = ResetEventInfo,
     label = make_ref()
    }.

%%------------------------------------------------------------------------------

update_state(#event{actor = Actor, special = Special} = Event, State) ->
  #scheduler_state{logger = Logger, trace = [Last|Prev]} = State,
  #trace_state{
     active_processes = ActiveProcesses,
     done             = Done,
     index            = Index,
     pending_messages = PendingMessages,
     preemptions      = Preemptions,
     sleeping         = Sleeping,
     wakeup_tree      = WakeupTree
    } = Last,
  ?trace(Logger, "~s~n", [?pretty_s(Index, Event)]),
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
  NewState = maybe_log(Event, InitNewState, Index),
  {ok, update_special(Special, NewState)}.

maybe_log(Event, State, Index) ->
  #scheduler_state{logger = Logger, treat_as_normal = Normal} = State,
  case Event#event.event_info of
    #exit_event{reason = Reason} = Exit when Reason =/= normal ->
      {Tag, WasTimeout} =
        if is_tuple(Reason), size(Reason) > 0 ->
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
          #event{actor = Actor} = Event,
          Warnings = State#scheduler_state.current_warnings,
          Stacktrace = Exit#exit_event.stacktrace,
          NewWarnings = [{crash, {Index, Actor, Reason, Stacktrace}}|Warnings],
          State#scheduler_state{current_warnings = NewWarnings}
      end;
    #builtin_event{mfargs = {erlang, exit, [_,Reason]}}
      when Reason =/= normal ->
      ?unique(Logger, ?ltip, msg(signal), []),
      State;
    _ -> State
  end.

update_sleeping(NewEvent, Sleeping, State) ->
  #scheduler_state{logger = Logger} = State,
  Pred =
    fun(OldEvent) ->
        V = concuerror_dependencies:dependent_safe(OldEvent, NewEvent),
        ?trace(Logger, "AWAKE (~p):~n~s~nvs~n~s~n",
               [V|[?pretty_s(E) || E <- [OldEvent, NewEvent]]]),
        V =:= false
    end,
  lists:filter(Pred, Sleeping).

%% XXX: Stub.
update_preemptions(_Pid, _ActiveProcesses, _Prev, Preemptions) ->
  Preemptions.

update_special(List, State) when is_list(List) ->
  lists:foldl(fun update_special/2, State, List);
update_special(Special, State) ->
  #scheduler_state{message_info = MessageInfo, trace = [Next|Trace]} = State,
  case Special of
    halt ->
      NewNext = Next#trace_state{active_processes = []},
      State#scheduler_state{trace = [NewNext|Trace]};
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
    {system_communication, _} ->
      State
  end.

process_message(MessageEvent, PendingMessages, MessageInfo) ->
  #message_event{
     message = #message{id = Id},
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
  #scheduler_state{logger = Logger, message_info = MessageInfo} = State,
  #trace_state{done = [Event|RestEvents], index = Index} = TraceState,
  #event{actor = Actor, special = Special} = Event,
  ClockMap = get_base_clock(RevLate, RevEarly),
  OldClock = lookup_clock(Actor, ClockMap),
  ActorClock = orddict:store(Actor, Index, OldClock),
  ?trace(Logger, "HB: ~s~n", [?pretty_s(Index,Event)]),
  BaseHappenedBeforeClock =
    add_pre_message_clocks(Special, MessageInfo, ActorClock),
  HappenedBeforeClock =
    update_clock(RevLate++RevEarly, Event, BaseHappenedBeforeClock, State),
  maybe_mark_sent_message(Special, HappenedBeforeClock, MessageInfo),
  UpdatedEvent =
    case proplists:lookup(message_delivered, Special) of
      none -> Event;
      {message_delivered, MessageEvent} ->
        #message_event{message = #message{id = Id}} = MessageEvent,
        Delivery = {?message_delivered, HappenedBeforeClock},
        ets:update_element(MessageInfo, Id, Delivery),
        Patterns = ets:lookup_element(MessageInfo, Id, ?message_pattern),
        UpdatedMessageEvent =
          {message_delivered, MessageEvent#message_event{patterns = Patterns}},
        UpdatedSpecial =
          lists:keyreplace(message_delivered, 1, Special, UpdatedMessageEvent),
        Event#event{special = UpdatedSpecial}
    end,
  BaseNewClockMap = dict:store(Actor, HappenedBeforeClock, ClockMap),
  NewClockMap =
    case proplists:lookup(new, Special) of
      {new, SpawnedPid} ->
        dict:store(SpawnedPid, HappenedBeforeClock, BaseNewClockMap);
      none -> BaseNewClockMap
    end,
  NewTraceState =
    TraceState#trace_state{
      clock_map = NewClockMap,
      done = [UpdatedEvent|RestEvents]},
  assign_happens_before(Later, [NewTraceState|RevLate], RevEarly, State).

get_base_clock(RevLate, RevEarly) ->
  try
    get_base_clock(RevLate)
  catch
    throw:none ->
      try
        get_base_clock(RevEarly)
      catch
        throw:none -> dict:new()
      end
  end.

get_base_clock([]) -> throw(none);
get_base_clock([#trace_state{clock_map = ClockMap}|_]) -> ClockMap.

add_pre_message_clocks([], _, Clock) -> Clock;
add_pre_message_clocks([Special|Specials], MessageInfo, Clock) ->
  NewClock =
    case Special of
      {message_received, Id, _} ->
        case ets:lookup_element(MessageInfo, Id, ?message_delivered) of
          undefined -> Clock;
          RMessageClock -> max_cv(Clock, RMessageClock)
        end;
      {message_delivered, #message_event{message = #message{id = Id}}} ->
        message_clock(Id, MessageInfo, Clock);
      _ -> Clock
    end,
  add_pre_message_clocks(Specials, MessageInfo, NewClock).

message_clock(Id, MessageInfo, ActorClock) ->
  case ets:lookup_element(MessageInfo, Id, ?message_sent) of
    undefined -> ActorClock;
    MessageClock -> max_cv(ActorClock, MessageClock)
  end.

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
               [star(Dependent), ?pretty_s(EarlyIndex,EarlyEvent)]),
        case Dependent of
          false -> Clock;
          True when True =:= true; True =:= irreversible ->
            #trace_state{clock_map = ClockMap} = TraceState,
            EarlyActorClock = lookup_clock(EarlyActor, ClockMap),
            max_cv(Clock, EarlyActorClock)
        end
    end,
  update_clock(Rest, Event, NewClock, State).

star(false) -> " ";
star(_) -> "*".  

maybe_mark_sent_message(Special, Clock, MessageInfo) when is_list(Special)->
  Message = proplists:lookup(message, Special),
  maybe_mark_sent_message(Message, Clock, MessageInfo);
maybe_mark_sent_message({message, Message}, Clock, MessageInfo) ->
  #message_event{message = #message{id = Id}} = Message,
  ets:update_element(MessageInfo, Id, {?message_sent, Clock});
maybe_mark_sent_message(_, _, _) -> true.

plan_more_interleavings([], OldTrace, _SchedulerState) ->
  OldTrace;
plan_more_interleavings([TraceState|Rest], OldTrace, State) ->
  #scheduler_state{
     logger = Logger,
     message_info = MessageInfo,
     non_racing_system = NonRacingSystem
    } = State,
  #trace_state{done = [Event|_], index = Index} = TraceState,
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
      ActorClock = lookup_clock(Actor, ClockMap),
      BaseClock =
        case ?is_channel(Actor) of
          true ->
            #message_event{message = #message{id = Id}} = EventInfo,
            message_clock(Id, MessageInfo, ActorClock);
          false -> ActorClock
        end,
      ?trace(Logger, "~s~n", [?pretty_s(Index, Event)]),
      BaseNewOldTrace =
        more_interleavings_for_event(OldTrace, Event, Rest, BaseClock, State),
      NewOldTrace = [TraceState|BaseNewOldTrace],
      plan_more_interleavings(Rest, NewOldTrace, State)
  end.

more_interleavings_for_event(OldTrace, Event, Later, Clock, State) ->
  more_interleavings_for_event(OldTrace, Event, Later, Clock, State, []).

more_interleavings_for_event([], _Event, _Later, _Clock, _State, NewOldTrace) ->
  lists:reverse(NewOldTrace);
more_interleavings_for_event([TraceState|Rest], Event, Later, Clock, State,
                             NewOldTrace) ->
  #scheduler_state{logger = Logger} = State,
  #trace_state{
     clock_map = EarlyClockMap,
     done = [#event{actor = EarlyActor} = EarlyEvent|Done],
     index = EarlyIndex,
     sleeping = Sleeping
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
          irreversible ->
            NC = max_cv(lookup_clock(EarlyActor, EarlyClockMap), Clock),
            {update_clock, NC};
          true ->
            NC = max_cv(lookup_clock(EarlyActor, EarlyClockMap), Clock),
            ?trace(Logger, "   races with ~s~n",
                   [?pretty_s(EarlyIndex, EarlyEvent)]),
            NotDep =
              not_dep(NewOldTrace ++ Later, EarlyActor, EarlyIndex, Event),
            #trace_state{wakeup_tree = WakeupTree} = TraceState,
            case insert_wakeup(Sleeping ++ Done, WakeupTree, NotDep) of
              skip -> {update_clock, NC};
              NewWakeupTree ->
                concuerror_logger:plan(Logger),
                trace_plan(Logger, EarlyIndex, NotDep),
                NS = TraceState#trace_state{wakeup_tree = NewWakeupTree},
                {update, NS, NC}
            end
        end
    end,
  {NewTrace, NewClock} =
    case Action of
      none -> {[TraceState|NewOldTrace], Clock};
      {update_clock, C} ->
        ?trace(Logger, "     SKIP~n",[]),
        {[TraceState|NewOldTrace], C};
      {update, S, C} -> {[S|NewOldTrace], C}
    end,
  more_interleavings_for_event(Rest, Event, Later, NewClock, State, NewTrace).

not_dep(Trace, Actor, Index, Event) ->
  not_dep(Trace, Actor, Index, Event, []).

not_dep([], _Actor, _Index, Event, NotDep) ->
  %% The racing event's effect may differ, so new label.
  lists:reverse([Event#event{label = undefined}|NotDep]);
not_dep([TraceState|Rest], Actor, Index, Event, NotDep) ->
  #trace_state{
     clock_map = ClockMap,
     done = [#event{actor = LaterActor} = LaterEvent|_]
    } = TraceState,
  LaterClock = lookup_clock(LaterActor, ClockMap),
  ActorLaterClock = lookup_clock_value(Actor, LaterClock),
  NewNotDep =
    case Index > ActorLaterClock of
      false -> NotDep;
      true ->
        [LaterEvent|NotDep]
    end,
  not_dep(Rest, Actor, Index, Event, NewNotDep).

trace_plan(Logger, Index, NotDep) ->
  From = Index + 1,
  To = Index + length(NotDep),
  IndexedNotDep = lists:zip(lists:seq(From,To),NotDep),
  ?trace(
     Logger, "     PLAN~n~s",
     [lists:append(
        [io_lib:format("        ~s~n", [?pretty_s(I,S)])
         || {I,S} <- IndexedNotDep])]).

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

%%------------------------------------------------------------------------------

has_more_to_explore(State) ->
  #scheduler_state{logger = Logger, trace = Trace} = State,
  TracePrefix = find_prefix(Trace, State),
  case TracePrefix =:= [] of
    true -> {false, State#scheduler_state{trace = []}};
    false ->
      ?time(Logger, "New interleaving. Replaying..."),
      NewState = replay_prefix(TracePrefix, State),
      ?debug(Logger, "~s~n",["Replay done."]),
      FinalState = NewState#scheduler_state{trace = TracePrefix},
      {true, FinalState}
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
    #message_event{message = #message{id = Id}} ->
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
     first_process = {FirstProcess, EntryPoint},
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
  replay_prefix_aux(lists:reverse(Trace), State).

replay_prefix_aux([_], State) ->
  %% Last state has to be properly replayed.
  State;
replay_prefix_aux([#trace_state{done = [Event|_], index = I}|Rest], State) ->
  #scheduler_state{logger = Logger, print_depth = PrintDepth} = State,
  ?trace(Logger, "~s~n", [?pretty_s(I, Event)]),
  {ok, NewEvent} = get_next_event_backend(Event, State),
  try
    true = Event =:= NewEvent
  catch
    _:_ ->
      #scheduler_state{print_depth = PrintDepth} = State,
      ?crash({replay_mismatch, I, Event, NewEvent, PrintDepth})
  end,
  replay_prefix_aux(Rest, maybe_log(Event, State, I)).

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

assert_no_messages() ->
  receive
    Msg -> error({pending_message, Msg})
  after
    0 -> ok
  end.

-spec explain_error(term()) -> string().

explain_error(first_interleaving_crashed) ->
  {
    io_lib:format(
      "The first interleaving of your test had errors. Check the output file."
      " You may then use -i to tell Concuerror to continue or use other options"
      " to filter out the reported errors, if you consider them acceptable"
      " behaviours.",
      []),
    warning};
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
    "  original: ~s~n"
    "  new     : ~s~n"
    ?notify_us_msg,
    [I,Original,New]
   ).

%%==============================================================================

msg(signal) ->
  "An abnormal exit signal was sent to a process. This is probably the worst"
    " thing that can happen race-wise, as any other side-effecting"
    " operation races with the arrival of the signal. If the test produces"
    " too many interleavings consider refactoring your code.~n";
msg(shutdown) ->
  "A process crashed with reason 'shutdown'. This may happen when a"
    " supervisor is terminating its children. You can use --treat_as_normal"
    " shutdown if this is expected behaviour.~n";
msg(timeout) ->
  "A process crashed with reason '{timeout, ...}'. This may happen when a"
    " call to a gen_server (or similar) does not receive a reply within some"
    " standard timeout. Use the --after_timeout option to treat after clauses"
    " that exceed some threshold as 'impossible'.~n";
msg(treat_as_normal) ->
  "Some exit reasons were treated as normal (--treat_as_normal).~n".
