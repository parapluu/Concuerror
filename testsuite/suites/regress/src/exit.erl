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
%%% Description : Test the `exit/2' instrumentation
%%%----------------------------------------------------------------------

-module(exit).
-export([scenarios/0]).
-export([test1/0, test2/0, test3/0]).

scenarios() ->
    [{N,P,R} || {N,P} <- [{test1, inf}, {test2, inf}, {test3, inf}],
                R <- [full, dpor]].

test1() ->
    Pid = spawn(fun() ->
                        process_flag(trap_exit, true),
                        receive _ -> ok end
                end),
    exit(Pid, normal).

test2() ->
    Pid = spawn(fun() ->
                        process_flag(trap_exit, true),
                        receive _ -> ok end
                end),
    exit(Pid, foo).

test3() ->
    Pid = spawn(fun() ->
                        process_flag(trap_exit, true),
                        receive _ -> ok end
                end),
    exit(Pid, kill).
