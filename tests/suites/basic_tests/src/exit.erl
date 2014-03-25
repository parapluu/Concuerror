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
-export([test1/0, test2/0, test3/0, test4/0, test5/0, test6/0]).

scenarios() ->
    [{N,inf,dpor} || N <- [test1,test2,test3,test4,test5,test6]].

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

test4() ->
    Pid = spawn(fun() ->
                        receive infinity -> ok end
                end),
    exit(Pid, normal).

test5() ->
    Pid = spawn(fun() ->
                        receive infinity -> ok end
                end),
    exit(Pid, kill).

test6() ->
    spawn_link(fun() -> exit(crash_1) end),
    spawn_link(fun() -> exit(crash_2) end),
    exit(crash_main).
