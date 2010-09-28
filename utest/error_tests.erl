%%%----------------------------------------------------------------------
%%% File    : error_tests.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%           Maria Christakis <christakismaria@gmail.com>
%%% Description : error.erl unit tests
%%%
%%% Created : 28 Sep 2010 by Maria Christakis <christakismaria@gmail.com>
%%%----------------------------------------------------------------------

-module(error_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.


-spec format_error_type_test() -> term().

format_error_type_test() ->
    ErrorType = assertion_violation,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
                  []},
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual("Assertion violation", error:format_error_type(Error)).

-spec format_error_descr1_test() -> term().

format_error_descr1_test() ->
    ErrorType = assertion_violation,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
                  []},
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("~p.erl:~p: "
                               ++ "The expression '~s' evaluates to '~p' "
                               ++ "instead of '~p'~n"
                               ++ "Stack trace: ~p~n",
                               [mymodule, 42, "true =:= false", false, true,
                                []]),
                 error:format_error_descr(Error)).

-spec format_error_descr2_test() -> term().

format_error_descr2_test() ->
    ErrorType = deadlock,
    ErrorDescr = ["P1"],
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("Process ~s blocks~n", ["P1"]),
                 error:format_error_descr(Error)).

-spec format_error_descr3_test() -> term().

format_error_descr3_test() ->
    ErrorType = deadlock,
    ErrorDescr = ["P1", "P1.1"],
    Error = error:new(ErrorType, ErrorDescr),
    Ps = io_lib:format("~s and ~s", ["P1", "P1.1"]),
    ?assertEqual(io_lib:format("Processes ~s block~n", [Ps]),
                 error:format_error_descr(Error)).

-spec format_error_descr4_test() -> term().

format_error_descr4_test() ->
    ErrorType = deadlock,
    ErrorDescr = ["P1", "P1.1", "P1.2"],
    Error = error:new(ErrorType, ErrorDescr),
    Ps = io_lib:format("~s, ~s and ~s", ["P1", "P1.1", "P1.2"]),
    ?assertEqual(io_lib:format("Processes ~s block~n", [Ps]),
                 error:format_error_descr(Error)).

-spec format_error_descr5_test() -> term().

format_error_descr5_test() ->
    ErrorType = exception,
    ErrorDescr = foobar,
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("~p~n", [ErrorDescr]),
                 error:format_error_descr(Error)).

-spec format_error_descr6_test() -> term().

format_error_descr6_test() ->
    ErrorType = exception,
    ErrorDescr = {badarg, []},
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("Reason: ~p~nStack trace: ~p~n", [badarg, []]),
                 error:format_error_descr(Error)).

-spec deadlock_test() -> term().

deadlock_test() ->
    ErrorType = deadlock,
    ErrorDescr = ["P1", "P1.1", "P1.2"],
    Error = error:new(ErrorType, ErrorDescr),
    Blocked =
        sets:add_element("P1",
                         sets:add_element("P1.1",
                                          sets:add_element("P1.2",
                                                           sets:new()))),
    Deadlock = error:deadlock(Blocked),
    ?assertEqual(Error, Deadlock).
