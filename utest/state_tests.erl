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
%%% Description : State interface unit tests
%%%----------------------------------------------------------------------

-module(state_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

-spec extend_trim_head_test() -> 'ok'.

extend_trim_head_test() ->
    lid:start(),
    Init = state:empty(),
    Lid = lid:new(c:pid(0, 2, 3), noparent),
    State = state:extend(Init, Lid),
    {NewLid, NewState} = state:trim_head(State),
    ?assertEqual(NewLid, Lid),
    ?assertEqual(true, state:is_empty(NewState)),
    lid:stop().

-spec extend_trim_tail_test() -> 'ok'.

extend_trim_tail_test() ->
    lid:start(),
    Init = state:empty(),
    Lid = lid:new(c:pid(0, 2, 3), noparent),
    State = state:extend(Init, Lid),
    {NewLid, NewState} = state:trim_tail(State),
    ?assertEqual(NewLid, Lid),
    ?assertEqual(true, state:is_empty(NewState)),
    lid:stop().
