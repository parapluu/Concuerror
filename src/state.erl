%%%----------------------------------------------------------------------
%%% File    : state.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : State interface
%%%
%%% Created : 25 Sep 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

-module(state).

-export([extend/2, empty/0, is_empty/1, load/0, save/1, start/0, stop/0, trim/1]).

-export_type([state/0]).

-include("gen.hrl").

%% A state is a list of LIDs showing the (reverse) interleaving of
%% processes up to a point of the program.
-type state() :: [lid:lid()].

%% Given a state and a process LID, return a new extended state
%% containing the given LID as its last element.
-spec extend(state(), lid:lid()) -> state().

extend(State, Lid) ->
    [Lid|State].

%% Return initial (empty) state.
-spec empty() -> state().

empty() ->
    [].

%% Check if State is an empty state.
-spec is_empty(state()) -> boolean().

is_empty(State) ->
    State =:= [].

%% Remove and return a state.
%% If no states available, return 'no_state'.
-spec load() -> state() | 'no_state'.

load() ->
    case ets:first(?NT_STATE) of
	'$end_of_table' -> no_state;
	State ->
	    ets:delete(?NT_STATE, State),
	    lists:reverse(State)
    end.

%% Add a state to the `state` table.
-spec save(state()) -> 'true'.

save(State) ->
    ets:insert(?NT_STATE, {State}).

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

%% Return a tuple containing the first Lid in the given state
%% and a new state with that Lid removed.
-spec trim(state()) -> {lid:lid(), state()}.

trim([Lid|StateTail]) ->
    {Lid, StateTail}.
