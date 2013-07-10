%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Scheduler
%%%----------------------------------------------------------------------

-module(concuerror_sched).

%% UI related exports
-export([analyze/3]).

%% Internal exports
-export([notify/2, notify/3, wait/0]).

-export_type([analysis_target/0, analysis_ret/0, bound/0, transition/0]).

%%-define(COND_DEBUG, true).
%%-define(DEBUG, true).
-define(CLASSIC, classic).
-define(SOURCE, source).
-define(FULL, full).
-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

-define(INFINITY, infinity).
-define(NO_ERROR, undef).
-define(TIME_LIMIT, 20*1000). % (in ms)

%%%----------------------------------------------------------------------
%%% Records
%%%----------------------------------------------------------------------

%% 'next' messages are about next instrumented instruction not yet dispatched
%% 'prev' messages are about additional effects of a dispatched instruction
%% 'async' messages are about receives which have become enabled
-type sched_msg_type() :: 'next' | 'prev' | 'async'.

%% Internal message format
%%
%% msg    : An atom describing the type of the message.
%% pid    : The sender's LID.
%% misc   : Optional arguments, depending on the message type.
-record(sched, {msg          :: atom(),
                lid          :: concuerror_lid:lid(),
                misc = empty :: term(),
                type = next  :: sched_msg_type()}).

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type analysis_info() :: {analysis_target(),
                          non_neg_integer(),  %% Number of interleavings
                          non_neg_integer()}. %% Sleep-Set blocked traces


%% Analysis result tuple.
-type analysis_ret() ::
    {'ok', analysis_info()} |
    {'error', 'instr', analysis_info()} |
    {'error', 'analysis', analysis_info(), [concuerror_ticket:ticket()]}.

%% Module-Function-Arguments tuple.
-type analysis_target() :: {module(), atom(), [term()]}.

-type bound() :: 'inf' | non_neg_integer().

%% Scheduler notification.

-type notification() :: 'after' | 'block' | 'demonitor' | 'ets_delete' |
                        'ets_foldl' | 'ets_insert' | 'ets_insert_new' |
                        'ets_lookup' | 'ets_match_delete' | 'ets_match_object' |
                        'ets_select_delete' | 'fun_exit' | 'halt' |
                        'is_process_alive' | 'link' | 'monitor' | 'process_flag'
                        | 'receive' | 'receive_no_instr' | 'register' | 'send' |
                        'send_after' | 'spawn' | 'spawn_link' | 'spawn_monitor'
                        | 'spawn_opt' | 'start_timer' | 'unlink' | 'unregister'
                        | 'whereis' | 'port_command' | 'port_control'.

%%%----------------------------------------------------------------------
%%% User interface
%%%----------------------------------------------------------------------

%% @spec: analyze(analysis_target(), [file:filename()], concuerror:options()) ->
%%          analysis_ret()
%% @doc: Produce all interleavings of running `Target'.
-spec analyze(analysis_target(), [file:filename()], concuerror:options()) ->
            analysis_ret().

analyze({Mod,Fun,Args}=Target, Files, Options) ->
    PreBound =
        case lists:keyfind(preb, 1, Options) of
            {preb, inf} -> ?INFINITY;
            {preb, Bound} -> Bound;
            false -> ?DEFAULT_PREB
        end,
    Dpor =
        case lists:keyfind(dpor, 1, Options) of
            {dpor, Flavor} -> Flavor;
            false -> 'none'
        end,
    Ret =
        case concuerror_instr:instrument_and_compile(Files, Options) of
            {ok, Bin} ->
                %% Note: No error checking for load
                ok = concuerror_instr:load(Bin),
                %% Rename Target's module
                NewMod = concuerror_instr:check_module_name(Mod, Fun, 0),
                NewTarget = {NewMod, Fun, Args},
                concuerror_log:log(0, "\nRunning analysis with preemption "
                    "bound ~p... \n", [PreBound]),
                %% Reset the internal state for the progress logger
                concuerror_log:reset(),
                %% Unregister some key processes
                %% inet_gethos_native will run without supervisor
                %% (Icky fallback)
                catch unregister(kernel_safe_sup),
                catch unregister(net_sup),
                %% Run all possible interleavings
                {T1, _} = statistics(wall_clock),
                Result = do_analysis(NewTarget, PreBound, Dpor, Options),
                {T2, _} = statistics(wall_clock),
                {Mins, Secs} = concuerror_util:to_elapsed_time(T1, T2),
                ?debug("Done in ~wm~.2fs\n", [Mins, Secs]),
                %% Print analysis summary
                {Tickets, RunCount, SBlocked, Trans, STrans} = Result,
                StrB =
                    case SBlocked of
                        0 -> " ";
                        _ -> io_lib:format(
                                " (encountered ~w sleep-set blocked traces (~w transitions)) ",
                                [SBlocked, STrans])
                    end,
                MemoryStr =
                    try erlang:memory(maximum) of
                        N ->
                            MB = N / (1024*1024),
                            io_lib:format(" (using ~.2fMB)",[MB])
                    catch
                        _:_ ->
                            ""
                    end,
                concuerror_log:log(0, "\n\nAnalysis complete. Checked "
                    "~w interleaving(s) (~w transitions)~sin ~wm~.2fs~s:\n",
                    [RunCount, Trans, StrB, Mins, Secs, MemoryStr]),
                case Tickets =:= [] of
                    true ->
                        concuerror_log:log(0, "No errors found.~n"),
                        {ok, {Target, RunCount, SBlocked}};
                    false ->
                        TicketCount = length(Tickets),
                        concuerror_log:log(0,
                                "Found ~p erroneous interleaving(s).~n",
                                [TicketCount]),
                        {error, analysis, {Target, RunCount, SBlocked}, Tickets}
                end;
            error -> {error, instr, {Target, 0, 0}}
        end,
    concuerror_instr:delete_and_purge(Options),
    Ret.

%% Produce all possible process interleavings of (Mod, Fun, Args).
do_analysis(Target, PreBound, Dpor, Options) ->
    Self = self(),
    Fun = fun() -> scheduler_main(Target, PreBound, Self, Dpor, Options) end,
    process_flag(trap_exit, true),
    Backend = spawn_link(Fun),
    receive
        {interleave_result, Result} -> Result;
        {'EXIT', Backend, Reason} ->
            Msg = io_lib:format("Backend exited with reason:\n ~p\n", [Reason]),
            concuerror_log:internal(Msg)
    end.

%% =============================================================================
%% DATA STRUCTURES
%% =============================================================================

-type s_i()        :: non_neg_integer().
-type instr()      :: term().
-type transition() :: {concuerror_lid:lid(), instr(), list()}.
-type lid_trace()  :: [{concuerror_lid:lid(), transition(), lid_trace()}].
-type clock_map()  :: dict(). %% dict(concuerror_lid:lid(), clock_vector()).
-type clock_vector() :: orddict:orddict(). %% dict(concuerror_lid:lid(), s_i()).

-record(trace_state, {
          i         = 0                 :: s_i(),
          last      = init_tr()         :: transition(),
          last_blocked = false          :: boolean(),
          enabled   = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          blocked   = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          pollable  = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          backtrack = []                :: lid_trace(),
          done      = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          sleep_set = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          nexts     = dict:new()        :: dict(), % dict(lid(), instr()),
          clock_map = empty_clock_map() :: clock_map(),
          preemptions = 0               :: non_neg_integer(),
          race_checked = false          :: boolean(),
          receives_vector = []          :: clock_vector()
         }).

-type trace_state() :: #trace_state{}.

-record(dpor_state, {
          target                  :: analysis_target(),
          run_count    = 1        :: pos_integer(),
          sleep_blocked_count = 0 :: non_neg_integer(),
          total_trans = 0         :: non_neg_integer(),
          sleep_trans = 0         :: non_neg_integer(),
          show_output  = false    :: boolean(),
          tickets      = []       :: [concuerror_ticket:ticket()],
          trace        = []       :: [trace_state()],
          must_replay  = false    :: boolean(),
          bound_flag   = false    :: boolean(),
          proc_before  = []       :: [pid()],
          dpor_flavor  = 'none'   :: 'full' | 'classic' | 'source' | 'none',
          preemption_bound = inf  :: non_neg_integer() | 'inf',
          group_leader            :: pid()
         }).

%% =============================================================================
%% LOGIC (high level description of the exploration algorithm)
%% =============================================================================

scheduler_main(Target, PreBound, Parent, Dpor, Options) ->
    %% fprof:trace(start),
    ?debug("Scheduler spawned\n"),
    register(?RP_SCHED, self()),
    Procs = processes(),
    %% To be able to clean up we need to be trapping exits...
    process_flag(trap_exit, true),
    %% Get `show_output' flag from options
    ShowOutput = lists:keymember('show_output', 1, Options),
    {Trace, GroupLeader} = start_target(Target),
    ?debug("Initial target spawned\n"),
    NewState = #dpor_state{trace = Trace, target = Target, proc_before = Procs,
        dpor_flavor = Dpor, preemption_bound = PreBound,
        show_output = ShowOutput, group_leader = GroupLeader},
    Result = explore(NewState),
    %% fprof:trace(stop),
    unregister(?RP_SCHED),
    Parent ! {interleave_result, Result}.

