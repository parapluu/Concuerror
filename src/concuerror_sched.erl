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

-export([notify/3, wait_poll_or_continue/0, lock_release_atom/0]).

-export_type([analysis_target/0, analysis_ret/0, bound/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

-define(INFINITY, 1000000).
-define(NO_ERROR, undef).

%%-define(F_DEBUG, true).
-ifdef(F_DEBUG).
-define(f_debug(A,B), case get(debug) of true -> concuerror_log:log(A,B); undefined -> ok end).
-define(f_debug(A), ?f_debug(A,[])).
-define(start_debug, put(debug,true)).
-define(stop_debug, erase(debug)).
-define(DEPTH, 12).
-else.
-define(f_debug(_A,_B), ok).
-define(f_debug(A), ok).
-define(start_debug, ok).
-define(stop_debug, ok).
-endif.

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

-type analysis_info() :: {analysis_target(), non_neg_integer()}.

-type analysis_options() :: [{'preb', bound()} |
                             {'include', [file:name()]} |
                             {'define', concuerror_instr:macros()}].


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
    Dpor = lists:keymember('dpor', 1, Options),
    Ret =
        case concuerror_instr:instrument_and_compile(Files, Include, Define) of
            {ok, Bin} ->
                %% Note: No error checking for load
                ok = concuerror_instr:load(Bin),
                concuerror_log:log("\nRunning analysis with preemption "
                    "bound ~p..\n", [PreBound]),
                {T1, _} = statistics(wall_clock),
                Result = interleave(Target, PreBound, Dpor),
                {T2, _} = statistics(wall_clock),
                {Mins, Secs} = elapsed_time(T1, T2),
                case Result of
                    {ok, RunCount} ->
                        concuerror_log:log("~n~nAnalysis complete (checked ~w "
                                "interleaving(s) in ~wm~.2fs):~n",
                                [RunCount, Mins, Secs]),
                        concuerror_log:log("No errors found.~n"),
                        {ok, {Target, RunCount}};
                    {error, RunCount, Tickets} ->
                        TicketCount = length(Tickets),
                        concuerror_log:log("Analysis complete (checked ~w "
                                "interleaving(s) in ~wm~.2fs):~n",
                                [RunCount, Mins, Secs]),
                        concuerror_log:log(
                                "Found ~p erroneous interleaving(s).~n",
                                [TicketCount]),
                        {error, analysis, {Target, RunCount}, Tickets}
                end;
            error -> {error, instr, {Target, 0}}
        end,
    concuerror_instr:delete_and_purge(Files),
    Ret.

%% Produce all possible process interleavings of (Mod, Fun, Args).
interleave(Target, PreBound, Dpor) ->
    Self = self(),
    spawn_link(fun() -> interleave_aux(Target, PreBound, Self, Dpor) end),
    receive
        {interleave_result, Result} -> Result
    end.

interleave_aux(Target, PreBound, Parent, Dpor) ->
    ?f_debug("Dpor is not really ready yet...\n"),
    register(?RP_SCHED, self()),
    Result = interleave_dpor(Target, PreBound, Dpor),
    unregister(?RP_SCHED),
    ?stop_debug,
    Parent ! {interleave_result, Result}.

-type s_i()        :: non_neg_integer().
-type instr()      :: term().
-type transition() :: {concuerror_lid:lid(), instr(), list()}.
-type clock_map()  :: dict(). %% dict(concuerror_lid:lid(), clock_vector()).
%% -type clock_vector() :: dict(). %% dict(concuerror_lid:lid(), s_i()).

-record(trace_state, {
          i         = 0                 :: s_i(),
          last      = init_tr()         :: transition(),
          enabled   = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          blocked   = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          pollable  = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
          backtrack = ordsets:new()     :: ordsets:ordset(concuerror_lid:lid()),
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

empty_clock_vector() -> dict:new().

-type trace_state() :: #trace_state{}.

-record(dpor_state, {
          target              :: analysis_target(),
          run_count    = 1     :: pos_integer(),
          tickets      = []    :: [concuerror_ticket:ticket()],
          trace        = []    :: [trace_state()],
          must_replay  = false :: boolean(),
          proc_before  = []    :: [pid()],
          dpor_enabled = false :: boolean(),
          preemption_bound = inf :: non_neg_integer() | 'inf'
         }).

interleave_dpor(Target, PreBound, Dpor) ->
    ?start_debug,
    ?f_debug("Interleave dpor!\n"),
    Procs = processes(),
    %% To be able to clean up we need to be trapping exits...
    process_flag(trap_exit, true),
    Trace = start_target(Target),
    ?f_debug("Target started!\n"),
    NewState = #dpor_state{trace = Trace, target = Target, proc_before = Procs,
                           dpor_enabled = Dpor, preemption_bound = PreBound},
    explore(NewState).

start_target(Target) ->
    FirstLid = start_target_op(Target),
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
    [TraceTop].

start_target_op(Target) ->
    concuerror_lid:start(),
    {Mod, Fun, Args} = Target,
    NewFun = fun() -> apply(Mod, Fun, Args) end,
    SpawnFun = fun() -> concuerror_rep:spawn_fun_wrapper(NewFun) end,
    FirstPid = spawn(SpawnFun),
    concuerror_lid:new(FirstPid, noparent).

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
    ?f_debug("------------\nExplore ~p\n------------\n",
             [TraceTop#trace_state.i + 1]),
    case ordsets:subtract(Backtrack, Done) of
        [] ->
            ?f_debug("Backtrack set explored\n",[]),
            none;
        [SelectedLid|_RestLids] ->
            State =
                case MightNeedReplayState#dpor_state.must_replay of
                    true -> replay_trace(MightNeedReplayState);
                    false -> MightNeedReplayState
                end,
            Instruction = dict:fetch(SelectedLid, TraceTop#trace_state.nexts),
            NewDone = ordsets:add_element(SelectedLid, Done),
            NewTraceTop = TraceTop#trace_state{done = NewDone},
            NewState = State#dpor_state{trace = [NewTraceTop|RestTrace]},
            {ok, Instruction, NewState}
    end.

replay_trace(#dpor_state{proc_before = ProcBefore,
                         run_count = RunCnt,
                         target = Target} = State) ->
    ?f_debug("\nReplay (~p) is required...\n", [RunCnt + 1]),
    [#trace_state{lid_trace = LidTrace}|_] = State#dpor_state.trace,
    concuerror_lid:stop(),
    proc_cleanup(processes() -- ProcBefore),
    start_target_op(Target),
    replay_lid_trace(LidTrace),
    ?f_debug("Done replaying...\n\n"),
    State#dpor_state{run_count = RunCnt + 1, must_replay = false}.

replay_lid_trace(Queue) ->
    replay_lid_trace(0, Queue).

replay_lid_trace(N, Queue) ->
    {V, NewQueue} = queue:out(Queue),
    case V of
        {value, {{_Lid,  block, _},               _}} ->
            replay_lid_trace(N, NewQueue);
        {value, {{Lid, Command, _} = Transition, VC}} ->
            ?f_debug(" ~-4w: ~P",[N, Transition, ?DEPTH]),
            _ = wait_next(Lid, Command),
            ?f_debug("."),
            _ = handle_instruction_op(Transition),
            ?f_debug("."),
            _ = replace_messages(Lid, VC),
            ?f_debug("\n"),
            replay_lid_trace(N+1, NewQueue);
        empty ->
            ok
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

may_have_dependencies({_Lid, {error, _}, []}) -> false;
may_have_dependencies({_Lid, {Spawn, _}, []})
  when Spawn =:= spawn; Spawn =:= spawn_link; Spawn =:= spawn_monitor;
       Spawn =:= spawn_opt -> false;
may_have_dependencies({_Lid, {'receive', {unblocked, _, _}}, []}) -> false;
may_have_dependencies({_Lid, exited, []}) -> false;
may_have_dependencies(_Else) -> true.

-spec lock_release_atom() -> '_._concuerror_lock_release'.

lock_release_atom() -> '_._concuerror_lock_release'.

dependent(A, B) ->
    dependent(A, B, true, true).

dependent({Lid, _Instr1, _Msgs1}, {Lid, _Instr2, _Msgs2}, true, true) ->
    %% No need to take care of same Lid dependencies
    false;

%% Register and unregister have the same dependencies.
%% Use a unique value for the Pid to avoid checks there.
dependent({Lid, {unregister, RegName}, Msgs}, B, true, true) ->
    dependent({Lid, {register, {RegName, make_ref()}}, Msgs}, B, true, true);
dependent(A, {Lid, {unregister, RegName}, Msgs}, true, true) ->
    dependent(A, {Lid, {register, {RegName, make_ref()}}, Msgs}, true, true);


%% Decisions depending on messages sent and receive statements:

%% Sending to the same process:
dependent({_Lid1, _Instr1, [_|_] = Msgs1} = Trans1,
          {_Lid2, _Instr2, [_|_] = Msgs2} = Trans2,
          true, true) ->
    Lids1 = ordsets:from_list(orddict:fetch_keys(Msgs1)),
    Lids2 = ordsets:from_list(orddict:fetch_keys(Msgs2)),
    case ordsets:intersection(Lids1, Lids2) of
        [] -> dependent(Trans1, Trans2, false, true);
        [Key] ->
            case {orddict:fetch(Key, Msgs1), orddict:fetch(Key, Msgs2)} of
                {[V1], [V2]} ->
                    LockReleaseAtom = lock_release_atom(),
                    V1 =/= LockReleaseAtom andalso V2 =/= LockReleaseAtom;
                _Else -> true
            end;
        _ -> true
    end;

%% Sending the message that triggered a receive's 'had_after'
dependent({Lid1,                             _Instr1, [_|_] = Msgs1} = Trans1,
          {Lid2, {'receive', {had_after, Lid1, Msg}},        _Msgs2} = Trans2,
          ChkMsg, Swap) ->
    %% TODO: Add CV to the send messages?
    Dependent =
        case orddict:find(Lid2, Msgs1) of
            {ok, MsgsToLid2} -> lists:member(Msg, MsgsToLid2);
            error -> false
        end,
    case Dependent of
        true -> true;
        false ->
            case Swap of
                true -> dependent(Trans2, Trans1, ChkMsg, false);
                false -> false
            end
    end;

%% Sending to an activated after clause depends on that receive's patterns
dependent({_Lid1,        _Instr1, [_|_] = Msgs1} = Trans1,
          { Lid2, {'after', Fun},        _Msgs2} = Trans2,
          ChkMsg, Swap) ->
    Dependent =
        case orddict:find(Lid2, Msgs1) of
            {ok, MsgsToLid2} -> lists:any(Fun, MsgsToLid2);
            error -> false
        end,
    case Dependent of
        true -> true;
        false ->
            case Swap of
                true -> dependent(Trans2, Trans1, ChkMsg, false);
                false -> false
            end
    end;


%% ETS operations live in their own small world.
dependent({_Lid1, {ets, Op1}, _Msgs1},
          {_Lid2, {ets, Op2}, _Msgs2},
          _ChkMsg, true) ->
    dependent_ets(Op1, Op2);

%% Registering a table with the same name as an existing one.
dependent({_Lid1, { ets, {   new,           [_Table, Name, Options]}}, _Msgs1},
          {_Lid2, {exit, {normal, {{_Heirs, Tables}, _Name, _Links}}}, _Msgs2},
          _ChkMsg, _Swap) ->
    NamedTables = [N || {_Lid, {ok, N}} <- Tables],
    lists:member(named_table, Options) andalso
        lists:member(Name, NamedTables);

%% Table owners exits mess things up.
dependent({_Lid1, { ets, {   _Op,                     [Table|_Rest]}}, _Msgs1},
          {_Lid2, {exit, {normal, {{_Heirs, Tables}, _Name, _Links}}}, _Msgs2},
          _ChkMsg, _Swap) ->
    lists:keymember(Table, 1, Tables);

%% Heirs exit should also be monitored.
%% Links exit should be monitored to be sure that messages are captured.
dependent({Lid1, {exit, {normal, {{Heirs1, _Tbls1}, _Name1, Links1}}}, _Msgs1},
          {Lid2, {exit, {normal, {{Heirs2, _Tbls2}, _Name2, Links2}}}, _Msgs2},
          _ChkMsg, true) ->
    lists:member(Lid1, Heirs2) orelse lists:member(Lid2, Heirs1) orelse
        lists:member(Lid1, Links2) orelse lists:member(Lid2, Links1);


%% Registered processes:

%% Sending using name to a process that may exit and unregister.
dependent({_Lid1, {send,                     {TName, _TLid, _Msg}}, _Msgs1},
          {_Lid2, {exit, {normal, {_Tables, {ok, TName}, _Links}}}, _Msgs2},
          _ChkMsg, _Swap) ->
    true;

%% Send using name before process has registered itself (or after ungeristering).
dependent({_Lid1, {register,      {RegName, _TLid}}, _Msgs1},
          {_Lid2, {    send, {RegName, _Lid, _Msg}}, _Msgs2},
          _ChkMsg, _Swap) ->
    true;

%% Two registers using the same name or the same process.
dependent({_Lid1, {register, {RegName1, TLid1}}, _Msgs1},
          {_Lid2, {register, {RegName2, TLid2}}, _Msgs2},
          _ChkMsg, true) ->
    RegName1 =:= RegName2 orelse TLid1 =:= TLid2;

%% Register a process that may exit.
dependent({_Lid1, {register, {_RegName, TLid}}, _Msgs1},
          { TLid, {    exit,  {normal, _Info}}, _Msgs2},
          _ChkMsg, _Swap) ->
    true;

%% Register for a name that might be in use.
dependent({_Lid1, {register,                           {Name, _TLid}}, _Msgs1},
          {_Lid2, {    exit, {normal, {_Tables, {ok, Name}, _Links}}}, _Msgs2},
          _ChkMsg, _Swap) ->
    true;

%% Whereis using name before process has registered itself.
dependent({_Lid1, {register, {RegName, _TLid1}}, _Msgs1},
          {_Lid2, { whereis, {RegName, _TLid2}}, _Msgs2},
          _ChkMsg, _Swap) ->
    true;

%% Process alive and exits
dependent({_Lid1, {is_process_alive,            TLid}, _Msgs1},
          { TLid, {            exit, {normal, _Info}}, _Msgs2},
          _ChkMsg, _Swap) ->
    true;

%% Process registered and exits
dependent({_Lid1, {whereis,                          {Name, _TLid1}}, _Msgs1},
          {_Lid2, {   exit, {normal, {_Tables, {ok, Name}, _Links}}}, _Msgs2},
          _ChkMsg, _Swap) ->
    true;

%% Monitor/Demonitor and exit.
dependent({_Lid, {Linker,            TLid}, _Msgs1},
          {TLid, {  exit, {normal, _Info}}, _Msgs2},
          _ChkMsg, _Swap)
  when Linker =:= demonitor; Linker =:= link; Linker =:= unlink ->
    true;

dependent({_Lid, {monitor, {TLid, _MonRef}}, _Msgs1},
          {TLid, {   exit, {normal, _Info}}, _Msgs2},
          _ChkMsg, _Swap) ->
    true;

%% Trap exits flag and linked process exiting.
dependent({Lid1, {process_flag,        {trap_exit, _Value, Links1}}, _Msgs1},
          {Lid2, {        exit, {normal, {_Tables, _Name, Links2}}}, _Msgs2},
          _ChkMsg, _Swap) ->
    lists:member(Lid2, Links1) orelse lists:member(Lid1, Links2);

%% Swap the two arguments if the test is not symmetric by itself.
dependent(TransitionA, TransitionB, ChkMsgs, true) ->
    dependent(TransitionB, TransitionA, ChkMsgs, false);
dependent(_TransitionA, _TransitionB, _ChkMsgs, false) ->
    false.


%% ETS table dependencies:

dependent_ets(Op1, Op2) ->
    dependent_ets(Op1, Op2, false).

dependent_ets({insert, [T, _, Keys1, KP, Objects1, true]},
              {insert, [T, _, Keys2, KP, Objects2, true]}, false) ->
    case ordsets:intersection(Keys1, Keys2) of
        [] -> false;
        Keys ->
            Fold =
                fun(_K, true) -> true;
                   (K, false) ->
                        lists:keyfind(K, KP, Objects1) =/=
                            lists:keyfind(K, KP, Objects2)
                end,
            lists:foldl(Fold, false, Keys)
    end;
dependent_ets({insert_new, [_, _, _, _, _, false]},
              {insert_new, [_, _, _, _, _, false]}, false) ->
    false;
dependent_ets({insert_new, [T, _, Keys1, KP, _Objects1, _Status1]},
              {insert_new, [T, _, Keys2, KP, _Objects2, _Status2]}, false) ->
    ordsets:intersection(Keys1, Keys2) =/= [];
dependent_ets({insert_new, [T, _, Keys1, KP, _Objects1, _Status1]},
              {insert, [T, _, Keys2, KP, _Objects2, true]}, _Swap) ->
    ordsets:intersection(Keys1, Keys2) =/= [];
dependent_ets({Insert, [T, _, Keys, _KP, _Objects1, true]},
              {lookup, [T, _, K]}, _Swap)
  when Insert =:= insert; Insert =:= insert_new ->
    ordsets:is_element(K, Keys);
dependent_ets({delete, [T, _]}, {_, [T|_]}, _Swap) ->
    true;
dependent_ets({new, [_Tid1, Name, Options1]},
              {new, [_Tid2, Name, Options2]}, false) ->
    lists:member(named_table, Options1) andalso
        lists:member(named_table, Options2);
dependent_ets(Op1, Op2, false) ->
    dependent_ets(Op2, Op1, true);
dependent_ets(_Op1, _Op2, true) ->
    false.


add_all_backtracks(#dpor_state{preemption_bound = PreBound,
                               trace = Trace} = State) ->
    case State#dpor_state.dpor_enabled of
        false ->
            %% add_some_next will take care of all the backtracks.
            State;
        true ->
            [#trace_state{last = Transition}|_] = Trace,
            case may_have_dependencies(Transition) of
                true ->
                    NewTrace =
                        add_all_backtracks_trace(Transition, Trace, PreBound),
                    State#dpor_state{trace = NewTrace};
                false -> State
            end
    end.

add_all_backtracks_trace({Lid, _, _} = Transition, Trace, PreBound) ->
    [#trace_state{i = I} = Top|
     [#trace_state{clock_map = ClockMap}|_] = PTrace] = Trace,
    ClockVector = dict:store(Lid, I, lookup_clock(Lid, ClockMap)),
    add_all_backtracks_trace(Transition, Lid, ClockVector,
                             PreBound, PTrace, [Top]).

add_all_backtracks_trace(_Transition, _Lid, _ClockVector,
                         _PreBound, [_] = Init, Acc) ->
    lists:reverse(Acc, Init);
add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound,
                         [#trace_state{preemptions = Preempt} = StateI|Trace],
                         Acc)
  when Preempt + 1 > PreBound ->
    add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound,
                             Trace, [StateI|Acc]);
add_all_backtracks_trace(Transition, Lid, ClockVector, PreBound,
                         [StateI|Trace], Acc) ->
    #trace_state{i = I,
                 last = {ProcSI, _, _} = SI,
                 clock_map = ClockMap} = StateI,
    Clock = lookup_clock_value(ProcSI, ClockVector),
    Action =
        case I > Clock andalso dependent(Transition, SI) of
            false -> {continue, Lid, ClockVector};
            true ->
                ?f_debug("~4w: ~p ~P Clock ~p\n",
                         [I, dependent(Transition, SI), SI, ?DEPTH, Clock]),
                [#trace_state{enabled = Enabled,
                              backtrack = Backtrack,
                              sleep_set = SleepSet} =
                     PreSI|Rest] = Trace,
                Candidates = ordsets:subtract(Enabled, SleepSet),
                Predecessors = predecessors(Candidates, I, ClockVector),
                Initial =
                    ordsets:del_element(ProcSI, find_initial(I, Acc)),
                ?f_debug("  Backtrack: ~w\n", [Backtrack]),
                ?f_debug("  Predecess: ~w\n", [Predecessors]),
                ?f_debug("  SleepSet : ~w\n", [SleepSet]),
                ?f_debug("  Initial  : ~w\n", [Initial]),
                case ordsets:intersection(Initial, Backtrack) =/= [] of
                    true ->
                        ?f_debug("One initial already in backtrack.\n"),
                        {done, Trace};
                    false ->
                        case {ordsets:is_element(Lid, SleepSet),Predecessors} of
                            {false, [P|_]} ->
                                NewBacktrack =
                                    ordsets:add_element(P, Backtrack),
                                ?f_debug("     Add: ~w\n", [P]),
                                NewPreSI =
                                    PreSI#trace_state{
                                      backtrack = NewBacktrack},
                                {done, [NewPreSI|Rest]};
                            _Else ->
                                ?f_debug("     All sleeping...\n"),
                                NewClockVector =
                                    lookup_clock(ProcSI, ClockMap),
                                {continue, ProcSI, NewClockVector}
                        end
                end
        end,
    case Action of
        {continue, NewLid, UpdClockVector} ->
            add_all_backtracks_trace(Transition, NewLid, UpdClockVector,
                                     PreBound, Trace, [StateI|Acc]);
        {done, FinalTrace} ->
            lists:reverse(Acc, [StateI|FinalTrace])
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

find_initial(I, RevTrace) ->
    Empty = ordsets:new(),
    find_initial(I, RevTrace, Empty, Empty).

find_initial(_I, [], Initial, _NotInitial) ->
    Initial;
find_initial(I, [TraceTop|Rest], Initial, NotInitial) ->
    #trace_state{last = {P,_,_}, clock_map = ClockMap} = TraceTop,
    Add =
        case ordsets:is_element(P, Initial) orelse
            ordsets:is_element(P, NotInitial) of
            true -> false;
            false ->
                Clock = lookup_clock(P, ClockMap),
                case has_dependency_after(Clock, P, I) of
                    true -> not_initial;
                    false -> initial
                end
        end,
    case Add of
        false -> find_initial(I, Rest, Initial, NotInitial);
        initial ->
            NewInitial = ordsets:add_element(P, Initial),
            find_initial(I, Rest, NewInitial, NotInitial);
        not_initial ->
            NewNotInitial = ordsets:add_element(P, NotInitial),
            find_initial(I, Rest, Initial, NewNotInitial)            
    end.

has_dependency_after(Clock, P, I) ->
    Fold =
        fun(_Key, _Value, true) -> true;
           (Key, Value, false) -> P =/= Key andalso Value >= I
        end,
    dict:fold(Fold, false, Clock).                

predecessors(Candidates, I, ClockVector) ->
    Fold =
        fun(Lid, Acc) ->
                Clock = lookup_clock_value(Lid, ClockVector),
                ?f_debug("  ~p: ~p\n",[Lid, Clock]),
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
                dpor_enabled = Dpor} = State,
    #trace_state{i = I, enabled = Enabled, blocked = Blocked,
                 pollable = Pollable, done = Done,
                 nexts = Nexts, lid_trace = LidTrace,
                 clock_map = ClockMap, sleep_set = SleepSet,
                 preemptions = Preemptions, last = {LLid,_,_}} = PrevTraceTop,
    NewN = I+1,
    ClockVector = lookup_clock(Lid, ClockMap),
    ?f_debug("Happened before: ~p\n", [dict:to_list(ClockVector)]),
    BaseClockVector = dict:store(Lid, NewN, ClockVector),
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
    BaseMessages = orddict:from_list(replace_messages(Lid, UpdatedClockVector)),
    Messages = dead_process_send(RewrittenInstr, BaseMessages),
    PossiblyRewrittenSelected = {Lid, RewrittenInstr, Messages},
    ?f_debug("Selected: ~P\n",[PossiblyRewrittenSelected, ?DEPTH]),
    NewBaseLidTrace =
        queue:in({PossiblyRewrittenSelected, UpdatedClockVector}, LidTrace),
    NewLidTrace =
        case ordsets:is_element(Lid, NewBlocked) of
            false -> NewBaseLidTrace;
            true ->
                ?f_debug("Blocking ~p\n",[Lid]),
                queue:in({{Lid, block, []}, UpdatedClockVector}, NewBaseLidTrace)
        end,
    NewTraceTop = check_pollable(InstrNewTraceTop),
    NewSleepSet =
        case Dpor of
            false -> [];
            true  ->
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
                    case dependent(Transition, Transition2) of
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
                Dep = dependent(Instr, Selected),
                ?f_debug(" vs ~p: ~p\n",[Instr, Dep]),
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
    Variables = handle_instruction_op(Transition),
    handle_instruction_al(Transition, TraceTop, Variables).

handle_instruction_op({Lid, {Spawn, _Info}, _Msgs})
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
    {Info, ChildNextInstr};
handle_instruction_op({Lid, {ets, {Updatable, _Info}}, _Msgs})
  when Updatable =:= new; Updatable =:= insert_new ->
    receive
        %% This is the replaced message
        #sched{msg = ets, lid = Lid, misc = {Updatable, Info}, type = prev} ->
            Info
    end;
handle_instruction_op({Lid, {Updatable, _Info}, _Msgs})
  when Updatable =:= exit; Updatable =:= send; Updatable =:= whereis;
       Updatable =:= monitor; Updatable =:= 'receive';
       Updatable =:= process_flag ->
    receive
        #sched{msg = Updatable, lid = Lid, misc = Info, type = prev} ->
            Info
    end;
handle_instruction_op(_) ->
    {}.

handle_instruction_al({Lid, {exit, _OldInfo}, Msgs}, TraceTop, Info) ->
    #trace_state{enabled = Enabled, nexts = Nexts} = TraceTop,
    NewEnabled = ordsets:del_element(Lid, Enabled),
    NewNexts = dict:erase(Lid, Nexts),
    NewLast = {Lid, {exit, Info}, Msgs},
    TraceTop#trace_state{enabled = NewEnabled, nexts = NewNexts,
                         last = NewLast};
handle_instruction_al({Lid, {Spawn, _OldInfo}, Msgs}, TraceTop,
                      {Info, ChildNextInstr})
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
    NewLast = {Lid, {Spawn, Info}, Msgs},
    TraceTop#trace_state{last = NewLast,
                         clock_map = NewClockMap,
                         enabled = NewEnabled,
                         blocked = NewBlocked,
                         pollable = NewPollable,
                         nexts = NewNexts};
