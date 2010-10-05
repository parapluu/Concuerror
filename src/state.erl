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
-type state() :: binary().

%% Given a state and a process LID, return a new extended state
%% containing the given LID as its last element.
-spec extend(state(), lid:lid()) -> state().

extend(State, Lid) ->
    NewState = queue:in(Lid, binary_to_term(State)),
    term_to_binary(NewState, [compressed]).

%% Return initial (empty) state.
-spec empty() -> state().

empty() ->
    term_to_binary(queue:new(), [compressed]).

%% Check if State is an empty state.
-spec is_empty(state()) -> boolean().

is_empty(State) ->
    queue:is_empty(binary_to_term(State)).

%% Return a tuple containing the first Lid in the given state
%% and a new state with that Lid removed.
-spec trim(state()) -> {lid:lid(), state()}.

trim(State) ->
    {{value, Lid}, NewState} = queue:out(binary_to_term(State)),
    {Lid, term_to_binary(NewState, [compressed])}.