init_tr() -> {concuerror_lid:root_lid(), init, []}.

start_target(Target) ->
    {FirstLid, GroupLeader} = start_target_op(Target),
    Next = wait_next(FirstLid, init),
    New = ordsets:new(),
    MaybeEnabled = ordsets:add_element(FirstLid, New),
    {Pollable, Enabled, Blocked} =
        update_lid_enabled(FirstLid, Next, New, MaybeEnabled, New),
    %% FIXME: check_messages and poll should also be called here for
    %%        instrumenting "black" initial messages.
    TraceTop =
        #trace_state{nexts = dict:store(FirstLid, Next, dict:new()),
                     enabled = Enabled, blocked = Blocked,
                     backtrack = new_backtrack([{P, Next} || P <- Enabled]),
                     pollable = Pollable},
    {[TraceTop], GroupLeader}.

new_backtrack(LidList) ->
    [{Lid, Tr, []} || {Lid, Tr} <- LidList].

%% -----------------------------------------------------------------------------
%% The main explore routine
%% -----------------------------------------------------------------------------

explore(State) ->
    receive
        stop_analysis -> dpor_return(State)
    after 0 ->
        case select_from_backtrack(State) of
            {ok, {Lid, Cmd, _} = Selected, UpdState} ->
                case Cmd of
                    {error, _ErrorInfo} ->
                        RaceCheckState = race_check(UpdState),
                        ErrorState = report_error(Selected, RaceCheckState),
                        NewState = drop_last_frame(ErrorState),
                        explore(NewState);
                    _Else ->
                        ?debug("Plan: ~p\n",[Selected]),
                        Next = wait_next(Lid, Cmd),
                        NextState = update_trace(Selected, Next, UpdState),
                        NewState = add_some_next_to_backtrack(NextState),
                        explore(NewState)
                end;
            none ->
                UpdState =
                    case State#dpor_state.must_replay of
                        true ->
                            %% Already backtracking
                            State;
                        false ->
                            RaceCheckState = race_check(State),
                            report_possible_deadlock(RaceCheckState)
                    end,
                NewState = drop_last_frame(UpdState),
                case finished(NewState) of
                    false -> explore(NewState);
                    true -> dpor_return(NewState)
                end
        end
    end.

%% -----------------------------------------------------------------------------

select_from_backtrack(#dpor_state{trace = []}) -> none;
select_from_backtrack(#dpor_state{must_replay = MustReplay, trace = Trace,
                                  bound_flag = BoundFlag} = State) ->
    [#trace_state{backtrack = Backtrack,
                  done = Done,
                  sleep_set = SleepSet} = _TraceTop|_] = Trace,
    ?debug("------------\nExplore ~p\n------------\n",
           [_TraceTop#trace_state.i + 1]),
    Sleepers = ordsets:union(SleepSet, Done),
    case pick_from_backtrack(BoundFlag, Backtrack, Sleepers) of
        none ->
            ?debug("Backtrack set explored\n",[]),
            none;
        {true, SelectedLid} ->
            UpdState =
                case MustReplay of
                    true -> replay_trace(State);
                    false -> State
                end,
            [NewTraceTop|RestTrace] = UpdState#dpor_state.trace,
            Instruction =
                dict:fetch(SelectedLid, NewTraceTop#trace_state.nexts),
            NewDone = ordsets:add_element(SelectedLid, Done),
            FinalTraceTop =
                NewTraceTop#trace_state{done = NewDone},
            FinalState = UpdState#dpor_state{trace = [FinalTraceTop|RestTrace]},
            {ok, Instruction, FinalState}
    end.

pick_from_backtrack(true, _Backtrack, _Sleepers) -> none;
pick_from_backtrack(_BoundFlag, Backtrack, Sleepers) ->
    pick_from_backtrack(Backtrack, Sleepers).

pick_from_backtrack([], _) -> none;
pick_from_backtrack([{B, _, _}|Rest], Done) ->
    case ordsets:is_element(B, Done) of
        true  -> pick_from_backtrack(Rest, Done);
        false -> {true, B}
    end.

%% -----------------------------------------------------------------------------

%% - add new entry with new entry
%% - wait any possible additional messages
%% - check for async
update_trace(Selected, Next, State) ->
    #dpor_state{trace = Trace, dpor_flavor = Flavor} = State,
    NewTrace = update_trace(Selected, Next, Trace, Flavor, false),
    State#dpor_state{trace = NewTrace}.

update_trace({Lid, _, _} = Selected, Next, [PrevTraceTop|_] = Trace,
             Flavor, Replaying) ->
    #trace_state{i = I, enabled = Enabled, blocked = Blocked,
                 pollable = Pollable, done = Done, backtrack = Backtrack,
                 nexts = Nexts, clock_map = ClockMap, sleep_set = SleepSet,
                 preemptions = Preemptions, last = {LLid,_,_}} = PrevTraceTop,
    Expected = dict:fetch(Lid, Nexts),
    NewNexts = dict:store(Lid, Next, Nexts),
    ClockVector = lookup_clock(Lid, ClockMap),
    MaybeNotPollable = ordsets:del_element(Lid, Pollable),
    {NewPollable, NewEnabled, NewBlocked} =
        update_lid_enabled(Lid, Next, MaybeNotPollable, Enabled, Blocked),
    CommonNewTraceTop =
        case Replaying of
            false ->
                NewN = I+1,
                BaseClockVector = orddict:store(Lid, NewN, ClockVector),
                LidsClockVector =
                    recent_dependency_cv(Selected, BaseClockVector, Trace),
                NewClockMap = dict:store(Lid, LidsClockVector, ClockMap),
                NewPreemptions =
                    case ordsets:is_element(LLid, Enabled) of
                        true ->
                            case Lid =:= LLid of
                                false -> Preemptions + 1;
                                true -> Preemptions
                            end;
                        false -> Preemptions
                    end,
                NewSleepSetCandidates =
                    ordsets:union(ordsets:del_element(Lid, Done), SleepSet),
                #trace_state{
                   i = NewN, last = Selected, nexts = NewNexts,
                   enabled = NewEnabled, sleep_set = NewSleepSetCandidates,
                   blocked = NewBlocked, clock_map = NewClockMap,
                   pollable = NewPollable, preemptions = NewPreemptions};
            {true, ReplayTop} ->
                ReplayTop#trace_state{
                  last = Selected, nexts = NewNexts, pollable = NewPollable}
        end,
    InstrNewTraceTop = check_external_changes(CommonNewTraceTop),
    UpdTraceTop =
        #trace_state{last = UpdSelected,
                     sleep_set = UpdSleepSet,
                     nexts = UpdNexts,
                     backtrack = TempBacktrack} =
        update_instr_info(Lid, Selected, InstrNewTraceTop),
    PrevTrace =
        case UpdSelected =:= Expected of
            true -> Trace;
            false ->
                rewrite_while_awaked(UpdSelected, Expected, Trace)
        end,
    FinalTraceTop =
        case Replaying of
            false ->
                ?debug("Selected: ~P\n", [UpdSelected, ?DEBUG_DEPTH]),
                ?debug("Happened before: ~p\n",
                       [orddict:to_list(
                          begin
                              CMM = UpdTraceTop#trace_state.clock_map,
                              CCC = lookup_clock(Lid, CMM),
                              case lookup_clock_value(Lid, ClockVector) of
                                  0 -> orddict:erase(Lid, CCC);
                                  QQ -> orddict:store(Lid, QQ, CCC)
                              end
                          end)]),
                {NewSleepSet, NewAwaked} =
                    case Flavor =:= 'none' of
                        true -> {[], []};
                        false ->
                            filter_awaked(UpdSleepSet, UpdNexts, UpdSelected)
                    end,
                NewBacktrack =
                    case TempBacktrack =:= [] of
                        true ->
                            case {Next, Selected} of
                                {_, {_, { halt, _}, _}} -> [];
                                {{_, {error, _}, _}, _} ->
                                    new_backtrack([{Lid, Next}]);
                                _ ->
                                    NB =
                                        element(3, lists:keyfind(Lid, 1,
                                                                 Backtrack)),
                                    case
                                        Flavor =:= ?FULL orelse
                                        Flavor =:= none
                                    of
                                        true -> NB;
                                        false ->
                                            prioritize_awaked(NB, NewAwaked)
                                    end
                            end;
                        false -> TempBacktrack
                    end,
                NewLastBlocked = ordsets:is_element(Lid, NewBlocked),
                UpdTraceTop#trace_state{
                  last_blocked = NewLastBlocked,
                  backtrack = NewBacktrack,
                  sleep_set = NewSleepSet};
            {true, _ReplayTop} ->
                UpdTraceTop
        end,
    [FinalTraceTop|PrevTrace].