handle_instruction_al({Lid, {'receive', Tag}, Msgs},
                      TraceTop, {From, CV, Msg}) ->
    #trace_state{clock_map = ClockMap} = TraceTop,
    Vector = lookup_clock(Lid, ClockMap),
    NewLast = {Lid, {'receive', {Tag, From, Msg}}, Msgs},
    NewVector = max_cv(Vector, CV),
    NewClockMap = dict:store(Lid, NewVector, ClockMap),
    TraceTop#trace_state{last = NewLast, clock_map = NewClockMap};
handle_instruction_al({Lid, {ets, {Updatable, _Info}}, Msgs}, TraceTop, Info)
  when Updatable =:= new; Updatable =:= insert_new ->
    NewLast = {Lid, {ets, {Updatable, Info}}, Msgs},
    TraceTop#trace_state{last = NewLast};
handle_instruction_al({Lid, {Updatable, _Info}, Msgs}, TraceTop, Info)
  when Updatable =:= send; Updatable =:= whereis; Updatable =:= monitor;
       Updatable =:= process_flag ->
    NewLast = {Lid, {Updatable, Info}, Msgs},
    TraceTop#trace_state{last = NewLast};
handle_instruction_al({_Lid, {halt, _Status}, _Msgs}, TraceTop, {}) ->
    TraceTop#trace_state{enabled = [], blocked = [], error_nxt = none};
