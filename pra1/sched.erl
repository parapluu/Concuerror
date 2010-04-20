-module(sched).
%%-export([start/3, test/0, test/1]).
%%-export([yield/0]).
-compile(export_all).

%% Scheduler state
%%
%% active:  A set containing all processes ready to be scheduled.
%% blocked: A set containing all processes that cannot be scheduled next
%%          (e.g. waiting for a message on a `receive`).
%% state:   The current state of the program.
%%          A state is a list of LIDs showing the (reverse?) interleaving of
%%          processes up to a point of the program.
%%          
%%          NOTE:
%%          The logical id (LID) for each process reflects the process' logical
%%          position in the program's "process creation tree" and doesn't change
%%          between different runs of the same program (as opposed to erlang
%%          pids).
-record(info, {active, blocked, state}).

%% Internal message format
%%
%% msg:     An atom describing the type of the message.
%% pid:     The sender's pid.
%% spawned: The newly spawned process' pid (in case of a `spawn` message).
-record(sched, {msg, pid, spawned}).

%%%----------------------------------------------------------------------
%%% Exported functions
%%%----------------------------------------------------------------------

interleave(Mod, Fun, Args) ->
    register(sched, self()),
    process_flag(trap_exit, true),
    %% Start state service.
    state_start(),
    %% Insert first state to replay, i.e. "run first process first".
    %% XXX: Breaks state and lid abstraction.
    ets:insert(state, {["P1"]}),
    inter_loop(Mod, Fun, Args, 1),
    state_stop(),
    unregister(sched).

inter_loop(Mod, Fun, Args, RunCounter) ->
    %% Lookup state to replay.
    case state_pop() of
 	no_state -> ok;
 	ReplayState ->
	    log("Interleaving ~p~n", [RunCounter]),
	    log("----------------~n"),
 	    %% Start LID service.
 	    lid_start(),
 	    %% Create the first process.
 	    %% The process is created linked to the scheduler, so that the latter
 	    %% can receive the former's exit message when it terminates. In the same
 	    %% way, every process that may be spawned in the flow of the program
 	    %% shall be linked to this (`sched`) process.
 	    FirstPid = spawn_link(Mod, Fun, Args),
 	    %% Create the first LID and register it with FirstPid.
 	    lid_new(FirstPid),
 	    %% The initial `active` and `blocked` sets are empty.
 	    Active = set_new(),
 	    Blocked = set_new(),
 	    %% Create initial state.
 	    State = state_init(),
 	    %% Receive first message from 
 	    NewInfo = dispatcher(#info{active = Active,
 				       blocked = Blocked,
 				       state = State}),
 	    %% Use driver to replay ReplayState.
 	    driver(NewInfo, ReplayState),
 	    %% Stop LID service (LID tables have to be reset on each run).
 	    lid_stop(),
 	    inter_loop(Mod, Fun, Args, RunCounter + 1)
    end.

%%%----------------------------------------------------------------------
%%% Scheduler core components
%%%----------------------------------------------------------------------

%% Delegates messages sent by instrumented client code to the appropriate
%% handlers.
dispatcher(Info) ->
    receive
	#sched{msg = block, pid = Pid} -> handler(block, Pid, Info, []);
	#sched{msg = spawn, pid = Pid, spawned = ChildPid} ->
	    handler(spawn, Pid, Info, [ChildPid]);
	#sched{msg = yield, pid = Pid} -> handler(yield, Pid, Info, []);
	{'EXIT', Pid, Reason} -> handler(exit, Pid, Info, [Reason]);
	Other -> internal("Dispatcher received: ~p", [Other])
    end.

