%%%----------------------------------------------------------------------
%%% File    : sched.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : Scheduler
%%%
%%% Created : 16 May 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%
%%% @doc: Scheduler
%%% @end
%%%----------------------------------------------------------------------

-module(sched).

%% UI related exports.
-export([analyze/2, replay/1]).

%% Instrumentation related exports.
-export([rep_link/1, rep_receive/1, rep_receive_notify/2,
	 rep_send/2, rep_spawn/1, rep_spawn_link/1, rep_yield/0]).

-export_type([proc_action/0, analysis_target/0, error_descr/0, state/0]).

-include("gen.hrl").

%%%----------------------------------------------------------------------
%%% Eunit related
%%%----------------------------------------------------------------------

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

%%%----------------------------------------------------------------------
%%% Types
%%%----------------------------------------------------------------------

-type analysis_info() :: {analysis_target(), {integer(), integer()}}.

%% Analysis result tuple.
-type analysis_ret() :: {'ok', analysis_info()} |
                        {'error', 'instr', analysis_info()} |
                        {'error', 'analysis', analysis_info(),
			 [ticket:ticket()]}.

%% Module-Function-Options tuple.
-type analysis_target() :: {module(), atom(), [term()]}.

%% The destination of a `send' operation.
-type dest() :: pid() | port() | atom() | {atom(), node()}.

%% Error descriptor.
-type error_descr() :: 'deadlock' | 'assert'.

-type error_info() :: 'assert'.

%% A process' exit reasons
-type exit_reasons() :: {{'assertion_failed', [term()]}, term()}.

%% The logical id (LID) for each process reflects the process' logical
%% position in the program's "process creation tree" and doesn't change
%% between different runs of the same program (as opposed to erlang pids).
-type lid() :: string().

%% Tuples providing information about a process' action.
-type proc_action() :: {'block', lid()} |
                       {'link', lid(), lid()} |
                       {'receive', lid(), lid(), term()} |
                       {'send', lid(), lid(), term()} |
                       {'spawn', lid(), lid()} |
                       {'exit', lid(), exit_reasons()}.

%% A state is a list of LIDs showing the (reverse) interleaving of
%% processes up to a point of the program.
-type state() :: [lid()].

%%%----------------------------------------------------------------------
%%% Records
%%%----------------------------------------------------------------------

%% Scheduler state
%%
%% active:  A set containing all processes ready to be scheduled.
%% blocked: A set containing all processes that cannot be scheduled next
%%          (e.g. waiting for a message on a `receive`).
%% error:   An atom describing the error that occured.
%% state:   The current state of the program.
-record(info, {active  :: set(),
               blocked :: set(),
	       error   :: error_info(),
               state   :: state()}).

%% Internal message format
%%
%% msg:     An atom describing the type of the message.
%% pid:     The sender's pid.
%% misc:    A list of optional arguments, depending on the the message type.
-record(sched, {msg  :: atom(),
                pid  :: pid(),
                misc :: [term()]}).

%%%----------------------------------------------------------------------
%%% User interface
%%%----------------------------------------------------------------------

%% @spec: analyze(analysis_target(), [term()]) -> analysis_ret()
%% @doc: Produce all interleavings of running `Target'.
-spec analyze(analysis_target(), [term()]) -> analysis_ret().

analyze(Target, Options) ->
    %% List of files to instrument.
    Files = case lists:keyfind(files, 1, Options) of
		false -> [];
	        {files, List} -> List
	    end,
    %% Disable error logging messages.
    error_logger:tty(false),
    case instr:instrument_and_load(Files) of
	ok ->
	    log:log("Running analysis...~n"),
	    {Result, {Mins, Secs}} = interleave(Target),
	    case Result of
		{ok, RunCount} ->
		    log:log("Analysis complete (checked ~w interleavings "
			    "in ~wm~.2fs):~n", [RunCount, Mins, Secs]),
		    log:log("No errors found.~n"),
		    Info = {Target, {Mins, Secs}},
		    {ok, Info};
		{error, RunCount, Tickets} ->
		    TicketCount = length(Tickets),
		    log:log("Analysis complete (checked ~w interleavings "
			    "in ~wm~.2fs):~n", [RunCount, Mins, Secs]),
		    log:log("Found ~p error(s).~n", [TicketCount]),
		    Info = {Target, {Mins, Secs}},
		    {error, analysis, Info, Tickets}
	    end;
	error ->
	    Info = {Target, {0, 0}},
	    {error, instr, Info}
    end.