update_lid_enabled(Lid, {_, Next, _}, Pollable, Enabled, Blocked) ->
    {NewEnabled, NewBlocked} =
        case is_enabled(Next) of
            true -> {Enabled, Blocked};
            false ->
                {ordsets:del_element(Lid, Enabled),
                 ordsets:add_element(Lid, Blocked)}
        end,
    NewPollable =
        case is_pollable(Next) of
            false -> Pollable;
            true -> ordsets:add_element(Lid, Pollable)
        end,
    {NewPollable, NewEnabled, NewBlocked}.

is_enabled({'receive', blocked}) -> false;
is_enabled(_Else) -> true.

is_pollable({'receive', blocked}) -> true;
is_pollable({'after', _Info}) -> true;
is_pollable(_Else) -> false.

recent_dependency_cv(Transition, ClockVector, Trace) ->
    Fun =
        fun(#trace_state{i = I,
                         last = {Lid, _, _} = Transition2,
                         clock_map = CM}, CVAcc) ->
                case
                    lookup_clock_value(Lid, CVAcc) < I andalso
                    concuerror_deps:dependent(Transition, Transition2)
                of
                    true ->
                        CV = lookup_clock(Lid, CM),
                        max_cv(CVAcc, CV);
                    false -> CVAcc
                end
        end,
    lists:foldl(Fun, ClockVector, Trace).

%% Handle instruction is broken in two parts to reuse code in replay.
handle_instruction(Transition, TraceTop) ->
    {NewTransition, Extra} = handle_instruction_op(Transition),
    handle_instruction_al(NewTransition, TraceTop, Extra).

check_external_changes(TraceTop) ->
    case unexpected_exits(TraceTop) of
        {true, NewTraceTop} -> NewTraceTop;
        none ->
            #trace_state{pollable = Pollable} = TraceTop,
            PollableList = ordsets:to_list(Pollable),
            lists:foldl(fun poll_all/2, TraceTop, PollableList)
    end.

unexpected_exits(#trace_state{nexts = Nexts} = TraceTop) ->
    receive
        {'DOWN', _, process, _, normal} -> unexpected_exits(TraceTop);
        {'DOWN', _, process, Pid, Reason} ->
            ?debug("Unexpected exit: ~p ~p\n", [Pid, Reason]),
            Lid = lid_from_pid(Pid),
            Entry = {Lid, {error, [exit, Reason, []]}, []},
            NewNexts = dict:store(Lid, Entry, Nexts),
            {true, TraceTop#trace_state{nexts = NewNexts,
                                        backtrack = [{Lid, Entry, []}]
                                       }}
    after
        0 -> none
    end.

poll_all(Lid, TraceTop) ->
    case poll(Lid) of
        {'receive', Info} = Res when
              Info =:= unblocked;
              Info =:= had_after ->
            #trace_state{pollable = Pollable,
                         blocked = Blocked,
                         enabled = Enabled,
                         %% TODO: Remove next line
                         sleep_set = SleepSet,
                         nexts = Nexts} = TraceTop,
            NewPollable = ordsets:del_element(Lid, Pollable),
            NewBlocked = ordsets:del_element(Lid, Blocked),
            NewSleepSet = ordsets:del_element(Lid, SleepSet),
            NewEnabled = ordsets:add_element(Lid, Enabled),
            {Lid, _Old, Msgs} = dict:fetch(Lid, Nexts),
            NewNexts = dict:store(Lid, {Lid, Res, Msgs}, Nexts),
            TraceTop#trace_state{pollable = NewPollable,
                                 blocked = NewBlocked,
                                 enabled = NewEnabled,
                                 sleep_set = NewSleepSet,
                                 nexts = NewNexts};
        _Else ->
            TraceTop
    end.

update_instr_info(Lid, Selected, CommonNewTraceTop) ->
    IntermediateTraceTop = handle_instruction(Selected, CommonNewTraceTop),
    UpdatedClockVector =
        lookup_clock(Lid, IntermediateTraceTop#trace_state.clock_map),
    {Lid, RewrittenInstr, _Msgs} = IntermediateTraceTop#trace_state.last,
    Messages = orddict:from_list(replace_messages(Lid, UpdatedClockVector)),
    IntermediateTraceTop#trace_state{last = {Lid, RewrittenInstr, Messages}}.

filter_awaked(SleepSet, Nexts, Selected) ->
    Filter =
        fun(Lid) ->
                Instr = dict:fetch(Lid, Nexts),
                Dep = concuerror_deps:dependent(Instr, Selected),
                ?debug(" vs ~p: ~p\n",[Instr, Dep]),
                not Dep
        end,
    {A, NA} = lists:partition(Filter, SleepSet),
    {ordsets:from_list(A), ordsets:from_list(NA)}.

prioritize_awaked(Backtrack, Awaked) ->
    Fold = fun(P, Acc) -> [{P, dummy, Acc}] end,
    lists:foldl(Fold, Backtrack, Awaked).

rewrite_while_awaked(Transition, Original, Trace) ->
    rewrite_while_awaked(Transition, Original, Trace, []).

rewrite_while_awaked(_Transition, _Original, [], Acc) -> lists:reverse(Acc);
rewrite_while_awaked({P, _, _} = Transition, Original,
                     [TraceTop|Rest] = Trace, Acc) ->
    #trace_state{sleep_set = SleepSet,
                 nexts = Nexts} = TraceTop,
    case
        not ordsets:is_element(P, SleepSet) andalso
        {ok, Original} =:= dict:find(P, Nexts)
    of
        true ->
            NewNexts = dict:store(P, Transition, Nexts),
            NewTraceTop = TraceTop#trace_state{nexts = NewNexts},
            rewrite_while_awaked(Transition, Original, Rest, [NewTraceTop|Acc]);
        false ->
            lists:reverse(Acc, Trace)
    end.

%% -----------------------------------------------------------------------------
%% Dpor logic
%% -----------------------------------------------------------------------------

race_check(#dpor_state{preemption_bound = Bound, trace = Trace,
                       dpor_flavor = Flavor, bound_flag = BoundFlag} = State) ->
    case Flavor =:= 'none' of
        true ->
            %% add_some_next will take care of all the backtracks.
            State;
        false ->
            case BoundFlag of
                true -> State;
                false ->
                    NewTrace = race_check(Trace, Bound, Flavor),
                    State#dpor_state{trace = NewTrace}
            end
    end.

race_check(Trace, PreBound, Flavor) ->
    race_check(Trace, [], PreBound, Flavor).

