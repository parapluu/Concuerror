%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Author      : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : State interface
%%%----------------------------------------------------------------------

-module(concuerror_state).

-export([extend/2, empty/0, is_empty/1, pack/1, trim_head/1, trim_tail/1]).

-export_type([state/0]).

-include("gen.hrl").

%%-define(ENABLE_COMPRESSION, true).
-ifdef(ENABLE_COMPRESSION).
-type state() :: binary().
-define(OPT_T2B, [compressed]).
-define(BIN_TO_TERM(X), binary_to_term(X)).
-define(TERM_TO_BIN(X), term_to_binary(X, ?OPT_T2B)).
-else.
-type state() :: {{concuerror_lid:lid(),pos_integer()} | 'undefined',
                  queue(),
                  {concuerror_lid:lid(),pos_integer()} | 'undefined'}.
-define(BIN_TO_TERM(X), X).
-define(TERM_TO_BIN(X), X).
-endif.

%% Given a state and a process LID, return a new extended state
%% containing the given LID as its last element.
-spec extend(state(), concuerror_lid:lid()) -> state().

extend(State, Lid) ->
    {Front, Queue, Rear} = ?BIN_TO_TERM(State),
    case Rear of
        {RLid, N} when RLid==Lid ->
            NewState = {Front, Queue, {RLid, N+1}},
            ?TERM_TO_BIN(NewState);
        {_RLid, _N} ->
            NewQueue = queue:in(Rear, Queue),
            NewState = {Front, NewQueue, {Lid, 1}},
            ?TERM_TO_BIN(NewState);
        undefined ->
            NewState = {Front, Queue, {Lid, 1}},
            ?TERM_TO_BIN(NewState)
    end.

%% Return initial (empty) state.
-spec empty() -> state().

empty() ->
    NewState = {undefined, queue:new(), undefined},
    ?TERM_TO_BIN(NewState).

%% Check if State is an empty state.
-spec is_empty(state()) -> boolean().

is_empty(State) ->
    case ?BIN_TO_TERM(State) of
        {undefined, Queue, undefined} ->
            queue:is_empty(Queue);
        _ -> false
    end.

%% Pack out state.
-spec pack(state()) -> state().

pack(State) ->
    {Front, Queue, Rear} = ?BIN_TO_TERM(State),
    Queue1 =
        case Front of
            undefined -> Queue;
            _ -> queue:in_r(Front, Queue)
        end,
    Queue2 =
        case Rear of
            undefined -> Queue1;
            _ -> queue:in(Rear, Queue1)
        end,
    NewState = {undefined, Queue2, undefined},
    ?TERM_TO_BIN(NewState).

%% Return a tuple containing the first Lid in the given state
%% and a new state with that Lid removed.
%% Assume the State is packed and not empty.
-spec trim_head(state()) -> {concuerror_lid:lid(), state()}.

trim_head(State) ->
    {Front, Queue, Rear} = ?BIN_TO_TERM(State),
    case Front of
        {Lid, N} when N>1  ->
            NewState = {{Lid, N-1}, Queue, Rear},
            {Lid, ?TERM_TO_BIN(NewState)};
        {Lid, N} when N==1 ->
            NewState = {undefined, Queue, Rear},
            {Lid, ?TERM_TO_BIN(NewState)};
        undefined ->
            {{value, NewFront}, NewQueue} = queue:out(Queue),
            NewState = {NewFront, NewQueue, Rear},
            trim_head(?TERM_TO_BIN(NewState))
    end.

%% Return a tuple containing the last Lid in the given state
%% and a new state with that Lid removed.
%% Assume the State is packed and not empty.
-spec trim_tail(state()) -> {concuerror_lid:lid(), state()}.

trim_tail(State) ->
    {Front, Queue, Rear} = ?BIN_TO_TERM(State),
    case Rear of
        {Lid, N} when N>1  ->
            NewState = {Front, Queue, {Lid, N-1}},
            {Lid, ?TERM_TO_BIN(NewState)};
        {Lid, N} when N==1 ->
            NewState = {Front, Queue, undefined},
            {Lid, ?TERM_TO_BIN(NewState)};
        undefined ->
            {{value, NewRear}, NewQueue} = queue:out_r(Queue),
            NewState = {Front, NewQueue, NewRear},
            trim_tail(?TERM_TO_BIN(NewState))
    end.
