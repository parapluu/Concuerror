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
%% action  : The last action performed (proc_action:proc_action()).
%% error   : A term describing the error that occurred.
%% state   : The current state of the program.
-record(context, {active         :: ?SET_TYPE(lid:lid()),
                  blocked        :: ?SET_TYPE(lid:lid()),
                  current        :: lid:lid(),
                  action         :: proc_action:proc_action(),
                  error          :: ?NO_ERROR | error:error(),
                  state          :: state:state()}).

%% Internal message format
%%
%% msg    : An atom describing the type of the message.
%% pid    : The sender's LID.
%% misc   : Optional arguments, depending on the message type.
-record(sched, {msg  :: atom(),
                lid  :: lid:lid(),
                misc  = empty :: term()}).

%% Special internal message format (fields same as above).
-record(special, {msg :: atom(),
                  lid :: lid:lid() | 'not_found',
                  misc = empty :: term()}).

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type analysis_info() :: {analysis_target(), non_neg_integer()}.

-type analysis_options() :: [{'preb', bound()} |
                             {'include', [file()]} |
                             {'define', [{atom(), atom()}]}].


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

%% @spec: analyze(analysis_target(), [file()], analysis_options()) ->
%%          analysis_ret()
%% @doc: Produce all interleavings of running `Target'.
-spec analyze(analysis_target(), [file()], analysis_options()) ->
            analysis_ret().

analyze(Target, Files, Options) ->
    PreBound =
        case lists:keyfind(preb, 1, Options) of
            {preb, inf} -> ?INFINITY;
            {preb, Bound} -> Bound;
            false -> ?INFINITY
        end,
    Ret =
        case instr:instrument_and_compile(Files) of
            {ok, Bin} ->
                %% Note: No error checking for load
                ok = instr:load(Bin),
                log:log("Running analysis...~n~n"),
                {T1, _} = statistics(wall_clock),
                Result = interleave(Target, PreBound),
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
interleave(Target, PreBound) ->
    Self = self(),
    spawn_link(fun() -> interleave_aux(Target, PreBound, Self) end),
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
            Context = #context{active=Active, state=State, blocked=Blocked},
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
        true -> driver_normal(Context, []);
        false -> driver_replay(Context, ReplayState, [])
    end.

driver_replay(Context, ReplayState, Actions) ->
    {Next, Rest} = state:trim_head(ReplayState),
    NewContext = run(Context#context{current = Next, error = ?NO_ERROR}),
    #context{blocked = NewBlocked, action = Action} = NewContext,
    case state:is_empty(Rest) of
        true ->
            case ?SETS:is_element(Next, NewBlocked) of
                %% If the last action of the replayed state prefix is a block,
                %% we can safely abort.
                true -> abort;
                %% Replay has finished; proceed in normal mode, after checking
                %% for errors during the last replayed action.
                false -> check_for_errors(NewContext, Actions)
            end;
        false ->
            case ?SETS:is_element(Next, NewBlocked) of
                true -> log:internal("Proc. ~p should be active.", [Next]);
                false -> driver_replay(NewContext, Rest, [Action|Actions])
            end
    end.

driver_normal(#context{active=Active, current=LastLid,
                       state = State} = Context, Actions) ->
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
    check_for_errors(NewContext, Actions).

%% Handle four possible cases:
%% - An error occured during the execution of the last process =>
%%   Terminate the run and report the erroneous interleaving sequence.
%% - Only blocked processes exist =>
%%   Terminate the run and report a deadlock.
%% - No active or blocked processes exist =>
%%   Terminate the run without errors.
%% - There exists at least one active process =>
%%   Continue run.
check_for_errors(#context{error=NewError, action=Action, active=NewActive,
                          blocked=NewBlocked} = NewContext, Actions) ->
    NewActions = [Action | Actions],
    case NewError of
        ?NO_ERROR ->
            case ?SETS:size(NewActive) of
                0 ->
                    case ?SETS:size(NewBlocked) of
                        0 -> ok;
                        _NonEmptyBlocked ->
                            Deadlock = error:new({deadlock, NewBlocked}),
                            ErrorState = lists:reverse(NewActions),
                            {error, Deadlock, ErrorState}
                    end;
                _NonEmptyActive -> driver_normal(NewContext, NewActions)
            end;
        _Other ->
            ErrorState = lists:reverse(NewActions),
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

handler('after', Lid, Context, _Misc) ->
    Action = {'after', Lid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

%% Move the process to the blocked set.
handler(block, Lid,
        #context{active = Active, blocked = Blocked} = Context,
        _Misc) ->
    Action = {'block', Lid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:del_element(Lid, Active),
    NewBlocked = ?SETS:add_element(Lid, Blocked),
    Context#context{active = NewActive, blocked = NewBlocked, action = Action};

handler(demonitor, Lid, Context, _Ref) ->
    %% TODO: Get LID from Ref?
    TargetLid = lid:mock(0),
    Action = {demonitor, Lid, TargetLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

%% Remove the exited process from the active set.
%% NOTE: This is called after a process has exited, not when it calls
%%       exit/1 or exit/2.
handler(exit, Lid, #context{active = Active} = Context,
        Reason) ->
    NewActive = ?SETS:del_element(Lid, Active),
    %% Cleanup LID stored info.
    lid:cleanup(Lid),
    %% Handle and propagate errors.
    case Reason of
        normal ->
            Action = {exit, Lid, normal},
            ?debug_1(proc_action:to_string(Action) ++ "~n"),
            Context#context{active = NewActive, action = Action};
        _Else ->
            Error = error:new(Reason),
            Action = {exit, Lid, error:type(Error)},
            ?debug_1(proc_action:to_string(Action) ++ "~n"),
            Context#context{active = NewActive, error = Error, action = Action}
    end;

%% Return empty active and blocked queues to force run termination.
handler(halt, Lid, Context, Misc) ->
    Action =
        case Misc of
            empty -> {halt, Lid};
            Status -> {halt, Lid, Status}
        end,
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{active=?SETS:new(), blocked=?SETS:new(), action=Action};

handler(is_process_alive, Lid, Context, TargetPid) ->
    TargetLid = lid:from_pid(TargetPid),
    Action = {is_process_alive, Lid, TargetLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

handler(link, Lid, Context, TargetPid) ->
    TargetLid = lid:from_pid(TargetPid),
    Action = {link, Lid, TargetLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

handler(monitor, Lid, Context, {Item, _Ref}) ->
    TargetLid = lid:from_pid(Item),
    Action = {monitor, Lid, TargetLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

handler(process_flag, Lid, Context, {Flag, Value}) ->
    Action = {process_flag, Lid, Flag, Value},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

%% Normal receive message handler.
handler('receive', Lid, Context, {From, Msg}) ->
    Action = {'receive', Lid, From, Msg},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

%% Receive message handler for special messages, like 'EXIT' and 'DOWN',
%% which don't have an associated sender process.
handler('receive_no_instr', Lid, Context, Msg) ->
    Action = {'receive_no_instr', Lid, Msg},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

handler(register, Lid, Context, {RegName, RegLid}) ->
    Action = {register, Lid, RegName, RegLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

handler(send, Lid, Context, {DstPid, Msg}) ->
    DstLid = lid:from_pid(DstPid),
    Action = {send, Lid, DstLid, Msg},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

%% Link the newly spawned process to the scheduler process and add it to the
%% active set.
handler(spawn, ParentLid, #context{active = Active} = Context, ChildPid) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    Action = {spawn, ParentLid, ChildLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive, action = Action};

%% FIXME: Refactor this (it's exactly the same as 'spawn')
handler(spawn_link, ParentLid, #context{active = Active} = Context, ChildPid) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    Action = {spawn_link, ParentLid, ChildLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive, action = Action};

%% FIXME: Refactor this (it's almost the same as 'spawn')
handler(spawn_monitor, ParentLid,
        #context{active = Active} = Context, {ChildPid, _Ref}) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    Action = {spawn_monitor, ParentLid, ChildLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive, action = Action};

%% Similar to above depending on options.
handler(spawn_opt, ParentLid,
        #context{active = Active} = Context, {Ret, Opt}) ->
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
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive, action = Action};

handler(unlink, Lid, Context, TargetPid) ->
    TargetLid = lid:from_pid(TargetPid),
    Action = {unlink, Lid, TargetLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

handler(unregister, Lid, Context, RegName) ->
    Action = {unregister, Lid, RegName},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

handler(whereis, Lid, Context, {RegName, Result}) ->
    ResultLid = lid:from_pid(Result),
    Action = {whereis, Lid, RegName, ResultLid},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action};

%% Handler for anything "non-special". It just passes the arguments
%% for logging.
%% TODO: We may be able to delete some of the above that can be handled
%%       by this generic handler.
handler(CallMsg, Lid, Context, Args) ->
    Action = {CallMsg, Lid, Args},
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    Context#context{action = Action}.

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