%% @spec: replay(analysis_target(), state()) -> [proc_action()]
%% @doc: Replay the given state and return detailed information about the
%% process interleaving.
-spec replay(ticket:ticket()) -> [proc_action()].

replay(Ticket) ->
    replay_logger:start(),
    replay_logger:start_replay(),
    Target = ticket:get_target(Ticket),
    State = ticket:get_state(Ticket),
    interleave(Target, [details, {init_state, State}]),
    Result = replay_logger:get_replay(),
    replay_logger:stop(),
    Result.

%% Produce all possible process interleavings of (Mod, Fun, Args).
%% Options:
%%   {init_state, InitState}: State to replay (default: state_init()).
%%   details: Produce detailed interleaving information (see `replay_logger`).
interleave(Target) ->
    interleave(Target, [init_state, state_init()]).

interleave(Target, Options) ->
    Self = self(),
    %% TODO: Need spawn_link?
    spawn(fun() -> interleave_aux(Target, Options, Self) end),
    receive
	{interleave_result, Result} -> Result
    end.

interleave_aux(Target, Options, Parent) ->
    InitState =
	case lists:keyfind(init_state, 1, Options) of
	    false -> state_init();
	    {init_state, Any} -> Any
	end,
    DetailsFlag = lists:member(details, Options),
    register(?RP_SCHED, self()),
    %% The mailbox is flushed mainly to discard possible `exit` messages
    %% before enabling the `trap_exit` flag.
    flush_mailbox(),
    process_flag(trap_exit, true),
    %% Start state service.
    state_start(),
    %% Insert empty replay state for the first run.
    state_insert(InitState),
    {T1, _} = statistics(wall_clock),
    Result = interleave_loop(Target, 1, [], DetailsFlag),
    {T2, _} = statistics(wall_clock),
    Time = elapsed_time(T1, T2),
    state_stop(),
    unregister(?RP_SCHED),
    Parent ! {interleave_result, {Result, Time}}.

%% Main loop for producing process interleavings.
interleave_loop(Target, RunCounter, Tickets) ->
    interleave_loop(Target, RunCounter, Tickets, false).

interleave_loop(Target, RunCounter, Tickets, DetailsFlag) ->
    %% Lookup state to replay.
    case state_pop() of
        no_state ->
	    case Tickets of
		[] -> {ok, RunCounter - 1};
		_Any -> {error, RunCounter - 1, lists:reverse(Tickets)}
	    end;
        ReplayState ->
            ?debug_1("Running interleaving ~p~n", [RunCounter]),
            ?debug_1("----------------------~n"),
            %% Start LID service.
            lid_start(),
            %% Create the first process.
            %% The process is created linked to the scheduler, so that the
            %% latter can receive the former's exit message when it terminates.
            %% In the same way, every process that may be spawned in the course
            %% of the program shall be linked to this process.
	    {Mod, Fun, Args} = Target,
            FirstPid = spawn_link(Mod, Fun, Args),
            %% Create the first LID and register it with FirstPid.
            lid_new(FirstPid),
            %% The initial `active` and `blocked` sets are empty.
            Active = set_new(),
            Blocked = set_new(),
            %% Create initial state.
            State = state_init(),
	    %% TODO: Not especially nice (maybe refactor into driver?).
            %% Receive the first message from the first process. That is, wait
            %% until it yields, blocks or terminates.
            NewInfo = dispatcher(#info{active = Active,
                                       blocked = Blocked,
                                       state = State},
				 DetailsFlag),
            %% Use driver to replay ReplayState.
            Ret = driver(NewInfo, ReplayState, DetailsFlag),
	    %% TODO: Proper cleanup of any remaining processes.
            %% Stop LID service (LID tables have to be reset on each run).
            lid_stop(),
            case Ret of
                ok -> interleave_loop(Target, RunCounter + 1, Tickets);
                {error, ErrorDescr, ErrorState} ->
		    Ticket = ticket:new(Target, ErrorDescr, ErrorState),
		    interleave_loop(Target, RunCounter + 1, [Ticket|Tickets])
            end
    end.

