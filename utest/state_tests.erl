%%%----------------------------------------------------------------------
%%% File        : state_tests.erl
%%% Author      : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : State interface unit tests
%%% Created     : 25 Sep 2010
%%%----------------------------------------------------------------------

-module(state_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

-spec extend_trim_test() -> term().

extend_trim_test() ->
    lid:start(),
    Init = state:empty(),
    Lid = lid:new(c:pid(0, 2, 3), noparent),
    State = state:extend(Init, Lid),
    {NewLid, NewState} = state:trim(State),
    ?assertEqual(NewLid, Lid),
    ?assertEqual(true, state:is_empty(NewState)),
    lid:stop().
