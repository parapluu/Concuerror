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
%%% Description : A regress test case for the bug fix introduced
%%%                 in commit 645ccee1a61dd1c33681544d5e02c8a4b2be0c04
%%%----------------------------------------------------------------------

-module(receive_catchall).
-export([scenarios/0]).
-export([test1/0, test2/0, test3/0]).

scenarios() ->
    [{N,inf,dpor} || N <- [test1,test2,test3]].

%% This is ok.
test1() ->
    self() ! hoho,
    self() ! foo,
    receive foo -> ok end.

%% This is ok.
test2() ->
    Msg = foo,
    self() ! foo,
    self() ! hoho,
    receive Msg -> ok end.

%% This used to fail.
test3() ->
    Msg = foo,
    self() ! hoho,
    self() ! foo,
    receive Msg -> ok end.
