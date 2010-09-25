%%%----------------------------------------------------------------------
%%% File    : state_tests.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : state.erl unit tests
%%%
%%% Created : 25 Sep 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

-module(state_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.


-spec insert_pop_equal_test() -> term().

insert_pop_equal_test() ->
    state:start(),
    Init = state:init(),
    state:insert(Init),
    ?assertEqual(Init, state:pop()),
    state:stop().
