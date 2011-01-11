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
-export([block/0, notify/2, wait/0, yield/0]).

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
-define(ERROR_UNDEF, undef).

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
                  error          :: ?ERROR_UNDEF | error:error(),
                  state          :: state:state()}).

%% Internal message format
%%
%% msg    : An atom describing the type of the message.
%% pid    : The sender's pid.
%% misc   : Optional arguments, depending on the message type.
-record(sched, {msg  :: atom(),
                pid  :: pid(),
                misc  = empty :: term()}).

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

-type context() :: #context{}.

%% Driver return type.
-type driver_ret() :: 'ok' | 'block' | {'error', error:error(), state:state()}.

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
    blocked_start(),
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
    blocked_stop(),
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
	    Search = fun(C) -> search(C) end,
	    %% Interleave using driver.
            Ret = driver(Search, Context, ReplayState),
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
		    block ->
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
dispatcher(#context{current = Lid} = Context) ->
    Pid = lid:get_pid(Lid),
    receive
	#sched{msg = Type, pid = Pid, misc = Misc} ->
	    handler(Type, Pid, Context, Misc);
	{'EXIT', Pid, Reason} ->
	    handler(exit, Pid, Context, Reason)
    end.

%% Main scheduler component.
%% Checks for different program states (normal, deadlock, termination, etc.)
%% and acts appropriately. The argument should be a blocked scheduler state,
%% i.e. no process running when the driver is called.
%% In the case of a normal (meaning non-terminal) state:
%% - if the ReplayState is empty, the search component is called to handle
%% state expansion and returns a process for activation;
%% - if the ReplayState is not empty, we are in replay mode and the process
%% to be run next is provided by ReplayState.
-spec driver(function(), context(), state:state()) -> driver_ret().

driver(Search, #context{state = OldState} = Context, ReplayState) ->
    {Next, Rest, {_InsertMode, InsertLids} = Insert} =
	case state:is_empty(ReplayState) of
	    %% If in normal mode, run search algorithm to
	    %% find next process to be run.
	    true ->
		{NextTemp, InsertLaterTemp} = Search(Context),
		{NextTemp, ReplayState, InsertLaterTemp};
	    %% If in replay mode, next process to be run
	    %% is defined by ReplayState.
	    false ->
		{NextTemp, RestTemp} = state:trim_head(ReplayState),
		{NextTemp, RestTemp, {current, []}}
	end,
    ContextToRun = Context#context{current = Next, error = ?ERROR_UNDEF},
    #context{active = Active, blocked = Blocked, error = Error,
	     state = State, details = Det} = RunContext = run(ContextToRun),
    %% Update active and blocked sets, moving Lid from active to blocked,
    %% in the case that if it was run next, it would block.
    Fun = fun(L, Acc) ->
		  case blocked_lookup(state:extend(State, L)) of
		      true -> ?SETS:add_element(L, Acc);
		      false -> Acc
		  end
	  end,
    BlockedOracle = ?SETS:fold(Fun, ?SETS:new(), Active),
    NewActive = ?SETS:subtract(Active, BlockedOracle),
    NewBlocked = ?SETS:union(Blocked, BlockedOracle),
    NewContext = RunContext#context{active = NewActive, blocked = NewBlocked},
    case Error of
	?ERROR_UNDEF ->
	    case ?SETS:size(NewActive) of
		0 ->
		    case ?SETS:size(NewBlocked) of
			0 ->
			    insert_states(OldState, Insert),
			    ok;
			_NonEmptyBlocked ->
			    insert_states(OldState, Insert),
                            Deadlock = error:new({deadlock, NewBlocked}),
			    case ?SETS:is_element(Next, Blocked) of
				true -> {error, Deadlock, OldState};
				false -> {error, Deadlock, State}
			    end
		    end;
		_NonEmptyActive ->
                    case ?SETS:is_element(Next, Blocked) of
                        true ->
                            case Det of
				true -> driver(Search, NewContext, Rest);
				false ->
				    insert_states(OldState,
						  {current, InsertLids}),
				    blocked_save(State),
				    block
                            end;
                        false ->
                            insert_states(OldState, Insert),
                            driver(Search, NewContext, Rest)
                    end
	    end;
	_Other ->
	    insert_states(OldState, Insert),
	    {error, Error, State}
    end.

%% Stores states for later exploration and returns the process to be run next.
search(#context{active = Active, current = LastLid, state = State}) ->
    case state:is_empty(State) of
	%% Handle first call to search (empty state, one active process).
	true ->
	    [Next] = ?SETS:to_list(Active),
	    {Next, {current, []}};
	false ->
	    %% If the last process run is in the `active` set
	    %% (i.e. has not blocked or exited), remove it from the actives
	    %% and make it next-to-run, else do that for another process
	    %% from the actives.
	    %% In the former case, all other possible successor states are
	    %% stored in the next state queue to be explored on the next
	    %% preemption bound.
	    %% In the latter case, all other possible successor states are
	    %% stored in the current state queue, because a non-preemptive
	    %% context switch is happening (the last process either exited
	    %% or blocked).
	    case ?SETS:is_element(LastLid, Active) of
		true ->
		    NewActive = ?SETS:to_list(?SETS:del_element(LastLid, Active)),
		    {LastLid, {next, NewActive}};
		false ->
		    [Next|NewActive] = ?SETS:to_list(Active),
		    {Next, {current, NewActive}}
	    end
    end.

insert_states(State, {current, Lids}) ->
    [state_save(state:extend(State, L)) || L <- Lids];
insert_states(State, {next, Lids}) ->
    [state_save_next(state:extend(State, L)) || L <- Lids].

%% After message handler.
handler('after', Pid, #context{details = Det} = Context, _Misc) ->
    Lid = lid:from_pid(Pid),
    log_details(Det, {'after', Lid}),
    dispatcher(Context);

%% Block message handler.
%% Receiving a `block` message means that the process cannot be scheduled
%% next and must be moved to the blocked set.
handler(block, Pid, #context{blocked = Blocked, details = Det} = Context,
        _Misc) ->
    Lid = lid:from_pid(Pid),
    NewBlocked = ?SETS:add_element(Lid, Blocked),
    log_details(Det, {block, Lid}),
    Context#context{blocked = NewBlocked};

%% Demonitor message handler.
handler(demonitor, Pid, #context{details = Det} = Context, Ref) ->
    Lid = lid:from_pid(Pid),
    TargetLid = lid:demonitor(Lid, Ref),
    log_details(Det, {demonitor, Lid, TargetLid}),
    dispatcher(Context);

%% Exit handler (called when a process calls exit/2).
handler(fun_exit, Pid, #context{details = Det} = Context, {Target, Reason}) ->
    Lid = lid:from_pid(Pid),
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
%% If the exited process is irrelevant (i.e. has no LID assigned),
%% do nothing and call the dispatcher.
handler(exit, Pid,
	#context{active = Active, blocked = Blocked, details = Det} = Context,
	Reason) ->
    Lid = lid:from_pid(Pid),
    case Lid of
	not_found ->
	    ?debug_2("Unknown process (pid = ~p) exits (~p).~n", [Pid, Reason]),
	    dispatcher(Context);
	_Any ->
	    %% Wake up all processes linked to/monitoring the one that just
            %% exited.
	    Linked = lid:get_linked(Lid),
            Monitors = lid:get_monitored_by(Lid),
	    NewActive = ?SETS:union(?SETS:union(Active, Linked), Monitors),
	    NewBlocked = ?SETS:subtract(?SETS:subtract(Blocked, Linked),
                                       Monitors),
	    NewContext = Context#context{active = NewActive,
					 blocked = NewBlocked},
	    %% Cleanup LID stored info.
	    lid:cleanup(Lid),
	    %% Handle and propagate errors.
	    case Reason of
		normal ->
		    log_details(Det, {exit, Lid, normal}),
		    NewContext;
		_Else ->
		    Error = error:new(Reason),
		    log_details(Det, {exit, Lid, error:type(Error)}),
		    NewContext#context{error = Error}
	    end
    end;

%% Halt message handler.
%% Return empty active and blocked queues to force run termination.
handler(halt, Pid, #context{details = Det} = Context, Misc) ->
    Lid = lid:from_pid(Pid),
    Halt =
        case Misc of
            empty -> {halt, Lid};
            Status -> {halt, Lid, Status}
        end,
    log_details(Det, Halt),
    Context#context{active = ?SETS:new(), blocked = ?SETS:new()};

%% Link message handler.
handler(link, Pid, #context{details = Det} = Context, TargetPid) ->
    Lid = lid:from_pid(Pid),
    TargetLid = lid:from_pid(TargetPid),
    log_details(Det, {link, Lid, TargetLid}),
    case TargetLid of
        not_found -> continue;
        _ -> lid:link(Lid, TargetLid)
    end,
    dispatcher(Context);

%% Monitor message handler.
handler(monitor, Pid, #context{details = Det} = Context, {Item, Ref}) ->
    Lid = lid:from_pid(Pid),
    TargetLid = lid:from_pid(Item),
    log_details(Det, {monitor, Lid, TargetLid}),
    case TargetLid of
        not_found -> continue;
        _ -> lid:monitor(Lid, TargetLid, Ref)
    end,
    dispatcher(Context);

%% Process_flag message handler.
handler(process_flag, Pid, #context{details = Det} = Context, {Flag, Value}) ->
    Lid = lid:from_pid(Pid),
    log_details(Det, {process_flag, Lid, Flag, Value}),
    dispatcher(Context);

%% Normal receive message handler.
handler('receive', Pid, #context{details = Det} = Context, {From, Msg}) ->
    Lid = lid:from_pid(Pid),
    log_details(Det, {'receive', Lid, From, Msg}),
    dispatcher(Context);

%% Receive message handler for special messages, like 'EXIT' and 'DOWN',
%% which don't have an associated sender process.
handler('receive', Pid, #context{details = Det} = Context, Msg) ->
    Lid = lid:from_pid(Pid),
    log_details(Det, {'receive', Lid, Msg}),
    dispatcher(Context);

%% Register message handler.
handler(register, Pid, #context{details = Det} = Context, {RegName, RegLid}) ->
    Lid = lid:from_pid(Pid),
    log_details(Det, {register, Lid, RegName, RegLid}),
    dispatcher(Context);

%% Send message handler.
%% When a message is sent to a process, the receiving process has to be awaken
%% if it is blocked on a receive.
%% XXX: No check for reason of blocking for now. If the process is blocked on
%%      something else, it will be awaken!
handler(send, Pid, #context{details = Det} = Context, {DstPid, Msg}) ->
    Lid = lid:from_pid(Pid),
    DstLid = lid:from_pid(DstPid),
    log_details(Det, {send, Lid, DstLid, Msg}),
    NewContext = wakeup(DstLid, Context),
    dispatcher(NewContext);

%% Spawn message handler.
%% First, link the newly spawned process to the scheduler process.
%% The new process yields as soon as it gets spawned and the parent process
%% yields as soon as it spawns. Therefore wait for two `yield` messages using
%% two calls to the dispatcher.
handler(spawn, ParentPid,
	#context{active = Active, details = Det} = Context, ChildPid) ->
    link(ChildPid),
    ParentLid = lid:from_pid(ParentPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    log_details(Det, {spawn, ParentLid, ChildLid}),
    NewActive = ?SETS:add_element(ChildLid, Active),
    dispatcher(Context#context{active = NewActive});

%% Spawn_link message handler.
%% Same as above, but save linked LIDs.
handler(spawn_link, ParentPid,
	#context{active = Active, details = Det} = Context, ChildPid) ->
    link(ChildPid),
    ParentLid = lid:from_pid(ParentPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    log_details(Det, {spawn_link, ParentLid, ChildLid}),
    lid:link(ParentLid, ChildLid),
    NewActive = ?SETS:add_element(ChildLid, Active),
    dispatcher(Context#context{active = NewActive});

%% Spawn_monitor message handler.
%% Same as spawn, but save monitored LIDs.
handler(spawn_monitor, ParentPid,
	#context{active = Active, details = Det} = Context, {ChildPid, Ref}) ->
    link(ChildPid),
    ParentLid = lid:from_pid(ParentPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    log_details(Det, {spawn_monitor, ParentLid, ChildLid}),
    lid:monitor(ParentLid, ChildLid, Ref),
    NewActive = ?SETS:add_element(ChildLid, Active),
    dispatcher(Context#context{active = NewActive});

%% Spawn_opt message handler.
%% Similar to above depending on options.
handler(spawn_opt, ParentPid,
	#context{active = Active, details = Det} = Context, {Ret, Opt}) ->
    {ChildPid, Ref} =
	case Ret of
	    {C, R} -> {C, R};
	    C -> {C, noref}
	end,
    link(ChildPid),
    ParentLid = lid:from_pid(ParentPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    Opts = sets:to_list(sets:intersection(sets:from_list([link, monitor]),
					  sets:from_list(Opt))),
    log_details(Det, {spawn_opt, ParentLid, ChildLid, Opts}),
    case lists:member(link, Opts) of
	true -> lid:link(ParentLid, ChildLid);
	false -> continue
    end,
    case lists:member(monitor, Opts) of
	true -> lid:monitor(ParentLid, ChildLid, Ref);
	false -> continue
    end,
    NewActive = ?SETS:add_element(ChildLid, Active),
    dispatcher(Context#context{active = NewActive});

%% Unlink message handler.
handler(unlink, Pid, #context{details = Det} = Context, TargetPid) ->
    Lid = lid:from_pid(Pid),
    TargetLid = lid:from_pid(TargetPid),
    log_details(Det, {unlink, Lid, TargetLid}),
    case TargetLid of
        not_found -> continue;
        _ -> lid:unlink(Lid, TargetLid)
    end,
    dispatcher(Context);

%% Unregister message handler.
handler(unregister, Pid, #context{details = Det} = Context, RegName) ->
    Lid = lid:from_pid(Pid),
    log_details(Det, {unregister, Lid, RegName}),
    dispatcher(Context);

%% Whereis message handler.
handler(whereis, Pid, #context{details = Det} = Context, {RegName, Result}) ->
    Lid = lid:from_pid(Pid),
    ResultLid = lid:from_pid(Result),
    log_details(Det, {whereis, Lid, RegName, ResultLid}),
    dispatcher(Context);

%% Yield message handler.
%% Receiving a 'yield' message means that the process is preempted, but
%% remains in the active set.
handler(yield, Pid, #context{active = Active} = Context, _Misc) ->
    Lid = lid:from_pid(Pid),
    ?debug_2("Process ~s yields.~n", [lid:to_string(Lid)]),
    NewActive = ?SETS:add_element(Lid, Active),
    Context#context{active = NewActive}.

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

blocked_lookup(State) ->
    case ets:lookup(?NT_BLOCKED, State) of
	[] -> false;
	[{State}] -> true
    end.

blocked_save(State) ->
    ets:insert(?NT_BLOCKED, {State}).

blocked_start() ->
    ets:new(?NT_BLOCKED, [named_table]).

blocked_stop() ->
    ets:delete(?NT_BLOCKED).

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

%% Wake up a process.
%% If process is in `blocked` set, move to `active` set.
wakeup(Lid, #context{active = Active, blocked = Blocked} = Context) ->
    case ?SETS:is_element(Lid, Blocked) of
	true ->
            ?debug_2("Process ~s wakes up.~n", [lid:to_string(Lid)]),
	    NewBlocked = ?SETS:del_element(Lid, Blocked),
	    NewActive = ?SETS:add_element(Lid, Active),
	    Context#context{active = NewActive, blocked = NewBlocked};
	false -> Context
    end.

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

%% Used by functions where the process is required to block, i.e. moved to
%% the `blocked` set and stop being scheduled, until awaken.
-spec block() -> 'ok'.

block() ->
    ?RP_SCHED ! #sched{msg = block, pid = self()},
    wait().

%% Prompt process Pid to continue running.
continue(Pid) ->
    Pid ! #sched{msg = continue}.

%% Notify the scheduler of an event.
%% If the calling user process has an associated LID, then send
%% a notification and yield. Otherwise, for an unknown process
%% running instrumented code completely ignore this call.
-spec notify(atom(), any()) -> 'ok'.

notify(Msg, Misc) ->
    Self = self(),
    case lid:from_pid(Self) of
	not_found -> ok;
	_Lid ->
	    ?RP_SCHED ! #sched{msg = Msg, pid = self(), misc = Misc},
	    yield()
    end.

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
    ?RP_SCHED ! #sched{msg = yield, pid = self()},
    wait().