%% Main scheduler component.
%% Checks for different program states (normal, deadlock, termination, etc.)
%% and acts appropriately. The argument should be a blocked state, i.e. no
%% process running, when the driver is called.
%% In the case of a normal state, the search component is called to handle state
%% expansion and activation of a process. Subsequently the dispatcher is called
%% to delegate the messages received from the running process (or processes,
%% when a `spawn` call is executed) to the appropriate handler functions.
driver(#info{active = Active, blocked = Blocked, state = State} = Info) ->
    %% Deadlock/Termination check.
    %% If the `active` set is empty and the `blocked` set is non-empty, report
    %% a deadlock, else if both sets are empty, report program termination.
    case set_is_empty(Active) of
	true ->
	    case set_is_empty(Blocked) of
		%% TODO
		true ->
		    stop(normal);
		false ->
		    stop(deadlock)
	    end;
	false ->
	    %% Run search algorithm to find next process to be run.
	    Next = search(Info),
	    %% Remove process Next from the `active` set and run it.
	    NewActive = set_remove(Active, Next),
	    log("Running process ~p.~n", [Next]),
	    run(Next),
	    %% Create new state.
	    NewState = state_get_next(State, Next),
	    %% Call the dispatcher to handle incoming messages from the
	    %% running process.
	    NewInfo = dispatcher(Info#info{active = NewActive, state = NewState}),
	    driver(NewInfo)
    end.

%% Same as above, but instead of searching, the Next process is provided at each
%% step by the head of the State argument. When the State list becomes empty,
%% the driver falls back to the standard search behaviour stated above.
driver(Info, []) -> driver(Info);
driver(#info{active = Active, blocked = Blocked, state = State} = Info,
       [Next | Rest]) ->
    %% Deadlock/Termination check.
    %% If the `active` set is empty and the `blocked` set is non-empty, report
    %% a deadlock, else if both sets are empty, report program termination.
    case set_is_empty(Active) of
	true ->
	    case set_is_empty(Blocked) of
		%% TODO
		true ->
		    stop(normal);
		false ->
		    stop(deadlock)
	    end;
	false ->
	    %% Remove process Next from the `active` set and run it.
	    NewActive = set_remove(Active, Next),
	    log("Running process ~p.~n", [Next]),
	    run(Next),
	    %% Create new state.
	    NewState = state_get_next(State, Next),
	    %% Call the dispatcher to handle incoming messages from the
	    %% running process.
	    NewInfo = dispatcher(Info#info{active = NewActive, state = NewState}),
	    driver(NewInfo, Rest)
    end.

stop(Reason) ->
    log("Run terminated (~p).~n~n", [Reason]),
    %% Debug: print state table
    io:format("(Debug) Unexplored: ~p~n~n", [ets:match(state, '$1')]).


%% Signal process Lid to continue its execution.
run(Lid) ->
    Pid = lid_to_pid(Lid),
    Pid ! #sched{msg = continue}.

%% Implements the search logic.
%% Given a blocked state (no process running when called), creates all
%% possible next states, chooses one of them for running and inserts the rest
%% of them into the `states` table.
%% Returns the process to be run next.
search(#info{active = Active, state = State} = Info) ->
    %% Remove a process from the `actives` set and run it.
    {Next, NewActive} = set_pop(Active),
    %% Store all other possible successor states in `states` table for later
    %% exploration.
    state_store_succ(Info#info{active = NewActive, state = State}),
    Next.

%% Receiving a `block` message means that the process cannot be scheduled
%% next and must be moved to the blocked set.
handler(block, Pid, #info{blocked = Blocked} = Info, _Opt) ->
    NewBlocked = set_add(Blocked, lid(Pid)),
    Info#info{blocked = NewBlocked};

%% Discard the exited process (don't add to any set).
handler(exit, Pid, Info, [Reason]) ->
    Lid = lid(Pid),
    log("Process ~p exits (~p).~n", [Lid, Reason]),
    Info;

%% The newly spawned process runs until it reaches a blocking point or
%% terminates. The same goes for its parent process, which is running
%% concurrently. Therefore we have to receive two messages. Either of them
%% can be a `block`, a `yield` or an `exit` message. This is achieved by two
%% calls to the dispatcher.
handler(spawn, ParentPid, Info, [ChildPid]) ->
    ParentLid = lid(ParentPid),
    ChildLid = lid_new(ParentLid, ChildPid),
    log("Process ~p spawns process ~p.~n", [ParentLid, ChildLid]),
    NewInfo = dispatcher(Info),
    dispatcher(NewInfo);

%% Receiving a `yield` message means that the process is preempted, but
%% remains in the active set.
handler(yield, Pid, #info{active = Active} = Info, _Opt) ->
    Lid = lid(Pid),
    log("Process ~p yields.~n", [Lid]),
    NewActive = set_add(Active, Lid),
    Info#info{active = NewActive}.

%%%----------------------------------------------------------------------
%%% Instrumentation interface
%%%----------------------------------------------------------------------

%% Yield replacement.
%% The calling process is preempted, but remains in the active set and awaits
%% a message to continue.
rep_yield() ->
    sched ! #sched{msg = yield, pid = self()},
    receive
	#sched{msg = continue} -> continue
    end.

%% Spawn replacement.
%% The argument provided is a fun executing the original spawn statement,
%% i.e. Fun = fun() -> spawn(...) end.
%% First the process yields, using rep_yield. Afterwards it runs Fun, which
%% actually spawns the new process, informs the scheduler of the spawn and
%% returns the value returned by the original spawn (Pid).
rep_spawn(Fun) ->
    rep_yield(),
    Pid = Fun(),
    sched ! #sched{msg = spawn, pid = self(), spawned = Pid},
    Pid.

%%%----------------------------------------------------------------------
%%% LID interface
%%%----------------------------------------------------------------------

%% Return the LID of process Pid.
lid(Pid) ->
    ets:lookup_element(pid, Pid, 2).

%% "Register" a new process spawned by the process with LID `ParentLID`.
%% Pid is the new process' erlang pid.
%% If called without a `ParentLID` argument, it "registers" the first process.
%% Returns the LID of the newly "registered" process.
lid_new(Pid) ->
    %% The first process has LID = "P1" and has no children spawned at init.
    Lid = "P1",
    ets:insert(lid, {Lid, Pid, 0}),
    ets:insert(pid, {Pid, Lid}),
    Lid.

lid_new(ParentLID, Pid) ->
    [{_ParentLID, _ParentPid, Children}] = ets:lookup(lid, ParentLID),
    %% Create new process' Lid
    Lid = lists:concat([ParentLID, ".", Children + 1]),
    %% Update parent info (increment children counter).
    ets:update_element(lid, ParentLID, {3, Children + 1}),
    %% Insert child info.
    ets:insert(lid, {Lid, Pid, 0}),
    ets:insert(pid, {Pid, Lid}),
    Lid.

%% Initialize LID tables.
%% Must be called before any other call to lid_* functions.
lid_start() ->
    %% Table for storing process info.
    %% Its elements are of the form {Lid, Pid, Children}, where Children
    %% is the number of processes spawned by it so far.
    ets:new(lid, [named_table]),
    %% Table for reverse lookup (Lid -> Pid) purposes.
    %% Its elements are of the form {Pid, Lid}.
    ets:new(pid, [named_table]).

%% Clean up LID tables.
lid_stop() ->
    ets:delete(lid),
    ets:delete(pid).

%% Return the erlang pid of the process Lid.
lid_to_pid(Lid) ->
    ets:lookup_element(lid, Lid, 2).

%%%----------------------------------------------------------------------
%%% Log/Report interface
%%%----------------------------------------------------------------------

%% Print an internal error message.
internal(String) ->
    internal(String, []).

internal(String, Args) ->
    io:format(String, Args).

%% Add a message to log (for now just print to stdout).
log(String) ->
    io:format(String).

log(String, Args) ->
    io:format(String, Args).

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

%% Return a new empty set.
set_new() ->
    sets:new().

%% Remove a "random" element from Set and return that element and the
%% new set.
%% Crashes if given an empty set.
set_pop(Set) ->
    [Head | Tail] = sets:to_list(Set),
    {Head, sets:from_list(Tail)}.

%% Remove Element from Set.
set_remove(Set, Element) ->
    sets:del_element(Element, Set).

%%%----------------------------------------------------------------------
%%% State interface
%%%----------------------------------------------------------------------

%% Given the current state and a process to be run next, return the new state.
state_get_next(State, Next) ->
    [Next | State].

%% Return initial (empty) state.
state_init() ->
    [].

%% Remove and return a state.
%% If no states available, return 'no_state'.
state_pop() ->
    case ets:first(state) of
	'$end_of_table' -> no_state;
	State ->
	    ets:delete(state, State),
	    lists:reverse(State)
    end.

%% Initialize state table.
%% Must be called before any other call to state_* functions.
state_start() ->
    %% Table for storing unvisited states (as keys, the values are irrelevant).
    ets:new(state, [named_table]).

%% Clean up state table.
state_stop() ->
    ets:delete(state).

%% Create all possible next states and add them to the `states` table.
state_store_succ(#info{active = Active, state = State}) ->
    state_store_succ_aux(State, set_list(Active)).

state_store_succ_aux(_State, []) -> ok;
state_store_succ_aux(State, [Proc | Procs]) ->
    ets:insert(state, {[Proc | State]}),
    state_store_succ_aux(State, Procs).

%%%----------------------------------------------------------------------
%%% Unit tests
%%%----------------------------------------------------------------------

test_all(I, Max) when I > Max ->
    io:format("Unit test completed.~n");
test_all(I, Max) ->
    io:format("Running test ~p of ~p:~n", [I, Max]),
    io:format("---------------------~n"),
    try
	test(I),
	io:format("Passed~n~n")
    catch
	Error:Reason -> io:format("Failed (~p, ~p)~n~n", [Error, Reason])
    end,
    test_all(I + 1, Max).

%% Run all tests
test() ->
    test_all(1, 4).

test(1) ->
    io:format("Checking set interface:~n"),
    Set1 = set_new(),
    io:format("Initial set empty..."),
    case set_is_empty(Set1) of
	true -> ok();
	false -> error()
    end,
    io:format("Set add - pop..."),
    Set2 = set_add(Set1, "42"),
    case set_pop(Set2) of
	{"42", Set3} ->
	    case set_is_empty(Set3) of
		true -> ok();
		_Any -> error()
	    end;
	Set3 -> error()
    end,
    io:format("Set add multiple - to_list..."),
    Set4 = set_add(Set3, "42"),
    Set5 = set_add(Set4, "P4.2"),
    Set6 = set_add(Set5, "P42"),
    List = set_list(Set6),
    {Val1, Set7} = set_pop(Set6),
    {Val2, Set8} = set_pop(Set7),
    {Val3, Set9} = set_pop(Set8),
    SList1 = lists:sort(List),
    SList2 = lists:sort([Val1, Val2, Val3]),
    case SList1 =:= SList2 of
	true ->
	    case set_list(Set9) =:= [] of
		true -> ok();
		false -> error()
	    end;
	false -> error()
    end;
test(2) ->
    io:format("Checking lid interface..."),
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
    lid_stop(),
    if P1 =:= Pid1, P2 =:= Pid2, P3 =:= Pid3,
       L1 =:= Lid1, L2 =:= Lid2, L3 =:= Lid3 ->
	    ok();
       true ->
	    error()
    end;
test(3) ->
    Result = interleave(test_instr, test1, []),
    io:format("Result: ~p~n", [Result]);
test(4) ->
    Result = interleave(test_instr, test2, []),
    io:format("Result: ~p~n", [Result]).
%% test(4) ->
%%     Result = interleave(test_instr, test3, []),
%%     io:format("Result: ~p~n", [Result]).

ok() -> io:format(" ok~n").
error() -> io:format(" error~n"), throw(error).