%%%----------------------------------------------------------------------
%%% Core components
%%%----------------------------------------------------------------------

%% Delegates messages sent by instrumented client code to the appropriate
%% handlers.
dispatcher(Info) -> dispatcher(Info, false).

dispatcher(Info, DetailsFlag) ->
    receive
	#sched{msg = block, pid = Pid} ->
	    handler(block, Pid, Info, [], DetailsFlag);
	#sched{msg = link, pid = Pid, misc = [TargetPid]} ->
	    handler(link, Pid, Info, [TargetPid], DetailsFlag);
	#sched{msg = 'receive', pid = Pid, misc = [From, Msg]} ->
	    handler('receive', Pid, Info, [From, Msg], DetailsFlag);
	#sched{msg = send, pid = Pid, misc = [Dest, Msg]} ->
	    handler(send, Pid, Info, [Dest, Msg], DetailsFlag);
	#sched{msg = spawn, pid = Pid, misc = [ChildPid]} ->
	    handler(spawn, Pid, Info, [ChildPid], DetailsFlag);
	#sched{msg = yield, pid = Pid} ->
	    handler(yield, Pid, Info, [], DetailsFlag);
	{'EXIT', Pid, Reason} ->
	    handler(exit, Pid, Info, [Reason], DetailsFlag);
	Other ->
	    log:internal("Dispatcher received: ~p~n", [Other])
    end.

%% Main scheduler component.
%% Checks for different program states (normal, deadlock, termination, etc.)
%% and acts appropriately. The argument should be a blocked scheduler state,
%% i.e. no process running when the driver is called.
%% In the case of a normal (meaning non-terminal) state, the search component
%% is called to handle state expansion and returns a process for activation.
%% After activating said process the dispatcher is called to delegate the
%% messages received from the running process to the appropriate handler
%% functions.
driver(#info{active = Active, blocked = Blocked,
	     error = Error, state = State} = Info,
       DetailsFlag) when is_boolean(DetailsFlag) ->
    %% Assertion violation check.
    case Error of
	assert -> {error, assert, State};
	_NoError ->
	    %% Deadlock/Termination check.
	    %% If the `active` set is empty and the `blocked` set is non-empty,
            %% report a deadlock, else if both sets are empty, report normal
	    %% program termination.
	    case set_is_empty(Active) of
		true ->
		    ?debug_1("-----------------------~n"),
		    ?debug_1("Run terminated.~n~n"),
		    case set_is_empty(Blocked) of
			true -> ok;
			false -> {error, deadlock, State}
		    end;
		false ->
		    %% Run search algorithm to find next process to be run.
		    Next = search(Info),
		    %% Remove process Next from the `active` set and run it.
		    NewActive = set_remove(Active, Next),
		    ?debug_2("Running process ~s.~n", [Next]),
		    run(Next),
		    %% Create new state.
		    NewState = state_get_next(State, Next),
		    %% Call the dispatcher to handle incoming messages from the
		    %% running process.
		    NewInfo = dispatcher(Info#info{active = NewActive,
						   state = NewState},
					 DetailsFlag),
		    driver(NewInfo, DetailsFlag)
	    end
    end.

