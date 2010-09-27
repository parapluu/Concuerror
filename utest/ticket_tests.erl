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
    ErrorDescr = {{assertion_failed, [{module, mymodule}, {line, 42},
                                      {expression, "true =:= false"},
                                      {expected, true}, {value, false}]},
                  []},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, ErrorType, ErrorDescr, ErrorState),
    ?assertEqual("Assertion violation", ticket:get_error_type_str(Ticket)).

-spec get_error_descr_str1_test() -> term().

get_error_descr_str1_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = assert,
    ErrorDescr = {{assertion_failed, [{module, mymodule}, {line, 42},
                                      {expression, "true =:= false"},
                                      {expected, true}, {value, false}]},
                  []},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, ErrorType, ErrorDescr, ErrorState),
    ?assertEqual(io_lib:format("~p.erl:~p: The assertion failed~n",
                               [mymodule, 42]),
                 ticket:get_error_descr_str(Ticket)).

-spec get_error_descr_str2_test() -> term().

get_error_descr_str2_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = exception,
    ErrorDescr = foobar,
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, ErrorType, ErrorDescr, ErrorState),
    ?assertEqual(io_lib:format("~p~n", [ErrorDescr]),
                 ticket:get_error_descr_str(Ticket)).

-spec get_target_test() -> term().

get_target_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = assert,
    ErrorDescr = {{assertion_failed, [{module, mymodule}, {line, 42},
                                      {expression, "true =:= false"},
                                      {expected, true}, {value, false}]},
                  []},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, ErrorType, ErrorDescr, ErrorState),
    ?assertEqual(Target, ticket:get_target(Ticket)).

-spec get_state_test() -> term().

get_state_test() ->
    Target = {mymodule, myfunction, []},
    ErrorType = assert,
    ErrorDescr = {{assertion_failed, [{module, mymodule}, {line, 42},
                                      {expression, "true =:= false"},
                                      {expected, true}, {value, false}]},
                  []},
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, ErrorType, ErrorDescr, ErrorState),
    ?assertEqual(ErrorState, ticket:get_state(Ticket)).
