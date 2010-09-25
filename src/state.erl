%%%----------------------------------------------------------------------
%%% File    : state.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : State interface
%%%
%%% Created : 25 Sep 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

-module(state).

-export([extend/2, init/0, insert/1, pop/0, start/0, stop/0]).

-export_type([state/0]).

-include("gen.hrl").

%% A state is a list of LIDs showing the (reverse) interleaving of
%% processes up to a point of the program.
-type state() :: [sched:lid()].

%% Given the current state and a process to be run next, return the new state.
-spec extend(state(), sched:lid()) -> state().

extend(State, Next) ->
    [Next|State].

%% Return initial (empty) state.
-spec init() -> state().

init() ->
    [].

%% Add a state to the `state` table.
-spec insert(state()) -> 'true'.

insert(State) ->
    ets:insert(?NT_STATE, {State}).

%% Remove and return a state.
%% If no states available, return 'no_state'.
-spec pop() -> state() | 'no_state'.

pop() ->
    case ets:first(?NT_STATE) of
	'$end_of_table' -> no_state;
	State ->
	    ets:delete(?NT_STATE, State),
	    lists:reverse(State)
    end.

%% Initialize state table.
%% Must be called before any other call to state_* functions.
-spec start() -> ets:tid() | atom().

start() ->
    %% Table for storing unvisited states (as keys, the values are irrelevant).
    ets:new(?NT_STATE, [named_table]).

%% Clean up state table.
-spec stop() -> 'true'.

stop() ->
    ets:delete(?NT_STATE).
