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
          actors      = []         :: [pid() | {channel(), queue()}],
          clock_map   = dict:new() :: clock_map(),
          delay_bound = infinity   :: bound(),
          done        = []         :: [event()],
          index       = 1          :: index(),
          graph_ref   = make_ref() :: reference(),
          sleeping    = []         :: [event()],
          wakeup_tree = []         :: event_tree()
         }).

-type trace_state() :: #trace_state{}.

-record(scheduler_state, {
          ignore_first_crash = true :: boolean(),
          assume_racing     = true :: boolean(),
          current_warnings  = []   :: [concuerror_warning_info()],
          delay             = 0    :: non_neg_integer(),
          depth_bound              :: pos_integer(),
          entry_point              :: mfargs(),
          first_process            :: pid(),
          ignore_error      = []   :: [atom()],
          logger                   :: pid(),
          last_scheduled           :: pid(),
          message_info             :: message_info(),
          non_racing_system = []   :: [atom()],
          optimal           = true :: boolean(),
          print_depth              :: pos_integer(),
          processes                :: processes(),
          scheduling = oldest      :: scheduling(),
          show_races = true        :: boolean(),
          strict_scheduling = false :: boolean(),
          system            = []   :: [pid()],
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
  {FirstProcess, System} =
    concuerror_callback:spawn_first_process(Options),
  InitialTrace =
    #trace_state{
       actors = [FirstProcess],
       delay_bound = ?opt(delay_bound, Options)
      },
  InitialState =
    #scheduler_state{
       ignore_first_crash = ?opt(ignore_first_crash, Options),
       assume_racing = ?opt(assume_racing, Options),
       depth_bound = ?opt(depth_bound, Options),
       entry_point = EntryPoint = ?opt(entry_point, Options),
       first_process = FirstProcess,
       ignore_error = ?opt(ignore_error, Options),
       last_scheduled = FirstProcess,
       logger = Logger = ?opt(logger, Options),
       message_info = ets:new(message_info, [private]),
       non_racing_system = ?opt(non_racing_system, Options),
       optimal = ?opt(optimal, Options),
       print_depth = ?opt(print_depth, Options),
       processes = ?opt(processes, Options),
       scheduling = ?opt(scheduling, Options),
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
  Warnings = filter_warnings(UnfilteredWarnings, Ignored),
  case UnfilteredWarnings =/= Warnings of
    true ->
      Message = "Some errors were ignored ('--ignore_error').~n",
      ?unique(Logger, ?lwarning, Message, []);
    false ->
      ok
  end,
  Log =
    case Warnings =:= [] of
      true -> none;
      false ->
        TraceInfo =
          case Warnings =:= [sleep_set_block] of
            true -> [];
            false ->
              #scheduler_state{trace = Trace} = State,
              Fold =
                fun(#trace_state{done = [A|_], index = I}, Acc) ->
                    [{I, A}|Acc]
                end,
              lists:foldl(Fold, [], Trace)
          end,
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
get_next_event(#scheduler_state{system = System, trace = [Last|_]} = State) ->
  #trace_state{
     actors      = Actors,
     delay_bound = DelayBound,
     index       = I,
     sleeping    = Sleeping,
     wakeup_tree = WakeupTree
    } = Last,
  SortedActors = schedule_sort(Actors, State),
  AvailableActors = filter_sleeping(Sleeping, SortedActors),
  case WakeupTree of
    [] ->
      Event = #event{label = make_ref()},
      get_next_event(Event, System ++ AvailableActors, State#scheduler_state{delay = 0});
    [{#event{actor = Actor, label = Label} = Event, _}|_] ->
      false = lists:member(Actor, Sleeping),
      Delay =
        case DelayBound =/= infinity of
          true -> count_delay(SortedActors, Actor);
          false -> 0
        end,
      {ok, UpdatedEvent} =
        case Label =/= undefined of
          true ->
            NewEvent = get_next_event_backend(Event, State),
            try {ok, Event} = NewEvent
            catch
              _:_ ->
                #scheduler_state{print_depth = PrintDepth} = State,
                Reason =
                  {replay_mismatch, I, Event, element(2, NewEvent), PrintDepth},
                ?crash(Reason)
            end;
          false ->
            %% Last event = Previously racing event = Result may differ.
            ResetEvent = reset_event(Event),
            get_next_event_backend(ResetEvent, State)
        end,
      update_state(UpdatedEvent, State#scheduler_state{delay = Delay})
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

count_delay(Actors, Actor) ->
  count_delay(Actors, Actor, 0).

count_delay([{Actor,_}|_], Actor, N) -> N;
count_delay([Actor|_], Actor, N) -> N;
count_delay([Channel|Rest], Actor, N) when ?is_channel(Channel) ->
  count_delay(Rest, Actor, N+1);
count_delay([Other|Rest], Actor, N) ->
  NN =
    case concuerror_callback:enabled(Other) of
      true -> N+1;
      false -> N
    end,
  count_delay(Rest, Actor, NN).

get_next_event(Event, [{Channel, Queue}|_], State) ->
  %% Pending messages can always be sent
  MessageEvent = queue:get(Queue),
  UpdatedEvent = Event#event{actor = Channel, event_info = MessageEvent},
  {ok, FinalEvent} = get_next_event_backend(UpdatedEvent, State),
  update_state(FinalEvent, State);
get_next_event(Event, [P|ActiveProcesses], State) ->
  case get_next_event_backend(Event#event{actor = P}, State) of
    retry -> get_next_event(Event, ActiveProcesses, State);
    {ok, UpdatedEvent} -> update_state(UpdatedEvent, State)
  end;
get_next_event(_Event, [], State) ->
  %% Nothing to do, trace is completely explored
  #scheduler_state{
     current_warnings = Warnings,
     logger = Logger,
     trace = [Last|Prev]
    } = State,
  #trace_state{actors = Actors, sleeping = Sleeping} = Last,
  NewWarnings =
    case Sleeping =/= [] of
      true ->
        ?debug(Logger, "Sleep set block:~n ~p~n", [Sleeping]),
        ?unique(Logger, ?lwarning, msg(sleep_set_block), []),
        [sleep_set_block];
      false ->
        case concuerror_callback:collect_deadlock_info(Actors) of
          [] -> Warnings;
          Info ->
            ?debug(Logger, "Deadlock: ~p~n", [[P || {P,_} <- Info]]),
            [{deadlock, Info}|Warnings]
        end
    end,
  {none, State#scheduler_state{current_warnings = NewWarnings, trace = Prev}}.

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
     delay  = Delay,
     logger = Logger,
     trace  = [Last|Prev]
    } = State,
  #trace_state{
     actors      = Actors,
     delay_bound = DelayBound,
     done        = Done,
     index       = Index,
     graph_ref   = Ref,
     sleeping    = Sleeping,
     wakeup_tree = WakeupTree
    } = Last,
  ?trace(Logger, "~s~n", [?pretty_s(Index, Event)]),
  concuerror_logger:graph_new_node(Logger, Ref, Index, Event),
  AllSleeping = ordsets:union(ordsets:from_list(Done), Sleeping),
  NextSleeping = update_sleeping(Event, AllSleeping, State),
  {NewLastWakeupTree, NextWakeupTree} =
    case WakeupTree of
      [] -> {[], []};
      [{_, NWT}|Rest] -> {Rest, NWT}
    end,
  NewLastDone = [Event|Done],
  NewDelayBound =
    case Delay =:= 0 of
      true -> DelayBound;
      false -> DelayBound - Delay
    end,
  InitNextTrace =
    #trace_state{
       actors      = Actors,
       delay_bound = NewDelayBound,
       index       = Index + 1,
       sleeping    = NextSleeping,
       wakeup_tree = NextWakeupTree
      },
  NewLastTrace =
    Last#trace_state{done = NewLastDone, wakeup_tree = NewLastWakeupTree},
  InitNewState =
    State#scheduler_state{trace = [InitNextTrace, NewLastTrace|Prev]},
  NewState = maybe_log(Event, InitNewState, Index),
  {ok, update_special(Special, NewState)}.

maybe_log(#event{actor = P} = Event, State0, Index) ->
  #scheduler_state{logger = Logger, treat_as_normal = Normal} = State0,
  State = 
    case is_pid(P) of
      true -> State0#scheduler_state{last_scheduled = P};
      false -> State0
    end,
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
  #scheduler_state{message_info = MessageInfo, trace = [Next|Trace]} = State,
  #trace_state{actors = Actors} = Next,
  NewActors =
    case Special of
      halt -> [];
      {message, Message} ->
        add_message(Message, Actors, MessageInfo);
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

add_message(MessageEvent, Actors, MessageInfo) ->
  #message_event{
     message = #message{id = Id},
     recipient = Recipient,
     sender = Sender
    } = MessageEvent,
  Channel = {Sender, Recipient},
  Update = fun(Queue) -> queue:in(MessageEvent, Queue) end,
  Initial = queue:from_list([MessageEvent]),
  ets:insert(MessageInfo, ?new_message_info(Id)),
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
  #scheduler_state{logger = _Logger, message_info = MessageInfo} = State,
  #trace_state{done = [Event|RestEvents], index = Index} = TraceState,
  #event{actor = Actor, special = Special} = Event,
  ClockMap = get_base_clock(RevLate, RevEarly),
  OldClock = lookup_clock(Actor, ClockMap),
  ActorClock = orddict:store(Actor, Index, OldClock),
  ?trace(_Logger, "HB: ~s~n", [?pretty_s(Index,Event)]),
  BaseHappenedBeforeClock =
    add_pre_message_clocks(Special, MessageInfo, ActorClock),
  HappenedBeforeClock =
    update_clock(RevLate++RevEarly, Event, BaseHappenedBeforeClock, State),
  maybe_mark_sent_message(Special, HappenedBeforeClock, MessageInfo),
  case proplists:lookup(message_delivered, Special) of
    none -> true;
    {message_delivered, MessageEvent} ->
      #message_event{message = #message{id = Id}} = MessageEvent,
      Delivery = {?message_delivered, HappenedBeforeClock},
      ets:update_element(MessageInfo, Id, Delivery)
  end,
  BaseNewClockMap = dict:store(Actor, HappenedBeforeClock, ClockMap),
  NewClockMap =
    case proplists:lookup(new, Special) of
      {new, SpawnedPid} ->
        dict:store(SpawnedPid, HappenedBeforeClock, BaseNewClockMap);
      none -> BaseNewClockMap
    end,
  StateClock = lookup_clock(state, ClockMap),
  OldActorClock = lookup_clock_value(Actor, StateClock),
  FinalActorClock = orddict:store(Actor, OldActorClock, HappenedBeforeClock),
  FinalStateClock = orddict:store(Actor, Index, StateClock),
  FinalClockMap =
    dict:store(
      Actor, FinalActorClock,
      dict:store(state, FinalStateClock, NewClockMap)),
  NewTraceState =
    TraceState#trace_state{
      clock_map = FinalClockMap,
      done = [Event|RestEvents]},
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
      {message_received, Id} ->
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
     logger = _Logger,
     message_info = MessageInfo,
     non_racing_system = NonRacingSystem
    } = State,
  #trace_state{done = [Event|_], index = _Index} = TraceState,
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
            message_clock(Id, MessageInfo, ActorClock);
          false -> ActorClock
        end,
      ?debug(_Logger, "~s~n", [?pretty_s(_Index, Event)]),
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
          irreversible ->
            NC = max_cv(lookup_clock(EarlyActor, EarlyClockMap), Clock),
            {update_clock, NC};
          true ->
            ?debug(Logger, "   races with ~s~n",
                   [?pretty_s(EarlyIndex, EarlyEvent)]),
            NC = max_cv(lookup_clock(EarlyActor, EarlyClockMap), Clock),
            case
              update_trace(Event, TraceState, Later, NewOldTrace, State)
            of
              skip -> {update_clock, NC};
              UpdatedNewOldTrace ->
                concuerror_logger:plan(Logger),
                {update, UpdatedNewOldTrace, NC}
            end
        end
    end,
  {NewTrace, NewClock} =
    case Action of
      none -> {[TraceState|NewOldTrace], Clock};
      {update_clock, C} -> {[TraceState|NewOldTrace], C};
      {update, S, C} ->
        if State#scheduler_state.show_races ->
            ?unique(
               Logger, ?lrace,
               "You can disable race pair messages with '--show_races false'~n",
               []),
            concuerror_logger:race(Logger, EarlyEvent, Event);
           true -> ok
        end,
        {S, C}
    end,
  more_interleavings_for_event(Rest, Event, Later, NewClock, State, NewTrace).

update_trace(Event, TraceState, Later, NewOldTrace, State) ->
  #scheduler_state{logger = Logger, optimal = Optimal} = State,
  #trace_state{
     done = [#event{actor = EarlyActor}|Done],
     delay_bound = DelayBound,
     index = EarlyIndex,
     sleeping = Sleeping,
     wakeup_tree = WakeupTree
    } = TraceState,
  NotDep = not_dep(NewOldTrace ++ Later, EarlyActor, EarlyIndex, Event),
  case insert_wakeup(Sleeping ++ Done, WakeupTree, NotDep, Optimal) of
    skip ->
      ?debug(Logger, "     SKIP~n",[]),
      skip;
    NewWakeupTree ->
      case
        (DelayBound =:= infinity) orelse
        (DelayBound - length(Done ++ WakeupTree) > 0)
      of
        true ->
          trace_plan(Logger, EarlyIndex, NotDep),
          NS = TraceState#trace_state{wakeup_tree = NewWakeupTree},
          [NS|NewOldTrace];
        false ->
          Message =
            "Some interleavings were not considered due to delay bounding.~n",
          ?unique(Logger, ?lwarning, Message, []),
          ?debug(Logger, "     OVER BOUND~n",[]),
          skip
      end
  end.

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
      true -> [LaterEvent|NotDep]
    end,
  not_dep(Rest, Actor, Index, Event, NewNotDep).


trace_plan(_Logger, _Index, _NotDep) ->
  ?debug(
     _Logger, "     PLAN~n~s",
     begin
       Indices = lists:seq(_Index, _Index + length(_NotDep) - 1),
       IndexedNotDep = lists:zip(Indices, _NotDep),
       [lists:append(
          [io_lib:format("        ~s~n", [?pretty_s(I,S)])
           || {I,S} <- IndexedNotDep])]
     end).

insert_wakeup(Sleeping, Wakeup, [E|_] = NotDep, Optimal) ->
  case Optimal of
    true -> insert_wakeup(Sleeping, Wakeup, NotDep);
    false ->
      Initials = get_initials(NotDep),
      All = Sleeping ++ [W || {W, []} <- Wakeup],
      case existing(All, Initials) of
        true -> skip;
        false -> Wakeup ++ [{E,[]}]
      end
  end.      

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
  case lists:any(Pred, Initials) of
    true -> true;
    false -> existing(Rest, Initials)
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
find_prefix([#trace_state{wakeup_tree = []}|Rest], State) ->
  find_prefix(Rest, State);
find_prefix([#trace_state{graph_ref = Sibling} = Other|Rest], State) ->
  #scheduler_state{logger = Logger} = State,
  [#trace_state{graph_ref = Parent}|_] = Rest,
  concuerror_logger:graph_set_node(Logger, Parent, Sibling),
  [Other#trace_state{graph_ref = make_ref(), clock_map = dict:new()}|Rest].


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
  replay_prefix_aux(lists:reverse(Trace), State).

replay_prefix_aux([_], State) ->
  %% Last state has to be properly replayed.
  State;
replay_prefix_aux([#trace_state{done = [Event|_], index = I}|Rest], State) ->
  #scheduler_state{logger = _Logger, print_depth = PrintDepth} = State,
  ?trace(_Logger, "~s~n", [?pretty_s(I, Event)]),
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
    " supervisor is terminating its children. You can use '--treat_as_normal"
    " shutdown' if this is expected behaviour.~n";
msg(sleep_set_block) ->
  "Some interleavings were 'sleep-set blocked'. This is expected if you have"
    " specified '--optimal false', but reveals wasted effort.~n";
msg(timeout) ->
  "A process crashed with reason '{timeout, ...}'. This may happen when a"
    " call to a gen_server (or similar) does not receive a reply within some"
    " standard timeout. Use the '--after_timeout' option to treat after clauses"
    " that exceed some threshold as 'impossible'.~n";
msg(treat_as_normal) ->
  "Some abnormal exit reasons were treated as normal (--treat_as_normal).~n".
