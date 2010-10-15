%%%----------------------------------------------------------------------
%%% File        : preb.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Preemption bounding
%%% Created     : 28 Sep 2010
%%%----------------------------------------------------------------------

-module(preb).

-export([interleave/2]).

-include("gen.hrl").

%% Produce all possible process interleavings of (Mod, Fun, Args).
%% Options:
%%   {init_state, InitState}: State to replay (default: state_init()).
%%   details: Produce detailed interleaving information (see `replay_logger`).
-spec interleave(sched:analysis_target(), options()) -> sched:analysis_ret().

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
    %% Start state service.
    state_start(),
    %% Save empty replay state for the first run.
    {init_state, InitState} = lists:keyfind(init_state, 1, Options),
    state_save(InitState),
    {preb, Bound} = lists:keyfind(preb, 1, Options),
    Result = interleave_outer_loop(Target, 0, [], -1, Bound, Options),
    state_stop(),
    unregister(?RP_SCHED),
    Parent ! {interleave_result, Result}.

%% Outer analysis loop.
%% Preemption bound starts at 0 and is increased by 1 on each iteration.
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
	    %% Cleanup of any remaining processes.
	    sched:proc_cleanup(),
            lid:stop(),
	    ?debug_1("-----------------------~n"),
	    ?debug_1("Run terminated.~n~n"),
            NewTickets =
                case Ret of
                    ok -> Tickets;
                    {error, Error, ErrorState} ->
                        {files, Files} = lists:keyfind(files, 1, Options),
                        Ticket = ticket:new(Target, Files, Error, ErrorState),
                        [Ticket|Tickets]
                end,
            interleave_loop(Target, RunCnt + 1, NewTickets, Options)
    end.

%% Stores states for later exploration and returns the process to be run next.
search(#context{active = Active, state = State}) ->
    case state:is_empty(State) of
	%% Handle first call to search (empty state, one active process).
	true ->
	    [Next] = sets:to_list(Active),
	    Next;
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
		    NewActive = sets:del_element(LastLid, Active),
		    Fun = fun(L, Acc) ->
				  state_save_next(state:extend(State, L)),
				  Acc
			  end,
		    sets:fold(Fun, unused, NewActive),
		    LastLid;
		false ->
		    [Next|NewActive] = sets:to_list(Active),
		    [state_save(state:extend(State, L)) || L <- NewActive],
		    Next
	    end
    end.

%%%----------------------------------------------------------------------
%%% Helper functions
%%%----------------------------------------------------------------------

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

%% Add a state to the next `state` table.
state_save_next(State) ->
    ets:insert(?NT_STATE2, {State}).

%% Add a state to the current `state` table.
state_save(State) ->
    ets:insert(?NT_STATE1, {State}).

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