%% Same as above, but instead of searching, the process to be activated is
%% provided at each step by the head of the State argument. When the State list
%% is empty, the driver falls back to the standard search behavior stated above.
driver(Info, [], DetailsFlag) -> driver(Info, DetailsFlag);
driver(#info{active = Active, blocked = Blocked,
	     error = Error, state = State} = Info, [Next|Rest], DetailsFlag) ->
    %% Assertion violation check.
    case Error of
	assert -> {error, assert, State};
	_NoError ->
	    %% Deadlock/Termination check.
	    %% If the `active` set is empty and the `blocked` set is non-empty,
	    %% report a deadlock, else if both sets are empty, report normal
            %% program termination.
	    case set_is_empty(Active) of
		true ->
		    ?debug_1("-----------------------~n"),
		    ?debug_1("Run terminated.~n~n"),
		    case set_is_empty(Blocked) of
			true -> ok;
			false -> {error, deadlock, State}
		    end;
		false ->
		    %% Remove process Next from the `active` set and run it.
		    NewActive = set_remove(Active, Next),
		    ?debug_2("Running process ~s.~n", [Next]),
		    run(Next),
		    %% Create new state.
		    NewState = state_get_next(State, Next),
		    %% Call the dispatcher to handle incoming messages from the
		    %% running process.
		    NewInfo = dispatcher(Info#info{active = NewActive,
						   state = NewState},
					 DetailsFlag),
		    driver(NewInfo, Rest, DetailsFlag)
	    end
    end.