handle_instruction_al(_Transition, TraceTop, {}) ->
    TraceTop.

max_cv(D1, D2) ->
    Merger = fun(_Key, V1, V2) -> max(V1, V2) end,
    dict:merge(Merger, D1, D2).

dead_process_send({send, {_, TLid, Msg}}, Messages) ->
    case orddict:is_key(TLid, Messages) of
        true -> Messages;
        false -> orddict:store(TLid, [Msg], Messages)
    end;
dead_process_send(_Else, Messages) ->
    Messages.

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
    #dpor_state{trace = [TraceTop|Rest], dpor_enabled = Dpor,
                preemption_bound = PreBound} = State,
    #trace_state{enabled = Enabled, sleep_set = SleepSet,
                 error_nxt = ErrorNext, last = {Lid, _, _},
                 preemptions = Preemptions} = TraceTop,
    ?f_debug("Pick next: Enabled: ~w Sleeping: ~w\n", [Enabled, SleepSet]),
    Backtrack =
        case ErrorNext of
            none ->
                case Dpor of
                    false ->
                        case ordsets:is_element(Lid, Enabled) of
                            true when Preemptions =:= PreBound ->
                                [Lid];
                            _Else -> Enabled
                        end;
                    true ->
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
    ?f_debug("Picked: ~w\n",[Backtrack]),
    NewTraceTop = TraceTop#trace_state{backtrack = Backtrack},
    State#dpor_state{trace = [NewTraceTop|Rest]}.

