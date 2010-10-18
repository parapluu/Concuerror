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

%% UI related exports.
-export([analyze/2, driver/3, proc_cleanup/0, replay/1]).

%% Instrumentation related exports.
-export([rep_demonitor/1, rep_demonitor/2, rep_halt/0, rep_halt/1,
         rep_link/1, rep_monitor/2, rep_process_flag/2,
         rep_receive/1, rep_after_notify/0,
	 rep_receive_notify/1, rep_receive_notify/2,
         rep_register/2, rep_send/2, rep_spawn/1, rep_spawn/3,
	 rep_spawn_link/1, rep_spawn_link/3, rep_spawn_monitor/1,
	 rep_spawn_monitor/3, rep_unlink/1, rep_unregister/1,
	 rep_whereis/1, rep_yield/0, wait/0]).

-export_type([analysis_target/0, analysis_ret/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Definitions
%%%----------------------------------------------------------------------

-define(INFINITY, 1000000).

%%%----------------------------------------------------------------------
%%% Records
%%%----------------------------------------------------------------------

%% Scheduler state
%%
%% active  : A set containing all processes ready to be scheduled.
%% blocked : A set containing all processes that cannot be scheduled next
%%          (e.g. waiting for a message on a `receive`).
%% error   : A term describing the error that occured.
%% state   : The current state of the program.
%% details : A boolean being false when running a normal run and
%%           true when running a replay and need to send detailed
%%           info to the replay_logger.
-record(context, {active  :: set(),
                  blocked :: set(),
                  error = normal :: 'normal' | 
				    error:assertion() |
				    error:exception(),
                  state   :: state:state(),
                  details :: boolean()}).

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

-type analysis_info() :: analysis_target().

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

-type bound() :: 'infinite' | non_neg_integer().

-type context() :: #context{}.

%% The destination of a `send' operation.
-type dest() :: pid() | port() | atom() | {atom(), node()}.

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
    error_logger:tty(false),
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
			{ok, Target};
		    {error, RunCount, Tickets} ->
			TicketCount = length(Tickets),
			log:log("Analysis complete (checked ~w interleavings "
				"in ~wm~.2fs):~n", [RunCount, Mins, Secs]),
			log:log("Found ~p erroneous interleaving(s).~n",
				[TicketCount]),
			{error, analysis, Target, Tickets}
		end;
	    error ->
		{error, instr, Target}
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
    %% TODO: Need spawn_link?
    spawn(fun() -> interleave_aux(Target, Options, Self) end),
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
	    {preb, Bound} -> Bound;
	    false -> ?INFINITY
	end,
    Result = interleave_outer_loop(Target, 0, [], -1, PreBound, Options),
    blocked_stop(),
    state_stop(),
    unregister(?RP_SCHED),
    Parent ! {interleave_result, Result}.

interleave_outer_loop(_T, RunCnt, Tickets, MaxBound, MaxBound, _Opt) ->
    case Tickets of
	[] -> {ok, RunCnt};
	_Any -> {error, RunCnt, ticket:sort(Tickets)}
    end;
interleave_outer_loop(Target, RunCnt, Tickets, CurrBound, MaxBound, Options) ->
    {NewRunCnt, NewTickets} = interleave_loop(Target, 1, [], Options),
    TotalRunCnt = NewRunCnt + RunCnt,
    TotalTickets = NewTickets ++ Tickets,
    state_swap(),
    case state_peak() of
	no_state ->
	    case TotalTickets of
		[] -> {ok, TotalRunCnt};
		_Any -> {error, TotalRunCnt, ticket:sort(TotalTickets)}	
	    end;
	_State ->
	    interleave_outer_loop(Target, TotalRunCnt, TotalTickets,
				  CurrBound + 1, MaxBound, Options)
    end.

%% Main loop for producing process interleavings.
%% The first process (FirstPid) is created linked to the scheduler,
%% so that the latter can receive the former's exit message when it
%% terminates. In the same way, every process that may be spawned in
%% the course of the program shall be linked to the scheduler process.
interleave_loop(Target, RunCnt, Tickets, Options) ->
    Det = lists:member(details, Options),
    %% Lookup state to replay.
    case state_load() of
        no_state -> {RunCnt - 1, Tickets};
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
            Active = sets:add_element(FirstLid, sets:new()),
            Blocked = sets:new(),
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
            interleave_loop(Target, NewRunCnt, NewTickets, Options)
    end.

%%%----------------------------------------------------------------------
%%% Core components
%%%----------------------------------------------------------------------

%% Delegates messages sent by instrumented client code to the appropriate
%% handlers.
dispatcher(Context) ->
    receive
	#sched{msg = Type, pid = Pid, misc = Misc} ->
	    handler(Type, Pid, Context, Misc);
	{'EXIT', Pid, Reason} ->
	    handler(exit, Pid, Context, Reason);
	Other ->
	    log:internal("Dispatcher received: ~p~n", [Other])
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
    #context{active = Active, blocked = Blocked, error = Error,
	     state = State} = RunContext = run(Next, Context),
    %% Update active and blocked sets, moving Lid from active to blocked,
    %% in the case that if it was run next, it would block.
    Fun = fun(L, Acc) ->
		  case blocked_lookup(state:extend(State, L)) of
		      true -> sets:add_element(L, Acc);
		      false -> Acc
		  end
	  end,
    BlockedOracle = sets:fold(Fun, sets:new(), Active),
    NewActive = sets:subtract(Active, BlockedOracle),
    NewBlocked = sets:union(Blocked, BlockedOracle),
    NewContext = RunContext#context{active = NewActive, blocked = NewBlocked},
    case error:type(Error) of
	normal ->
	    case sets:size(NewActive) of
		0 ->
		    case sets:size(NewBlocked) of
			0 ->
			    insert_states(OldState, Insert),
			    ok;
			_NonEmptyBlocked ->
			    insert_states(OldState, Insert),
                            Deadlock = error:deadlock(NewBlocked),
                            {error, Deadlock, State}
		    end;
		_NonEmptyActive ->
		    case sets:is_element(Next, Blocked) of
			true ->
			    insert_states(OldState, {current, InsertLids}),
			    blocked_save(State),
			    block;
			false ->
			    insert_states(OldState, Insert),
			    driver(Search, NewContext, Rest)
		    end
	    end;
	_OtherErrorType ->
	    insert_states(OldState, Insert),
	    {error, Error, State}
    end.

%% Stores states for later exploration and returns the process to be run next.
search(#context{active = Active, state = State}) ->
    case state:is_empty(State) of
	%% Handle first call to search (empty state, one active process).
	true ->
	    [Next] = sets:to_list(Active),
	    {Next, {current, []}};
	false ->
	    %% Get last process that was run by the driver.
	    {LastLid, _Rest} = state:trim_tail(State),
	    %% If that process is in the `active` set (i.e. has not blocked),
	    %% remove it from the actives and make it next-to-run, else do
	    %% that for another process from the actives.
	    %% In the former case, all other possible successor states are
	    %% stored in the next state queue to be explored on the next
	    %% preemption bound.
	    %% In the latter case, all other possible successor states are
	    %% stored in the current state queue, because a non-preemptive
	    %% context switch is happening (the last process either exited
	    %% or blocked).
	    case sets:is_element(LastLid, Active) of
		true ->
		    NewActive = sets:to_list(sets:del_element(LastLid, Active)),
		    {LastLid, {next, NewActive}};
		false ->
		    [Next|NewActive] = sets:to_list(Active),
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
    NewBlocked = sets:add_element(Lid, Blocked),
    log_details(Det, {block, Lid}),
    Context#context{blocked = NewBlocked};

%% Demonitor message handler.
handler(demonitor, Pid, #context{details = Det} = Context, Ref) ->
    Lid = lid:from_pid(Pid),
    TargetLid = lid:demonitor(Lid, Ref),
    log_details(Det, {demonitor, Lid, TargetLid}),
    dispatcher(Context);

%% Exit message handler.
%% Discard the exited process (don't add to any set).
%% If the exited process is irrelevant (i.e. has no LID assigned),
%% do nothing and call the dispatcher.
handler(exit, Pid, 
	#context{active = Active, blocked = Blocked, details = Det} = Context,
	Reason) ->
    Lid = lid:from_pid(Pid),
    case Lid of
	not_found ->
	    ?debug_2("Process ~s (pid = ~p) exits (~p).~n",
		     [lid:to_string(Lid), Pid, Type]),
	    dispatcher(Context);
	_Any ->
	    %% Wake up all processes linked to/monitoring the one that just
            %% exited.
	    Linked = lid:get_linked(Lid),
            Monitors = lid:get_monitored_by(Lid),
	    NewActive = sets:union(sets:union(Active, Linked), Monitors),
	    NewBlocked = sets:subtract(sets:subtract(Blocked, Linked),
                                       Monitors),
	    NewContext = Context#context{active = NewActive,
					 blocked = NewBlocked},
	    %% Cleanup LID stored info.
	    lid:cleanup(Lid),
	    %% Handle and propagate errors.
	    Type =
		case Reason of
		    normal -> normal;
		    _Else -> error:type_from_description(Reason)
		end,
	    log_details(Det, {exit, Lid, Type}),
            case Type of
                normal -> NewContext;
                _Other ->
                    Error = error:new(Type, Reason),
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
    Context#context{active = sets:new(), blocked = sets:new()};

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
handler(spawn, ParentPid, #context{details = Det} = Context, ChildPid) ->
    link(ChildPid),
    ParentLid = lid:from_pid(ParentPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    log_details(Det, {spawn, ParentLid, ChildLid}),
    NewContext = dispatcher(Context),
    dispatcher(NewContext);

%% Spawn_link message handler.
%% Same as above, but save linked LIDs.
handler(spawn_link, ParentPid, #context{details = Det} = Context, ChildPid) ->
    link(ChildPid),
    ParentLid = lid:from_pid(ParentPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    log_details(Det, {spawn_link, ParentLid, ChildLid}),
    lid:link(ParentLid, ChildLid),
    NewContext = dispatcher(Context),
    dispatcher(NewContext);

%% Spawn_monitor message handler.
%% Same as spawn, but save monitored LIDs.
handler(spawn_monitor, ParentPid, #context{details = Det} = Context,
        {ChildPid, Ref}) ->
    link(ChildPid),
    ParentLid = lid:from_pid(ParentPid),
    ChildLid = lid:new(ChildPid, ParentLid),
    log_details(Det, {spawn_monitor, ParentLid, ChildLid}),
    lid:monitor(ParentLid, ChildLid, Ref),
    NewContext = dispatcher(Context),
    dispatcher(NewContext);

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
%% Receiving a `yield` message means that the process is preempted, but
%% remains in the active set.
handler(yield, Pid, #context{active = Active} = Context, _Misc) ->
    case lid:from_pid(Pid) of
        %% This case clause avoids a possible race between `yield` message
        %% of child and `spawn` message of parent.
        not_found ->
            ?RP_SCHED ! #sched{msg = yield, pid = Pid},
            dispatcher(Context);
        Lid ->
            ?debug_2("Process ~s yields.~n", [Lid]),
            NewActive = sets:add_element(Lid, Active),
            Context#context{active = NewActive}
    end.

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

%% Kill any remaining process.
-spec proc_cleanup() -> 'ok'.

proc_cleanup() ->
    lid:fold_pids(fun(P, Acc) -> exit(P, kill), Acc end, unused),
    ok.

%% Calculate and print elapsed time between T1 and T2.
elapsed_time(T1, T2) ->
    ElapsedTime = T2 - T1,
    Mins = ElapsedTime div 60000,
    Secs = (ElapsedTime rem 60000) / 1000,
    ?debug_1("Done in ~wm~.2fs\n", [Mins, Secs]),
    {Mins, Secs}.

find_pid(Pid) when is_pid(Pid) ->
    Pid;
find_pid(Port) when is_port(Port) ->
    erlang:port_info(Port, connected);
find_pid(Atom) when is_atom(Atom) ->
    whereis(Atom);
find_pid({Atom, Node}) when is_atom(Atom) andalso is_atom(Node) ->
    rpc:call(Node, erlang, whereis, [Atom]).

%% Print debug messages and send them to replay_logger if Det is true.
log_details(Det, Action) ->
    ?debug_1(proc_action:to_string(Action) ++ "~n"),
    case Det of
	true -> replay_logger:log(Action);
	false -> continue
    end.

%% Run process Lid in context Context.
run(Lid, #context{active = Active, state = State} = Context) ->
    ?debug_2("Running process ~s.~n", [Lid]),
    %% Remove process from the `active` set.
    NewActive = sets:del_element(Lid, Active),
    %% Create new state by adding this process.
    NewState = state:extend(State, Lid),
    %% Send message to "unblock" the process.
    Pid = lid:get_pid(Lid),
    Pid ! #sched{msg = continue},
    %% Call the dispatcher to handle incoming actions from the process
    %% we just "unblocked".
    dispatcher(Context#context{active = NewActive, state = NewState}).

%% Wake up a process.
%% If process is in `blocked` set, move to `active` set.
wakeup(Lid, #context{active = Active, blocked = Blocked} = Context) ->
    case sets:is_element(Lid, Blocked) of
	true ->
            ?debug_2("Process ~p wakes up.~n", [Lid]),
	    NewBlocked = sets:del_element(Lid, Blocked),
	    NewActive = sets:add_element(Lid, Active),
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

%% Not actually a replacement function, but used by functions where the process
%% is required to block, i.e. moved to the `blocked` set and stop being
%% scheduled, until awaken.
block() ->
    ?RP_SCHED ! #sched{msg = block, pid = self()},
    receive
	#sched{msg = continue} -> true
    end.

%% @spec: rep_demonitor(reference()) -> 'true'
%% @doc: Replacement for `demonitor/1'.
%%
%% Just yield after demonitoring.
-spec rep_demonitor(reference()) -> 'true'.

rep_demonitor(Ref) ->
    Result = demonitor(Ref),
    ?RP_SCHED ! #sched{msg = demonitor, pid = self(), misc = Ref},
    rep_yield(),
    Result.

%% @spec: rep_demonitor(reference(), ['flush' | 'info']) -> 'true'
%% @doc: Replacement for `demonitor/2'.
%%
%% Just yield after demonitoring.
-spec rep_demonitor(reference(), ['flush' | 'info']) -> 'true'.

rep_demonitor(Ref, Opts) ->
    Result = demonitor(Ref, Opts),
    ?RP_SCHED ! #sched{msg = demonitor, pid = self(), misc = Ref},
    rep_yield(),
    Result.

%% @spec: rep_halt() -> no_return().
%% @doc: Replacement for `halt/{0,1}'.
%%
%% Just send halt message and yield.
-spec rep_halt() -> no_return().

rep_halt() ->
    ?RP_SCHED ! #sched{msg = halt, pid = self()},
    rep_yield().

%% @spec: rep_halt() -> no_return().
%% @doc: Replacement for `halt/1'.
%%
%% Just send halt message and yield.
-spec rep_halt(non_neg_integer() | string()) -> no_return().

rep_halt(Status) ->
    ?RP_SCHED ! #sched{msg = halt, pid = self(), misc = Status},
    rep_yield().

%% @spec: rep_link(pid() | port()) -> 'true'
%% @doc: Replacement for `link/1'.
%%
%% Just yield after linking.
-spec rep_link(pid() | port()) -> 'true'.

rep_link(Pid) ->
    Result = link(Pid),
    ?RP_SCHED ! #sched{msg = link, pid = self(), misc = Pid},
    rep_yield(),
    Result.

%% @spec: rep_monitor('process', pid() | {atom(), node()} | atom()) ->
%%                           reference().  
%% @doc: Replacement for `monitor/2'.
%%
%% Just yield after monitoring.
-spec rep_monitor('process', pid() | {atom(), node()} | atom()) ->
                         reference().

rep_monitor(Type, Item) ->
    Ref = monitor(Type, Item),
    NewItem = find_pid(Item),
    ?RP_SCHED ! #sched{msg = monitor, pid = self(), misc = {NewItem, Ref}},
    rep_yield(),
    Ref.

%% @spec: rep_process_flag('trap_exit', boolean()) -> boolean();
%%                        ('error_handler', atom()) -> atom();
%%                        ('min_heap_size', non_neg_integer()) ->
%%                                non_neg_integer();
%%                        ('min_bin_vheap_size', non_neg_integer()) ->
%%                                non_neg_integer();
%%                        ('priority', process_priority_level()) ->
%%                                process_priority_level();
%%                        ('save_calls', non_neg_integer()) ->
%%                                non_neg_integer();
%%                        ('sensitive', boolean()) -> boolean().
%% @doc: Replacement for `process_flag/2'.
%%
%% Just yield after altering the process flag.
-type process_priority_level() :: 'max' | 'high' | 'normal' | 'low'.
-spec rep_process_flag('trap_exit', boolean()) -> boolean();
                      ('error_handler', atom()) -> atom();
                      ('min_heap_size', non_neg_integer()) -> non_neg_integer();
                      ('min_bin_vheap_size', non_neg_integer()) ->
                              non_neg_integer();
                      ('priority', process_priority_level()) ->
                              process_priority_level();
                      ('save_calls', non_neg_integer()) -> non_neg_integer();
                      ('sensitive', boolean()) -> boolean().

rep_process_flag(trap_exit = Flag, Value) ->
    Result = process_flag(Flag, Value),
    ?RP_SCHED ! #sched{msg = process_flag, pid = self(), misc = {Flag, Value}},
    rep_yield(),
    Result;
rep_process_flag(Flag, Value) ->
    process_flag(Flag, Value).

%% @spec rep_receive(fun((function()) -> term())) -> term()
%% @doc: Function called right before a receive statement.
%%
%% If a matching message is found in the process' message queue, continue
%% to actual receive statement, else block and when unblocked do the same.

-spec rep_receive(fun((term()) -> 'block' | 'continue')) -> term().

rep_receive(Fun) ->
    {messages, Mailbox} = process_info(self(), messages),
    case rep_receive_match(Fun, Mailbox) of
	block -> block(), rep_receive(Fun);
	continue -> continue
    end.

rep_receive_match(_Fun, []) ->
    block;
rep_receive_match(Fun, [H|T]) ->
    case Fun(H) of
	block -> rep_receive_match(Fun, T);
	continue -> continue
    end.

%% @spec rep_after_notify() -> 'ok'
%% @doc: Auxiliary function used in the `receive..after' statement
%% instrumentation.
%%
%% Called first thing after an `after' clause has been entered.
-spec rep_after_notify() -> 'ok'.

rep_after_notify() ->
    ?RP_SCHED ! #sched{msg = 'after', pid = self()},
    rep_yield(),
    ok.

%% @spec rep_receive_notify(pid(), term()) -> 'ok'
%% @doc: Auxiliary function used in the `receive' statement instrumentation.
%%
%% Called first thing after a message has been received, to inform the scheduler
%% about the message received and the sender.
-spec rep_receive_notify(pid(), term()) -> 'ok'.

rep_receive_notify(From, Msg) ->
    ?RP_SCHED ! #sched{msg = 'receive', pid = self(), misc = {From, Msg}},
    rep_yield(),
    ok.

%% @spec rep_receive_notify(term()) -> 'ok'
%% @doc: Auxiliary function used in the `receive' statement instrumentation.
%%
%% Similar to rep_receive/2, but used to handle 'EXIT' and 'DOWN' messages.
-spec rep_receive_notify(term()) -> 'ok'.

rep_receive_notify(Msg) ->
    case Msg of
	{'EXIT', _Pid, _Reason} -> continue;
	{'DOWN', _Ref, process, _Pid, _Reason} -> continue;
	Other -> log:internal("rep_receive_notify received ~p~n", [Other])
    end,
    ?RP_SCHED ! #sched{msg = 'receive', pid = self(), misc = Msg},
    rep_yield(),
    ok.

%% @spec rep_register(atom(), pid() | port()) -> 'true'
%% @doc: Replacement for `register/2'.
%%
%% Just yield after registering.
-spec rep_register(atom(), pid() | port()) -> 'true'.

rep_register(RegName, P) ->
    Ret = register(RegName, P),
    ?RP_SCHED ! #sched{msg = 'register', pid = self(),
                       misc = {RegName, lid:from_pid(P)}},
    rep_yield(),
    Ret.

%% @spec rep_send(dest(), term()) -> term()
%% @doc: Replacement for `send/2' (and the equivalent `!' operator).
%%
%% Just yield after sending.
-spec rep_send(dest(), term()) -> term().

rep_send(Dest, Msg) ->
    Dest ! {lid:from_pid(self()), Msg},
    NewDest = find_pid(Dest),
    ?RP_SCHED ! #sched{msg = send, pid = self(), misc = {NewDest, Msg}},
    rep_yield(),
    Msg.

%% @spec rep_spawn(function()) -> pid()
%% @doc: Replacement for `spawn/1'.
%%
%% The argument provided is the argument of the original spawn call.
%% When spawned, the new process has to yield.
-spec rep_spawn(function()) -> pid().

rep_spawn(Fun) ->
    Pid = spawn(fun() -> rep_yield(), Fun() end),
    ?RP_SCHED ! #sched{msg = spawn, pid = self(), misc = Pid},
    rep_yield(),
    Pid.

%% @spec rep_spawn(atom(), atom(), [term()]) -> pid()
%% @doc: Replacement for `spawn/3'.
%%
%% See `rep_spawn/1'.
-spec rep_spawn(atom(), atom(), [term()]) -> pid().

rep_spawn(Module, Function, Args) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn(Fun).

%% @spec rep_spawn_link(function()) -> pid()
%% @doc: Replacement for `spawn_link/1'.
%%
%% When spawned, the new process has to yield.
-spec rep_spawn_link(function()) -> pid().

rep_spawn_link(Fun) ->
    Pid = spawn_link(fun() -> rep_yield(), Fun() end),
    ?RP_SCHED ! #sched{msg = spawn_link, pid = self(), misc = Pid},
    rep_yield(),
    Pid.

%% @spec rep_spawn_link(atom(), atom(), [term()]) -> pid()
%% @doc: Replacement for `spawn_link/3'.
%%
%% See `rep_spawn_link/1'.
-spec rep_spawn_link(atom(), atom(), [term()]) -> pid().

rep_spawn_link(Module, Function, Args) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn_link(Fun).

%% @spec rep_spawn_monitor(function()) -> pid()
%% @doc: Replacement for `spawn_monitor/1'.
%%
%% When spawned, the new process has to yield.
-spec rep_spawn_monitor(function()) -> pid().

rep_spawn_monitor(Fun) ->
    Ret = spawn_monitor(fun() -> rep_yield(), Fun() end),
    ?RP_SCHED ! #sched{msg = spawn_monitor, pid = self(), misc = Ret},
    rep_yield(),
    Ret.

%% @spec rep_spawn_monitor(atom(), atom(), [term()]) -> pid()
%% @doc: Replacement for `spawn_monitor/3'.
%%
%% See rep_spawn_monitor/1.
-spec rep_spawn_monitor(atom(), atom(), [term()]) -> pid().

rep_spawn_monitor(Module, Function, Args) ->
    Fun = fun() -> apply(Module, Function, Args) end,
    rep_spawn_monitor(Fun).

%% @spec: rep_unlink(pid() | port()) -> 'true'
%% @doc: Replacement for `unlink/1'.
%%
%% Just yield after unlinking.
-spec rep_unlink(pid() | port()) -> 'true'.

rep_unlink(Pid) ->
    Result = unlink(Pid),
    ?RP_SCHED ! #sched{msg = unlink, pid = self(), misc = Pid},
    rep_yield(),
    Result.

%% @spec rep_unregister(atom()) -> 'true'
%% @doc: Replacement for `unregister/1'.
%%
%% Just yield after unregistering.
-spec rep_unregister(atom()) -> 'true'.

rep_unregister(RegName) ->
    Ret = unregister(RegName),
    ?RP_SCHED ! #sched{msg = 'unregister', pid = self(), misc = RegName},
    rep_yield(),
    Ret.

%% @spec rep_whereis(atom()) -> pid() | port() | 'undefined'
%% @doc: Replacement for `whereis/1'.
%%
%% Just yield after calling whereis/1.
-spec rep_whereis(atom()) -> pid() | port() | 'undefined'.

rep_whereis(RegName) ->
    Ret = whereis(RegName),
    ?RP_SCHED ! #sched{msg = 'whereis', pid = self(), misc = {RegName, Ret}},
    rep_yield(),
    Ret.

%% @spec rep_yield() -> 'true'
%% @doc: Replacement for `yield/0'.
%%
%% The calling process is preempted, but remains in the active set and awaits
%% a message to continue.
%%
%% Note: Besides replacing `yield/0', this function is heavily used by other
%%       functions of the instrumentation interface.

-spec rep_yield() -> 'true'.

rep_yield() ->
    ?RP_SCHED ! #sched{msg = yield, pid = self()},
    receive
	#sched{msg = continue} -> true
    end.

%% Wait until the scheduler prompts to continue.
-spec wait() -> 'true'.

wait() ->
    receive
	#sched{msg = continue} -> true
    end.
