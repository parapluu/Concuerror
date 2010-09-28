%%%----------------------------------------------------------------------
%%% File        : preb.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Preemption bounding
%%% Created     : 28 Sep 2010
%%%----------------------------------------------------------------------

-module(preb).

-export([interleave/1]).

-include("gen.hrl").

%% Produce all possible process interleavings of (Mod, Fun, Args).
%% Options:
%%   {init_state, InitState}: State to replay (default: state_init()).
%%   details: Produce detailed interleaving information (see `replay_logger`).
-spec interleave(sched:analysis_target()) -> sched:analysis_ret().

interleave(Target) ->
    interleave(Target, [{init_state, state:empty()}]).

interleave(Target, Options) ->
    Self = self(),
    %% TODO: Need spawn_link?
    spawn(fun() -> interleave_aux(Target, Options, Self) end),
    receive
	{interleave_result, Result} -> Result
    end.

interleave_aux(Target, Options, Parent) ->
    {init_state, InitState} = lists:keyfind(init_state, 1, Options),
    Det = lists:member(details, Options),
    register(?RP_SCHED, self()),
    %% The mailbox is flushed mainly to discard possible `exit` messages
    %% before enabling the `trap_exit` flag.
    util:flush_mailbox(),
    process_flag(trap_exit, true),
    %% Start state service.
    state:start(),
    %% Save empty replay state for the first run.
    state:save(InitState),
    Result = interleave_loop(Target, 1, [], Det),
    state:stop(),
    unregister(?RP_SCHED),
    Parent ! {interleave_result, Result}.

%% Main loop for producing process interleavings.
%% The first process (FirstPid) is created linked to the scheduler,
%% so that the latter can receive the former's exit message when it
%% terminates. In the same way, every process that may be spawned in
%% the course of the program shall be linked to the scheduler process.
interleave_loop(Target, RunCnt, Tickets, Det) ->
    %% Lookup state to replay.
    case state:load() of
        no_state ->
	    case Tickets of
		[] -> {ok, RunCnt - 1};
		_Any -> {error, RunCnt - 1, lists:reverse(Tickets)}
	    end;
        ReplayState ->
            ?debug_1("Running interleaving ~p~n", [RunCnt]),
            ?debug_1("----------------------~n"),
            lid:start(),
	    %% Spawn initial process.
	    {Mod, Fun, Args} = Target,
	    NewFun = fun() -> sched:wait(), apply(Mod, Fun, Args) end,
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
            Ret = sched:driver(Search, Context, ReplayState),
	    %% Cleanup.
            lid:stop(),
	    ?debug_1("-----------------------~n"),
	    ?debug_1("Run terminated.~n~n"),
	    %% TODO: Proper cleanup of any remaining processes.
            case Ret of
                ok -> interleave_loop(Target, RunCnt + 1, Tickets, Det);
                {error, Error, ErrorState} ->
		    Ticket = ticket:new(Target, Error, ErrorState),
		    interleave_loop(Target, RunCnt + 1, [Ticket|Tickets], Det)
            end
    end.

%% Implements the search logic (currently depth-first when looked at combined
%% with the replay logic).
%% Given a blocked state (no process running when called), creates all
%% possible next states, chooses one of them for running and inserts the rest
%% of them into the `states` table.
%% Returns the process to be run next.
search(#context{active = Active, state = State}) ->
    %% Remove a process to be run next from the `actives` set.
    [Next|NewActive] = sets:to_list(Active),
    %% Store all other possible successor states for later exploration.
    [state:save(state:extend(State, Lid)) || Lid <- NewActive],
    Next.
