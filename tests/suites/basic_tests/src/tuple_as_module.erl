%%%----------------------------------------------------------------------
%%% Copyright (c) 2012, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Ilias Tsitsimpis <iliastsi@hotmail.com>
%%% Description : Test correct renaming tuple-modules.
%%%----------------------------------------------------------------------
-module(tuple_as_module).
-export([scenarios/0]).
-export([test/0, action/2]).

scenarios() ->
    [{test,inf,dpor}].

test() ->
    P = {?MODULE, [1,2,3]},
    P:action(head),
    P:action(tail).

action(head, {?MODULE, List}) ->
    hd(List);
action(tail, {?MODULE, List}) ->
    tl(List).
