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

-module(concuerror_error_tests).

-include_lib("eunit/include/eunit.hrl").

-include("gen.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

-spec short_deadlock_test() -> 'ok'.

short_deadlock_test() ->
    Lid1 = concuerror_lid:mock(1),
    Lid2 = concuerror_lid:mock(2),
    Blocked = ?SETS:add_element(Lid1, ?SETS:add_element(Lid2, ?SETS:new())),
    Error = concuerror_error:new({deadlock, Blocked}),
    ?assertEqual("P1, P2", concuerror_error:short(Error)).

-spec short_system_exception_test() -> 'ok'.

short_system_exception_test() ->
    Stack = [{erlang,link,[c:pid(0, 2, 3)]},{sched,rep_link,1},{test,test08,0}],
    Error = concuerror_error:new({noproc, Stack}),
    ?assertEqual("{noproc,[...]}", concuerror_error:short(Error)).

-spec short_user_exception_test() -> 'ok'.

short_user_exception_test() ->
    Error = concuerror_error:new(foobar),
    ?assertEqual("foobar", concuerror_error:short(Error)).

-spec short_user_exception_similar_to_system_test() -> 'ok'.

short_user_exception_similar_to_system_test() ->
    Error = concuerror_error:new({foo, bar}),
    ?assertEqual("{foo,bar}", concuerror_error:short(Error)).

-spec short_assert_equal_violation_test() -> 'ok'.

short_assert_equal_violation_test() ->
    Error = concuerror_error:new({{assertEqual_failed,
			[{module, mymodule}, {line, 42},
			 {expression, "false"},
			 {expected, true}, {value, false}]}, []}),
    ?assertEqual("mymodule.erl:42", concuerror_error:short(Error)).

-spec short_assert_violation_test() -> 'ok'.

short_assert_violation_test() ->
    Error = concuerror_error:new({{assertion_failed,
			[{module, mymodule}, {line, 42},
			 {expression, "true =:= false"},
			 {expected, true}, {value, false}]}, []}),
    ?assertEqual("mymodule.erl:42", concuerror_error:short(Error)).