race_check([_] = Trace, _Rest, _PreBound, _Flavor) -> Trace;
race_check([#trace_state{race_checked = true}|_] = Trace,
           _Rest, _PreBound, Flavor)
  when Flavor =:= ?CLASSIC; Flavor =:= ?SOURCE ->
    Trace;
race_check(Trace, Rest, PreBound, Flavor) ->
    [#trace_state{i = I, last = {Lid, {Tag, Info}, _} = Transition} = Top|
     [#trace_state{clock_map = ClockMap}|_] = PTrace] = Trace,
    NewPTrace = race_check(PTrace, [Top|Rest], PreBound, Flavor),
    NewTop = Top#trace_state{race_checked = true},
    ?debug("Race check: ~p ~p\n", [I, Transition]),
    case concuerror_deps:may_have_dependencies(Transition) of
        true ->
            BasicClock = orddict:store(Lid, I, lookup_clock(Lid, ClockMap)),
            InescapableReceive =
                case Tag =:= 'receive' of
                    false -> false;
                    true -> element(1, Info) =:= unblocked
                end,
            ClockVector =
                case InescapableReceive of
                    true ->
                        MsgVector = Top#trace_state.receives_vector,
                        max_cv(BasicClock, MsgVector);
                    false ->
                        BasicClock
                end,
            add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound,
                                     Flavor, NewPTrace, [NewTop], Rest);
        false -> [NewTop|NewPTrace]
    end.

add_all_backtracks_trace(_Transition, _Lid, _ClockVector, _PreBound,
                         _Flavor, [_] = Init, Acc, _Rest) ->
    lists:reverse(Acc, Init);
add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound, Flavor,
                         [#trace_state{preemptions = Preempt} = StateI|Trace],
                         Acc, Rest)
  when Preempt + 1 > PreBound, PreBound =/= ?INFINITY ->
    add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound, Flavor,
                             Trace, [StateI|Acc], Rest);
add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound, Flavor,
                         [StateI,PreSI|Rest], Acc, AccRest) ->
    #trace_state{i = I, last = {ProcSI, _, _} = SI,
                 clock_map = ClockMap} = StateI,
    Clock = lookup_clock_value(ProcSI, ClockVector),
    Action =
        case I > Clock andalso concuerror_deps:dependent(Transition, SI) of
            false -> {continue, PreSI, ClockVector};
            true ->
                ?debug("~4w: ~P Clock ~p\n", [I, SI, ?DEBUG_DEPTH, Clock]),
                #trace_state{enabled = Enabled,
                             backtrack = Backtrack,
                             done = Done,
                             sleep_set = SleepSet} = PreSI,
                Sleepers = ordsets:union(SleepSet, Done),
                case Flavor of
                    ?FULL ->
                        Result =
                            find_path([StateI|Acc], AccRest, ProcSI, I,
                                      Sleepers, Backtrack),
                        NewClockVector = orddict:store(ProcSI, I, ClockVector),
                        case Result of
                            inversion_explored ->
                                ?debug("    Inversion is explored...\n"),
                                {continue, PreSI, NewClockVector};
                            equivalent_scheduled ->
                                ?debug("    Equivalent is scheduled...\n"),
                                {continue, PreSI, NewClockVector};
                            {replace, NewBacktrack} ->
                                ?debug("    NewBacktrack: ~p\n",[NewBacktrack]),
                                {continue,
                                 PreSI#trace_state{backtrack = NewBacktrack},
                                 NewClockVector}
                        end;
                    ?SOURCE ->
                        Candidates = ordsets:subtract(Enabled, Sleepers),
                        {Predecessor, Initial} =
                            find_preds_and_initials(Lid, ProcSI, Candidates,
                                                    I, ClockVector, Acc),
                        BacktrackSet =
                            ordsets:from_list([B || {B,_,_} <- Backtrack]),
                        case Predecessor of
                            [] ->
                                ?debug("    All sleeping...\n"),
                                NewClockVector =
                                    lookup_clock(ProcSI, ClockMap),
                                MaxClockVector =
                                    max_cv(NewClockVector, ClockVector),
                                {continue_source, ProcSI, MaxClockVector};
                            [P] ->
                                Intersection =
                                    ordsets:intersection(BacktrackSet, Initial),
                                NewBacktrack =
                                    case Intersection =/= [] of
                                        true ->
                                            ?debug("    Init in backtrack\n"),
                                            Backtrack;
                                        false ->
                                            ?debug("    Add: ~p\n", [P]),
                                            Backtrack ++ [{P, dummy, []}]
                                    end,
                                ?debug("    NewBacktrack: ~p\n",[NewBacktrack]),
                                {done,
                                 PreSI#trace_state{backtrack = NewBacktrack}}
                        end;
                    ?CLASSIC ->
                        Candidates = ordsets:subtract(Enabled, Sleepers),
                        {Predecessor, _Initial} =
                            find_preds_and_initials(Lid, ProcSI, Candidates,
                                                    I, ClockVector, Acc),
                        case
                            decide_classic(Predecessor, Backtrack, Candidates,
                                           PreSI)
                        of
                            {done, _} = DoneResult -> DoneResult;
                            continue ->
                                NewClockVector =
                                    lookup_clock(ProcSI, ClockMap),
                                MaxClockVector =
                                    max_cv(NewClockVector, ClockVector),
                                {continue_source, ProcSI, MaxClockVector}
                        end
                end
        end,
    case Action of
        {continue, NewPreSI, UpdClockVector} ->
            add_all_backtracks_trace(Transition, Lid, UpdClockVector, PreBound,
                                     Flavor, [NewPreSI|Rest], [StateI|Acc],
                                     AccRest);
        {continue_source, UpdProcSI, UpdClockVector} ->
            add_all_backtracks_trace(Transition, UpdProcSI, UpdClockVector,
                                     PreBound, Flavor, [PreSI|Rest],
                                     [StateI|Acc], AccRest);

        {done, NewPreSI} ->
            lists:reverse([StateI|Acc], [NewPreSI|Rest])
    end.

%% -----------------
%% For optimal DPOR:
%% -----------------

find_path([#trace_state{nexts = Nexts}|Acc],
          Rest, ProcSI, I, Sleepers, Backtrack) ->
    SleepSet = ordsets:del_element(ProcSI, Sleepers),
    Annotated = [{P, dict:fetch(P, Nexts)} || P <- SleepSet],
    NotDeps = not_deps(Acc, Rest, ProcSI, I),
    ?debug("      NotDeps:~p\n",[NotDeps]),
    try
        case find_weak_initial(NotDeps, Annotated) of
            {true, _, _} -> throw(inversion_explored);
            false ->
                Pred = fun({P,_,_}) -> P =/= ProcSI end,
                {Done, [{ProcSI,_,_} = Current|Future]} =
                    lists:splitwith(Pred, Backtrack),
                ?debug("      Future:~p\n",[Future]),
                NewFuture = insert_best_match(Future, NotDeps),
                {replace, Done ++ [Current|NewFuture]}
        end
    catch
        throw:Reason -> Reason
    end.

find_weak_initial(    _,    []) -> false;
find_weak_initial(Trace, [C|R]) ->
    case find_weak_initial(Trace, [C], []) of
        false -> find_weak_initial(Trace, R);
        True -> True
    end.

find_weak_initial(_, [], _) -> false;
find_weak_initial([], [{Lid, _}|_], Acc) ->
    {true, Lid, lists:reverse(Acc)};
find_weak_initial([{Lid, _, _} = Tr|Rest], Candidates, Acc) ->
    case lists:keyfind(Lid, 1, Candidates) of
        {Lid, _} -> {true, Lid, lists:reverse(Acc, Rest)};
        false ->
            Pred = fun({_, Tr2}) -> not concuerror_deps:dependent(Tr, Tr2) end,
            NewCandidates = lists:filter(Pred, Candidates),
            find_weak_initial(Rest, NewCandidates, [Tr|Acc])
    end.

insert_best_match([], Trace) ->
    Fold = fun({P, _,_} = Tr, PAcc) -> [{P, Tr, PAcc}] end,
    lists:foldl(Fold, [], lists:reverse(Trace));
insert_best_match(Backtrack, Trace) ->
    ?debug("      Trace:~p\n", [Trace]),
    Ps = [{P,Tr} || {P,Tr,_} <- Backtrack],
    case find_weak_initial(Trace, Ps) of
        {true, Lid, NewTrace} ->
            ?debug("      WeakIni:~p\n", [Lid]),
            {Lid, Tr, Further} = lists:keyfind(Lid, 1, Backtrack),
            ?debug("      Further:~p\n",[Further]),
            case Further =:= [] of
                true -> throw(equivalent_scheduled);
                false ->
                    NewFuther = insert_best_match(Further, NewTrace),
                    lists:keyreplace(Lid, 1, Backtrack, {Lid, Tr, NewFuther})
            end;
        false ->
            Backtrack ++ insert_best_match([], Trace)
    end.

not_deps(Acc, Rest, ProcSI, I) ->
    not_deps(Acc, Rest, ProcSI, I, []).

not_deps([], no_rest, _, _, Path) ->
    lists:reverse(Path);
not_deps([#trace_state{last = Last}], Rest, ProcSI, I, Path)
  when Rest =/= no_rest ->
    not_deps(Rest, no_rest, ProcSI, I, [Last|Path]);
not_deps([#trace_state{last = {Lid, _, _} = Last, clock_map = ClockMap}|Acc],
         Rest, ProcSI, I, Path) ->
    Lid2Clock = lookup_clock(Lid, ClockMap),
    NewPath =
        case lookup_clock_value(ProcSI, Lid2Clock) >= I of
            true  -> Path;
            false -> [Last|Path]
        end,
    not_deps(Acc, Rest, ProcSI, I, NewPath).

%% --------------------------------------
%% For source set based and classic DPOR:
%% --------------------------------------

find_preds_and_initials(Lid, ProcSI, Candidates, I, ClockVector, RevTrace) ->
    {Racing, NonRacing} = find_initials(Candidates, ProcSI, I, RevTrace),
    Initial =
        case not ordsets:is_element(Lid, Candidates)
            orelse ordsets:is_element(Lid, Racing) of
            true -> NonRacing;
            false -> ordsets:add_element(Lid, NonRacing)
        end,
    {predecessor(Initial, I, ClockVector), Initial}.

find_initials(Candidates, ProcSI, I, RevTrace) ->
    RealCandidates = ordsets:del_element(ProcSI, Candidates),
    find_initials(RealCandidates, I, RevTrace, [ProcSI], []).

find_initials(Candidates, _I,        [_], Racing, NonRacing) ->
    {Racing,ordsets:union(Candidates, NonRacing)};
find_initials(        [], _I,     _Trace, Racing, NonRacing) ->
    {Racing, NonRacing};
find_initials(Candidates,  I, [Top|Rest], Racing, NonRacing) ->
    #trace_state{last = {P,_,_}, clock_map = CM} = Top,
    ClockVector = lookup_clock(P, CM),
    case ordsets:is_element(P, Candidates) of
        false ->
            find_initials(Candidates, I, Rest, Racing, NonRacing);
        true ->
            Fun2 = fun(K, V, A) -> A andalso (K =:= P orelse V < I) end,
            {NewRacing, NewNonRacing} =
                case orddict:fold(Fun2, true, ClockVector) of
                    false ->
                        {ordsets:add_element(P, Racing), NonRacing};
                    true ->
                        {Racing, ordsets:add_element(P, NonRacing)}
                end,
            NewCandidates = ordsets:del_element(P, Candidates),
            find_initials(NewCandidates, I, Rest, NewRacing, NewNonRacing)
    end.

predecessor(Initial, I, ClockVector) ->
    DropWhile = fun(Lid) -> lookup_clock_value(Lid, ClockVector) < I end,
    case lists:dropwhile(DropWhile, Initial) of
        [] -> [];
        [H|_] -> [H]
    end.

decide_classic(Predecessor, Backtrack, Candidates, PreSI) ->
    BacktrackSet = ordsets:from_list([B || {B,_,_} <- Backtrack]),
    case ordsets:intersection(BacktrackSet, Predecessor) =/= [] of
        true ->
            ?debug("One pred already in backtrack.\n"),
            {done, PreSI};
        false ->
            case ordsets:intersection(Predecessor, Candidates) of
                [OneP|_] ->
                    ?debug(" Add as 'choose-one': ~p\n", [OneP]),
                    Add = [{OneP, dummy, []}],
                    {done, PreSI#trace_state{backtrack = Backtrack ++ Add}};
                [] -> continue
            end
    end.

%% --------------------------------------
%% Manipulating the clock vectors / maps:
%% --------------------------------------

empty_clock_map() -> dict:new().

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

%% -----------------------------------------------------------------------------

add_some_next_to_backtrack(State) ->
    #dpor_state{trace = [TraceTop|Rest], dpor_flavor = Flavor,
                preemption_bound = PreBound} = State,
    #trace_state{enabled = Enabled, sleep_set = SleepSet,
                 backtrack = OldBacktrack, last = {Lid, _, _},
                 preemptions = Preemptions, nexts = Nexts} = TraceTop,
    ?debug("Pick next: Enabled: ~p Sleeping: ~p\n", [Enabled, SleepSet]),
    Backtrack =
        case OldBacktrack =:= [] of
            true ->
                Set =
                    case Flavor =:= 'none' of
                        true ->
                            case ordsets:is_element(Lid, Enabled) of
                                true when Preemptions =:= PreBound -> [Lid];
                                _Else -> Enabled
                            end;
                        false ->
                            case ordsets:subtract(Enabled, SleepSet) of
                                [] -> [];
                                [H|_] = Candidates ->
                                    case ordsets:is_element(Lid, Candidates) of
                                        true -> [Lid];
                                        false -> [H]
                                    end
                            end
                    end,
                Annotated = [{P, dict:fetch(P, Nexts)} || P <- Set],
                new_backtrack(Annotated);
            false ->
                ?debug("Predefined: ~p\n", [OldBacktrack]),
                [A || {K, _, _} = A <- OldBacktrack,
                      not ordsets:is_element(K, SleepSet)]
        end,
    BoundFlag =
        Flavor =:= 'full' andalso
        PreBound =/= ?INFINITY andalso
        Preemptions > PreBound,
    ?debug("Picked: ~p\n",[Backtrack]),
    NewTraceTop = TraceTop#trace_state{backtrack = Backtrack},
    State#dpor_state{trace = [NewTraceTop|Rest], bound_flag = BoundFlag}.

%% -----------------------------------------------------------------------------

report_error(Transition, State) ->
    #dpor_state{trace = [TraceTop|_] = Trace, tickets = Tickets,
                total_trans = TotalTrans} = State,
    #trace_state{i = Steps} = TraceTop,
    NewTotalTrans = TotalTrans + Steps,
    ?debug("ERROR!\n~P\n",[Transition, ?DEBUG_DEPTH]),
    Error = convert_error_info(Transition),
    LidTrace = convert_trace_to_error_trace(Trace, [Transition]),
    Ticket = create_ticket(Error, LidTrace),
    %% Report the error to the progress logger.
    concuerror_log:progress({'error', Ticket}),
    State#dpor_state{must_replay = true, tickets = [Ticket|Tickets],
                     total_trans = NewTotalTrans}.

report_possible_deadlock(#dpor_state{trace = []} = State) -> State;
report_possible_deadlock(State) ->
    #dpor_state{trace = [TraceTop|_] = Trace, tickets = Tickets,
                sleep_blocked_count = SBlocked, bound_flag = BoundFlag,
                total_trans = TotalTrans, sleep_trans = SleepTrans} = State,
    #trace_state{i = Steps} = TraceTop,
    NewTotalTrans = TotalTrans + Steps,
    {NewTickets, NewSBlocked, NewSleepTrans} =
        case TraceTop#trace_state.enabled of
            [] ->
                case TraceTop#trace_state.blocked of
                    [] ->
                        ?debug("NORMAL!\n"),
                        {Tickets, SBlocked, SleepTrans};
                    Blocked ->
                        ?debug("DEADLOCK!\n"),
                        Error = {deadlock, Blocked},
                        LidTrace = convert_trace_to_error_trace(Trace, []),
                        Ticket = create_ticket(Error, LidTrace),
                        %% Report error
                        concuerror_log:progress({'error', Ticket}),
                        {[Ticket|Tickets], SBlocked, SleepTrans}
                end;
            _Else ->
                case
                    TraceTop#trace_state.sleep_set =/= [] andalso
                    TraceTop#trace_state.done =:= [] andalso
                    not BoundFlag
                of
                    false ->
                        {Tickets, SBlocked, SleepTrans};
                    true ->
                        ?debug("SLEEP SET BLOCK\n"),
                        %% debug_trace(lists:reverse(Trace)),
                        %% exit(sleep_set_block),
                        {Tickets, SBlocked+1, SleepTrans+Steps}
                end
        end,
    State#dpor_state{must_replay = true, tickets = NewTickets,
                     sleep_blocked_count = NewSBlocked,
                     total_trans = NewTotalTrans,
                     sleep_trans = NewSleepTrans}.

%% debug_trace([]) -> ok;
%% debug_trace([Top|Rest]) ->
%%     #trace_state{
%%        i = I,
%%        last = Last,
%%        backtrack = Backtrack,
%%        sleep_set = SleepSet,
%%        done = Done,
%%        nexts = Nexts} = Top,
%%     BT = [K || {K, _, _} <- Backtrack],
%%     Keys = ordsets:union(Done, SleepSet),
%%     Pred = fun(K,_) -> ordsets:is_element(K, Keys) end,
%%     FilteredNexts = dict:filter(Pred, Nexts),
%%     io:format("~p: ~p\nBacktrack:~p\nSleep Set:~p\n"
%%               "FilteredNexts:~p\n~p\n---\n",
%%               [I, Last, BT, ordsets:union(Done,SleepSet),
%%                dict:to_list(FilteredNexts)]),
%%     debug_trace(Rest).

