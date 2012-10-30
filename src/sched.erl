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

-module(sched).

%% UI related exports
-export([analyze/3]).

%% Internal exports
-export([block/0, notify/2, wait/0, wakeup/0, no_wakeup/0, lid_from_pid/1]).

-export([notify/3, wait_poll_or_continue/0]).

-export_type([analysis_target/0, analysis_ret/0, bound/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

-define(INFINITY, 1000000).
-define(NO_ERROR, undef).

% -define(F_DEBUG, true).
-ifdef(F_DEBUG).
-define(f_debug(A,B), log:log(A,B)).
-define(f_debug(A), log:log(A,[])).
-else.
-define(f_debug(_A,_B), ok).
-define(f_debug(A), ok).
-endif.

%%%----------------------------------------------------------------------
%%% Records
%%%----------------------------------------------------------------------

%% Scheduler state
%%
%% active  : A set containing all processes ready to be scheduled.
%% blocked : A set containing all processes that cannot be scheduled next
%%          (e.g. waiting for a message on a `receive`).
%% current : The LID of the currently running or last run process.
%% actions : The actions performed (proc_action:proc_action()).
%% error   : A term describing the error that occurred.
%% state   : The current state of the program.
-record(context, {active         :: ?SET_TYPE(lid:lid()),
                  blocked        :: ?SET_TYPE(lid:lid()),
                  current        :: lid:lid(),
                  actions        :: [proc_action:proc_action()],
                  error          :: ?NO_ERROR | error:error(),
                  state          :: state:state()}).


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
                lid          :: lid:lid(),
                misc = empty :: term(),
                type = next  :: sched_msg_type()}).

%% Special internal message format (fields same as above).
-record(special, {msg :: atom(),
                  lid :: lid:lid() | 'not_found',
                  misc = empty :: term()}).

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type analysis_info() :: {analysis_target(), non_neg_integer()}.

-type analysis_options() :: [{'preb', bound()} |
                             {'include', [file:name()]} |
                             {'define', instr:macros()}].


%% Analysis result tuple.
-type analysis_ret() ::
    {'ok', analysis_info()} |
    {'error', 'instr', analysis_info()} |
    {'error', 'analysis', analysis_info(), [ticket:ticket()]}.

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

