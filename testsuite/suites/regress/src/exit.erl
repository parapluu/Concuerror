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
%%%                 (This test should currenty fail)
%%%----------------------------------------------------------------------

-module(exit).
-export([scenarios/0]).
-export([test1/0, test2/0]).

scenarios() ->
    [{test1, inf}, {test2, inf}].

%% Right now we do not handle `exit/2' at all.

%% Here lies is a deadlock
test1() ->
    Pid = spawn_link(fun() ->
                process_flag(trap_exit, true),
                receive _ -> ok end
          end),
    exit(Pid, normal).

%% Here lies is an exception
test2() ->
    Pid = spawn_link(fun() ->
                process_flag(trap_exit, true),
                receive _ -> ok end
          end),
    exit(Pid, foo).

%% This leads to a killed process that
%% concuerror this is blocked
test3() ->
    Pid = spawn_link(fun() ->
                process_flag(trap_exit, true),
                receive _ -> ok end
          end),
    exit(Pid, kill).