convert_trace_to_error_trace([], Acc) -> Acc;
convert_trace_to_error_trace([#trace_state{
                                 last = {Lid, _, _} = Entry,
                                 last_blocked = Blocked}|Rest], Acc) ->
    NewAcc =
        [Entry|
         case Blocked of
             false -> Acc;
             true -> [{Lid, block, []}|Acc]
         end],
    convert_trace_to_error_trace(Rest, NewAcc).

create_ticket(Error, LidTrace) ->
    InitTr = init_tr(),
    [{P1, init, []} = InitTr|Trace] = LidTrace,
    InitSet = sets:add_element(P1, sets:new()),
    {ErrorState, _Procs} =
        lists:mapfoldl(fun convert_error_trace/2, InitSet, Trace),
    concuerror_ticket:new(Error, ErrorState).

convert_error_trace({Lid, {error, [ErrorOrThrow,Kind|_]}, _Msgs}, Procs)
  when ErrorOrThrow =:= error; ErrorOrThrow =:= throw ->
    Msg =
        concuerror_error:type(concuerror_error:new({Kind, foo})),
    {{exit, Lid, Msg}, Procs};
convert_error_trace({Lid, block, []}, Procs) ->
    {{block, Lid}, Procs};
convert_error_trace({Lid, {Instr, Extra}, _Msgs}, Procs) ->
    NewProcs =
        case Instr of
            Spawn when Spawn =:= spawn; Spawn =:= spawn_link;
                       Spawn =:= spawn_monitor; Spawn =:= spawn_opt ->
                NewLid =
                    case Extra of
                        {Lid0, _MonLid} -> Lid0;
                        Lid0 -> Lid0
                    end,
                sets:add_element(NewLid, Procs);
            exit   -> sets:del_element(Lid, Procs);
            _ -> Procs
        end,
    NewInstr =
        case Instr of
            send ->
                {Orig, Dest, Msg} = Extra,
                NewDest =
                    case is_atom(Orig) of
                        true -> {name, Orig};
                        false -> check_lid_liveness(Dest, NewProcs)
                    end,
                {send, Lid, NewDest, Msg};
            'receive' ->
                {_Tag, Origin, Msg} = Extra,
                {'receive', Lid, Origin, Msg};
            'after' ->
                {'after', Lid};
            is_process_alive ->
                {is_process_alive, Lid, check_lid_liveness(Extra, NewProcs)};
            TwoArg when TwoArg =:= register;
                        TwoArg =:= whereis ->
                {Name, TLid} = Extra,
                {TwoArg, Lid, Name, check_lid_liveness(TLid, NewProcs)};
            process_flag ->
                {trap_exit, Value, _Links} = Extra,
                {process_flag, Lid, trap_exit, Value};
            exit ->
                {exit, Lid, normal};
            exit_2 ->
                {Lid2, Reason} = Extra,
                {exit_2, Lid, Lid2, Reason};
            send_after ->
                {Lid2, Msg} = Extra,
                {send_after, Lid, Lid2, Msg};
            start_timer ->
                {Lid2, Msg} = Extra,
                {start_timer, Lid, Lid2, Msg};
            PortOp when PortOp =:= port_command;
                        PortOp =:= port_control ->
                {PortOp, Lid, Extra};
            Monitor when Monitor =:= monitor;
                         Monitor =:= spawn_monitor ->
                {TLid, _RefLid} = Extra,
                {Monitor, Lid, check_lid_liveness(TLid, NewProcs)};
            ets ->
                case Extra of
                    {insert, [_EtsLid, Tid, _K, _KP, Objects, _Status]} ->
                        {ets_insert, Lid, {Tid, Objects}};
                    {insert_new, [_EtsLid, Tid, _K, _KP, Objects, _Status]} ->
                        {ets_insert_new, Lid, {Tid, Objects}};
                    {delete, [_EtsLid, Tid]} ->
                        {ets_delete, Lid, Tid};
                    {C, [_EtsLid | Options]} ->
                        ListC = atom_to_list(C),
                        AtomC = list_to_atom("ets_" ++ ListC),
                        {AtomC, Lid, list_to_tuple(Options)}
                end;
            _ ->
                {Instr, Lid, Extra}
        end,
    {NewInstr, NewProcs}.