%% @spec: analyze(analysis_target(), [file:filename()], analysis_options()) ->
%%          analysis_ret()
%% @doc: Produce all interleavings of running `Target'.
-spec analyze(analysis_target(), [file:filename()], analysis_options()) ->
            analysis_ret().

analyze(Target, Files, Options) ->
    PreBound =
        case lists:keyfind(preb, 1, Options) of
            {preb, inf} -> ?INFINITY;
            {preb, Bound} -> Bound;
            false -> ?DEFAULT_PREB
        end,
    Include =
        case lists:keyfind('include', 1, Options) of
            {'include', I} -> I;
            false -> ?DEFAULT_INCLUDE
        end,
    Define =
        case lists:keyfind('define', 1, Options) of
            {'define', D} -> D;
            false -> ?DEFAULT_DEFINE
        end,
    Dpor = lists:member({dpor}, Options),
    DporFake = lists:member({dpor_fake}, Options),
    Ret =
        case instr:instrument_and_compile(Files, Include, Define, Dpor) of
            {ok, Bin} ->
                %% Note: No error checking for load
                ok = instr:load(Bin),
                log:log("Running analysis...~n~n"),
                {T1, _} = statistics(wall_clock),
                Result = interleave(Target, PreBound, Dpor, DporFake),
                {T2, _} = statistics(wall_clock),
                {Mins, Secs} = elapsed_time(T1, T2),
                case Result of
                    {ok, RunCount} ->
                        log:log("Analysis complete (checked ~w interleaving(s) "
                                "in ~wm~.2fs):~n", [RunCount, Mins, Secs]),
                        log:log("No errors found.~n"),
                        {ok, {Target, RunCount}};
                    {error, RunCount, Tickets} ->
                        TicketCount = length(Tickets),
                        log:log("Analysis complete (checked ~w interleaving(s) "
                                "in ~wm~.2fs):~n", [RunCount, Mins, Secs]),
                        log:log("Found ~p erroneous interleaving(s).~n",
                                [TicketCount]),
                        {error, analysis, {Target, RunCount}, Tickets}
                end;
            error -> {error, instr, {Target, 0}}
        end,
    instr:delete_and_purge(Files),
    Ret.

%% Produce all possible process interleavings of (Mod, Fun, Args).
interleave(Target, PreBound, Dpor, DporFake) ->
    Self = self(),
    Fun =
        fun() ->
                case Dpor of
                    true -> interleave_dpor(Target, PreBound, Self, DporFake);
                    false -> interleave_aux(Target, PreBound, Self)
                end
        end,
    spawn_link(Fun),
    receive
        {interleave_result, Result} -> Result
    end.

interleave_aux(Target, PreBound, Parent) ->
    register(?RP_SCHED, self()),
    %% The mailbox is flushed mainly to discard possible `exit` messages
    %% before enabling the `trap_exit` flag.
    util:flush_mailbox(),
    process_flag(trap_exit, true),
    %% Initialize state table.
    state_start(),
    %% Save empty replay state for the first run.
    InitState = state:empty(),
    state_save([InitState]),
    Result = interleave_outer_loop(Target, 0, [], -1, PreBound),
    state_stop(),
    unregister(?RP_SCHED),
    Parent ! {interleave_result, Result}.

interleave_dpor(Target, PreBound, Parent, DporFake) ->
    ?f_debug("Dpor is not really ready yet...\n"),
    register(?RP_SCHED, self()),
    Result = interleave_dpor(Target, PreBound, DporFake),
    Parent ! {interleave_result, Result}.

interleave_outer_loop(_T, RunCnt, Tickets, MaxBound, MaxBound) ->
    interleave_outer_loop_ret(Tickets, RunCnt);
interleave_outer_loop(Target, RunCnt, Tickets, CurrBound, MaxBound) ->
    {NewRunCnt, TotalTickets, Stop} = interleave_loop(Target, 1, Tickets),
    TotalRunCnt = NewRunCnt + RunCnt,
    state_swap(),
    case state_peak() of
        no_state -> interleave_outer_loop_ret(TotalTickets, TotalRunCnt);
        _State ->
            case Stop of
                true -> interleave_outer_loop_ret(TotalTickets, TotalRunCnt);
                false ->
                    interleave_outer_loop(Target, TotalRunCnt, TotalTickets,
                                          CurrBound + 1, MaxBound)
            end
    end.

interleave_outer_loop_ret([], RunCnt) ->
    {ok, RunCnt};
interleave_outer_loop_ret(Tickets, RunCnt) ->
    {error, RunCnt, Tickets}.

%%------------------------------------------------------------------------------

-type s_i()        :: non_neg_integer().
-type instr()      :: term().
-type transition() :: {lid:lid(), instr()}.
-type clock_map()  :: dict(). %% dict(lid:lid(), clock_vector()).
%% -type clock_vector() :: dict(). %% dict(lid:lid(), s_i()).

-record(trace_state, {
          i         = 0                 :: s_i(),
          last      = init_tr()         :: transition(),
          enabled   = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
          blocked   = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
          pollable  = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
          backtrack = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
          done      = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
          sleep_set = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
          nexts     = dict:new()        :: dict(), %% dict(lid:lid(), instr()),
          error_nxt = none              :: lid:lid() | 'none',
          clock_map = empty_clock_map() :: clock_map(),
          preemptions = 0               :: non_neg_integer(),
          lid_trace = new_lid_trace()   :: queue() %% queue({transition(), clock_vector()})
         }).

init_tr() ->
	{lid:root_lid(), init}.

empty_clock_map() -> dict:new().

new_lid_trace() ->
    queue:in({init_tr(), empty_clock_vector()}, queue:new()).

empty_clock_vector() -> dict:new().

-type trace_state() :: #trace_state{}.

-record(dpor_state, {
          target              :: analysis_target(),
          run_count   = 1     :: pos_integer(),
          tickets     = []    :: [ticket:ticket()],
          trace       = []    :: [trace_state()],
          must_replay = false :: boolean(),
          proc_before = []    :: [pid()],
          fake_dpor   = false :: boolean(),
          preemption_bound = inf :: non_neg_integer() | 'inf'
         }).

%% STUB
interleave_dpor(Target, PreBound, DporFake) ->
    ?f_debug("Interleave dpor!\n"),
    Procs = processes(),
    %% To be able to clean up we need to be trapping exits...
    process_flag(trap_exit, true),
    Trace = start_target(Target),
    ?f_debug("Target started!\n"),
    NewState = #dpor_state{trace = Trace, target = Target, proc_before = Procs,
                           fake_dpor = DporFake, preemption_bound = PreBound},
    explore(NewState).

start_target(Target) ->
    FirstLid = start_target_op(Target),
    Next = wait_next(FirstLid, init),
    MaybeEnabled = ordsets:add_element(FirstLid, ordsets:new()),
    {Pollable, Enabled, Blocked} =
        update_lid_enabled(FirstLid, Next, ordsets:new(), MaybeEnabled, ordsets:new()),
    %% FIXME: check_messages and poll should also be called here for instrumenting
    %%        "black" initial messages.
    TraceTop =
        #trace_state{nexts = dict:store(FirstLid, Next, dict:new()),
                     enabled = Enabled, blocked = Blocked, backtrack = Enabled,
                     pollable = Pollable},
    [TraceTop].

start_target_op(Target) ->
    lid:start(),
    {Mod, Fun, Args} = Target,
    NewFun = fun() -> apply(Mod, Fun, Args) end,
    SpawnFun = fun() -> rep:spawn_fun_wrapper(NewFun) end,
    FirstPid = spawn(SpawnFun),
    lid:new(FirstPid, noparent).

explore(MightNeedReplayState) ->
    ?f_debug("--------\nExplore!\n--------\n"),
    case select_from_backtrack(MightNeedReplayState) of
        {ok, {Lid, Cmd} = Selected, State} ->
            ?f_debug("Selected: ~p\n",[Selected]),
            %% ?f_debug("D1: ~p\n",[D1]),
            case Cmd of
                {error, _ErrorInfo} ->
                    NewState = report_error(Selected, State),
                    explore(NewState);
                _Else ->
                    Next = wait_next(Lid, Cmd),
                    ?f_debug("Next: ~p\n",[Next]),
                    LocalAddState = add_local_backtracks(Selected, State),
                    %% ?f_debug("AAS: ~p\n",[AllAddState]),
                    UpdState = update_trace(Selected, Next, LocalAddState),
                    %% ?f_debug("LAS: ~p\n",[UpdState]),
                    AllAddState = add_all_backtracks({Lid, Next}, UpdState),
                    NewChildState = add_all_child_backtracks(Cmd, AllAddState),
                    %% ?f_debug("US : ~p\n",[UpdState]),
                    NewState = add_some_next_to_backtrack(NewChildState),
                    explore(NewState)
            end;
        none ->
            NewState = report_possible_deadlock(MightNeedReplayState),
            case finished(NewState) of
                false -> explore(NewState);
                true -> dpor_return(MightNeedReplayState)
            end
    end.

select_from_backtrack(#dpor_state{trace = Trace} = MightNeedReplayState) ->
    %% FIXME: Pick first and don't really subtract.
    %% FIXME: This is actually the trace bottom...
    [TraceTop|RestTrace] = Trace,
    Backtrack = TraceTop#trace_state.backtrack,
    Done = TraceTop#trace_state.done,
    case ordsets:subtract(Backtrack, Done) of
	[] ->
            ?f_debug("Backtrack set explored\n",[]),
            none;
        [SelectedLid|_RestLids] ->
            ?f_debug("Have to try ~p...\n",[SelectedLid]),
            State =
                case MightNeedReplayState#dpor_state.must_replay of
                    true -> replay_trace(MightNeedReplayState);
                    false -> MightNeedReplayState
                end,
	    Instruction = dict:fetch(SelectedLid, TraceTop#trace_state.nexts),
            NewDone = ordsets:add_element(SelectedLid, Done),
            NewTraceTop = TraceTop#trace_state{done = NewDone},
            NewState = State#dpor_state{trace = [NewTraceTop|RestTrace]},
	    {ok, {SelectedLid, Instruction}, NewState}
    end.

%% STUB
replay_trace(#dpor_state{proc_before = ProcBefore} = State) ->
    ?f_debug("Replay is required...\n"),
    [#trace_state{lid_trace = LidTrace}|_] = State#dpor_state.trace,
    ?f_debug("~p\n",[[S || {S, _V} <- queue:to_list(LidTrace)]]),
    Target = State#dpor_state.target,
    lid:stop(),
    proc_cleanup(processes() -- ProcBefore),
    start_target_op(Target),
    replay_lid_trace(LidTrace),
    flush_mailbox(),
    RunCnt = State#dpor_state.run_count,
    ?f_debug("Done replaying...\n"),
    State#dpor_state{run_count = RunCnt + 1, must_replay = false}.

replay_lid_trace(Queue) ->
    {V, NewQueue} = queue:out(Queue),
    case V of
        {value, {{Lid, Command} = Transition, VC}} ->
            ?f_debug("Replay: ~p\n",[Transition]),
            _ = wait_next(Lid, Command),
            _ = handle_instruction_op(Transition),
            replace_messages(Lid, VC),
            replay_lid_trace(NewQueue);
        empty ->
            ok
    end.

wait_next(Lid, Prev) ->
    case Prev of
        {exit, normal} ->
            ok = resume(Lid),
            exited;
        {Spawn, _} when Spawn =:= spawn; Spawn =:= spawn_link ->
            ok = resume(Lid),
            %% This interruption happens to make sure that a child has an LID
            %% before the parent wants to do any operation with its PID.
            ChildPid =
                receive
                    #sched{msg = spawned,
                           lid = Lid,
                           misc = Pid,
                           type = prev} = Msg ->
                        Pid
                end,
            ChildLid = lid:new(ChildPid, Lid),
            ?f_debug("Child process is registered\n"),
            resume(Lid),
            self() ! Msg#sched{misc=ChildLid},
            get_next(Lid);
        _Other ->
            ok = resume(Lid),
            get_next(Lid)
    end.

resume(Lid) ->
    ?f_debug("resume "),
    Pid = lid:get_pid(Lid),
    ?f_debug("{lid,~p,pid,~p}\n",[Lid,Pid]),
    Pid ! #sched{msg = continue},
    ok.

get_next(Lid) ->
    receive
        #sched{msg = Type, lid = Lid, misc = Misc, type = next} ->
            {Type, Misc}
    end.

add_local_backtracks(Transition, #dpor_state{preemption_bound = PreBound,
                                             trace = Trace} = State) ->
    [TraceTop|RestTrace] = Trace,
    #trace_state{backtrack = Backtrack, nexts = Nexts, enabled = Enabled,
                 sleep_set = SleepSet, preemptions = Preemptions,
                 last = {LLid, _}} = TraceTop,
    Allowed =
        case ordsets:is_element(LLid, Enabled) of
            false -> true;
            true -> Preemptions < PreBound
        end,
    case Allowed of
        true ->
            NewBacktrack = add_local_backtracks(Transition, Nexts, Enabled, Backtrack),
            SleepingRemoved = ordsets:subtract(NewBacktrack, SleepSet),
            case Backtrack =/= SleepingRemoved of
                true ->
                    ?f_debug("OldBacktrack:~w\n",[Backtrack]),
                    ?f_debug("Sleeping:~w\n",[SleepSet]),
                    ?f_debug("Local adds: ~w\n",[ordsets:subtract(SleepingRemoved, Backtrack)]);
                false -> ok
            end,
            NewTrace = [TraceTop#trace_state{backtrack = SleepingRemoved}|RestTrace],
            State#dpor_state{trace = NewTrace};
        false ->
            State
    end.

add_local_backtracks({NLid, _} = Transition, Nexts, AllEnabled, Backtrack) ->
    Fold =
        fun(Lid, AccBacktrack) ->
            Dependent =
                case NLid =/= Lid of
                    true -> 
                        Instruction = dict:fetch(Lid, Nexts),
                        dependent({Lid, Instruction}, Transition);
                    false ->
                        false
                end,
            case Dependent of
                true -> ordsets:add_element(Lid, AccBacktrack);
                false -> AccBacktrack
            end
        end,
    lists:foldl(Fold, Backtrack, ordsets:to_list(AllEnabled)).

%% STUB
%% All Trace:
%%   dependent(New, Older)
%% Local Trace:
%%   dependent(Possible, Chosen)
dependent({X, _}, {X, _}) ->
    %% You are already in the backtrack set.
    false;
%% TODO:
%% Exits depends on sends to registered processes because if you send
%% to an exited registered process you crash...
%% dependent({_, {exit, normal}}, _) ->
%%     false;
%% dependent(A, {_, {exit, normal}} = B) ->
%%     dependent(B, A);
dependent({_Lid1, {send, {Lid, Msg1}}}, {_Lid2, {send, {Lid, Msg2}}}) ->
    Msg1 =/= Msg2;
dependent({_Lid1, {send, {Lid, _Msg}}}, {Lid, {'after', empty}}) ->
    true;
dependent(_TransitionA, _TransitionB) ->
    ?f_debug("A:~p B:~p\n",[_TransitionA, _TransitionB]),
    false.

add_all_backtracks(Transition, #dpor_state{preemption_bound = PreBound,
                                           trace = Trace} = State) ->
    case State#dpor_state.fake_dpor of
        false ->
            NewTrace = add_all_backtracks_trace(Transition, Trace, PreBound),
            State#dpor_state{trace = NewTrace};
        true ->
            %% add_some_next will take care of all the backtracks.
            State
    end.

add_all_backtracks_trace(exited, Trace, _PreBound) ->
    Trace;
add_all_backtracks_trace({Lid, _} = Transition, Trace, PreBound) ->
    [#trace_state{clock_map = ClockMap}|_] = Trace,
    ClockVector = lookup_clock(Lid, ClockMap),
    add_all_backtracks_trace(Transition, ClockVector, PreBound, Trace, []).

add_all_backtracks_trace(_Transition, _ClockVector, _PreBound, [_] = Init, Acc) ->
    lists:reverse(Acc, Init);
add_all_backtracks_trace(Transition, ClockVector, PreBound, [StateI|Trace], Acc) ->
    #trace_state{i = I, last = {ProcSI, _} = SI, preemptions = Preemptions} = StateI,
    case Preemptions + 1 =< PreBound of
        true ->
            Dependent = dependent(Transition, SI),
            Clock = lookup_clock_value(ProcSI, ClockVector),
            ?f_debug("Dep ~p andalso ~p\n",[Dependent, I > Clock]),
            case Dependent andalso I > Clock of
                false ->
                    add_all_backtracks_trace(Transition, ClockVector, PreBound, Trace, [StateI|Acc]);
                true ->
                    ?f_debug("NEW Backtrack! ~p: I:~p ~p\n",[Transition, I, SI]),
                    [#trace_state{enabled = Enabled, backtrack = Backtrack, sleep_set = SleepSet} =
                         PreSI|Rest] = Trace,
                    P = pick_from_E(ordsets:subtract(Enabled, SleepSet), I, ClockVector),
                    NewBacktrack = ordsets:add_element(P, Backtrack),
                    NewSleepSet = ordsets:add_element(ProcSI, SleepSet),
                    ?f_debug("      New backtrack: ~w\n", [NewBacktrack]),
                    NewPreSI =
                        PreSI#trace_state{backtrack = NewBacktrack, sleep_set = NewSleepSet},
                    lists:reverse(Acc, [StateI,NewPreSI|Rest])
            end;
        false ->
            add_all_backtracks_trace(Transition, ClockVector, PreBound, Trace, [StateI|Acc])
    end.

lookup_clock(P, ClockMap) ->
    case dict:find(P, ClockMap) of
        {ok, Clock} -> Clock;
        error -> dict:new()
    end.

lookup_clock_value(P, CV) ->
    case dict:find(P, CV) of
        {ok, Value} -> Value;
        error -> 0
    end.

pick_from_E(Candidates, I, ClockVector) ->
    Fold =
        fun(Lid, Acc) ->
                Clock = lookup_clock_value(Lid, ClockVector),
                case Clock > I of
                    false -> Acc;
                    true ->
                        case Acc of
                            none -> {ok, Lid, Clock};
                            {ok, _OldLid, OldClock} = Old ->
                                case OldClock > Clock of
                                    true -> {ok, Lid, Clock};
                                    false -> Old
                                end
                        end
                end
        end,
    {ok, Pick, _Clock} = lists:foldl(Fold, none, Candidates),
    Pick.

%% - add new entry with new entry
%% - wait any possible additional messages
%% - check for async
update_trace({Lid, _} = Selected, Next, State) ->
    #dpor_state{trace = [TraceTop|Rest]} = State,
    #trace_state{i = I, enabled = Enabled, blocked = Blocked,
                 pollable = Pollable,
                 nexts = Nexts, lid_trace = LidTrace,
                 clock_map = ClockMap, sleep_set = SleepSet,
                 preemptions = Preemptions, last = {LLid,_}} = TraceTop,
    ?f_debug("Sele: ~w Next: ~w\nPreemptions: ~w\n",[Selected, Next, Preemptions]),
    NewN = I+1,
    ClockVector = lookup_clock(Lid, ClockMap),
    LidsClockVector = dict:store(Lid, NewN, ClockVector),
    NewClockMap = dict:store(Lid, LidsClockVector, ClockMap),
    NewNexts = dict:store(Lid, Next, Nexts),
    MaybeNotPollable = ordsets:del_element(Lid, Pollable),
    {NewPollable, NewEnabled, NewBlocked} =
        update_lid_enabled(Lid, Next, MaybeNotPollable, Enabled, Blocked),
    NewSleepSet = remove_awaked(SleepSet, Nexts, Selected),
    ErrorNext =
        case Next of
            {error, _} -> Lid;
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
    CommonNewTraceTop =
        #trace_state{i = NewN, last = Selected, nexts = NewNexts,
                     enabled = NewEnabled, blocked = NewBlocked,
                     clock_map = NewClockMap, sleep_set = NewSleepSet,
                     pollable = NewPollable, error_nxt = ErrorNext,
                     preemptions = NewPreemptions},
    NewTraceTop = handle_instruction(Selected, CommonNewTraceTop),
    UpdatedClockVector = lookup_clock(Lid, NewTraceTop#trace_state.clock_map),
    replace_messages(Lid, UpdatedClockVector),
    PossiblyRewrittenSelected = NewTraceTop#trace_state.last,
    NewLidTrace =
        queue:in({PossiblyRewrittenSelected, UpdatedClockVector}, LidTrace),
    {NewPrevTraceTop, UnblockedTraceTop} = check_pollable(TraceTop, NewTraceTop),
    State#dpor_state{trace = [UnblockedTraceTop#trace_state{lid_trace = NewLidTrace},
                              NewPrevTraceTop|Rest]}.

update_lid_enabled(Lid, Next, Pollable, Enabled, Blocked) ->
    {NewEnabled, NewBlocked} =
        case is_enabled(Next) of
            true -> {Enabled, Blocked};
            false ->
                ?f_debug("Blocking ~p\n",[Lid]),
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
is_pollable({'after', empty}) -> true;
is_pollable(_Else) -> false.

remove_awaked(SleepSet, Nexts, Selected) ->
    ?f_debug("OldSS: ~w\n",[SleepSet]),
    Filter =
        fun(Lid) ->
                Instr = dict:fetch(Lid, Nexts),
                not dependent({Lid, Instr}, Selected)
        end,
    N = [S || S <- SleepSet, Filter(S)],
    ?f_debug("NewSS:~w\n", [N]),
    N.

%% Handle instruction is broken in two parts to reuse code in replay.
handle_instruction(Transition, TraceTop) ->
    Variables = handle_instruction_op(Transition),
    handle_instruction_al(Transition, TraceTop, Variables).

handle_instruction_op({Lid, {Spawn, _Info}}) when Spawn =:= spawn; Spawn =:= spawn_link ->
    ParentLid = Lid,
    ChildLid =
        receive
            %% This is the replaced message
            #sched{msg = spawned, lid = ParentLid, misc = ChildLid0, type = prev} ->
                ChildLid0
        end,
    ChildNextInstr = wait_next(ChildLid, init),
    flush_mailbox(),
    {ChildLid, ChildNextInstr};
handle_instruction_op({Lid, {'receive', _TagOrInfo}}) ->
    receive
        #sched{msg = 'receive', lid = Lid, misc = Details, type = prev} ->
            Details
    end;
handle_instruction_op(_) ->
    flush_mailbox(),
    {}.

flush_mailbox() ->
    receive
        _Any ->
            ?f_debug("NONEMPTY!\n~p\n",[_Any]),
            flush_mailbox()
    after 0 ->
            ok
    end.

%% STUB
handle_instruction_al({Lid, {exit, normal}}, TraceTop, {}) ->
    ?f_debug("Exit\n"),
    #trace_state{enabled = Enabled, nexts = Nexts} = TraceTop,
    NewEnabled = ordsets:del_element(Lid, Enabled),
    NewNexts = dict:erase(Lid, Nexts),
    TraceTop#trace_state{enabled = NewEnabled, nexts = NewNexts};
handle_instruction_al({Lid, {Spawn, unknown}}, TraceTop, {ChildLid, ChildNextInstr})
  when Spawn =:= spawn; Spawn =:= spawn_link ->
    #trace_state{enabled = Enabled, blocked = Blocked,
                 nexts = Nexts, pollable = Pollable} = TraceTop,
    NewNexts = dict:store(ChildLid, ChildNextInstr, Nexts),
    MaybeEnabled = ordsets:add_element(ChildLid, Enabled),
    ?f_debug("NextChild:~p\n",[ChildNextInstr]),
    {NewPollable, NewEnabled, NewBlocked} =
        update_lid_enabled(ChildLid, ChildNextInstr, Pollable, MaybeEnabled, Blocked),
    NewLast = {Lid, {Spawn, ChildLid}},
    TraceTop#trace_state{last = NewLast,
                         enabled = NewEnabled,
                         blocked = NewBlocked,
                         pollable = NewPollable,
                         nexts = NewNexts};
handle_instruction_al({Lid, {'receive', Tag}}, TraceTop, {From, CV, Msg}) ->
    #trace_state{clock_map = ClockMap} = TraceTop,
    Vector = lookup_clock(Lid, ClockMap),
    Info =
        case Tag of
            unblocked -> {From, Msg};
            had_after ->
                When = lookup_clock_value(From, CV),
                {From, Msg, When}
        end,
    NewLast = {Lid, {'receive', Info}},
    NewVector = max_cv(Vector, CV),
    NewClockMap = dict:store(Lid, NewVector, ClockMap),
    TraceTop#trace_state{last = NewLast, clock_map = NewClockMap};
handle_instruction_al(_Transition, TraceTop, {}) ->
    TraceTop.

max_cv(D1, D2) ->
    Merger = fun(_Key, V1, V2) -> max(V1, V2) end,
    dict:merge(Merger, D1, D2).

check_pollable(OldTraceTop, TraceTop) ->
    #trace_state{pollable = Pollable, blocked = Blocked,
                 enabled = Enabled, nexts = Nexts,
                 sleep_set = SleepSet} = TraceTop,
    #trace_state{backtrack = Backtrack} = OldTraceTop,
    PollableList = ordsets:to_list(Pollable),
    InitAcc = {Backtrack, SleepSet, Pollable, Blocked, Enabled, Nexts},
    {NewBacktrack, NewSleepSet, NewPollable, NewBlocked, NewEnabled, NewNexts} =
        lists:foldl(fun poll_all/2, InitAcc, PollableList),
    ?f_debug("  Pollable: ~w\n  Blocked: ~w\n  Enabled: ~w\n  Nexts: ~w\n",
             [NewPollable, NewBlocked, NewEnabled, dict:to_list(NewNexts)]),
    {OldTraceTop#trace_state{backtrack = NewBacktrack},
     TraceTop#trace_state{pollable = NewPollable,
                          blocked = NewBlocked,
                          enabled = NewEnabled,
                          sleep_set = NewSleepSet,
                          nexts = NewNexts}}.

poll_all(Lid, {Backtrack, SleepSet, Pollable, Blocked, Enabled, Nexts} = Original) ->
    ?f_debug("Poll ~p: ",[Lid]),
    Res = poll(Lid),
    ?f_debug("~p\n",[Res]),
    case Res of
        {'receive', Info} when
              Info =:= unblocked;
              Info =:= had_after ->
            {NewBacktrack, NewSleepSet} =
                case Info of
                    unblocked -> {Backtrack, SleepSet};
                    had_after ->
                        case ordsets:is_element(Lid, SleepSet) of
                            true ->
                                {Backtrack,
                                 ordsets:del_element(Lid, SleepSet)};
                            false ->
                                {ordsets:add_element(Lid, Backtrack),
                                 SleepSet}
                        end
                end,
            {NewBacktrack,
             NewSleepSet,
             ordsets:del_element(Lid, Pollable),
             ordsets:del_element(Lid, Blocked),
             ordsets:add_element(Lid, Enabled),
             dict:store(Lid, Res, Nexts)};
        _Else ->
            Original
    end.

add_all_child_backtracks({spawn, unknown}, State) ->
    #dpor_state{trace = [TraceTop|_]} = State,
    #trace_state{last = {_, {spawn, ChildLid}}, enabled = Enabled,
                 nexts = Nexts} = TraceTop,
    case ordsets:is_element(ChildLid, Enabled) of
        true ->
            ChildNext = dict:fetch(ChildLid, Nexts),
            add_all_backtracks({ChildLid, ChildNext}, State);
        false ->
            State
    end;
add_all_child_backtracks(_Else, State) ->
    State.    

%% STUB
add_some_next_to_backtrack(State) ->
    #dpor_state{trace = [TraceTop|Rest], fake_dpor = Fake} = State,
    #trace_state{enabled = Enabled, sleep_set = SleepSet,
                 error_nxt = ErrorNext, last = {Lid, _}} = TraceTop,
    ?f_debug("Pick random: Enabled: ~w Sleeping: ~w\n",
             [Enabled, SleepSet]),
    Backtrack =
        case ordsets:subtract(Enabled, SleepSet) of
            [] -> [];
            [H|_] = Candidates ->
                case Fake of
                    true -> Candidates;
                    false ->
                        case ErrorNext of
                            none ->
                                case ordsets:is_element(Lid, Candidates) of
                                    true -> [Lid];
                                    false -> ?f_debug("Picked: ~w\n",[H]), [H]
                                end;
                            Else ->
                                ?f_debug("Picked to crash: ~w\n",[H]),
                                [Else]
                        end
                end
        end,
    State#dpor_state{trace = [TraceTop#trace_state{backtrack = Backtrack}|Rest]}.

%% STUB
report_error(Transition, State) ->
    #dpor_state{trace = [TraceTop|_], tickets = Tickets} = State,
    ?f_debug("ERROR!\n~p\n",[Transition]),
    InitTr = init_tr(),
    [{P1, init} = InitTr|Trace] =
        [S || {S,_V} <- queue:to_list(queue:in({Transition, foo}, TraceTop#trace_state.lid_trace))],
    InitSet = sets:add_element(P1, sets:new()),
    {ErrorState, _Procs} =
        lists:mapfoldl(fun convert_error_trace/2, InitSet, Trace),
    Error = convert_error_info(Transition),
    Ticket = ticket:new(Error, ErrorState),
    log:show_error(Ticket),
    State#dpor_state{must_replay = true, tickets = [Ticket|Tickets]}.

convert_error_trace({Lid, {error, [ErrorOrThrow|_]}}, Procs)
  when ErrorOrThrow =:= error; ErrorOrThrow =:= throw ->
    {{exit, Lid, "Exception"}, Procs};
convert_error_trace({Lid, {Instr, Extra}}, Procs) ->
    NewProcs =
        case Instr of
            Spawn when Spawn =:= spawn; Spawn =:= spawn_link ->
                sets:add_element(Extra, Procs);
            exit   -> sets:del_element(Lid, Procs);
            _ -> Procs
        end,
    NewInstr =
        case Instr of
            send ->
                {Dest, Msg} = Extra,
                NewDest =
                    case sets:is_element(Dest, Procs) of
                        true -> Dest;
                        false -> not_found %{dead, Dest}
                    end,
                {send, Lid, NewDest, Msg};
            'receive' ->
                {Origin, Msg} =
                    case Extra of
                        {O, M, _W} -> {O, M};
                        _Else -> Extra
                    end,
                {'receive', Lid, Origin, Msg};
            'after' ->
                {'after', Lid};
            _ ->
                {Instr, Lid, Extra}
        end,
    {NewInstr, NewProcs}.

convert_error_info({_Lid, {error, [Kind, Type, Stacktrace]}})->
    NewType =
        case Kind of
            error -> Type;
            throw -> {nocatch, Type}
        end,
    [_|TmpStacktrace] = lists:reverse(Stacktrace),
    {exception,{NewType, lists:reverse(TmpStacktrace)}}.

%% STUB
report_possible_deadlock(State) ->
    #dpor_state{trace = [TraceTop|Trace], tickets = Tickets} = State,
    NewTickets =
        case TraceTop#trace_state.enabled of
            [] ->
                LidTrace = [S || {S, _V} <- queue:to_list(TraceTop#trace_state.lid_trace)],
                case TraceTop#trace_state.blocked of
                    [] ->
                        %% log:log("~p\n",[State#dpor_state.run_count]),
                        %% log:log("All processes exited:~p\n",[LidTrace]),
                        Tickets;
                    Blocked ->
                        InitTr = init_tr(),
                        [InitTr|DeadTrace] = LidTrace,
                        ?f_debug("Deadlock:~p\n",[DeadTrace]),
                        {ErrorState, _Procs} =
                            lists:mapfoldl(fun convert_error_trace/2,
                                           sets:new(), DeadTrace),
                        Error = {deadlock, Blocked},
                        Ticket = ticket:new(Error, ErrorState),
                        log:show_error(Ticket),
                        [Ticket|Tickets]
                end;
            _Else ->
                Tickets
        end,
    ?f_debug("Stack frame dropped\n"),
    State#dpor_state{must_replay = true, trace = Trace, tickets = NewTickets}.

finished(#dpor_state{trace = Trace}) ->
    Trace =:= [].

dpor_return(State) ->
    RunCnt = State#dpor_state.run_count,
    case State#dpor_state.tickets of
        [] -> {ok, RunCnt};
        Tickets -> {error, RunCnt, Tickets}
    end.

%%------------------------------------------------------------------------------

%% Main loop for producing process interleavings.
%% The first process (FirstPid) is created linked to the scheduler,
%% so that the latter can receive the former's exit message when it
%% terminates. In the same way, every process that may be spawned in
%% the course of the program shall be linked to the scheduler process.
interleave_loop(Target, RunCnt, Tickets) ->
    %% Lookup state to replay.
    case state_load() of
        no_state -> {RunCnt - 1, Tickets, false};
        ReplayState ->
            ?debug_1("Running interleaving ~p~n", [RunCnt]),
            ?debug_1("----------------------~n"),
            lid:start(),
            %% Save current process list (any process created after
            %% this will be cleaned up at the end of the run)
            ProcBefore = processes(),
            %% Spawn initial user process
            {Mod, Fun, Args} = Target,
            NewFun = fun() -> wait(), apply(Mod, Fun, Args) end,
            FirstPid = spawn_link(NewFun),
            %% Initialize scheduler context
            FirstLid = lid:new(FirstPid, noparent),
            Active = ?SETS:add_element(FirstLid, ?SETS:new()),
            Blocked = ?SETS:new(),
            State = state:empty(),
            Context = #context{active=Active, state=State,
                blocked=Blocked, actions=[]},
            %% Interleave using driver
            Ret = driver(Context, ReplayState),
            %% Cleanup
            proc_cleanup(processes() -- ProcBefore),
            lid:stop(),
            NewTickets =
                case Ret of
                    {error, Error, ErrorState} ->
                        Ticket = ticket:new(Error, ErrorState),
                        log:show_error(Ticket),
                        [Ticket|Tickets];
                    _OtherRet1 -> Tickets
                end,
            NewRunCnt =
                case Ret of
                    abort ->
                        ?debug_1("-----------------------~n"),
                        ?debug_1("Run aborted.~n~n"),
                        RunCnt;
                    _OtherRet2 ->
                        ?debug_1("-----------------------~n"),
                        ?debug_1("Run terminated.~n~n"),
                        RunCnt + 1
                end,
            receive
                stop_analysis -> {NewRunCnt - 1, NewTickets, true}
            after 0 ->
                    interleave_loop(Target, NewRunCnt, NewTickets)
            end
    end.

%%%----------------------------------------------------------------------
%%% Core components
%%%----------------------------------------------------------------------

driver(Context, ReplayState) ->
    case state:is_empty(ReplayState) of
        true -> driver_normal(Context);
        false -> driver_replay(Context, ReplayState)
    end.

driver_replay(Context, ReplayState) ->
    {Next, Rest} = state:trim_head(ReplayState),
    NewContext = run(Context#context{current = Next, error = ?NO_ERROR}),
    #context{blocked = NewBlocked} = NewContext,
    case state:is_empty(Rest) of
        true ->
            case ?SETS:is_element(Next, NewBlocked) of
                %% If the last action of the replayed state prefix is a block,
                %% we can safely abort.
                true -> abort;
                %% Replay has finished; proceed in normal mode, after checking
                %% for errors during the last replayed action.
                false -> check_for_errors(NewContext)
            end;
        false ->
            case ?SETS:is_element(Next, NewBlocked) of
                true -> log:internal("Proc. ~p should be active.", [Next]);
                false -> driver_replay(NewContext, Rest)
            end
    end.

driver_normal(#context{active=Active, current=LastLid,
                       state = State} = Context) ->
    Next =
        case ?SETS:is_element(LastLid, Active) of
            true ->
                TmpActive = ?SETS:to_list(?SETS:del_element(LastLid, Active)),
                {LastLid,TmpActive, next};
            false ->
                [Head|TmpActive] = ?SETS:to_list(Active),
                {Head, TmpActive, current}
        end,
    {NewContext, Insert} = run_no_block(Context, Next),
    insert_states(State, Insert),
    check_for_errors(NewContext).

%% Handle four possible cases:
%% - An error occured during the execution of the last process =>
%%   Terminate the run and report the erroneous interleaving sequence.
%% - Only blocked processes exist =>
%%   Terminate the run and report a deadlock.
%% - No active or blocked processes exist =>
%%   Terminate the run without errors.
%% - There exists at least one active process =>
%%   Continue run.
check_for_errors(#context{error=NewError, actions=Actions, active=NewActive,
                          blocked=NewBlocked} = NewContext) ->
    case NewError of
        ?NO_ERROR ->
            case ?SETS:size(NewActive) of
                0 ->
                    case ?SETS:size(NewBlocked) of
                        0 -> ok;
                        _NonEmptyBlocked ->
                            Deadlock = error:new({deadlock, NewBlocked}),
                            ErrorState = lists:reverse(Actions),
                            ?f_debug("SNEAK A PEEK!\nES:~p\nE:~p\n",
                                     [ErrorState, Deadlock]),
                            {error, Deadlock, ErrorState}
                    end;
                _NonEmptyActive -> driver_normal(NewContext)
            end;
        _Other ->
            ErrorState = lists:reverse(Actions),
            ?f_debug("SNEAK A PEEK!\nES:~p\nE:~p\n",[ErrorState, NewError]),
            {error, NewError, ErrorState}
    end.

run_no_block(#context{state = State} = Context, {Next, Rest, W}) ->
    NewContext = run(Context#context{current = Next, error = ?NO_ERROR}),
    #context{blocked = NewBlocked} = NewContext,
    case ?SETS:is_element(Next, NewBlocked) of
        true ->
            case Rest of
                [] -> {NewContext#context{state = State}, {[], W}};
                [RH|RT] ->
                    NextContext = NewContext#context{state = State},
                    run_no_block(NextContext, {RH, RT, current})
            end;
        false -> {NewContext, {Rest, W}}
    end.

insert_states(State, {Lids, current}) ->
    Extend = lists:map(fun(L) -> state:extend(State, L) end, Lids),
    state_save(Extend);
insert_states(State, {Lids, next}) ->
    Extend = lists:map(fun(L) -> state:extend(State, L) end, Lids),
    state_save_next(Extend).

%% Run process Lid in context Context until it encounters a preemption point.
run(#context{current = Lid, state = State} = Context) ->
    ?debug_2("Running process ~s.~n", [lid:to_string(Lid)]),
    %% Create new state by adding this process.
    NewState = state:extend(State, Lid),
    %% Send message to "unblock" the process.
    continue(Lid),
    %% Dispatch incoming notifications to the appropriate handler.
    NewContext = dispatch(Context#context{state = NewState}),
    %% Update context due to wakeups caused by the last action.
    ?SETS:fold(fun check_wakeup/2, NewContext, NewContext#context.blocked).

check_wakeup(Lid, #context{active = Active, blocked = Blocked} = Context) ->
    continue(Lid),
    receive
        #special{msg = wakeup} ->
            NewBlocked = ?SETS:del_element(Lid, Blocked),
            NewActive = ?SETS:add_element(Lid, Active),
            Context#context{active = NewActive, blocked = NewBlocked};
        #special{msg = no_wakeup} -> Context
    end.

%% Delegate notifications sent by instrumented client code to the appropriate
%% handlers.
dispatch(Context) ->
    receive
        #sched{msg = Type, lid = Lid, misc = Misc} ->
            handler(Type, Lid, Context, Misc);
        %% Ignore unknown processes.
        {'EXIT', Pid, Reason} ->
            case lid:from_pid(Pid) of
                not_found -> dispatch(Context);
                Lid -> handler(exit, Lid, Context, Reason)
            end
    end.

%%%----------------------------------------------------------------------
%%% Handlers
%%%----------------------------------------------------------------------

handler('after', Lid, #context{actions=Actions}=Context, _Misc) ->
    Action = {'after', Lid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

%% Move the process to the blocked set.
handler(block, Lid,
        #context{active=Active, blocked=Blocked, actions=Actions} = Context,
        _Misc) ->
    Action = {'block', Lid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:del_element(Lid, Active),
    NewBlocked = ?SETS:add_element(Lid, Blocked),
    Context#context{active=NewActive, blocked=NewBlocked, actions=NewActions};

handler(demonitor, Lid, #context{actions=Actions}=Context, _Ref) ->
    %% TODO: Get LID from Ref?
    TargetLid = lid:mock(0),
    Action = {demonitor, Lid, TargetLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

%% Remove the exited process from the active set.
%% NOTE: This is called after a process has exited, not when it calls
%%       exit/1 or exit/2.
handler(exit, Lid, #context{active = Active, actions = Actions} = Context,
        Reason) ->
    NewActive = ?SETS:del_element(Lid, Active),
    %% Cleanup LID stored info.
    lid:cleanup(Lid),
    %% Handle and propagate errors.
    case Reason of
        normal ->
            Action1 = {exit, Lid, normal},
            NewActions1 = [Action1 | Actions],
            ?debug_1(proc_action:to_string(Action1) ++ "~n"),
            Context#context{active = NewActive, actions = NewActions1};
        _Else ->
            Error = error:new(Reason),
            Action2 = {exit, Lid, error:type(Error)},
            NewActions2 = [Action2 | Actions],
            ?debug_1(proc_action:to_string(Action2) ++ "~n"),
            Context#context{active=NewActive, error=Error, actions=NewActions2}
    end;

%% Return empty active and blocked queues to force run termination.
handler(halt, Lid, #context{actions = Actions}=Context, Misc) ->
    Action =
        case Misc of
            empty  -> {halt, Lid};
            Status -> {halt, Lid, Status}
        end,
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{active=?SETS:new(),blocked=?SETS:new(),actions=NewActions};

handler(is_process_alive, Lid, #context{actions=Actions}=Context, TargetPid) ->
    TargetLid = lid:from_pid(TargetPid),
    Action = {is_process_alive, Lid, TargetLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

handler(link, Lid, #context{actions = Actions}=Context, TargetPid) ->
    TargetLid = lid:from_pid(TargetPid),
    Action = {link, Lid, TargetLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

handler(monitor, Lid, #context{actions = Actions}=Context, {Item, _Ref}) ->
    TargetLid = lid:from_pid(Item),
    Action = {monitor, Lid, TargetLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

handler(process_flag, Lid, #context{actions=Actions}=Context, {Flag, Value}) ->
    Action = {process_flag, Lid, Flag, Value},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

%% Normal receive message handler.
handler('receive', Lid, #context{actions = Actions}=Context, {From, Msg}) ->
    Action = {'receive', Lid, From, Msg},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

%% Receive message handler for special messages, like 'EXIT' and 'DOWN',
%% which don't have an associated sender process.
handler('receive_no_instr', Lid, #context{actions = Actions}=Context, Msg) ->
    Action = {'receive_no_instr', Lid, Msg},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

handler(register, Lid, #context{actions=Actions}=Context, {RegName, RegLid}) ->
    Action = {register, Lid, RegName, RegLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

handler(send, Lid, #context{actions = Actions}=Context, {DstPid, Msg}) ->
    DstLid = lid:from_pid(DstPid),
    Action = {send, Lid, DstLid, Msg},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

%% Link the newly spawned process to the scheduler process and add it to the
%% active set.
handler(spawn, ParentLid,
        #context{active= Active, actions = Actions} = Context, ChildPid) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    Action = {spawn, ParentLid, ChildLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive, actions = NewActions};

%% FIXME: Refactor this (it's exactly the same as 'spawn')
handler(spawn_link, ParentLid,
        #context{active = Active, actions = Actions} = Context, ChildPid) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    Action = {spawn_link, ParentLid, ChildLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive, actions = NewActions};

%% FIXME: Refactor this (it's almost the same as 'spawn')
handler(spawn_monitor, ParentLid,
        #context{active=Active, actions=Actions}=Context, {ChildPid, _Ref}) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    Action = {spawn_monitor, ParentLid, ChildLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive, actions = NewActions};

%% Similar to above depending on options.
handler(spawn_opt, ParentLid,
        #context{active=Active, actions=Actions}=Context, {Ret, Opt}) ->
    {ChildPid, _Ref} =
        case Ret of
            {_C, _R} = CR -> CR;
            C -> {C, noref}
        end,
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    Opts = sets:to_list(sets:intersection(sets:from_list([link, monitor]),
                                          sets:from_list(Opt))),
    Action = {spawn_opt, ParentLid, ChildLid, Opts},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive, actions = NewActions};

handler(unlink, Lid, #context{actions = Actions}=Context, TargetPid) ->
    TargetLid = lid:from_pid(TargetPid),
    Action = {unlink, Lid, TargetLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

handler(unregister, Lid, #context{actions = Actions}=Context, RegName) ->
    Action = {unregister, Lid, RegName},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

handler(whereis, Lid, #context{actions = Actions}=Context, {RegName, Result}) ->
    ResultLid = lid:from_pid(Result),
    Action = {whereis, Lid, RegName, ResultLid},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions};

%% Handler for anything "non-special". It just passes the arguments
%% for logging.
%% TODO: We may be able to delete some of the above that can be handled
%%       by this generic handler.
handler(CallMsg, Lid, #context{actions = Actions}=Context, Args) ->
    Action = {CallMsg, Lid, Args},
    NewActions = [Action | Actions],
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{actions = NewActions}.

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

%% Calculate and print elapsed time between T1 and T2.
elapsed_time(T1, T2) ->
    ElapsedTime = T2 - T1,
    Mins = ElapsedTime div 60000,
    Secs = (ElapsedTime rem 60000) / 1000,
    ?debug_1("Done in ~wm~.2fs\n", [Mins, Secs]),
    {Mins, Secs}.

%% Remove and return a state.
%% If no states available, return 'no_state'.
state_load() ->
    {Len1, Len2} = get(?NT_STATELEN),
    case get(?NT_STATE1) of
        [State | Rest] ->
            put(?NT_STATE1, Rest),
            log:progress(log, Len1-1),
            put(?NT_STATELEN, {Len1-1, Len2}),
            state:pack(State);
        [] -> no_state
    end.

%% Return a state without removing it.
%% If no states available, return 'no_state'.
state_peak() ->
    case get(?NT_STATE1) of
        [State|_] -> State;
        [] -> no_state
    end.

%% Add some states to the current `state` table.
state_save(State) ->
    Size = length(State),
    {Len1, Len2} = get(?NT_STATELEN),
    put(?NT_STATELEN, {Len1+Size, Len2}),
    put(?NT_STATE1, State ++ get(?NT_STATE1)).

%% Add some states to the next `state` table.
state_save_next(State) ->
    Size = length(State),
    {Len1, Len2} = get(?NT_STATELEN),
    put(?NT_STATELEN, {Len1, Len2+Size}),
    put(?NT_STATE2, State ++ get(?NT_STATE2)).

%% Initialize state tables.
state_start() ->
    put(?NT_STATE1, []),
    put(?NT_STATE2, []),
    put(?NT_STATELEN, {0, 0}),
    ok.

%% Clean up state table.
state_stop() ->
    ok.

%% Swap names of the two state tables and clear one of them.
state_swap() ->
    {_Len1, Len2} = get(?NT_STATELEN),
    log:progress(swap, Len2),
    put(?NT_STATELEN, {Len2, 0}),
    put(?NT_STATE1, put(?NT_STATE2, [])).


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
    get_next(Lid).

send_message(Pid, Message) when is_pid(Pid) ->
    Pid ! #sched{msg = Message},
    ok;
send_message(Lid, Message) ->
    Pid = lid:get_pid(Lid),
    Pid ! #sched{msg = Message},
    ok.

%% Notify the scheduler of an event.
%% If the calling user process has an associated LID, then send
%% a notification and yield. Otherwise, for an unknown process
%% running instrumented code completely ignore this call.
-spec notify(notification(), any()) -> 'ok'.

notify(Msg, Misc) ->
    notify(Msg, Misc, next).

-spec notify(notification(), any(), sched_msg_type()) -> 'ok'.

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

%% TODO: Maybe move into lid module.
-spec lid_from_pid(pid()) -> lid:lid() | 'not_found'.

lid_from_pid(Pid) ->
    lid:from_pid(Pid).

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
    {message_queue_len, Msgs} = process_info(self(), message_queue_len),
    receive
        #sched{msg = continue} -> Msg;
        #sched{msg = poll} -> poll;
        ?VECTOR_MSG(Lid, VC) ->
            {message_queue_len, NewMsgs} = process_info(self(), message_queue_len),
            case NewMsgs > Msgs of
                true -> instrument_my_messages(Lid, VC);
                false -> ok
            end,
            notify(vector, ok, async),
            wait_poll_or_continue(Msg)
    end.

replace_messages(Lid, VC) ->
    Unused = unused,
    Fun =
        fun(Pid, U) when U =:= Unused ->
            case is_process_alive(Pid) of
                true ->
                    link(Pid),
                    Pid ! ?VECTOR_MSG(Lid, VC),
                    receive
                        ?VECTOR_MSG(_PidsLid, ok) -> ok;
                        {'EXIT', Pid, _Reason} ->
                            %% Process may have been asked to exit.
                            ok                                                        
                    end,
                    unlink(Pid);
                false -> ok
            end,
            U
        end,
    lid:fold_pids(Fun, Unused).

-define(IS_INSTR_MSG(Msg),
        (is_tuple(Msg) andalso
         size(Msg) =:= 4 andalso
         element(1, Msg) =:= ?INSTR_MSG)).

instrument_my_messages(Lid, VC) ->
    Self = self(),
    Check =
        fun() ->
                receive
                    Msg when not ?IS_INSTR_MSG(Msg) ->
                        Instr = {?INSTR_MSG, Lid, VC, Msg},
                        Self ! Instr,
                        cont
                after
                    0 -> done
                end
        end,
    dynamic_loop(Check).

dynamic_loop(Check) ->
    case Check() of
        done -> ok;
        cont -> dynamic_loop(Check)
    end.
