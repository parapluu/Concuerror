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

-module(concuerror_ticket_tests).

-include_lib("eunit/include/eunit.hrl").

%% Spec for auto-generated test/0 function (eunit).
-spec test() -> 'ok' | {'error', term()}.

-spec get_error_test() -> 'ok'.

get_error_test() ->
    Error = concuerror_error:mock(),
    Pid = spawn(fun() -> ok end),
    concuerror_lid:start(),
    Lid = concuerror_lid:new(Pid, noparent),
    Actions = [{'after', Lid}, {'block', Lid}],
    Ticket = concuerror_ticket:new(Error, Actions),
    concuerror_lid:stop(),
    ?assertEqual(Error, concuerror_ticket:get_error(Ticket)).

-spec get_details_test() -> 'ok'.

get_details_test() ->
    Error = concuerror_error:mock(),
    Pid = spawn(fun() -> ok end),
    concuerror_lid:start(),
    Lid = concuerror_lid:new(Pid, noparent),
    Actions = [{'after', Lid}, {'block', Lid}],
    Ticket = concuerror_ticket:new(Error, Actions),
    concuerror_lid:stop(),
    ?assertEqual(Actions, concuerror_ticket:get_details(Ticket)).