check_lid_liveness(not_found, _Live) ->
    not_found;
check_lid_liveness(Lid, Live) ->
    case sets:is_element(Lid, Live) of
        true -> Lid;
        false -> {dead, Lid}
    end.

convert_error_info({_Lid, {error, [Kind, Type, Stacktrace]}, _Msgs})->
    NewType =
        case Kind of
            error -> Type;
            throw -> {nocatch, Type};
            exit -> Type
        end,
    {Tag, Details} = concuerror_error:new({NewType, foo}),
    Info =
        case Tag of
            exception -> {NewType, Stacktrace};
            assertion_violation -> Details
        end,
    {Tag, Info}.

%% -----------------------------------------------------------------------------

drop_last_frame(#dpor_state{trace = []} = State) -> State;
drop_last_frame(#dpor_state{trace = [_|Trace]} = State) ->
    State#dpor_state{trace = Trace}.

finished(#dpor_state{trace = Trace}) ->
    Trace =:= [].

dpor_return(State) ->
    %% First clean up the last interleaving
    GroupLeader = State#dpor_state.group_leader,
    Output = concuerror_io_server:group_leader_sync(GroupLeader),
    case State#dpor_state.show_output of
        true  -> io:put_chars(Output);
        false -> ok
    end,
    ProcBefore = State#dpor_state.proc_before,
    proc_cleanup(processes() -- ProcBefore),
    %% Return the analysis result
    RunCnt = State#dpor_state.run_count,
    SBlocked = State#dpor_state.sleep_blocked_count,
    Transitions = State#dpor_state.total_trans,
    STransitions = State#dpor_state.sleep_trans,
    Tickets = State#dpor_state.tickets,
    {Tickets, RunCnt, SBlocked, Transitions, STransitions}.

%% =============================================================================
%% ENGINE (manipulation of the Erlang processes under the scheduler)
%% =============================================================================

start_target_op(Target) ->
    concuerror_lid:start(),
    %% Initialize a new group leader
    GroupLeader = concuerror_io_server:new_group_leader(self()),
    {Mod, Fun, Args} = Target,
    NewFun = fun() -> ?REP_MOD:start_target(Mod, Fun, Args) end,
    SpawnFun = fun() -> concuerror_rep:spawn_fun_wrapper(NewFun) end,
    FirstPid = spawn(SpawnFun),
    %% Set our io_server as the group leader
    group_leader(GroupLeader, FirstPid),
    {concuerror_lid:new(FirstPid, noparent), GroupLeader}.

%% -----------------------------------------------------------------------------

replay_trace(#dpor_state{proc_before = ProcBefore,
                         run_count = RunCnt,
                         sleep_blocked_count = SBlocked,
                         group_leader = GroupLeader,
                         target = Target,
			 trace = Trace,
			 show_output = ShowOutput} = State) ->
    NewRunCnt = RunCnt + 1,
    ?debug("\nReplay (~p) is required...\n", [NewRunCnt]),
    concuerror_lid:stop(),
    %% Get buffered output from group leader
    %% TODO: For now just ignore it. Maybe we can print it
    %% only when we have an error (after the backtrace?)
    Output = concuerror_io_server:group_leader_sync(GroupLeader),
    case ShowOutput of
        true  -> io:put_chars(Output);
        false -> ok
    end,
    proc_cleanup(processes() -- ProcBefore),
    concuerror_util:flush_mailbox(),
    {FirstLid, NewGroupLeader} = start_target_op(Target),
    _ = wait_next(FirstLid, init),
    NewTrace = replay_trace_aux(Trace),
    ?debug("Done replaying...\n\n"),
    %% Report the start of a new interleaving
    concuerror_log:progress({'new', NewRunCnt, SBlocked}),
    State#dpor_state{run_count = NewRunCnt, must_replay = false,
                     bound_flag = false,
                     group_leader = NewGroupLeader, trace = NewTrace}.

replay_trace_aux(Trace) ->
    [Init|Rest] = lists:reverse(Trace),
    replay_trace_aux(Rest, [Init]).

replay_trace_aux([], Acc) -> Acc;
replay_trace_aux([TraceState|Rest], Acc) ->
    #trace_state{i = _I, last = {Lid, Cmd, _} = Last} = TraceState,
    %% ?debug(" ~-4w: ~P.",[_I, Last, ?DEBUG_DEPTH]),
    Next = wait_next(Lid, Cmd),
    %% ?debug("."),
    UpdAcc = update_trace(Last, Next, Acc, irrelevant, {true, TraceState}),
    %% [#trace_state{last = _NewLast}|_] = UpdAcc,
    %% ?debug("O:~p\nN:~p\n",[Last, _NewLast]),
    %% ?debug(".\n"),
    replay_trace_aux(Rest, UpdAcc).

%% -----------------------------------------------------------------------------

wait_next(Lid, {exit, {normal, _Info}} = Arg2) ->
    Pid = concuerror_lid:get_pid(Lid),
    Ref = monitor(process, Pid),
    continue(Lid),
    receive
        {'DOWN', Ref, process, Pid, normal} -> {Lid, exited, []}
    after
        ?TIME_LIMIT -> error(time_limit, [Lid, Arg2])
    end;
wait_next(Lid, Plan) ->
    DebugArgs = [Lid, Plan],
    continue(Lid),
    Replace =
        case Plan of
            {Spawn, _Info}
              when Spawn =:= spawn; Spawn =:= spawn_link;
                   Spawn =:= spawn_monitor; Spawn =:= spawn_opt ->
                {true,
                 %% This interruption happens to make sure that a child has an
                 %% LID before the parent wants to do any operation with its PID.
                 receive
                     #sched{msg = Spawn,
                            lid = Lid,
                            misc = Info,
                            type = prev} = Msg ->
                         case Info of
                             {Pid, Ref} ->
                                 monitor(process, Pid),
                                 ChildLid = concuerror_lid:new(Pid, Lid),
                                 continue(ChildLid),
                                 MonRef = concuerror_lid:ref_new(ChildLid, Ref),
                                 Msg#sched{misc = {ChildLid, MonRef}};
                             Pid ->
                                 monitor(process, Pid),
                                 ChildLid = concuerror_lid:new(Pid, Lid),
                                 continue(ChildLid),
                                 Msg#sched{misc = ChildLid}
                         end
                 after
                     ?TIME_LIMIT -> error(time_limit, DebugArgs)
                 end};
            {ets, {new, _Info}} ->
                {true,
                 receive
                     #sched{msg = ets, lid = Lid, misc = {new, [Tid|Rest]},
                            type = prev} = Msg ->
                         NewMisc = {new, [concuerror_lid:ets_new(Tid)|Rest]},
                         Msg#sched{misc = NewMisc}
                 after
                     ?TIME_LIMIT -> error(time_limit, DebugArgs)
                 end};
            {monitor, _Info} ->
                {true,
                 receive
                     #sched{msg = monitor, lid = Lid, misc = {TLid, Ref},
                            type = prev} = Msg ->
                         NewMisc = {TLid, concuerror_lid:ref_new(TLid, Ref)},
                         Msg#sched{misc = NewMisc}
                 after
                     ?TIME_LIMIT -> error(time_limit, DebugArgs)
                 end};
            _Other ->
                false
        end,
    case Replace of
        {true, NewMsg} ->
            continue(Lid),
            self() ! NewMsg,
            get_next(Lid);
        false ->
            get_next(Lid)
    end.

