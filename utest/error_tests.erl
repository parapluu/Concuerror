%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Error interface unit tests
%%%----------------------------------------------------------------------

-module(error_tests).

-include_lib("eunit/include/eunit.hrl").

-include("gen.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

-spec short_deadlock_test() -> 'ok'.

short_deadlock_test() ->
    Lid1 = lid:mock(1),
    Lid2 = lid:mock(2),
    Blocked = ?SETS:add_element(Lid1, ?SETS:add_element(Lid2, ?SETS:new())),
    Error = error:new({deadlock, Blocked}),
    ?assertEqual("P1, P2", error:short(Error)).

-spec short_system_exception_test() -> 'ok'.

short_system_exception_test() ->
    Stack = [{erlang,link,[c:pid(0, 2, 3)]},{sched,rep_link,1},{test,test08,0}],
    Error = error:new({noproc, Stack}),
    ?assertEqual("{noproc,[...]}", error:short(Error)).

-spec short_user_exception_test() -> 'ok'.

short_user_exception_test() ->
    Error = error:new(foobar),
    ?assertEqual("foobar", error:short(Error)).

-spec short_user_exception_similar_to_system_test() -> 'ok'.

short_user_exception_similar_to_system_test() ->
    Error = error:new({foo, bar}),
    ?assertEqual("{foo,bar}", error:short(Error)).

-spec short_assert_equal_violation_test() -> 'ok'.

short_assert_equal_violation_test() ->
    Error = error:new({{assertEqual_failed,
			[{module, mymodule}, {line, 42},
			 {expression, "false"},
			 {expected, true}, {value, false}]}, []}),
    ?assertEqual("mymodule.erl:42", error:short(Error)).

-spec short_assert_violation_test() -> 'ok'.

short_assert_violation_test() ->
    Error = error:new({{assertion_failed,
			[{module, mymodule}, {line, 42},
			 {expression, "true =:= false"},
			 {expected, true}, {value, false}]}, []}),
    ?assertEqual("mymodule.erl:42", error:short(Error)).
