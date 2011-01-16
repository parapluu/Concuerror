%%%----------------------------------------------------------------------
%%% File        : sched.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Scheduler
%%% Created     : 16 May 2010
%%%
%%% @doc: Scheduler
%%% @end
%%%----------------------------------------------------------------------

-module(sched).

%% UI related exports
-export([analyze/2, replay/1]).

%% Internal exports
-export([block/0, notify/2, wait/0, wakeup/0, yield/0]).

-export_type([analysis_target/0, analysis_ret/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Debug
%%%----------------------------------------------------------------------

%%-define(TTY, true).
-ifdef(TTY).
-define(tty(), ok).
-else.
-define(tty(), error_logger:tty(false)).
-endif.

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
%% details : A boolean being false when running a normal run and
%%           true when running a replay and need to send detailed
%%           info to the replay_logger.
%% error   : A term describing the error that occurred.
%% state   : The current state of the program.
-record(context, {active         :: ?SET_TYPE(lid:lid()),
                  blocked        :: ?SET_TYPE(lid:lid()),
		  current        :: lid:lid(),
		  details        :: boolean(),
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

-type analysis_options() :: ['details' |
			     {'files', [file()]} |
			     {'init_state', state:state()} |
			     {'preb',  bound()}].

%% Analysis result tuple.
-type analysis_ret() :: {'ok', analysis_info()} |
                        {'error', 'instr', analysis_info()} |
                        {'error', 'analysis', analysis_info(),
			 [ticket:ticket()]}.

%% Module-Function-Arguments tuple.
-type analysis_target() :: {module(), atom(), [term()]}.

-type bound() :: 'inf' | non_neg_integer().

%% Scheduler notification.
-type notification() :: 'after' | 'demonitor' | 'fun_exit' | 'halt' | 'link' |
                        'monitor' | 'process_flag' | 'receive' | 'register' |
                        'spawn' | 'spawn_link' | 'spawn_monitor' |
                        'spawn_opt' | 'unlink' | 'unregister' | 'whereis'.

%%%----------------------------------------------------------------------
%%% User interface
%%%----------------------------------------------------------------------

%% @spec: analyze(analysis_target(), options()) -> analysis_ret()
%% @doc: Produce all interleavings of running `Target'.
-spec analyze(analysis_target(), analysis_options()) -> analysis_ret().

analyze(Target, Options) ->
    %% List of files to instrument.
    Files =
	case lists:keyfind(files, 1, Options) of
	    false -> [];
	    {files, List} -> List
	end,
    %% Disable error logging messages.
    ?tty(),
    Ret =
	case instr:instrument_and_load(Files) of
	    ok ->
		log:log("Running analysis...~n"),
		{T1, _} = statistics(wall_clock),
		ISOption = {init_state, state:empty()},
		Result = interleave(Target, [ISOption|Options]),
		{T2, _} = statistics(wall_clock),
		{Mins, Secs} = elapsed_time(T1, T2),
		case Result of
		    {ok, RunCount} ->
			log:log("Analysis complete (checked ~w interleavings "
				"in ~wm~.2fs):~n", [RunCount, Mins, Secs]),
			log:log("No errors found.~n"),
			{ok, {Target, RunCount}};
		    {error, RunCount, Tickets} ->
			TicketCount = length(Tickets),
			log:log("Analysis complete (checked ~w interleavings "
				"in ~wm~.2fs):~n", [RunCount, Mins, Secs]),
			log:log("Found ~p erroneous interleaving(s).~n",
				[TicketCount]),
			{error, analysis, {Target, RunCount}, Tickets}
		end;
	    error ->
		{error, instr, {Target, 0}}
	end,
    instr:delete_and_purge(Files),
    Ret.

%% @spec: replay(analysis_target(), state()) -> [proc_action()]
%% @doc: Replay the given state and return detailed information about the
%% process interleaving.
-spec replay(ticket:ticket()) -> [proc_action:proc_action()].

replay(Ticket) ->
    replay_logger:start(),
    replay_logger:start_replay(),
    Target = ticket:get_target(Ticket),
    State = ticket:get_state(Ticket),
    Files = ticket:get_files(Ticket),
    Options = [details, {init_state, State}, {files, Files}],
    instr:instrument_and_load(Files),
    interleave(Target, Options),
    instr:delete_and_purge(Files),
    Result = replay_logger:get_replay(),
    replay_logger:stop(),
    Result.

%% Produce all possible process interleavings of (Mod, Fun, Args).
%% Options:
%%   {init_state, InitState}: State to replay (default: state_init()).
%%   details: Produce detailed interleaving information (see `replay_logger`).
interleave(Target, Options) ->
    Self = self(),
    spawn_link(fun() -> interleave_aux(Target, Options, Self) end),
    receive
	{interleave_result, Result} -> Result
    end.

interleave_aux(Target, Options, Parent) ->
    register(?RP_SCHED, self()),
    %% The mailbox is flushed mainly to discard possible `exit` messages
    %% before enabling the `trap_exit` flag.
    util:flush_mailbox(),
    process_flag(trap_exit, true),
    %% Initialize state table.
    state_start(),
    %% Save empty replay state for the first run.
    {init_state, InitState} = lists:keyfind(init_state, 1, Options),
    state_save(InitState),
    PreBound =
	case lists:keyfind(preb, 1, Options) of
	    {preb, inf} -> ?INFINITY;
	    {preb, Bound} -> Bound;
	    false -> ?INFINITY
	end,
    Result = interleave_outer_loop(Target, 0, [], -1, PreBound, Options),
    state_stop(),
    unregister(?RP_SCHED),
    Parent ! {interleave_result, Result}.

interleave_outer_loop(_T, RunCnt, Tickets, MaxBound, MaxBound, _Opt) ->
    interleave_outer_loop_ret(Tickets, RunCnt);
interleave_outer_loop(Target, RunCnt, Tickets, CurrBound, MaxBound, Options) ->
    {NewRunCnt, NewTickets, Stop} = interleave_loop(Target, 1, [], Options),
    TotalRunCnt = NewRunCnt + RunCnt,
    TotalTickets = NewTickets ++ Tickets,
    state_swap(),
    case state_peak() of
	no_state -> interleave_outer_loop_ret(TotalTickets, TotalRunCnt);
	_State ->
            case Stop of
                true -> interleave_outer_loop_ret(TotalTickets, TotalRunCnt);
                false ->
                    interleave_outer_loop(Target, TotalRunCnt, TotalTickets,
                                          CurrBound + 1, MaxBound, Options)
            end
    end.

interleave_outer_loop_ret([], RunCnt) ->
    {ok, RunCnt};
interleave_outer_loop_ret(Tickets, RunCnt) ->
    {error, RunCnt, ticket:sort(Tickets)}.

%% Main loop for producing process interleavings.
%% The first process (FirstPid) is created linked to the scheduler,
%% so that the latter can receive the former's exit message when it
%% terminates. In the same way, every process that may be spawned in
%% the course of the program shall be linked to the scheduler process.
interleave_loop(Target, RunCnt, Tickets, Options) ->
    Det = lists:member(details, Options),
    %% Lookup state to replay.
    case state_load() of
        no_state -> {RunCnt - 1, Tickets, false};
        ReplayState ->
            ?debug_1("Running interleaving ~p~n", [RunCnt]),
            ?debug_1("----------------------~n"),
            lid:start(),
	    %% Spawn initial process.
	    {Mod, Fun, Args} = Target,
	    NewFun = fun() -> wait(), apply(Mod, Fun, Args) end,
            FirstPid = spawn_link(NewFun),
            FirstLid = lid:new(FirstPid, noparent),
	    %% Initialize scheduler context.
            Active = ?SETS:add_element(FirstLid, ?SETS:new()),
            Blocked = ?SETS:new(),
            State = state:empty(),
	    Context = #context{active = Active, blocked = Blocked,
                               state = State, details = Det},
	    %% Interleave using driver.
            Ret = driver(Context, ReplayState),
	    %% Cleanup of any remaining processes.
	    proc_cleanup(),
            lid:stop(),
            NewTickets =
                case Ret of
                    {error, Error, ErrorState} ->
                        {files, Files} = lists:keyfind(files, 1, Options),
                        Ticket = ticket:new(Target, Files, Error, ErrorState),
                        case Det of
                            true -> continue;
                            false -> log:show_error(Ticket)
                        end,
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
                    interleave_loop(Target, NewRunCnt, NewTickets, Options)
            end
    end.

%%%----------------------------------------------------------------------
%%% Core components
%%%----------------------------------------------------------------------

%% Delegates messages sent by instrumented client code to the appropriate
%% handlers.
dispatcher(Context) ->
    receive
	#sched{msg = Type, lid = Lid, misc = Misc} ->
	    handler(Type, Lid, Context, Misc);
	%% Ignore unknown processes.
	{'EXIT', Pid, Reason} ->
	    case lid:from_pid(Pid) of
		not_found -> Context;
		Lid -> handler(exit, Lid, Context, Reason)
	    end
    end.

driver(Context, ReplayState) ->
    case state:is_empty(ReplayState) of
	true -> driver_normal(Context);
	false -> driver_replay(Context, ReplayState)
    end.

driver_replay(OldContext, ReplayState) ->
    Context = update_context(OldContext),
    {Next, Rest} = state:trim_head(ReplayState),
    NewContext = run(Context#context{current = Next, error = ?NO_ERROR}),
    #context{blocked = NewBlocked} = NewContext,
    case state:is_empty(Rest) of
	true ->
	    case ?SETS:is_element(Next, NewBlocked) of
		true -> abort;
		false -> check_for_errors(NewContext)
	    end;
	false -> driver_replay(NewContext, Rest)
    end.	    

driver_normal(OldContext) ->
    #context{active = Active, current = LastLid,
	     state = State} = Context = update_context(OldContext),
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

check_for_errors(#context{active = NewActive, blocked = NewBlocked,
			  error = NewError, state = NewState} = NewContext) ->
    case NewError of
	?NO_ERROR ->
	    case ?SETS:size(NewActive) of
		0 ->
		    case ?SETS:size(NewBlocked) of
			0 -> ok;
			_NonEmptyBlocked -> all_blocked(NewContext)
		    end;
		_NonEmptyActive -> driver_normal(NewContext)
	    end;
	_Other -> {error, NewError, NewState}
    end.

all_blocked(#context{blocked = Blocked, state = State} = Context) ->
    receive
	#special{msg = Type, lid = Lid, misc = Misc} ->
	    NewContext = special_handler(Type, Lid, Context, Misc),
	    driver_normal(NewContext)
    after 500 ->
	    Deadlock = error:new({deadlock, Blocked}),
	    {error, Deadlock, State}
    end.

update_context(Context) ->
    receive
	#special{msg = Type, lid = Lid, misc = Misc} ->
	    NewContext = special_handler(Type, Lid, Context, Misc),
	    update_context(NewContext)
    after 0 -> Context
    end.

special_handler(wakeup, Lid,
		#context{active = Active, blocked = Blocked} = Context, _M) ->
    NewBlocked = ?SETS:del_element(Lid, Blocked),
    NewActive = ?SETS:add_element(Lid, Active),
    Context#context{active = NewActive, blocked = NewBlocked};
special_handler(spawn, not_found,
		#context{active = Active, details = Det} = Context, ChildPid) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, noparent),
    log_details(Det, {spawn, not_found, ChildLid}),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive};
special_handler(spawn_opt, not_found,
		#context{active = Active, details = Det} = Context,
		{Ret, Opt}) ->
    {ChildPid, _Ref} =
	case Ret of
	    {C, R} -> {C, R};
	    C -> {C, noref}
	end,
    link(ChildPid),
    ChildLid = lid:new(ChildPid, noparent),
    Opts = sets:to_list(sets:intersection(sets:from_list([link, monitor]),
					  sets:from_list(Opt))),
    log_details(Det, {spawn_opt, not_found, ChildLid, Opts}),
    NewActive = ?SETS:add_element(ChildLid, Active),
    Context#context{active = NewActive}.

run_no_block(#context{state = State} = Context, {Next, Rest, W}) ->
    NewContext = run(Context#context{current = Next, error = ?NO_ERROR}),
    #context{blocked = NewBlocked} = NewContext,
    case ?SETS:is_element(Next, NewBlocked) of
	true ->
	    case Rest of
		[] -> {NewContext, {[], W}};
		[RH|RT] ->
		    NextContext = NewContext#context{state = State},
		    run_no_block(NextContext, {RH, RT, current})
	    end;
	false -> {NewContext, {Rest, W}}
    end.

insert_states(State, {Lids, current}) ->
    [state_save(state:extend(State, L)) || L <- Lids];
insert_states(State, {Lids, next}) ->
    [state_save_next(state:extend(State, L)) || L <- Lids].

%% After message handler.
handler('after', Pid, #context{details = Det} = Context, _Misc) ->
    Lid = lid:from_pid(Pid),
    log_details(Det, {'after', Lid}),
    dispatcher(Context);

%% Block message handler.
%% Receiving a `block` message means that the process cannot be scheduled
%% next and must be moved to the blocked set.
handler(block, Lid, #context{blocked = Blocked, details = Det} = Context,
        _Misc) ->
    NewBlocked = ?SETS:add_element(Lid, Blocked),
    log_details(Det, {block, Lid}),
    Context#context{blocked = NewBlocked};

%% Demonitor message handler.
handler(demonitor, Lid, #context{details = Det} = Context, _Ref) ->
    %% TODO: Get LID from Ref?
    TargetLid = lid:mock(0),
    log_details(Det, {demonitor, Lid, TargetLid}),
    dispatcher(Context);

%% Exit handler (called when a process calls exit/2).
handler(fun_exit, Lid, #context{details = Det} = Context, {Target, Reason}) ->
    TargetLid = lid:from_pid(Target),
    log_details(Det, {fun_exit, Lid, TargetLid, Reason}),
    NewContext = dispatcher(Context),
    case TargetLid of
	not_found -> NewContext;
	_Found ->
	    %% If Reason is kill or Target is not trapping exits and
	    %% Reason is not normal, call the dispatcher a second
	    %% time to handle the exit of Target.
	    %% NOTE: If Target gets killed, this is not recorded as
	    %% a seperate action in the state queue, but rather is
	    %% seen as one action together with the exit/2 call
	    %% (although it is logged as a seperate event).
	    TempContext = NewContext#context{current = TargetLid},
	    case Reason of
		kill ->
		    NewerContext = dispatcher(TempContext),
		    NewerContext#context{current = Lid};
		normal -> NewContext;
		_OtherReason ->
		    case process_info(Target, trap_exit) of
			{trap_exit, false} ->
			    NewerContext = dispatcher(TempContext),
			    NewerContext#context{current = Lid};
			_OtherInfo -> NewContext
		    end
	    end
    end;

%% Exit handler (called when a process has exited).
%% Discard the exited process (don't add to any set).
handler(exit, Lid, #context{details = Det} = Context, Reason) ->
    %% Cleanup LID stored info.
    lid:cleanup(Lid),
    %% Handle and propagate errors.
    case Reason of
	normal ->
	    log_details(Det, {exit, Lid, normal}),
	    Context;
	_Else ->
	    Error = error:new(Reason),
	    log_details(Det, {exit, Lid, error:type(Error)}),
	    Context#context{error = Error}
    end;

%% Halt message handler.
%% Return empty active and blocked queues to force run termination.
handler(halt, Lid, #context{details = Det} = Context, Misc) ->
    Halt =
        case Misc of
            empty -> {halt, Lid};
            Status -> {halt, Lid, Status}
        end,
    log_details(Det, Halt),
    Context#context{active = ?SETS:new(), blocked = ?SETS:new()};

%% Link message handler.
handler(link, Lid, #context{details = Det} = Context, TargetPid) ->
    TargetLid = lid:from_pid(TargetPid),
    log_details(Det, {link, Lid, TargetLid}),
    dispatcher(Context);

%% Monitor message handler.
handler(monitor, Lid, #context{details = Det} = Context, {Item, _Ref}) ->
    TargetLid = lid:from_pid(Item),
    log_details(Det, {monitor, Lid, TargetLid}),
    dispatcher(Context);

%% Process_flag message handler.
handler(process_flag, Lid, #context{details = Det} = Context, {Flag, Value}) ->
    log_details(Det, {process_flag, Lid, Flag, Value}),
    dispatcher(Context);

%% Normal receive message handler.
handler('receive', Lid, #context{details = Det} = Context, {From, Msg}) ->
    log_details(Det, {'receive', Lid, From, Msg}),
    dispatcher(Context);

%% Receive message handler for special messages, like 'EXIT' and 'DOWN',
%% which don't have an associated sender process.
handler('receive', Lid, #context{details = Det} = Context, Msg) ->
    log_details(Det, {'receive', Lid, Msg}),
    dispatcher(Context);

%% Register message handler.
handler(register, Lid, #context{details = Det} = Context, {RegName, RegLid}) ->
    log_details(Det, {register, Lid, RegName, RegLid}),
    dispatcher(Context);

%% Send message handler.
handler(send, Lid, #context{details = Det} = Context, {DstPid, Msg}) ->
    DstLid = lid:from_pid(DstPid),
    log_details(Det, {send, Lid, DstLid, Msg}),
    dispatcher(Context);

%% Spawn message handler.
%% First, link the newly spawned process to the scheduler process.
%% The new process yields as soon as it gets spawned and the parent process
%% yields as soon as it spawns. Therefore wait for two `yield` messages using
%% two calls to the dispatcher.
handler(spawn, ParentLid,
	#context{active = Active, details = Det} = Context, ChildPid) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    log_details(Det, {spawn, ParentLid, ChildLid}),
    NewActive = ?SETS:add_element(ChildLid, Active),
    dispatcher(Context#context{active = NewActive});

%% Spawn_link message handler.
%% Same as above, but save linked LIDs.
handler(spawn_link, ParentLid,
	#context{active = Active, details = Det} = Context, ChildPid) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    log_details(Det, {spawn_link, ParentLid, ChildLid}),
    NewActive = ?SETS:add_element(ChildLid, Active),
    dispatcher(Context#context{active = NewActive});

%% Spawn_monitor message handler.
%% Same as spawn, but save monitored LIDs.
handler(spawn_monitor, ParentLid,
	#context{active = Active, details = Det} = Context, {ChildPid, _Ref}) ->
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    log_details(Det, {spawn_monitor, ParentLid, ChildLid}),
    NewActive = ?SETS:add_element(ChildLid, Active),
    dispatcher(Context#context{active = NewActive});

%% Spawn_opt message handler.
%% Similar to above depending on options.
handler(spawn_opt, ParentLid,
	#context{active = Active, details = Det} = Context, {Ret, Opt}) ->
    {ChildPid, _Ref} =
	case Ret of
	    {C, R} -> {C, R};
	    C -> {C, noref}
	end,
    link(ChildPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    Opts = sets:to_list(sets:intersection(sets:from_list([link, monitor]),
					  sets:from_list(Opt))),
    log_details(Det, {spawn_opt, ParentLid, ChildLid, Opts}),
    NewActive = ?SETS:add_element(ChildLid, Active),
    dispatcher(Context#context{active = NewActive});

%% Unlink message handler.
handler(unlink, Lid, #context{details = Det} = Context, TargetPid) ->
    TargetLid = lid:from_pid(TargetPid),
    log_details(Det, {unlink, Lid, TargetLid}),
    dispatcher(Context);

%% Unregister message handler.
handler(unregister, Lid, #context{details = Det} = Context, RegName) ->
    log_details(Det, {unregister, Lid, RegName}),
    dispatcher(Context);

%% Whereis message handler.
handler(whereis, Lid, #context{details = Det} = Context, {RegName, Result}) ->
    ResultLid = lid:from_pid(Result),
    log_details(Det, {whereis, Lid, RegName, ResultLid}),
    dispatcher(Context);

%% Yield message handler.
%% Receiving a 'yield' message means that the process is preempted, but
%% remains in the active set.
handler(yield, Lid, #context{active = Active} = Context, _Misc) ->
    ?debug_2("Process ~s yields.~n", [lid:to_string(Lid)]),
    NewActive = ?SETS:add_element(Lid, Active),
    Context#context{active = NewActive}.

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

%% Kill any remaining processes.
%% If the run was terminated by an exception, processes linked to
%% the one where the exception occurred could have been killed by the
%% exit signal of the latter without having been deleted from the pid/lid
%% tables. Thus, 'EXIT' messages with any reason are accepted.
proc_cleanup() ->
    Fun = fun(P, Acc) ->
		  exit(P, kill),
		  receive {'EXIT', P, _Reason} -> Acc end
	  end,
    lid:fold_pids(Fun, unused),
    ok.

%% Calculate and print elapsed time between T1 and T2.
elapsed_time(T1, T2) ->
    ElapsedTime = T2 - T1,
    Mins = ElapsedTime div 60000,
    Secs = (ElapsedTime rem 60000) / 1000,
    ?debug_1("Done in ~wm~.2fs\n", [Mins, Secs]),
    {Mins, Secs}.

%% Print debug messages and send them to replay_logger if Det is true.
log_details(Det, Action) ->
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    case Det of
	true -> replay_logger:log(Action);
	false -> continue
    end.

%% Run process Lid in context Context.
run(#context{active = Active, current = Lid, state = State} = Context) ->
    ?debug_2("Running process ~s.~n", [lid:to_string(Lid)]),
    %% Remove process from the `active` set.
    NewActive = ?SETS:del_element(Lid, Active),
    %% Create new state by adding this process.
    NewState = state:extend(State, Lid),
    %% Send message to "unblock" the process.
    Pid = lid:get_pid(Lid),
    continue(Pid),
    %% Call the dispatcher to handle incoming actions from the process
    %% we just "unblocked".
    dispatcher(Context#context{active = NewActive, state = NewState}).

%% Remove and return a state.
%% If no states available, return 'no_state'.
state_load() ->
    case ets:first(?NT_STATE1) of
	'$end_of_table' -> no_state;
	State ->
	    ets:delete(?NT_STATE1, State),
	    State
    end.

%% Return a state without removing it.
%% If no states available, return 'no_state'.
state_peak() ->
    case ets:first(?NT_STATE1) of
	'$end_of_table' ->  no_state;
	State -> State
    end.

%% Add a state to the current `state` table.
state_save(State) ->
    ets:insert(?NT_STATE1, {State}).

%% Add a state to the next `state` table.
state_save_next(State) ->
    ets:insert(?NT_STATE2, {State}).

%% Initialize state tables.
state_start() ->
    ets:new(?NT_STATE1, [named_table]),
    ets:new(?NT_STATE2, [named_table]).

%% Clean up state table.
state_stop() ->
    ets:delete(?NT_STATE1),
    ets:delete(?NT_STATE2).

%% Swap names of the two state tables and clear one of them.
state_swap() ->
    ets:rename(?NT_STATE1, ?NT_STATE_TEMP),
    ets:rename(?NT_STATE2, ?NT_STATE1),
    ets:rename(?NT_STATE_TEMP, ?NT_STATE2),
    ets:delete_all_objects(?NT_STATE2).

%%%----------------------------------------------------------------------
%%% Instrumentation interface
%%%----------------------------------------------------------------------

%% Notify the scheduler of a blocked process.
-spec block() -> 'ok'.

block() ->
    %% TODO: Depending on how 'receive' is instrumented, a check for
    %% whether the caller is a known process might be needed here.
    ?RP_SCHED ! #sched{msg = block, lid = lid:from_pid(self())},
    ok.

%% Prompt process Pid to continue running.
continue(Pid) ->
    Pid ! #sched{msg = continue}.

%% Notify the scheduler of an event.
%% If the calling user process has an associated LID, then send
%% a notification and yield. Otherwise, for an unknown process
%% running instrumented code completely ignore this call.
-spec notify(notification(), any()) -> 'ok'.

notify(Msg, Misc) ->
    case lid:from_pid(self()) of
	not_found ->
	    SpawnFamily = [spawn, spawn_link, spawn_monitor, spawn_opt],
	    case lists:member(Msg, SpawnFamily) of
		true ->
		    ?RP_SCHED ! #special{msg = Msg, misc = Misc},
		    ok;
		false -> ok
	    end;
	Lid ->
	    ?RP_SCHED ! #sched{msg = Msg, lid = Lid, misc = Misc},
	    yield()
    end.

-spec wakeup() -> 'ok'.

wakeup() ->
    %% TODO: Depending on how 'receive' is instrumented, a check for
    %% whether the caller is a known process might be needed here.
    ?RP_SCHED ! #special{msg = wakeup, lid = lid:from_pid(self())},
    ok.

%% Wait until the scheduler prompts to continue.
-spec wait() -> 'ok'.

wait() ->
    receive
	#sched{msg = continue} -> ok
    end.

%% Functionally same as block. Used when a process is scheduled out, but
%% remains in the `active` set.
-spec yield() -> 'ok'.

yield() ->
    ?RP_SCHED ! #sched{msg = yield, lid = lid:from_pid(self())},
    wait().