get_next(Lid) ->
    receive
        #sched{msg = Type, lid = Lid, misc = Misc, type = next} ->
            {Lid, {Type, Misc}, []}
    after
        ?TIME_LIMIT -> error(time_limit, [Lid])
    end.

%% =============================================================================
%% INSTRUCTIONS (logic and engine for Erlang instructions)
%% =============================================================================

handle_instruction_op({Lid, {Spawn, _Info}, Msgs} = DebugArg)
  when Spawn =:= spawn; Spawn =:= spawn_link; Spawn =:= spawn_monitor;
       Spawn =:= spawn_opt ->
    ParentLid = Lid,
    Info =
        receive
            %% This is the replaced message
            #sched{msg = Spawn, lid = ParentLid,
                   misc = Info0, type = prev} ->
                Info0
        after
            ?TIME_LIMIT -> error(time_limit, [DebugArg])
        end,
    ChildLid =
        case Info of
            {Lid0, _MonLid} -> Lid0;
            Lid0 -> Lid0
        end,
    ChildNextInstr = get_next(ChildLid),
    {{Lid, {Spawn, Info}, Msgs}, ChildNextInstr};
handle_instruction_op({Lid, {ets, {Updatable, _Info}}, Msgs} = DebugArg)
  when Updatable =:= new; Updatable =:= insert_new; Updatable =:= insert ->
    receive
        %% This is the replaced message
        #sched{msg = ets, lid = Lid, misc = {Updatable, Info}, type = prev} ->
            {{Lid, {ets, {Updatable, Info}}, Msgs}, {}}
    after
        ?TIME_LIMIT -> error(time_limit, [DebugArg])
    end;
handle_instruction_op({Lid, {'receive', Tag}, Msgs} = DebugArg) ->
    NewTag =
        case Tag of
            {T, _, _} -> T;
            T -> T
        end,
    receive
        #sched{msg = 'receive', lid = Lid,
               misc = {From, CV, Msg}, type = prev} ->
            {{Lid, {'receive', {NewTag, From, Msg}}, Msgs}, CV}
    after
        ?TIME_LIMIT -> error(time_limit, [DebugArg])
    end;
handle_instruction_op({Lid, {'after', {Fun, _, _}}, Msgs} = DebugArg) ->
    receive
        #sched{msg = 'after', lid = Lid,
               misc = {Links, Monitors}, type = prev} ->
            {{Lid, {'after', {Fun, Links, Monitors}}, Msgs}, {}}
    after
        ?TIME_LIMIT -> error(time_limit, [DebugArg])
    end;
handle_instruction_op({Lid, {Updatable, _Info}, Msgs} = DebugArg)
  when Updatable =:= exit; Updatable =:= send; Updatable =:= whereis;
       Updatable =:= monitor; Updatable =:= process_flag ->
    receive
        #sched{msg = Updatable, lid = Lid, misc = Info, type = prev} ->
            {{Lid, {Updatable, Info}, Msgs}, {}}
    after
        ?TIME_LIMIT -> error(time_limit, [DebugArg])
    end;
