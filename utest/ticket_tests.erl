%%%----------------------------------------------------------------------
%%% File    : ticket_tests.erl
%%% Author  : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : ticket.erl unit tests
%%%
%%% Created : 25 Sep 2010 by Alkis Gotovos <el3ctrologos@hotmail.com>
%%%----------------------------------------------------------------------

-module(ticket_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.


-spec get_error_string_test() -> term().

get_error_string_test() ->
    Target = {mymodule, myfunction, []},
    ErrorDescr = assert,
    ErrorState = state:init(),
    Ticket = ticket:new(Target, ErrorDescr, ErrorState),
    ?assertEqual("Assertion violation", ticket:get_error_string(Ticket)).

-spec get_target_test() -> term().

get_target_test() ->
    Target = {mymodule, myfunction, []},
    ErrorDescr = assert,
    ErrorState = state:init(),
    Ticket = ticket:new(Target, ErrorDescr, ErrorState),
    ?assertEqual(Target, ticket:get_target(Ticket)).

-spec get_state_test() -> term().

get_state_test() ->
    Target = {mymodule, myfunction, []},
    ErrorDescr = assert,
    ErrorState = state:init(),
    Ticket = ticket:new(Target, ErrorDescr, ErrorState),
    ?assertEqual(ErrorState, ticket:get_state(Ticket)).
