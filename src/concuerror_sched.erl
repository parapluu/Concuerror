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
-export([block/0, notify/2, wait/0, wakeup/0, no_wakeup/0, lid_from_pid/1]).

-export([notify/3, wait_poll_or_continue/0]).

-export_type([analysis_target/0, analysis_ret/0, bound/0, transition/0]).

%%-define(DEBUG, true).
-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

-define(INFINITY, infinity).
-define(NO_ERROR, undef).

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

%% Special internal message format (fields same as above).
-record(special, {msg :: atom(),
                  lid :: concuerror_lid:lid() | 'not_found',
                  misc = empty :: term()}).

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
                        'is_process_alive' | 'link' | 'monitor' |
                        'process_flag' | 'receive' | 'receive_no_instr' |
                        'register' | 'send' | 'spawn' | 'spawn_link' |
                        'spawn_monitor' | 'spawn_opt' | 'unlink' |
                        'unregister' | 'whereis'.

%%%----------------------------------------------------------------------
%%% User interface
%%%----------------------------------------------------------------------

%% @spec: analyze(analysis_target(), [file:filename()], concuerror:options()) ->
%%          analysis_ret()
%% @doc: Produce all interleavings of running `Target'.
-spec analyze(analysis_target(), [file:filename()], concuerror:options()) ->
            analysis_ret().

analyze({Mod,Fun,Args}=_Target, Files, Options) ->
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
    %% Rename Target's module
    NewMod = concuerror_instr:new_module_name(Mod),
    Target = {NewMod, Fun, Args},
    Ret =
        case concuerror_instr:instrument_and_compile(Files, Options) of
            {ok, Bin} ->
                %% Note: No error checking for load
                ok = concuerror_instr:load(Bin),
                concuerror_log:log(0, "\nRunning analysis with preemption "
                    "bound ~p..\n", [PreBound]),
                %% Reset the internal state for the progress logger
                concuerror_log:reset(),
                {T1, _} = statistics(wall_clock),
                Result = interleave(Target, PreBound, Dpor),
                {T2, _} = statistics(wall_clock),
                {Mins, Secs} = concuerror_util:to_elapsed_time(T1, T2),
                ?debug("Done in ~wm~.2fs\n", [Mins, Secs]),
                %% Print analysis summary
                RunCount = element(2, Result),
                SBlocked = element(3, Result),
                StrB =
                    case SBlocked of
                        0 -> " ";
                        _ -> io_lib:format(
                                " (encountered ~w sleep-set blocked traces) ",
                                [SBlocked])
                    end,
                concuerror_log:log(0, "\n\nAnalysis complete. Checked "
                    "~w interleaving(s)~sin ~wm~.2fs:\n",
                    [RunCount, StrB, Mins, Secs]),
                case Result of
                    {ok, _, _} ->
                        concuerror_log:log(0, "No errors found.~n"),
                        {ok, {Target, RunCount, SBlocked}};
                    {error, _, _, Tickets} ->
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
interleave(Target, PreBound, Dpor) ->
    Self = self(),
    spawn_link(fun() -> interleave_aux(Target, PreBound, Self, Dpor) end),
    receive
        {interleave_result, Result} -> Result
    end.

interleave_aux(Target, PreBound, Parent, Dpor) ->
    ?debug("Dpor is not really ready yet...\n"),
    register(?RP_SCHED, self()),
    Result = interleave_dpor(Target, PreBound, Dpor),
    unregister(?RP_SCHED),
    Parent ! {interleave_result, Result}.

-type s_i()        :: non_neg_integer().
-type instr()      :: term().
-type transition() :: {concuerror_lid:lid(), instr(), list()}.
-type clock_map()  :: dict(). %% dict(concuerror_lid:lid(), clock_vector()).
%% -type clock_vector() :: orddict(). %% dict(concuerror_lid:lid(), s_i()).

select_one_shallow_except_with_fix(DeepList, Exceptions) ->
    select_one_shallow_except_with_fix(DeepList, Exceptions, []).

select_one_shallow_except_with_fix([[DH|_]|T]     ,      _, Acc) ->
    {ok, DH, lists:reverse(Acc, [DH|T])};
select_one_shallow_except_with_fix([     H|_] = DL,     [], Acc) ->
    {ok,  H, lists:reverse(Acc, DL)};
select_one_shallow_except_with_fix([     H|T]     , [H|XT], Acc) ->
    select_one_shallow_except_with_fix(T, XT, [H|Acc]);
select_one_shallow_except_with_fix([     H|_] = DL, [X|XT], Acc) ->
    case H < X of
        true  -> {ok, H, lists:reverse(Acc, DL)};
        false -> select_one_shallow_except_with_fix(DL, XT, Acc)
    end;
select_one_shallow_except_with_fix(        []     ,      _,   _) ->
    none.


deep_intersect_with_fix(DeepList, List) ->
    ?debug("DIWF: DL: ~w L: ~w\n", [DeepList, List]),
    R = deep_intersect_with_fix(DeepList, List, []),
    ?debug("  R: ~w\n", [R]),
    R.

deep_intersect_with_fix([H|T] = DL, L, Acc) ->
    case is_list(H) of
        false ->
            case ordsets:is_element(H, L) of
                true  -> {true, lists:reverse(Acc, DL)};
                false -> deep_intersect_with_fix(T, L, [H|Acc])
            end;
        true ->
            case ordsets:intersection(H, L) of
                [] -> deep_intersect_with_fix(T, L,  [H|Acc]);
                Else ->
                    {true, lists:reverse(Acc, insert_to_deep_list(T, Else))}
            end
    end;
deep_intersect_with_fix([], _, _) -> false.


insert_to_deep_list(DeepList, List) ->
    ?debug("ITDL: DL: ~w L: ~w\n", [DeepList, List]),
    insert_to_deep_list(DeepList, List, []).

insert_to_deep_list([DLH|T], [NH|NT] = N, Acc) ->
    {DH, H} =
        case DLH of
            [HDLH|_] -> {HDLH, DLH};
            Else     -> {Else, Else}
        end,
    case NH < DH of
        true  ->
            NE =
                case NT =/= [] of
                    true -> N;
                    false -> NH
                end,
            lists:reverse(Acc, [NE, H|T]);
        false -> insert_to_deep_list(T, N, [H|Acc])
    end;
insert_to_deep_list([], [NH|NT] = N, Acc) ->
    NE =
        case NT =/= [] of
            true -> N;
            false -> NH
        end,
    lists:reverse([NE|Acc]).


-record(trace_state, {
          i         = 0                 :: s_i(),
          last      = init_tr()         :: transition(),
          enabled   = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          blocked   = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          pollable  = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          backtrack = ordsets:new()     :: [concuerror_lid:lid() |
                                            ordsets:ordset(
                                              concuerror_lid:lid())],
          done      = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          sleep_set = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          nexts     = dict:new()        :: dict(), %% dict(concuerror_lid:lid(), instr()),
          error_nxt = none              :: concuerror_lid:lid() | 'none',
          clock_map = empty_clock_map() :: clock_map(),
          preemptions = 0               :: non_neg_integer(),
          lid_trace = new_lid_trace()   :: queue() %% queue({transition(),
                                                   %%        clock_vector()})
         }).

init_tr() ->
	{concuerror_lid:root_lid(), init, []}.

empty_clock_map() -> dict:new().

new_lid_trace() ->
    queue:in({init_tr(), empty_clock_vector()}, queue:new()).

empty_clock_vector() -> orddict:new().

-type trace_state() :: #trace_state{}.

-record(dpor_state, {
          target                  :: analysis_target(),
          run_count    = 1        :: pos_integer(),
          sleep_blocked_count = 0 :: non_neg_integer(),
          tickets      = []       :: [concuerror_ticket:ticket()],
          trace        = []       :: [trace_state()],
          must_replay  = false    :: boolean(),
          proc_before  = []       :: [pid()],
          dpor_flavor  = 'none'   :: 'full' | 'flanagan' | 'none',
          preemption_bound = inf  :: non_neg_integer() | 'inf',
          group_leader            :: pid()
         }).

interleave_dpor(Target, PreBound, Dpor) ->
    ?debug("Interleave dpor!\n"),
    Procs = processes(),
    %% To be able to clean up we need to be trapping exits...
    process_flag(trap_exit, true),
    {Trace, GroupLeader} = start_target(Target),
    ?debug("Target started!\n"),
    NewState = #dpor_state{trace = Trace, target = Target, proc_before = Procs,
                           dpor_flavor = Dpor, preemption_bound = PreBound,
                           group_leader = GroupLeader},
    explore(NewState).

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
                     enabled = Enabled, blocked = Blocked, backtrack = Enabled,
                     pollable = Pollable},
    {[TraceTop], GroupLeader}.

start_target_op(Target) ->
    concuerror_lid:start(),
    %% Initialize a new group leader
    GroupLeader = concuerror_io_server:new_group_leader(self()),
    {Mod, Fun, Args} = Target,
    NewFun = fun() -> apply(Mod, Fun, Args) end,
    SpawnFun = fun() -> concuerror_rep:spawn_fun_wrapper(NewFun) end,
    FirstPid = spawn(SpawnFun),
    %% Set our io_server as the group leader
    group_leader(GroupLeader, FirstPid),
    {concuerror_lid:new(FirstPid, noparent), GroupLeader}.

explore(MightNeedReplayState) ->
    receive
        stop_analysis -> dpor_return(MightNeedReplayState)
    after 0 ->
        case select_from_backtrack(MightNeedReplayState) of
            {ok, {Lid, Cmd, _} = Selected, State} ->
                case Cmd of
                    {error, _ErrorInfo} ->
                        NewState = report_error(Selected, State),
                        explore(NewState);
                    _Else ->
                        Next = wait_next(Lid, Cmd),
                        UpdState = update_trace(Selected, Next, State),
                        AllAddState = add_all_backtracks(UpdState),
                        NewState = add_some_next_to_backtrack(AllAddState),
                        explore(NewState)
                end;
            none ->
                NewState = report_possible_deadlock(MightNeedReplayState),
                case finished(NewState) of
                    false -> explore(NewState);
                    true -> dpor_return(NewState)
                end
        end
    end.

select_from_backtrack(#dpor_state{trace = Trace} = MightNeedReplayState) ->
    %% FIXME: Pick first and don't really subtract.
    %% FIXME: This is actually the trace bottom...
    [TraceTop|RestTrace] = Trace,
    Backtrack = TraceTop#trace_state.backtrack,
    Done = TraceTop#trace_state.done,
    ?debug("------------\nExplore ~p\n------------\n",
             [TraceTop#trace_state.i + 1]),
    case select_one_shallow_except_with_fix(Backtrack, Done) of
        none ->
            ?debug("Backtrack set explored\n",[]),
            none;
        {ok, SelectedLid, NewBacktrack} ->
            State =
                case MightNeedReplayState#dpor_state.must_replay of
                    true -> replay_trace(MightNeedReplayState);
                    false -> MightNeedReplayState
                end,
            [NewTraceTop|RestTrace] = State#dpor_state.trace,
            Instruction = dict:fetch(SelectedLid, NewTraceTop#trace_state.nexts),
            NewDone = ordsets:add_element(SelectedLid, Done),
            FinalTraceTop =
                NewTraceTop#trace_state{backtrack = NewBacktrack,
                                        done = NewDone},
            FinalState = State#dpor_state{trace = [FinalTraceTop|RestTrace]},
            {ok, Instruction, FinalState}
    end.

replay_trace(#dpor_state{proc_before = ProcBefore,
                         run_count = RunCnt,
                         sleep_blocked_count = SBlocked,
                         group_leader = GroupLeader,
                         target = Target} = State) ->
    NewRunCnt = RunCnt + 1,
    ?debug("\nReplay (~p) is required...\n", [NewRunCnt]),
    [TraceTop|TraceRest] = State#dpor_state.trace,
    LidTrace = TraceTop#trace_state.lid_trace,
    concuerror_lid:stop(),
    %% Get buffered output from group leader
    %% TODO: For now just ignore it. Maybe we can print it
    %% only when we have an error (after the backtrace?)
    _Output = concuerror_io_server:group_leader_sync(GroupLeader),
    proc_cleanup(processes() -- ProcBefore),
    {_FirstLid, NewGroupLeader} = start_target_op(Target),
    NewLidTrace = replay_lid_trace(LidTrace),
    ?debug("Done replaying...\n\n"),
    %% Report the start of a new interleaving
    concuerror_log:progress({'new', NewRunCnt, SBlocked}),
    NewTrace = [TraceTop#trace_state{lid_trace = NewLidTrace}|TraceRest],
    State#dpor_state{run_count = NewRunCnt, must_replay = false,
                     group_leader = NewGroupLeader, trace = NewTrace}.

replay_lid_trace(Queue) ->
    replay_lid_trace(0, Queue, queue:new()).

replay_lid_trace(N, Queue, Acc) ->
    {V, NewQueue} = queue:out(Queue),
    case V of
        {value, {{_Lid,  block, _},  _VC} = Entry} ->
            replay_lid_trace(N, NewQueue, queue:in(Entry, Acc));
        {value, {{Lid, Command, _} = Transition, VC}} ->
            %% ?debug(" ~-4w: ~P",[N, Transition, ?DEBUG_DEPTH]),
            _ = wait_next(Lid, Command),
            %% ?debug("."),
            {NewTransition, _} = handle_instruction_op(Transition),
            %% ?debug("."),
            _ = replace_messages(Lid, VC),
            %% ?debug("\n"),
            replay_lid_trace(N+1, NewQueue, queue:in({NewTransition, VC}, Acc));
        empty ->
            Acc
    end.

wait_next(Lid, {exit, {normal, _Info}}) ->
    Pid = concuerror_lid:get_pid(Lid),
    link(Pid),
    continue(Lid),
    receive
        {'EXIT', Pid, normal} -> {Lid, exited, []}
    end;
wait_next(Lid, Plan) ->
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
                                 ChildLid = concuerror_lid:new(Pid, Lid),
                                 MonRef = concuerror_lid:ref_new(ChildLid, Ref),
                                 Msg#sched{misc = {ChildLid, MonRef}};
                             Pid ->
                                 Msg#sched{misc = concuerror_lid:new(Pid, Lid)}
                         end
                 end};
            {ets, {new, _Info}} ->
                {true,
                 receive
                     #sched{msg = ets, lid = Lid, misc = {new, [Tid|Rest]},
                            type = prev} = Msg ->
                         NewMisc = {new, [concuerror_lid:ets_new(Tid)|Rest]},
                         Msg#sched{misc = NewMisc}
                 end};
            {monitor, _Info} ->
                {true,
                 receive
                     #sched{msg = monitor, lid = Lid, misc = {TLid, Ref},
                            type = prev} = Msg ->
                         NewMisc = {TLid, concuerror_lid:ref_new(TLid, Ref)},
                         Msg#sched{misc = NewMisc}
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
    end.

add_all_backtracks(#dpor_state{preemption_bound = PreBound,
                               trace = Trace} = State) ->
    case State#dpor_state.dpor_flavor of
        none ->
            %% add_some_next will take care of all the backtracks.
            State;
        Flavor ->
            [#trace_state{last = Transition}|_] = Trace,
            case concuerror_deps:may_have_dependencies(Transition) of
                true ->
                    NewTrace =
                        add_all_backtracks_trace(Transition, Trace,
                                                 PreBound, Flavor),
                    State#dpor_state{trace = NewTrace};
                false -> State
            end
    end.

add_all_backtracks_trace({Lid, _, _} = Transition, Trace, PreBound, Flavor) ->
    [#trace_state{i = I} = Top|
     [#trace_state{clock_map = ClockMap}|_] = PTrace] = Trace,
    ClockVector = orddict:store(Lid, I, lookup_clock(Lid, ClockMap)),
    add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound,
                             Flavor, PTrace, [Top]).

add_all_backtracks_trace(_Transition, _Lid, _ClockVector, _PreBound,
                         _Flavor, [_] = Init, Acc) ->
    lists:reverse(Acc, Init);
add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound, Flavor,
                         [#trace_state{preemptions = Preempt} = StateI|Trace],
                         Acc)
  when Preempt + 1 > PreBound, PreBound =/= ?INFINITY ->
    add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound, Flavor,
                             Trace, [StateI|Acc]);
add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound, Flavor,
                         [StateI|Trace], Acc) ->
    #trace_state{i = I,
                 last = {ProcSI, _, _} = SI,
                 clock_map = ClockMap} = StateI,
    Clock = lookup_clock_value(ProcSI, ClockVector),
    Action =
        case I > Clock andalso concuerror_deps:dependent(Transition, SI) of
            false -> {continue, Lid, ClockVector};
            true ->
                ?debug("~4w: ~p ~P Clock ~p\n",
                         [I, concuerror_deps:dependent(Transition, SI), SI,
                          ?DEBUG_DEPTH, Clock]),
                [#trace_state{enabled = Enabled,
                              backtrack = Backtrack,
                              nexts = Nexts,
                              sleep_set = SleepSet} =
                     PreSI|Rest] = Trace,
                Candidates = ordsets:subtract(Enabled, SleepSet),
                Predecessors = predecessors(Candidates, I, ClockVector),
                case Flavor of
                    full ->
                        All = find_all_not_racing(SI, Enabled, Nexts),
                        Possible = find_could_have_run(All, [PreSI,StateI|Acc]),
                        Initial =
                            case ordsets:is_element(Lid, Predecessors) of
                                true  -> ordsets:add_element(Lid, Possible);
                                false -> Possible
                            end,
                        ?debug("  Backtrack: ~w\n", [Backtrack]),
                        ?debug("  Predecess: ~w\n", [Predecessors]),
                        ?debug("  SleepSet : ~w\n", [SleepSet]),
                        ?debug("  Initial  : ~w\n", [Initial]),
                        case deep_intersect_with_fix(Backtrack, Initial) of
                            {true, NewBacktrack} ->
                                ?debug("One initial already in backtrack.\n"),
                                {done,
                                 [PreSI#trace_state{
                                    backtrack = NewBacktrack
                                   }|Rest]};
                            false ->
                                case ordsets:is_element(Lid, SleepSet)
                                    orelse Predecessors =:= [] of
                                    false ->
                                        NewBacktrack =
                                            insert_to_deep_list(Backtrack,
                                                                Predecessors),
                                        ?debug("     Add: ~w (~w)\n",
                                                 [Predecessors, NewBacktrack]),
                                        NewPreSI =
                                            PreSI#trace_state{
                                              backtrack = NewBacktrack},
                                        {done, [NewPreSI|Rest]};
                                    true ->
                                        ?debug("     All sleeping...\n"),
                                        NewClockVector =
                                            lookup_clock(ProcSI, ClockMap),
                                        MaxClockVector =
                                            max_cv(NewClockVector, ClockVector),
                                        {continue, ProcSI, MaxClockVector}
                                end
                        end;
                    flanagan ->
                        case deep_intersect_with_fix(Backtrack, Predecessors) of
                            {true, NewBacktrack} ->
                                ?debug("One pred already in backtrack.\n"),
                                {done,
                                 [PreSI#trace_state{
                                    backtrack = NewBacktrack
                                   }|Rest]};
                            false ->
                                NewBacktrack =
                                    case Predecessors of
                                        [P|_] ->
                                            ?debug(" Add: ~w\n", [P]),
                                            ordsets:add_element(P, Backtrack);
                                        [] ->
                                            ?debug(" Add: ~w\n",
                                                     [Candidates]),
                                            ordsets:union(Candidates, Backtrack)
                                    end,
                                NewPreSI =
                                    PreSI#trace_state{backtrack = NewBacktrack},
                                {done, [NewPreSI|Rest]}
                        end
                end
        end,
    case Action of
        {continue, NewLid, UpdClockVector} ->
            add_all_backtracks_trace(Transition, NewLid, UpdClockVector, PreBound,
                                     Flavor, Trace, [StateI|Acc]);
        {done, FinalTrace} ->
            lists:reverse(Acc, [StateI|FinalTrace])
    end.

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

find_all_not_racing(Transition, Ps, Nexts) ->
    Filter =
        fun(P) ->
                Next = dict:fetch(P, Nexts),
                not concuerror_deps:dependent(Transition, Next)
        end,
    lists:filter(Filter, Ps).

find_could_have_run(Ps, Trace) ->
    find_could_have_run(Ps, Trace, ordsets:new()).

find_could_have_run([],     _, Acc) -> Acc;
find_could_have_run( _, [_,_], Acc) -> Acc;
find_could_have_run(Ps, [TraceTop|Rest], Acc) -> 
    #trace_state{last = {P,_,_}, done = Done, sleep_set = SleepSet} = TraceTop,
    NotAllowed = ordsets:union(SleepSet, Done),
    Could1 = ordsets:subtract(Ps, NotAllowed),
    Could =
        case ordsets:is_element(P, Ps) of
            true  -> ordsets:add_element(P, Could1);
            false -> Could1
        end,
    find_could_have_run(ordsets:subtract(Ps, Could),
                        Rest, ordsets:union(Could, Acc)).

predecessors(Candidates, I, ClockVector) ->
    Fold =
        fun(Lid, Acc) ->
                Clock = lookup_clock_value(Lid, ClockVector),
                ?debug("  ~p: ~p\n",[Lid, Clock]),
                case Clock > I of
                    false -> Acc;
                    true -> ordsets:add_element({Clock, Lid}, Acc)
                end
        end,
    [P || {_C, P} <- lists:foldl(Fold, ordsets:new(), Candidates)].

%% - add new entry with new entry
%% - wait any possible additional messages
%% - check for async
update_trace({Lid, _, _} = Selected, Next, State) ->
    #dpor_state{trace = [PrevTraceTop|Rest],
                dpor_flavor = Flavor} = State,
    #trace_state{i = I, enabled = Enabled, blocked = Blocked,
                 pollable = Pollable, done = Done,
                 nexts = Nexts, lid_trace = LidTrace,
                 clock_map = ClockMap, sleep_set = SleepSet,
                 preemptions = Preemptions, last = {LLid,_,_}} = PrevTraceTop,
    NewN = I+1,
    ClockVector = lookup_clock(Lid, ClockMap),
    ?debug("Happened before: ~p\n", [orddict:to_list(ClockVector)]),
    BaseClockVector = orddict:store(Lid, NewN, ClockVector),
    LidsClockVector = recent_dependency_cv(Selected, BaseClockVector, LidTrace),
    NewClockMap = dict:store(Lid, LidsClockVector, ClockMap),
    NewNexts = dict:store(Lid, Next, Nexts),
    MaybeNotPollable = ordsets:del_element(Lid, Pollable),
    {NewPollable, NewEnabled, NewBlocked} =
        update_lid_enabled(Lid, Next, MaybeNotPollable, Enabled, Blocked),
    ErrorNext =
        case Next of
            {_, {error, _}, _} -> Lid;
            _Else -> none
        end,
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
    CommonNewTraceTop =
        #trace_state{i = NewN, last = Selected, nexts = NewNexts,
                     enabled = NewEnabled, blocked = NewBlocked,
                     clock_map = NewClockMap, sleep_set = NewSleepSetCandidates,
                     pollable = NewPollable, error_nxt = ErrorNext,
                     preemptions = NewPreemptions},
    InstrNewTraceTop = handle_instruction(Selected, CommonNewTraceTop),
    UpdatedClockVector =
        lookup_clock(Lid, InstrNewTraceTop#trace_state.clock_map),
    {Lid, RewrittenInstr, _Msgs} = InstrNewTraceTop#trace_state.last,
    Messages = orddict:from_list(replace_messages(Lid, UpdatedClockVector)),
    PossiblyRewrittenSelected = {Lid, RewrittenInstr, Messages},
    ?debug("Selected: ~P\n",[PossiblyRewrittenSelected, ?DEBUG_DEPTH]),
    NewBaseLidTrace =
        queue:in({PossiblyRewrittenSelected, UpdatedClockVector}, LidTrace),
    NewLidTrace =
        case ordsets:is_element(Lid, NewBlocked) of
            false -> NewBaseLidTrace;
            true ->
                ?debug("Blocking ~p\n",[Lid]),
                queue:in({{Lid, block, []}, UpdatedClockVector}, NewBaseLidTrace)
        end,
    NewTraceTop = check_pollable(InstrNewTraceTop),
    NewSleepSet =
        case Flavor of
            'none' -> [];
            _Other ->
                AfterPollingSleepSet = NewTraceTop#trace_state.sleep_set,
                AfterPollingNexts = NewTraceTop#trace_state.nexts,
                filter_awaked(AfterPollingSleepSet,
                              AfterPollingNexts,
                              PossiblyRewrittenSelected)
        end,
    PrevTrace =
        case PossiblyRewrittenSelected =:= Selected of
            true -> [PrevTraceTop|Rest];
            false -> rewrite_while_awaked(PossiblyRewrittenSelected,
                                          Selected,
                                          [PrevTraceTop|Rest])
        end,
    NewTrace =
        [NewTraceTop#trace_state{
           last = PossiblyRewrittenSelected,
           lid_trace = NewLidTrace,
           sleep_set = NewSleepSet}|
         PrevTrace],
    State#dpor_state{trace = NewTrace}.

recent_dependency_cv({_Lid, {ets, _Info}, _} = Transition,
                     ClockVector, LidTrace) ->
    Fun =
        fun({Queue, CVAcc}) ->
            {Ret, NewQueue} = queue:out_r(Queue),
            case Ret of
                empty -> {done, CVAcc};
                {value, {Transition2, CV}} ->
                    case concuerror_deps:dependent(Transition, Transition2) of
                        true -> {cont, {NewQueue, max_cv(CVAcc, CV)}};
                        false -> {cont, {NewQueue, CVAcc}}
                    end
            end
        end,
    dynamic_loop_acc(Fun, {LidTrace, ClockVector});
recent_dependency_cv(_Transition, ClockVector, _Trace) ->
    ClockVector.

dynamic_loop_acc(Fun, Arg) ->
    case Fun(Arg) of
        {done, Ret} -> Ret;
        {cont, NewArg} -> dynamic_loop_acc(Fun, NewArg)
    end.

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
is_pollable({'after', _Fun}) -> true;
is_pollable(_Else) -> false.

filter_awaked(SleepSet, Nexts, Selected) ->
    Filter =
        fun(Lid) ->
                Instr = dict:fetch(Lid, Nexts),
                Dep = concuerror_deps:dependent(Instr, Selected),
                ?debug(" vs ~p: ~p\n",[Instr, Dep]),
                not Dep
        end,
    [S || S <- SleepSet, Filter(S)].

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

%% Handle instruction is broken in two parts to reuse code in replay.
handle_instruction(Transition, TraceTop) ->
    {NewTransition, Extra} = handle_instruction_op(Transition),
    handle_instruction_al(NewTransition, TraceTop, Extra).

handle_instruction_op({Lid, {Spawn, _Info}, Msgs})
  when Spawn =:= spawn; Spawn =:= spawn_link; Spawn =:= spawn_monitor;
       Spawn =:= spawn_opt ->
    ParentLid = Lid,
    Info =
        receive
            %% This is the replaced message
            #sched{msg = Spawn, lid = ParentLid,
                   misc = Info0, type = prev} ->
                Info0
        end,
    ChildLid =
        case Info of
            {Lid0, _MonLid} -> Lid0;
            Lid0 -> Lid0
        end,
    ChildNextInstr = wait_next(ChildLid, init),
    {{Lid, {Spawn, Info}, Msgs}, ChildNextInstr};
handle_instruction_op({Lid, {ets, {Updatable, _Info}}, Msgs})
  when Updatable =:= new; Updatable =:= insert_new; Updatable =:= insert ->
    receive
        %% This is the replaced message
        #sched{msg = ets, lid = Lid, misc = {Updatable, Info}, type = prev} ->
            {{Lid, {ets, {Updatable, Info}}, Msgs}, {}}
    end;
handle_instruction_op({Lid, {'receive', Tag}, Msgs}) ->
    receive
        #sched{msg = 'receive', lid = Lid,
               misc = {From, CV, Msg}, type = prev} ->
            {{Lid, {'receive', {Tag, From, Msg}}, Msgs}, CV}
    end;
handle_instruction_op({Lid, {Updatable, _Info}, Msgs})
  when Updatable =:= exit; Updatable =:= send; Updatable =:= whereis;
       Updatable =:= monitor; Updatable =:= process_flag ->
    receive
        #sched{msg = Updatable, lid = Lid, misc = Info, type = prev} ->
            {{Lid, {Updatable, Info}, Msgs}, {}}
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
    TraceTop#trace_state{last = Trans, clock_map = NewClockMap};
handle_instruction_al({_Lid, {ets, {Updatable, _Info}}, _Msgs} = Trans,
                      TraceTop, {})
  when Updatable =:= new; Updatable =:= insert_new; Updatable =:= insert ->
    TraceTop#trace_state{last = Trans};
handle_instruction_al({_Lid, {Updatable, _Info}, _Msgs} = Trans, TraceTop, {})
  when Updatable =:= send; Updatable =:= whereis; Updatable =:= monitor;
       Updatable =:= process_flag ->
    TraceTop#trace_state{last = Trans};
handle_instruction_al({_Lid, {halt, _Status}, _Msgs}, TraceTop, {}) ->
    TraceTop#trace_state{enabled = [], blocked = [], error_nxt = none};
handle_instruction_al(_Transition, TraceTop, {}) ->
    TraceTop.

max_cv(D1, D2) ->
    Merger = fun(_Key, V1, V2) -> max(V1, V2) end,
    orddict:merge(Merger, D1, D2).

check_pollable(TraceTop) ->
    #trace_state{pollable = Pollable} = TraceTop,
    PollableList = ordsets:to_list(Pollable),
    lists:foldl(fun poll_all/2, TraceTop, PollableList).

poll_all(Lid, TraceTop) ->
    case poll(Lid) of
        {'receive', Info} = Res when
              Info =:= unblocked;
              Info =:= had_after ->
            #trace_state{pollable = Pollable,
                         blocked = Blocked,
                         enabled = Enabled,
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

add_some_next_to_backtrack(State) ->
    #dpor_state{trace = [TraceTop|Rest], dpor_flavor = Flavor,
                preemption_bound = PreBound} = State,
    #trace_state{enabled = Enabled, sleep_set = SleepSet,
                 error_nxt = ErrorNext, last = {Lid, _, _},
                 preemptions = Preemptions} = TraceTop,
    ?debug("Pick next: Enabled: ~w Sleeping: ~w\n", [Enabled, SleepSet]),
    Backtrack =
        case ErrorNext of
            none ->
                case Flavor of
                    'none' ->
                        case ordsets:is_element(Lid, Enabled) of
                            true when Preemptions =:= PreBound ->
                                [Lid];
                            _Else -> Enabled
                        end;
                    _Other ->
                        case ordsets:subtract(Enabled, SleepSet) of
                            [] -> [];
                            [H|_] = Candidates ->
                                case ordsets:is_element(Lid, Candidates) of
                                    true -> [Lid];
                                    false -> [H]
                                end
                        end
                end;
            Else -> [Else]
        end,
    ?debug("Picked: ~w\n",[Backtrack]),
    NewTraceTop = TraceTop#trace_state{backtrack = Backtrack},
    State#dpor_state{trace = [NewTraceTop|Rest]}.

report_error(Transition, State) ->
    #dpor_state{trace = [TraceTop|_], tickets = Tickets} = State,
    ?debug("ERROR!\n~P\n",[Transition, ?DEBUG_DEPTH]),
    Error = convert_error_info(Transition),
    LidTrace = queue:in({Transition, foo}, TraceTop#trace_state.lid_trace),
    Ticket = create_ticket(Error, LidTrace),
    %% Report the error to the progress logger.
    concuerror_log:progress({'error', Ticket}),
    State#dpor_state{must_replay = true, tickets = [Ticket|Tickets]}.

create_ticket(Error, LidTrace) ->
    InitTr = init_tr(),
    [{P1, init, []} = InitTr|Trace] = [S || {S,_V} <- queue:to_list(LidTrace)],
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

report_possible_deadlock(State) ->
    #dpor_state{trace = [TraceTop|Trace], tickets = Tickets,
                sleep_blocked_count = SBlocked} = State,
    {NewTickets, NewSBlocked} =
        case TraceTop#trace_state.enabled of
            [] ->
                case TraceTop#trace_state.blocked of
                    [] ->
                        ?debug("NORMAL!\n"),
                        {Tickets, SBlocked};
                    Blocked ->
                        ?debug("DEADLOCK!\n"),
                        Error = {deadlock, Blocked},
                        LidTrace = TraceTop#trace_state.lid_trace,
                        Ticket = create_ticket(Error, LidTrace),
                        %% Report error
                        concuerror_log:progress({'error', Ticket}),
                        {[Ticket|Tickets], SBlocked}
                end;
            _Else ->
                case TraceTop#trace_state.sleep_set =/= []
                    andalso TraceTop#trace_state.done =:= [] of
                    false ->
                        {Tickets, SBlocked};
                    true ->
                        ?debug("SLEEP SET BLOCK\n"),
                        {Tickets, SBlocked+1}
                end
        end,
    ?debug("Stack frame dropped\n"),
    State#dpor_state{must_replay = true, trace = Trace, tickets = NewTickets,
                     sleep_blocked_count = NewSBlocked}.

finished(#dpor_state{trace = Trace}) ->
    Trace =:= [].

dpor_return(State) ->
    RunCnt = State#dpor_state.run_count,
    SBlocked = State#dpor_state.sleep_blocked_count,
    case State#dpor_state.tickets of
        [] -> {ok, RunCnt, SBlocked};
        Tickets -> {error, RunCnt, SBlocked, Tickets}
    end.

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

%% Notify the scheduler of a blocked process.
-spec block() -> 'ok'.

block() ->
    notify(block, []).

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
    Pid ! #sched{msg = Message},
    ok.

%% Notify the scheduler of an event.
%% If the calling user process has an associated LID, then send
%% a notification and yield. Otherwise, for an unknown process
%% running instrumented code completely ignore this call.
-spec notify(notification(), any()) -> 'ok' | 'continue' | 'poll'.

notify(Msg, Misc) ->
    notify(Msg, Misc, next).

-spec notify(notification(), any(), sched_msg_type()) ->
                    'ok' | 'continue' | 'poll'.

notify(Msg, Misc, Type) ->
    case lid_from_pid(self()) of
        not_found -> ok;
        Lid ->
            ?RP_SCHED_SEND ! #sched{msg = Msg, lid = Lid, misc = Misc, type = Type},
            case Type of
                next  ->
                    case Msg of
                        'receive' -> wait_poll_or_continue();
                        _Other -> wait()
                    end;
                _Else -> ok
            end
    end.

-spec lid_from_pid(pid()) -> concuerror_lid:lid() | 'not_found'.

lid_from_pid(Pid) ->
    concuerror_lid:from_pid(Pid).

-spec wakeup() -> 'ok'.

wakeup() ->
    %% TODO: Depending on how 'receive' is instrumented, a check for
    %% whether the caller is a known process might be needed here.
    ?RP_SCHED_SEND ! #special{msg = wakeup},
    wait().

-spec no_wakeup() -> 'ok'.

no_wakeup() ->
    %% TODO: Depending on how 'receive' is instrumented, a check for
    %% whether the caller is a known process might be needed here.
    ?RP_SCHED_SEND ! #special{msg = no_wakeup},
    wait().

%% Wait until the scheduler prompts to continue.
-spec wait() -> 'ok'.

wait() ->
    wait_poll_or_continue(ok).

-spec wait_poll_or_continue() -> 'poll' | 'continue'.

wait_poll_or_continue() ->
    wait_poll_or_continue(continue).

-define(VECTOR_MSG(LID, VC),
        #sched{msg = vector, lid = LID, misc = VC, type = async}).

wait_poll_or_continue(Msg) ->
    receive
        #sched{msg = continue} -> Msg;
        #sched{msg = poll} -> poll;
        ?VECTOR_MSG(Lid, VC) ->
            Msgs = instrument_my_messages(Lid, VC),
            notify(vector, Msgs, async),
            wait_poll_or_continue(Msg)
    end.

replace_messages(Lid, VC) ->
    %% Let "black" processes send any remaining messages.
    erlang:yield(),
    Fun =
        fun(Pid, MsgAcc) ->
            Pid ! ?VECTOR_MSG(Lid, VC),
            receive
                ?VECTOR_MSG(PidsLid, Msgs) ->
                    case Msgs =:= [] of
                        true -> MsgAcc;
                        false -> [{PidsLid, Msgs}|MsgAcc]
                    end
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
                    0 -> {done, Acc}
                end
        end,
    dynamic_loop_acc(Fun, []).