handle_instruction_op(Instr) ->
    {Instr, {}}.

handle_instruction_al({Lid, {exit, _Info}, _Msgs} = Trans, TraceTop, {}) ->
    #trace_state{enabled = Enabled, nexts = Nexts} = TraceTop,
    NewEnabled = ordsets:del_element(Lid, Enabled),
    NewNexts = dict:erase(Lid, Nexts),
    TraceTop#trace_state{enabled = NewEnabled, nexts = NewNexts, last = Trans};
handle_instruction_al({Lid, {Spawn, Info}, _Msgs} = Trans,
                      TraceTop, ChildNextInstr)
  when Spawn =:= spawn; Spawn =:= spawn_link; Spawn =:= spawn_monitor;
       Spawn =:= spawn_opt ->
    ChildLid =
        case Info of
            {Lid0, _MonLid} -> Lid0;
            Lid0 -> Lid0
        end,
    #trace_state{enabled = Enabled, blocked = Blocked,
                 nexts = Nexts, pollable = Pollable,
                 clock_map = ClockMap} = TraceTop,
    NewNexts = dict:store(ChildLid, ChildNextInstr, Nexts),
    ClockVector = lookup_clock(Lid, ClockMap),
    NewClockMap = dict:store(ChildLid, ClockVector, ClockMap),
    MaybeEnabled = ordsets:add_element(ChildLid, Enabled),
    {NewPollable, NewEnabled, NewBlocked} =
        update_lid_enabled(ChildLid, ChildNextInstr, Pollable,
                           MaybeEnabled, Blocked),
    TraceTop#trace_state{last = Trans,
                         clock_map = NewClockMap,
                         enabled = NewEnabled,
                         blocked = NewBlocked,
                         pollable = NewPollable,
                         nexts = NewNexts};
handle_instruction_al({Lid, {'receive', _Info}, _Msgs} = Trans,
                      TraceTop, CV) ->
    #trace_state{clock_map = ClockMap} = TraceTop,
    Vector = lookup_clock(Lid, ClockMap),
    NewVector = max_cv(Vector, CV),
    NewClockMap = dict:store(Lid, NewVector, ClockMap),
    TraceTop#trace_state{last = Trans, clock_map = NewClockMap,
                         receives_vector = CV};
handle_instruction_al({_Lid, {ets, {Updatable, _Info}}, _Msgs} = Trans,
                      TraceTop, {})
  when Updatable =:= new; Updatable =:= insert_new; Updatable =:= insert ->
    TraceTop#trace_state{last = Trans};
handle_instruction_al({_Lid, {Updatable, _Info}, _Msgs} = Trans, TraceTop, {})
  when Updatable =:= send; Updatable =:= whereis; Updatable =:= monitor;
       Updatable =:= process_flag; Updatable =:= 'after' ->
    TraceTop#trace_state{last = Trans};
handle_instruction_al({_Lid, {register, {Name, PLid}}, _Msgs},
                      #trace_state{nexts = Nexts} = TraceTop, {}) ->
    TraceTop#trace_state{nexts = update_named_sends(Name, PLid, Nexts)};
handle_instruction_al({_Lid, {halt, _Status}, _Msgs}, TraceTop, {}) ->
    TraceTop#trace_state{enabled = [], blocked = []};
handle_instruction_al(_Transition, TraceTop, {}) ->
    TraceTop.

update_named_sends(Name, PLid, Nexts) ->
    Map =
        fun(Lid, Instr) ->
                case Instr of
                    {Lid, {send, {Name, _OldPLid, Msg}}, Msgs} ->
                        {Lid, {send, {Name, PLid, Msg}}, Msgs};
                    _Other -> Instr
                end
        end,
    dict:map(Map, Nexts).

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

%% Kill any remaining processes.
%% If the run was terminated by an exception, processes linked to
%% the one where the exception occurred could have been killed by the
%% exit signal of the latter without having been deleted from the pid/lid
%% tables. Thus, 'EXIT' messages with any reason are accepted.
proc_cleanup(ProcList) ->
    Link_and_kill = fun(P) -> link(P), exit(P, kill) end,
    lists:foreach(Link_and_kill, ProcList),
    wait_for_exit(ProcList).

wait_for_exit([]) -> ok;
wait_for_exit([P|Rest]) ->
    receive {'EXIT', P, _Reason} -> wait_for_exit(Rest) end.

%%%----------------------------------------------------------------------
%%% Instrumentation interface
%%%----------------------------------------------------------------------

%% Prompt process Pid to continue running.
continue(LidOrPid) ->
    send_message(LidOrPid, continue).

poll(Lid) ->
    send_message(Lid, poll),
    {Lid, Res, []} = get_next(Lid),
    Res.

send_message(Pid, Message) when is_pid(Pid) ->
    Pid ! #sched{msg = Message},
    ok;
send_message(Lid, Message) ->
    Pid = concuerror_lid:get_pid(Lid),
    send_message(Pid, Message).

%% Notify the scheduler of an event.
%% If the calling user process has an associated LID, then send
%% a notification and yield. Otherwise, for an unknown process
%% running instrumented code completely ignore this call.
-spec notify(notification(), any()) -> 'ok' | 'poll' | 'ignore'.

notify(Msg, Misc) ->
    notify(Msg, Misc, next).

-spec notify(notification(), any(), sched_msg_type()) ->
                    'ok' | 'poll' | 'ignore'.

notify(Msg, Misc, Type) ->
    case lid_from_pid(self()) of
        not_found -> ok;
        Lid ->
            Rec = #sched{msg = Msg, lid = Lid, misc = Misc, type = Type},
            ?RP_SCHED_SEND ! Rec,
            case Type of
                next  -> wait();
                _Else -> ignore
            end
    end.

-spec lid_from_pid(pid()) -> concuerror_lid:lid() | 'not_found'.

lid_from_pid(Pid) ->
    concuerror_lid:from_pid(Pid).

-define(VECTOR_MSG(LID, VC),
        #sched{msg = vector, lid = LID, misc = VC, type = async}).

%% Wait until the scheduler prompts to continue.
-spec wait() -> 'ok' | 'poll'.

wait() ->
    receive
        #sched{msg = continue} -> ok;
        #sched{msg = poll} -> poll;
        ?VECTOR_MSG(Lid, VC) ->
            Msgs = instrument_my_messages(Lid, VC),
            ignore = notify(vector, Msgs, async),
            wait()
    end.

replace_messages(Lid, VC) ->
    Fun =
        fun(Pid, MsgAcc) ->
            Pid ! ?VECTOR_MSG(Lid, VC),
            receive
                ?VECTOR_MSG(PidsLid, {Msgs, _, _} = MsgInfo) ->
                    case Msgs =:= [] of
                        true -> MsgAcc;
                        false -> [{PidsLid, MsgInfo}|MsgAcc]
                    end
            after
                ?TIME_LIMIT -> error(time_limit, [Pid, MsgAcc])
            end
        end,
    concuerror_lid:fold_pids(Fun, []).

-define(IS_INSTR_MSG(Msg),
        (is_tuple(Msg) andalso
         size(Msg) =:= 4 andalso
         element(1, Msg) =:= ?INSTR_MSG)).

instrument_my_messages(Lid, VC) ->
    Self = self(),
    Fun =
        fun(Acc) ->
                receive
                    Msg when not ?IS_INSTR_MSG(Msg) ->
                        Instr = {?INSTR_MSG, Lid, VC, Msg},
                        Self ! Instr,
                        {cont, [Msg|Acc]}
                after
                    0 ->
                        {trap_exit, Trapping} = erlang:process_info(self(), trap_exit),
                        Links =
                            case Acc =:= [] orelse not Trapping of
                                true -> [];
                                false -> concuerror_rep:find_my_links()
                            end,
                        Monitors =
                            case Acc =:= [] of
                                true -> [];
                                false -> concuerror_rep:find_my_monitors()
                            end,
                        {done, {Acc, Links, Monitors}}
                end
        end,
    dynamic_loop_acc(Fun, []).

dynamic_loop_acc(Fun, Arg) ->
    case Fun(Arg) of
        {done, Ret} -> Ret;
        {cont, NewArg} -> dynamic_loop_acc(Fun, NewArg)
    end.