report_error(Transition, State) ->
    #dpor_state{trace = [TraceTop|_], tickets = Tickets} = State,
    ?f_debug("ERROR!\n~P\n",[Transition, ?DEPTH]),
    Error = convert_error_info(Transition),
    LidTrace = queue:in({Transition, foo}, TraceTop#trace_state.lid_trace),
    Ticket = create_ticket(Error, LidTrace),
    State#dpor_state{must_replay = true, tickets = [Ticket|Tickets]}.

create_ticket(Error, LidTrace) ->
    InitTr = init_tr(),
    [{P1, init, []} = InitTr|Trace] = [S || {S,_V} <- queue:to_list(LidTrace)],
    InitSet = sets:add_element(P1, sets:new()),
    {ErrorState, _Procs} =
        lists:mapfoldl(fun convert_error_trace/2, InitSet, Trace),
    Ticket = concuerror_ticket:new(Error, ErrorState),
    %% Report the error to the progress logger.
    concuerror_log:progress(Ticket),
    Ticket.

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
    #dpor_state{trace = [TraceTop|Trace], tickets = Tickets} = State,
    NewTickets =
        case TraceTop#trace_state.enabled of
            [] ->
                case TraceTop#trace_state.blocked of
                    [] ->
                        ?f_debug("NORMAL!\n"),
                        %% Report that we finish an interleaving
                        %% without errors in the progress logger.
                        concuerror_log:progress(ok),
                        Tickets;
                    Blocked ->
                        ?f_debug("DEADLOCK!\n"),
                        Error = {deadlock, Blocked},
                        LidTrace = TraceTop#trace_state.lid_trace,
                        Ticket = create_ticket(Error, LidTrace),
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