%% Implements the search logic (currently depth-first when looked at combined
%% with the replay logic).
%% Given a blocked state (no process running when called), creates all
%% possible next states, chooses one of them for running and inserts the rest
%% of them into the `states` table.
%% Returns the process to be run next.
search(#info{active = Active, state = State} = Info) ->
    %% Remove a process from the `actives` set and run it.
    {Next, NewActive} = set_pop(Active),
    %% Store all other possible successor states in `states` table for later
    %% exploration.
    state_insert_succ(Info#info{active = NewActive, state = State}),
    Next.

%% Block message handler.
%% Receiving a `block` message means that the process cannot be scheduled
%% next and must be moved to the blocked set.
handler(block, Pid, #info{blocked = Blocked} = Info, _Misc, DetailsFlag) ->
    Lid = lid(Pid),
    NewBlocked = set_add(Blocked, Lid),
    ?debug_1("Process ~s blocks.~n", [Lid]),
    case DetailsFlag of
	true -> replay_logger:log({block, Lid});
	false -> continue
    end,
    Info#info{blocked = NewBlocked};

%% Exit message handler.
%% Discard the exited process (don't add to any set).
%% If the exited process is irrelevant (i.e. has no LID assigned),
%% call the dispatcher.
handler(exit, Pid, Info, [Reason], DetailsFlag) ->
    Lid = lid(Pid),
    case Lid of
	not_found ->
	    ?debug_2("Process ~s (pid = ~p) exits (~p).~n", [Lid, Pid, Reason]),
	    dispatcher(Info);
	_Any ->
	    ?debug_1("Process ~s exits (~p).~n", [Lid, Reason]),
	    case DetailsFlag of
		true -> replay_logger:log({exit, Lid, Reason});
		false -> continue
	    end,
	    %% If the exception was caused by an assertion violation, propagate
	    %% it to the driver via the `error` field of the `info` record.
	    case Reason of
		{{assertion_failed, _Details}, _Stack} ->
		    Info#info{error = assert};
		_Other -> Info
	    end
    end;

%% Link message handler.
handler(link, Pid, Info, [TargetPid], DetailsFlag) ->
    Lid = lid(Pid),
    TargetLid = lid(TargetPid),
    ?debug_1("Process ~s links to process ~s.~n", [Lid, TargetLid]),
    case DetailsFlag of
	true -> replay_logger:log({link, Lid, TargetLid});
	false -> continue
    end,
    dispatcher(Info, DetailsFlag);

%% Receive message handler.
handler('receive', Pid, Info, [From, Msg], DetailsFlag) ->
    Lid = lid(Pid),
    SenderLid = lid(From),
    ?debug_1("Process ~s receives message `~p` from process ~s.~n",
	    [Lid, Msg, SenderLid]),
    case DetailsFlag of
	true -> replay_logger:log({'receive', Lid, SenderLid, Msg});
	false -> continue
    end,
    dispatcher(Info, DetailsFlag);

%% Send message handler.
%% When a message is sent to a process, the receiving process has to be awaken
%% if it is blocked on a receive.
%% XXX: No check for reason of blocking for now. If the process is blocked on
%%      something else, it will be awaken!
handler(send, Pid, Info, [DstPid, Msg], DetailsFlag) ->
    Lid = lid(Pid),
    DstLid = lid(DstPid),
    ?debug_1("Process ~s sends message `~p` to process ~s.~n",
	    [Lid, Msg, DstLid]),
    case DetailsFlag of
	true -> replay_logger:log({send, Lid, DstLid, Msg});
	false -> continue
    end,
    NewInfo = wakeup(DstLid, Info),
    dispatcher(NewInfo, DetailsFlag);

%% Spawn message handler.
%% First, link the newly spawned process to the scheduler process.
%% The new process yields as soon as it gets spawned and the parent process
%% yields as soon as it spawns. Therefore wait for two `yield` messages using
%% two calls to the dispatcher.
handler(spawn, ParentPid, Info, [ChildPid], DetailsFlag) ->
    link(ChildPid),
    ParentLid = lid(ParentPid),
    ChildLid = lid_new(ParentLid, ChildPid),
    ?debug_1("Process ~s spawns process ~s.~n", [ParentLid, ChildLid]),
    case DetailsFlag of
	true -> replay_logger:log({spawn, ParentLid, ChildLid});
	false -> continue
    end,
    NewInfo = dispatcher(Info, DetailsFlag),
    dispatcher(NewInfo, DetailsFlag);

%% Yield message handler.
%% Receiving a `yield` message means that the process is preempted, but
%% remains in the active set.
handler(yield, Pid, #info{active = Active} = Info, _Opt, DetailsFlag) ->
    case lid(Pid) of
        %% This case clause avoids a possible race between `yield` message
        %% of child and `spawn` message of parent.
        not_found ->
            ?RP_SCHED ! #sched{msg = yield, pid = Pid},
            dispatcher(Info, DetailsFlag);
        Lid ->
            ?debug_2("Process ~s yields.~n", [Lid]),
            NewActive = set_add(Active, Lid),
            Info#info{active = NewActive}
    end.

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

%% Flush a process' mailbox.
flush_mailbox() ->
    receive
	_Any -> flush_mailbox()
    after 0 -> ok
    end.

%% Calculate and print elapsed time between T1 and T2.
elapsed_time(T1, T2) ->
    ElapsedTime = T2 - T1,
    Mins = ElapsedTime div 60000,
    Secs = (ElapsedTime rem 60000) / 1000,
    ?debug_1("Done in ~wm~.2fs\n", [Mins, Secs]),
    {Mins, Secs}.

%% Signal process Lid to continue its execution.
run(Lid) ->
    Pid = lid_to_pid(Lid),
    Pid ! #sched{msg = continue}.

%% Wakeup a process.
%% If process is in `blocked` set, move to `active` set.
wakeup(Lid, #info{active = Active, blocked = Blocked} = Info) ->
    case set_member(Blocked, Lid) of
	true ->
            ?debug_2("Process ~p wakes up.~n", [Lid]),
	    NewBlocked = set_remove(Blocked, Lid),
	    NewActive = set_add(Active, Lid),
	    Info#info{active = NewActive, blocked = NewBlocked};
	false ->
	    Info
    end.

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

%% @spec: rep_link(pid() | port()) -> 'true'
%% @doc: Replacement for `link/1'.
%%
%% Just yield after linking.
-spec rep_link(pid() | port()) -> 'true'.

rep_link(Pid) ->
    Result = link(Pid),
    ?RP_SCHED ! #sched{msg = link, pid = self(), misc = [Pid]},
    rep_yield(),
    Result.

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

%% @spec rep_receive(fun((function()) -> term())) -> term()
%% @doc: Replacement for a `receive' statement.
%%
%% The first time the process is scheduled it searches its mailbox. If no
%% matching message is found, it blocks (i.e. is moved to the blocked set).
%% When a new message arrives the process is woken up.
%% The check mailbox - block - wakeup loop is repeated until a matching message
%% arrives.
-spec rep_receive(fun((function()) -> term())) -> term().

rep_receive(Fun) ->
    rep_receive_aux(Fun).

rep_receive_aux(Fun) ->
    Fun(fun() -> block(), rep_receive_aux(Fun) end).

%% @spec rep_receive_notify(pid(), term()) -> 'ok'
%% @doc: Auxiliary function used in the `receive' statetement instrumentation.
%%
%% Called first thing after a message has been received, to inform the scheduler
%% about the message received and the sender.
-spec rep_receive_notify(pid(), term()) -> 'ok'.

rep_receive_notify(From, Msg) ->
    ?RP_SCHED ! #sched{msg = 'receive', pid = self(), misc = [From, Msg]},
    rep_yield(),
    ok.

%% @spec rep_send(dest(), term()) -> term()
%% @doc: Replacement for `send/2' (and the equivalent `!' operator).
%%
%% Just yield after sending.
-spec rep_send(dest(), term()) -> term().

rep_send(Dest, Msg) ->
    {_Self, RealMsg} = Dest ! Msg,
    ?RP_SCHED ! #sched{msg = send, pid = self(), misc = [Dest, RealMsg]},
    rep_yield(),
    RealMsg.

%% @spec rep_spawn(function()) -> pid()
%% @doc: Replacement for `spawn/1'.
%%
%% The argument provided is the argument of the original spawn call.
%% When spawned, the new process has to yield.
-spec rep_spawn(function()) -> pid().

rep_spawn(Fun) ->
    Pid = spawn(fun() -> rep_yield(), Fun() end),
    ?RP_SCHED ! #sched{msg = spawn, pid = self(), misc = [Pid]},
    rep_yield(),
    Pid.

%% @spec rep_spawn_link(function()) -> pid()
%% @doc: Replacement for `spawn_link/1'.
%%
%% The argument provided is the argument of the original spawn call.
%% When spawned, the new process has to yield.
-spec rep_spawn_link(function()) -> pid().

rep_spawn_link(Fun) ->
    Pid = spawn_link(fun() -> rep_yield(), Fun() end),
    %% Same as rep_spawn for now.
    ?RP_SCHED ! #sched{msg = spawn, pid = self(), misc = [Pid]},
    rep_yield(),
    Pid.

%%%----------------------------------------------------------------------
%%% LID interface
%%%----------------------------------------------------------------------

%% Return the LID of process Pid or 'not_found' if mapping not in table.
lid(Pid) ->
    case ets:lookup(?NT_PID, Pid) of
	[{_Pid, Lid}] -> Lid;
	[] -> not_found
    end.

%% "Register" a new process spawned by the process with LID `ParentLID`.
%% Pid is the new process' erlang pid.
%% If called without a `ParentLID` argument, it "registers" the first process.
%% Returns the LID of the newly "registered" process.
lid_new(Pid) ->
    %% The first process has LID = "P1" and has no children spawned at init.
    Lid = "P1",
    ets:insert(?NT_LID, {Lid, Pid, 0}),
    ets:insert(?NT_PID, {Pid, Lid}),
    Lid.

lid_new(ParentLID, Pid) ->
    [{_ParentLID, _ParentPid, Children}] = ets:lookup(?NT_LID, ParentLID),
    %% Create new process' Lid
    Lid = lists:concat([ParentLID, ".", Children + 1]),
    %% Update parent info (increment children counter).
    ets:update_element(?NT_LID, ParentLID, {3, Children + 1}),
    %% Insert child info.
    ets:insert(?NT_LID, {Lid, Pid, 0}),
    ets:insert(?NT_PID, {Pid, Lid}),
    Lid.

%% Initialize LID tables.
%% Must be called before any other call to lid_* functions.
lid_start() ->
    %% Table for storing process info.
    %% Its elements are of the form {Lid, Pid, Children}, where Children
    %% is the number of processes spawned by it so far.
    ets:new(?NT_LID, [named_table]),
    %% Table for reverse lookup (Lid -> Pid) purposes.
    %% Its elements are of the form {Pid, Lid}.
    ets:new(?NT_PID, [named_table]).

%% Clean up LID tables.
lid_stop() ->
    ets:delete(?NT_LID),
    ets:delete(?NT_PID).

%% Return the erlang pid of the process Lid.
lid_to_pid(Lid) ->
    ets:lookup_element(?NT_LID, Lid, 2).

%%%----------------------------------------------------------------------
%%% Set interface
%%%----------------------------------------------------------------------

%% Add Element to Set and return new set.
set_add(Set, Element) ->
    sets:add_element(Element, Set).

%% Return true if Set is empty, false otherwise.
set_is_empty(Set) ->
    sets:to_list(Set) =:= [].

%% Return a list of the elements in Set.
set_list(Set) ->
    sets:to_list(Set).

%% Checks if Element is in Set.
set_member(Set, Element) ->
    sets:is_element(Element, Set).

%% Return a new empty set.
set_new() ->
    sets:new().

%% Remove a "random" element from Set and return that element and the
%% new set.
%% Crashes if given an empty set.
set_pop(Set) ->
    [Head|Tail] = sets:to_list(Set),
    {Head, sets:from_list(Tail)}.

%% Remove Element from Set.
set_remove(Set, Element) ->
    sets:del_element(Element, Set).

%%%----------------------------------------------------------------------
%%% State interface
%%%----------------------------------------------------------------------

%% Given the current state and a process to be run next, return the new state.
state_get_next(State, Next) ->
    [Next|State].

%% Return initial (empty) state.
state_init() ->
    [].

%% Add a state to the `state` table.
state_insert(State) ->
    ets:insert(?NT_STATE, {State}).

%% Create all possible next states and add them to the `state` table.
state_insert_succ(#info{active = Active, state = State}) ->
    state_insert_succ_aux(State, set_list(Active)).

state_insert_succ_aux(_State, []) -> ok;
state_insert_succ_aux(State, [Proc|Procs]) ->
    ets:insert(?NT_STATE, {[Proc|State]}),
    state_insert_succ_aux(State, Procs).

%% Remove and return a state.
%% If no states available, return 'no_state'.
state_pop() ->
    case ets:first(?NT_STATE) of
	'$end_of_table' -> no_state;
	State ->
	    ets:delete(?NT_STATE, State),
	    lists:reverse(State)
    end.

%% Initialize state table.
%% Must be called before any other call to state_* functions.
state_start() ->
    %% Table for storing unvisited states (as keys, the values are irrelevant).
    ets:new(?NT_STATE, [named_table]).

%% Clean up state table.
state_stop() ->
    ets:delete(?NT_STATE).

%%%----------------------------------------------------------------------
%%% Unit tests
%%%----------------------------------------------------------------------

-spec set_test_() -> term().

set_test_() ->
     [{"Empty",
       ?_assertEqual(true, set_is_empty(set_new()))},
      {"Add/remove one",
       ?_test(begin
		  {Result, NewSet} = set_pop(set_add(set_new(), 42)),
		  ?assertEqual(42, Result),
		  ?assertEqual(true, set_is_empty(NewSet))
	      end)},
      {"Add/remove multiple",
      ?_test(begin
		 Set = set_add(set_add(set_add(set_new(), "42"), "P4.2"),
                               "P42"),
		 List1 = lists:sort(set_list(Set)),
		 {Val1, Set1} = set_pop(Set),
		 {Val2, Set2} = set_pop(Set1),
		 {Val3, Set3} = set_pop(Set2),
		 List2 = lists:sort([Val1, Val2, Val3]),
		 ?assertEqual(List1, List2),
		 ?assertEqual(true, set_is_empty(Set3))
	     end)}].

-spec lid_test_() -> term().

lid_test_() ->
     [{"Lid",
       ?_test(begin
		  lid_start(),
		  Pid1 = c:pid(0, 2, 3),
		  Lid1 = lid_new(Pid1),
		  Pid2 = c:pid(0, 2, 4),
		  Lid2 = lid_new(Lid1, Pid2),
		  Pid3 = c:pid(0, 2, 5),
		  Lid3 = lid_new(Lid1, Pid3),
		  P1 = lid_to_pid(Lid1),
		  L1 = lid(Pid1),
		  P2 = lid_to_pid(Lid2),
		  L2 = lid(Pid2),
		  P3 = lid_to_pid(Lid3),
		  L3 = lid(Pid3),
		  L4 = lid(c:pid(0, 2, 6)),
		  lid_stop(),
		  ?assertEqual(P1, Pid1),
		  ?assertEqual(P2, Pid2),
		  ?assertEqual(P3, Pid3),
		  ?assertEqual(L1, Lid1),
		  ?assertEqual(L2, Lid2),
		  ?assertEqual(L3, Lid3),
		  ?assertEqual(L4, 'not_found')
	      end)}].

-spec interleave_test_() -> term().

interleave_test_() ->
    {setup,
     fun() -> log:start(log, []) end,
     fun(_) -> log:stop() end,
     [{"test1",
       ?_assertMatch({ok, {{test, test1, []}, _}},
		     analyze({test, test1, []}, [{files, ["./test/test.erl"]}]))},
      {"test2",
       ?_assertMatch({ok, {{test, test2, []}, _}},
		     analyze({test, test2, []}, [{files, ["./test/test.erl"]}]))},
      {"test3",
       ?_assertMatch({ok, {{test, test3, []}, _}},
		     analyze({test, test3, []}, [{files, ["./test/test.erl"]}]))},
      {"test4",
       ?_test(
	  begin
	      Target = {test, test4, []},
	      Options = [{files, ["./test/test.erl"]}],
	      {error, analysis, Info, [Ticket|_Tickets]} =
		  analyze(Target, Options),
	      ?assertMatch({Target, {_, _}}, Info), 
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual("Deadlock", ticket:get_error_string(Ticket))
	  end)},
      {"test5",
       ?_test(
	  begin
	      Target = {test, test5, []},
	      Options = [{files, ["./test/test.erl"]}],
	      {error, analysis, Info, [Ticket|_Tickets]} =
		  analyze(Target, Options),
	      ?assertMatch({Target, {_, _}}, Info), 
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual("Deadlock", ticket:get_error_string(Ticket))
	  end)},
      {"test6",
       ?_assertMatch({ok, {{test, test6, []}, _}},
		     analyze({test, test6, []}, [{files, ["./test/test.erl"]}]))},
      {"test7",
       ?_assertMatch({ok, {{test, test7, []}, _}},
		     analyze({test, test7, []}, [{files, ["./test/test.erl"]}]))},
      {"test8",
       ?_test(
	  begin
	      Target = {test, test8, []},
	      Options = [{files, ["./test/test.erl"]}],
	      {error, analysis, Info, [Ticket|_Tickets]} =
		  analyze(Target, Options),
	      ?assertMatch({Target, {_, _}}, Info), 
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual("Assertion violation",
			   ticket:get_error_string(Ticket))
	  end)},
      {"test9",
       ?_assertMatch({ok, {{test, test3, []}, _}},
		     analyze({test, test3, []},
			     [{files, ["./test/test.erl",
				       "./test/test_aux.erl"]}]))},
      {"test10",
       ?_assertMatch({ok, {{test, test9, []}, _}},
		     analyze({test, test9, []},
			     [{files, ["./test/test.erl",
				       "./test/test_aux.erl"]}]))},
      {"test11",
       ?_test(
	  begin
	      Target = {test, test10, []},
	      Options = [{files, ["./test/test.erl"]}],
	      {error, analysis, Info, [Ticket|_Tickets]} =
		  analyze(Target, Options),
	      ?assertMatch({Target, {_, _}}, Info), 
	      ?assertEqual(Target, ticket:get_target(Ticket)),
	      ?assertEqual("Assertion violation",
			   ticket:get_error_string(Ticket))
	  end)},
      {"test12",
       ?_assertMatch({ok, {{test, test11, []}, _}},
		     analyze({test, test11, []},
			     [{files, ["./test/test.erl",
				       "./test/test_aux.erl"]}]))},
      {"test13",
       ?_assertMatch({ok, {{test, test12, []}, _}},
		     analyze({test, test12, []},
			     [{files, ["./test/test.erl",
				       "./test/test_aux.erl"]}]))},
      {"test14",
       ?_assertMatch({ok, {{test, test13, []}, _}},
		     analyze({test, test13, []},
			     [{files, ["./test/test.erl",
				       "./test/test_aux.erl"]}]))}
     ]}.
