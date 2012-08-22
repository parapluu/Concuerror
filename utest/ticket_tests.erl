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
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Ticket interface unit tests
%%%----------------------------------------------------------------------

-module(ticket_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

-spec get_target_test() -> 'ok'.

get_target_test() ->
    Target = {mymodule, myfunction, []},
    Error = error:mock(),
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual(Target, ticket:get_target(Ticket)).

-spec get_error_test() -> 'ok'.

get_error_test() ->
    Target = {mymodule, myfunction, []},
    Error = error:mock(),
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual(Error, ticket:get_error(Ticket)).

-spec get_state_test() -> 'ok'.

get_state_test() ->
    Target = {mymodule, myfunction, []},
    Error = error:mock(),
    ErrorState = state:empty(),
    Ticket = ticket:new(Target, Error, ErrorState),
    ?assertEqual(ErrorState, ticket:get_state(Ticket)).
