-module(sched).
-compile(export_all).
%%-export([start/3, test/0]).

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
%% msg:    An atom describing the type of the message.
%% pid:    The sender's pid.
-record(sched, {msg, pid}).

%%%----------------------------------------------------------------------
%%% Exported functions
%%%----------------------------------------------------------------------

start(Mod, Fun, Args) ->
    register(sched, self()),
    process_flag(trap_exit, true),
    %% Start state and lid services.
    lid_start(),
    state_start(),
    %% Create the first process.
    %% The process is created linked to the scheduler, so that the latter
    %% can receive the former's exit message when it terminates. In the same
    %% way, every process that may be spawned in the flow of the program
    %% shall be linked to this (`sched`) process.
    FirstPid = spawn_link(Mod, Fun, Args),
    FirstLid = lid_new(FirstPid),
    %% The initial `active` set contains only the first process.
    ActiveInit = set_new(),
    Active = set_add(ActiveInit, FirstLid),
    %% The initial `blocked` set is empty.
    Blocked = set_new(),
    %% Create initial state.
    State = state_init(),
    driver(#info{active = Active, blocked = Blocked, state = State}).

%%%----------------------------------------------------------------------
%%% Scheduler core components
%%%----------------------------------------------------------------------

%% Delegates messages sent by instrumented client code to the appropriate
%% handlers.
dispatcher(Info) ->
    receive
	#sched{msg = block, pid = Pid} -> handler(block, Pid, Info, []);
	#sched{msg = spawn, pid = Pid} -> handler(spawn, Pid, Info, []);
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
%% The loop is closed by the handler functions calling the driver.
driver(#info{active = Active, blocked = Blocked} = Info) ->
    %% Deadlock/Termination check.
    %% If the `active` set is empty and the `blocked` set is non-empty, report
    %% a deadlock, else if both sets are empty, report program termination.
    case set_is_empty(Active) of
	true ->
	    case set_is_empty(Blocked) of
		true -> terminate; %% TODO
		false -> deadlock  %% TODO
	    end;
	false ->
	    NewInfo = search(Info),
	    dispatcher(NewInfo)
    end.

run(_Lid) ->
    unimplemented.

%% Implements the search logic.
%% Given a blocked state (no process running when called), creates all
%% possible next states, chooses one of them for running and inserts the rest
%% of them into the `states` table.
%% Returns the new scheduler state.
search(#info{active = Active, blocked = Blocked, state = State}) ->
    %% Remove a process from the `actives` set and run it.
    {Next, NewActive} = set_pop(Active),
    run(Next),
    %% Store all other possible successor states in `states` table for later
    %% exploration.
    state_store_succ(#info{active = NewActive, state = State}),
    %% Create new current state.
    NewState = state_get_next(State, Next),
    #info{active = NewActive, blocked = Blocked, state = NewState}.

%% Receiving a `block` message means that the process cannot be scheduled
%% next and must be moved to the blocked set.
handler(block, Pid, #info{blocked = Blocked} = Info, _Opt) ->
    NewBlocked = set_add(Blocked, lid(Pid)),
    driver(Info#info{blocked = NewBlocked});

%% Discard the exited process (don't add to any set).
handler(exit, _Pid, Info, [_Reason]) ->
    driver(Info);

%% The newly spawned process runs until it reaches a blocking point or
%% terminates. The same goes for its parent process, which is running
%% concurrently. Therefore we have to receive two messages. Either of them
%% can be a `block`, a `yield` or an `exit` message. This is achieved by two
%% calls to the dispatcher (FIXME: one here, one at the dispatcher?).
handler(spawn, Pid, #info{active = Active} = Info, _Opt) ->
    %% TODO: unimplemented
    NewActive = set_add(Active, lid(Pid)),
    driver(Info#info{active = NewActive});

%% Receiving a `yield` message means that the process is preempted, but
%% remains in the active set.
handler(yield, Pid, #info{active = Active} = Info, _Opt) ->
    NewActive = set_add(Active, lid(Pid)),
    driver(Info#info{active = NewActive}).

%%%----------------------------------------------------------------------
%%% LID interface
%%%----------------------------------------------------------------------

%% Return the LID of process Pid.
lid(Pid) ->
    {Lid, _Pid, _Children} = ets:lookup_element(proc, Pid, 2),
    Lid.

%% Initialize LID table.
%% Must be called before any other call to lid_* functions.
lid_start() ->
    %% Table for storing process info.
    %% Its elements are of the form {Lid, Pid, Children}, where Children
    %% is the number of processes spawned by it so far.
    ets:new(proc, [named_table]).

%% "Register" a new process spawned by the process with LID `ParentLID`.
%% Pid is the new process' erlang pid.
%% If called without a `ParentLID` argument, it "registers" the first process.
%% Returns the LID of the newly "registered" process.
lid_new(Pid) ->
    %% The first process has LID = "P1" and has no children spawned at init.
    Lid = "P1",
    ets:insert(proc, {Lid, Pid, 0}),
    Lid.

lid_new(ParentLID, Pid) ->
    [{_ParentLID, _ParentPid, Children}] = ets:lookup(proc, ParentLID),
    %% Create new process' Lid
    Lid = lists:concat([ParentLID, ".", Children + 1]),
    %% Update parent info (increment children counter).
    ets:update_element(proc, ParentLID, {3, Children + 1}),
    %% Insert child info.
    ets:insert(proc, {Lid, Pid, 0}),
    Lid.

%%%----------------------------------------------------------------------
%%% Log/Report interface
%%%----------------------------------------------------------------------

%% Print an internal error message.
internal(String) ->
    internal(String, []).

internal(String, Args) ->
    io:format(String, Args).

%%%----------------------------------------------------------------------
%%% Set interface
%%%----------------------------------------------------------------------

%% Add element to set and return new set.
set_add(Set, Element) ->
    sets:add_element(Element, Set).

%% Return true if the given set is empty, false otherwise.
set_is_empty(Set) ->
    sets:to_list(Set) =:= [].

%% Return a list of the elements in the set.
set_list(Set) ->
    sets:to_list(Set).

%% Return a new empty set.
set_new() ->
    sets:new().

%% Remove a "random" element from the set and return that element and the
%% new set. Crashes if given an empty set.
set_pop(Set) ->
    [Head | Tail] = sets:to_list(Set),
    {Head, sets:from_list(Tail)}.

%% Remove given element from set.
set_remove(Set, Element) ->
    sets:del_element(Element, Set).

%%%----------------------------------------------------------------------
%%% State interface
%%%----------------------------------------------------------------------

%% Initialize state table.
%% Must be called before any other call to state_* functions.
state_start() ->
    %% Table for storing unvisited states (as keys, the values are irrelevant).
    ets:new(state, [named_table]).

%% Return initial (empty) state.
state_init() ->
    [].
  
%% Given the current state and a process to be run next, return the new state.
state_get_next(State, Next) ->
    [Next | State].

%% Create all possible next states and add them to the `states` table.
state_store_succ(#info{active = Active, state = State}) ->
    state_store_succ_aux(State, set_list(Active)).

state_store_succ_aux(_State, []) -> ok;
state_store_succ_aux(State, [Proc | Procs]) ->
    ets:insert(states, [Proc | State]),
    state_store_succ_aux(State, Procs).

%%%----------------------------------------------------------------------
%%% Unit tests
%%%----------------------------------------------------------------------

test_all(I, Max) when I > Max ->
    io:format("Unit test completed.~n");
test_all(I, Max) ->
    io:format("Running test ~p of ~p:~n", [I, Max]),
    try
	test(I),
	io:format("Passed~n")
    catch
	_:_ -> io:format("Failed~n")
    end,
    test_all(I + 1, Max).

%% Run all tests
test() ->
    test_all(1, 1).

test(1) ->
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
    end.

ok() -> io:format(" ok~n").
error() -> io:format(" error~n"), throw(error).
