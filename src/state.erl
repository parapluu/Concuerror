%%%----------------------------------------------------------------------
%%% File        : state.erl
%%% Author      : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : State interface
%%% Created     : 25 Sep 2010
%%%----------------------------------------------------------------------

-module(state).

-export([extend/2, empty/0, is_empty/1, trim/1]).

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

%% Return a tuple containing the first Lid in the given state
%% and a new state with that Lid removed.
-spec trim(state()) -> {lid:lid(), state()}.

trim([Lid|StateTail]) ->
    {Lid, StateTail}.
