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

-export_type([analysis_target/0, analysis_ret/0, bound/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

-define(INFINITY, 1000000).
-define(NO_ERROR, undef).

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
    Flanagan = lists:member({flanagan}, Options),
    Ret =
        case instr:instrument_and_compile(Files, Include, Define, Flanagan) of
            {ok, Bin} ->
                %% Note: No error checking for load
                ok = instr:load(Bin),
                log:log("Running analysis...~n~n"),
                {T1, _} = statistics(wall_clock),
                Result = interleave(Target, PreBound, Flanagan),
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
interleave(Target, PreBound, Flanagan) ->
    Self = self(),
    Fun = 
        fun() ->
                case Flanagan of
                    true -> interleave_flanagan(Target, PreBound, Self);
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

interleave_flanagan(Target, PreBound, Parent) ->
    log:log("Flanagan is not really ready yet...\n"),
    register(?RP_SCHED, self()),
    Result = interleave_flanagan(Target, PreBound),
    Parent ! {interleave_result, Result}.


interleave_outer_loop(_T, RunCnt, Tickets, MaxBound, MaxBound) ->
    log:log("Context bound reached\n"),
    interleave_outer_loop_ret(Tickets, RunCnt);
interleave_outer_loop(Target, RunCnt, Tickets, CurrBound, MaxBound) ->
    log:log("Context bound: ~p\n",[CurrBound + 1]),
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

-type s_i()        :: non_neg_integer().
-type instr()      :: term().
-type transition() :: 'init' | {lid:lid(), instr()}.
-type clock_map()  :: dict(). %% dict(lid:lid(), clock_vector()).
%% -type clock_vector() :: dict(). %% dict(lid:lid() | s_i(), s_i()).

-record(trace_state, {
	  i         = 0                 :: s_i(),
	  last                          :: transition(),
	  enabled   = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
          blocked   = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
	  next      = dict:new()        :: dict(), %% dict(lid:lid(), instr()),
	  backtrack = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
	  done      = ordsets:new()     :: ordsets:ordset(), %% set(lid:lid()),
	  clock_map = empty_clock_map() :: clock_map()
	 }).

-type trace_state() :: #trace_state{}.

-record(flanagan_state, {
	  tickets     = []          :: [ticket:ticket()],
	  trace       = []          :: [trace_state()],
	  must_replay = false       :: boolean(),
	  quick_trace = queue:new() :: queue() %% queue(lid:lid()),
	 }).

empty_clock_map() -> dict:new().

interleave_flanagan(Target, _PreBound) ->
    {ok, 0}.

explore(MightNeedReplayState) ->
    NewState = 
        case select_from_backtrack(MightNeedReplayState) of
            {ok, Selected, State} ->
                case wait_next(Selected) of
                    {ok, Next} ->
                        LocalAddState = add_local_backtracks(Selected, State),
                        AllAddState = add_all_backtracks(Next, LocalAddState),
                        UpdState = update_trace(Selected, Next, AllAddState),
                        add_some_next_to_backtrack(UpdState);
                    {error, ErrorInfo} ->
                        report_error(Selected, ErrorInfo, State)
                end;
            none ->
                report_no_actives(MightNeedReplayState)
        end,
    explore(NewState).

select_from_backtrack(#flanagan_state{trace = Trace} = MightNeedReplayState) ->
    %% FIXME: Pick first and don't really subtract.
    [TraceTop|RestTrace] = Trace,
    Backtrack = TraceTop#trace_state.backtrack,
    Done = TraceTop#trace_state.done,
    case ordsets:subtract(Backtrack, Done) of
	[SelectedLid|_RestLids] ->
            State =
                case MightNeedReplayState#flanagan_state.must_replay of
                    true -> replay_trace(MightNeedReplayState);
                    false -> MightNeedReplayState
                end,
	    Instruction = dict:fetch(SelectedLid, TraceTop#trace_state.next),
            NewDone = ordsets:add_element(SelectedLid, Done),
            NewTraceTop = TraceTop#trace_state{done = NewDone},
            NewState = State#flanagan_state{trace = [NewTraceTop|RestTrace]},
	    {ok, {SelectedLid, Instruction}, NewDone};
	[] -> none
    end.

add_local_backtracks(Transition, #flanagan_state{trace = Trace} = State) ->
    [TraceTop|RestTrace] = Trace,
    #trace_state{backtrack = Backtrack, next = Next, clock_map = ClockMap} =
        TraceTop,
    NewBacktrack = add_local_backtracks(Transition, Next, ClockMap, Backtrack),
    NewTrace = [TraceTop#trace_state{backtrack = NewBacktrack}|RestTrace],
    State#flanagan_state{trace = NewTrace}.

add_local_backtracks({NLid, _} = Transition, Next, ClockMap, Backtrack) ->
    Fold =
        fun(Lid, Instruction, AccBacktrack) ->
            Add =
                case dependent(Transition, {Lid, Instruction}) of
                    false -> false;
                    true -> NLid =/= Lid
                end,
            case Add of
                true -> ordsets:add_element(Lid, AccBacktrack);
                false -> AccBacktrack
            end
        end,
    dict:fold(Fold, Backtrack, Next).

%% STUB
dependent(TransitionA, TransitionB) -> true.

%% - add new entry with new entry
%% - wait next of current process
%% - wait any possible additional messages
%% - check for async
update_trace(Selected, Next, State) ->
    UpdatedState = handle_instruction(Selected, State),
    UpdatedState.

%% STUB
replay_trace(State) ->
    State.

wait_next(Lid) ->
    ok = resume(Lid),
    receive
        #sched{msg = Type, lid = Lid, misc = Misc, type = next} ->
            case Type of
                error -> {error, Misc};
                _Else -> {ok, {Lid, {Type, Misc}}}
            end
    end.

resume(Lid) ->
    Pid = lid:get_pid(Lid),
    Pid ! #sched{msg = continue},
    ok.

%% STUB
handle_instruction({Lid, {spawn, Opts}}, State) ->
    %% Parent = Lid,
    %% [TraceTop|RestTrace] = Trace,
    %% #trace_state{i = N, next = Next, clock_map = ClockMap} = TraceTop,
    %% NewStep = #trace_state{i = N+1, last = Transition},

    %% #flanagan_state{trace = [TraceTop|RestTrace]
    %% ChildPid =
    %%     receive
    %%         #sched{msg = spawned, lid = Parent, misc = Pid, type = prev} ->
    %%             Pid
    %%     end,
    %% ChildNextInstr =
    %%     receive
    %%         #sched{msg = Next, lid = ChildPid, misc = Misc, type = next} ->
    %%             {Next, Misc}
    %%     end,
    
    State.

%% STUB
add_all_backtracks(Transition, State) ->
    State.

%% STUB
add_some_next_to_backtrack(State) ->
    State.

%% STUB
report_error(Transition, ErrorInfo, State) ->
    State.

%% STUB
report_no_actives(State) ->
    State.

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
            log:log("Running interleaving ~p~n", [RunCnt]),
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
        false ->
            log:log("Replay..."),
            driver_replay(Context, ReplayState)
    end.

driver_replay(Context, ReplayState) ->
    {Next, Rest} = state:trim_head(ReplayState),
    NewContext = run(Context#context{current = Next, error = ?NO_ERROR}),
    #context{blocked = NewBlocked} = NewContext,
    case state:is_empty(Rest) of
        true ->
            log:log("done\n"),
            case ?SETS:is_element(Next, NewBlocked) of
                %% If the last action of the replayed state prefix is a block,
                %% we can safely abort.
                true ->
                    log:log("I am a hidden interleaving! :-P\n"),
                    abort;
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
                log:log("Can continue with LastLid\n"),
                TmpActive = ?SETS:to_list(?SETS:del_element(LastLid, Active)),
                {LastLid,TmpActive, next};
            false ->
                [Head|TmpActive] = ?SETS:to_list(Active),
                log:log("Can NOT continue with LastLid. Pick ~p.\n",[Head]),
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
                            {error, Deadlock, ErrorState}
                    end;
                _NonEmptyActive -> driver_normal(NewContext)
            end;
        _Other ->
            ErrorState = lists:reverse(Actions),
            {error, NewError, ErrorState}
    end.

run_no_block(#context{state = State} = Context, {Next, Rest, W}) ->
    NewContext = run(Context#context{current = Next, error = ?NO_ERROR}),
    #context{blocked = NewBlocked} = NewContext,
    case ?SETS:is_element(Next, NewBlocked) of
        true ->
            case Rest of
                [] ->
                    log:log("Got blocked. Nothing remains\n"),
                    {NewContext#context{state = State}, {[], W}};
                [RH|RT] ->
                    log:log("Got blocked. Picking another.\n"),
                    NextContext = NewContext#context{state = State},
                    run_no_block(NextContext, {RH, RT, current})
            end;
        false ->
            log:log("Did not get blocked.\n"),
            {NewContext, {Rest, W}}
    end.

insert_states(State, {Lids, current}) ->
    log:log("Add ~w to current context bound.\n",[Lids]),
    Extend = lists:map(fun(L) -> state:extend(State, L) end, Lids),
    state_save(Extend);
insert_states(State, {Lids, next}) ->
    log:log("Add ~w to next context bound.\n",[Lids]),
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
continue(Pid) when is_pid(Pid) ->
    Pid ! #sched{msg = continue},
    ok;
continue(Lid) ->
    Pid = lid:get_pid(Lid),
    Pid ! #sched{msg = continue},
    ok.

%% Notify the scheduler of an event.
%% If the calling user process has an associated LID, then send
%% a notification and yield. Otherwise, for an unknown process
%% running instrumented code completely ignore this call.
-spec notify(notification(), any()) -> 'ok'.

notify(Msg, Misc) ->
    case lid_from_pid(self()) of
        not_found -> ok;
        Lid ->
            ?RP_SCHED_SEND ! #sched{msg = Msg, lid = Lid, misc = Misc},
            wait()
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
    receive
        #sched{msg = continue} -> ok
    end.
