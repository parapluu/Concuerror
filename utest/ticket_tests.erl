%%%----------------------------------------------------------------------
%%% File    : ticket_tests.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%           Maria Christakis <christakismaria@gmail.com>
%%% Description : ticket.erl unit tests
%%%
%%% Created : 25 Sep 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

-module(ticket_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.


-spec get_error_type_str_test() -> term().

get_error_type_str_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = assert,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
                  []},
    Error = {ErrorType, ErrorDescr},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual("Assertion violation", ticket:get_error_type_str(Ticket)).

-spec get_error_descr_str1_test() -> term().

get_error_descr_str1_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = assert,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
                  []},
    Error = {ErrorType, ErrorDescr},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual(io_lib:format("~p.erl:~p: "
                               ++ "The expression '~s' evaluates to '~p' "
                               ++ "instead of '~p'~n"
                               ++ "Stack trace: ~p~n",
                               [mymodule, 42, "true =:= false", false, true,
                                []]),
                 ticket:get_error_descr_str(Ticket)).

-spec get_error_descr_str2_test() -> term().

get_error_descr_str2_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = deadlock,
    ErrorDescr = ["P1"],
    Error = {ErrorType, ErrorDescr},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual(io_lib:format("Process ~s blocks~n", ["P1"]),
                 ticket:get_error_descr_str(Ticket)).

-spec get_error_descr_str3_test() -> term().

get_error_descr_str3_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = deadlock,
    ErrorDescr = ["P1", "P1.1"],
    Error = {ErrorType, ErrorDescr},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    Ps = io_lib:format("~s and ~s", ["P1", "P1.1"]),
    ?assertEqual(io_lib:format("Processes ~s block~n", [Ps]),
                 ticket:get_error_descr_str(Ticket)).

-spec get_error_descr_str4_test() -> term().

get_error_descr_str4_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = deadlock,
    ErrorDescr = ["P1", "P1.1", "P1.2"],
    Error = {ErrorType, ErrorDescr},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    Ps = io_lib:format("~s, ~s and ~s", ["P1", "P1.1", "P1.2"]),
    ?assertEqual(io_lib:format("Processes ~s block~n", [Ps]),
                 ticket:get_error_descr_str(Ticket)).

-spec get_error_descr_str5_test() -> term().

get_error_descr_str5_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = exception,
    ErrorDescr = foobar,
    Error = {ErrorType, ErrorDescr},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual(io_lib:format("~p~n", [ErrorDescr]),
                 ticket:get_error_descr_str(Ticket)).

-spec get_error_descr_str6_test() -> term().

get_error_descr_str6_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = exception,
    ErrorDescr = {badarg, []},
    Error = {ErrorType, ErrorDescr},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual(io_lib:format("Reason: ~p~nStack trace: ~p~n", [badarg, []]),
                 ticket:get_error_descr_str(Ticket)).

-spec get_target_test() -> term().

get_target_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = assert,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
                  []},
    Error = {ErrorType, ErrorDescr},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual(Target, ticket:get_target(Ticket)).

-spec get_state_test() -> term().

get_state_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = assert,
    ErrorDescr = {{assertion_violation, [{module, mymodule}, {line, 42},
                                         {expression, "true =:= false"},
                                         {expected, true}, {value, false}]},
                  []},
    Error = {ErrorType, ErrorDescr},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual(ErrorState, ticket:get_state(Ticket)).
