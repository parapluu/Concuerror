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

%%-define(ENABLE_COMPRESSION, true).
-ifdef(ENABLE_COMPRESSION).
-type state() :: binary().
-define(OPT_T2B, [compressed]).
-define(BIN_TO_TERM(X), binary_to_term(X)).
-define(TERM_TO_BIN(X), term_to_binary(X, ?OPT_T2B)).
-else.
-type state() :: queue().
-define(BIN_TO_TERM(X), X).
-define(TERM_TO_BIN(X), X).
-endif.

%% Given a state and a process LID, return a new extended state
%% containing the given LID as its last element.
-spec extend(state(), lid:lid()) -> state().

extend(State, Lid) ->
    NewState = queue:in(Lid, ?BIN_TO_TERM(State)),
    ?TERM_TO_BIN(NewState).

%% Return initial (empty) state.
-spec empty() -> state().

empty() ->
    ?TERM_TO_BIN(queue:new()).

%% Check if State is an empty state.
-spec is_empty(state()) -> boolean().

is_empty(State) ->
    queue:is_empty(?BIN_TO_TERM(State)).

%% Return a tuple containing the first Lid in the given state
%% and a new state with that Lid removed.
-spec trim(state()) -> {lid:lid(), state()}.

trim(State) ->
    {{value, Lid}, NewState} = queue:out(?BIN_TO_TERM(State)),
    {Lid, ?TERM_TO_BIN(NewState)}.
