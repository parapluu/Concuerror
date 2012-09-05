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

-spec get_error_test() -> 'ok'.

get_error_test() ->
    Error = error:mock(),
    Pid = spawn(fun() -> ok end),
    lid:start(),
    Lid = lid:new(Pid, noparent),
    Actions = [{'after', Lid}, {'block', Lid}],
    Ticket = ticket:new(Error, Actions),
    lid:stop(),
    ?assertEqual(Error, ticket:get_error(Ticket)).

-spec get_details_test() -> 'ok'.

get_details_test() ->
    Error = error:mock(),
    Pid = spawn(fun() -> ok end),
    lid:start(),
    Lid = lid:new(Pid, noparent),
    Actions = [{'after', Lid}, {'block', Lid}],
    Ticket = ticket:new(Error, Actions),
    lid:stop(),
    ?assertEqual(Actions, ticket:get_details(Ticket)).
