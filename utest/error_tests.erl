%%%----------------------------------------------------------------------
%%% File        : error_tests.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Error interface unit tests
%%% Created     : 28 Sep 2010
%%%----------------------------------------------------------------------

-module(error_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

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

-spec error_type_to_string_test() -> term().

error_type_to_string_test() ->
    ErrorType = assertion_violation,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
                  []},
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("~s~n", ["Assertion violation"]),
                 error:error_type_to_string(Error)).

-spec error_reason_to_string1_test() -> term().

error_reason_to_string1_test() ->
    ErrorType = assertion_violation,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
                  []},
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("On line ~p of module ~p, "
                               ++ "the expression ~s evaluates to ~p "
                               ++ "instead of ~p~n",
                               [42, mymodule, "true =:= false", false, true]),
                 error:error_reason_to_string(Error, long)).

-spec error_reason_to_string2_test() -> term().

error_reason_to_string2_test() ->
    ErrorType = deadlock,
    ErrorDescr = ["P1"],
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("Process ~s blocks~n", ["P1"]),
                 error:error_reason_to_string(Error, long)).

-spec error_reason_to_string3_test() -> term().

error_reason_to_string3_test() ->
    ErrorType = deadlock,
    ErrorDescr = ["P1", "P1.1"],
    Error = error:new(ErrorType, ErrorDescr),
    Ps = io_lib:format("~s and ~s", ["P1", "P1.1"]),
    ?assertEqual(io_lib:format("Processes ~s block~n", [Ps]),
                 error:error_reason_to_string(Error, long)).

-spec error_reason_to_string4_test() -> term().

error_reason_to_string4_test() ->
    ErrorType = deadlock,
    ErrorDescr = ["P1", "P1.1", "P1.2"],
    Error = error:new(ErrorType, ErrorDescr),
    Ps = io_lib:format("~s, ~s and ~s", ["P1", "P1.1", "P1.2"]),
    ?assertEqual(io_lib:format("Processes ~s block~n", [Ps]),
                 error:error_reason_to_string(Error, long)).

-spec error_reason_to_string5_test() -> term().

error_reason_to_string5_test() ->
    ErrorType = exception,
    ErrorDescr = foobar,
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("~p~n", [ErrorDescr]),
                 error:error_reason_to_string(Error, long)).

-spec error_reason_to_string6_test() -> term().

error_reason_to_string6_test() ->
    ErrorType = exception,
    ErrorDescr = {badarg, []},
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("~p~n", [badarg]),
                 error:error_reason_to_string(Error, long)).

-spec error_stack_to_string1_test() -> term().

error_stack_to_string1_test() ->
    ErrorType = assertion_violation,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
                  []},
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("~p", [[]]),
                 error:error_stack_to_string(Error)).

-spec error_stack_to_string2_test() -> term().

error_stack_to_string2_test() ->
    ErrorType = deadlock,
    ErrorDescr = ["P1"],
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual("", error:error_stack_to_string(Error)).

-spec error_stack_to_string3_test() -> term().

error_stack_to_string3_test() ->
    ErrorType = exception,
    ErrorDescr = foobar,
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual("", error:error_stack_to_string(Error)).

-spec error_stack_to_string4_test() -> term().

error_stack_to_string4_test() ->
    ErrorType = exception,
    ErrorDescr = {badarg, []},
    Error = error:new(ErrorType, ErrorDescr),
    ?assertEqual(io_lib:format("~p", [[]]),
                 error:error_stack_to_string(Error)).
