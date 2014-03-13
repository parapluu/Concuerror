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
%%% Description : Test the lids when we have many processes
%%%----------------------------------------------------------------------

-module(lid_test).
-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    %% Spawn a big number of processes
    spawn_N(1000),
    %% Throw an exception
    1 = 2.

spawn_N(0) -> ok;
spawn_N(I) ->
    spawn(fun() -> ok end),
    spawn_N(I-1).
