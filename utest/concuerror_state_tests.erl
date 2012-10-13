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

-module(concuerror_state_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

-spec extend_trim_head_test() -> 'ok'.

extend_trim_head_test() ->
    concuerror_lid:start(),
    Init = concuerror_state:empty(),
    Lid = concuerror_lid:new(c:pid(0, 2, 3), noparent),
    State1 = concuerror_state:extend(Init, Lid),
    State2 = concuerror_state:pack(State1),
    {NewLid, NewState} = concuerror_state:trim_head(State2),
    ?assertEqual(NewLid, Lid),
    ?assertEqual(true, concuerror_state:is_empty(NewState)),
    concuerror_lid:stop().

-spec extend_trim_tail_test() -> 'ok'.

extend_trim_tail_test() ->
    concuerror_lid:start(),
    Init = concuerror_state:empty(),
    Lid = concuerror_lid:new(c:pid(0, 2, 3), noparent),
    State1 = concuerror_state:extend(Init, Lid),
    State2 = concuerror_state:pack(State1),
    {NewLid, NewState} = concuerror_state:trim_tail(State2),
    ?assertEqual(NewLid, Lid),
    ?assertEqual(true, concuerror_state:is_empty(NewState)),
    concuerror_lid:stop().
