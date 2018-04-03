%%%----------------------------------------------------------------------
%%% Copyright (c) 2011, Alkis Gotovos <el3ctrologos@hotmail.com>,
%%%                     Maria Christakis <mchrista@softlab.ntua.gr>
%%%                 and Kostis Sagonas <kostis@cs.ntua.gr>.
%%% All rights reserved.
%%%
%%% This file is distributed under the Simplified BSD License.
%%% Details can be found in the LICENSE file.
%%%----------------------------------------------------------------------
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <mchrista@softlab.ntua.gr>
%%% Description : Some basic tests for the scheduler
%%%----------------------------------------------------------------------

-module(sched_tests).
-export([scenarios/0]).
-export([test_spawn/0,
     test_send/0, test_send_2/0, test_send_3/0,
     test_receive/0, test_receive_2/0,
     test_send_receive/0, test_send_receive_2/0, test_send_receive_3/0,
     test_receive_after_no_patterns/0, test_receive_after_with_pattern/0,
     test_receive_after_block_expr_action/0, test_after_clause_preemption/0,
     test_receive_after_infinity_with_pattern/0,
     test_receive_after_infinity_no_patterns/0,
     test_nested_send_receive_block_twice/0,
     test_spawn_link_race/0, test_link_receive_exit/0,
     test_spawn_link_receive_exit/0,
     test_link_unlink/0, test_spawn_link_unlink/0,
     test_spawn_link_unlink_2/0, test_spawn_link_unlink_3/0,
     test_trap_exit_timing/0,
     test_spawn_register_race/0, test_register_unregister/0,
     test_whereis/0,
     test_monitor_unexisting/0, test_spawn_monitor/0,
     test_spawn_monitor_demonitor/0, test_spawn_monitor_demonitor_2/0,
     test_spawn_monitor_demonitor_3/0, test_spawn_monitor_demonitor_4/0,
     test_spawn_monitor_demonitor_5/0,
     test_spawn_opt_link_receive_exit/0, test_spawn_opt_monitor/0,
     test_erlang_send_3/0,
     test_halt_0/0, test_halt_1/0,
     test_var_mod_fun/0,
     test_3_proc_receive_exit/0, test_3_proc_send_receive/0]).

-export([controversial_scenario_names/0]).

-include_lib("eunit/include/eunit.hrl").

%%%---------------------------------------
%%% Tests scenarios
%%%
-spec scenarios() -> [{term(), non_neg_integer()}].
scenarios() ->
    %% [{N,P,R} || {N,P} <- scenario_names(),
    %%              R <- [dpor, full]].
    [{N,inf,dpor} ||
        {N, inf} <- scenario_names()
            %% ++ controversial_scenario_names()
    ].

scenario_names() ->
    [{test_spawn, 0}, {test_spawn, 1}, {test_spawn, inf}
    ,{test_send, 0}, {test_send, 1}, {test_send, inf}
    ,{test_send_2, 0}, {test_send_2, 1}, {test_send_2, inf}
    ,{test_send_3, 0}, {test_send_3, 1}, {test_send_3, inf}
    ,{test_receive, 0}, {test_receive, inf}
    ,{test_receive_2, 0}, {test_receive_2, inf}
    ,{test_send_receive, 0}, {test_send_receive, 1}
    ,{test_send_receive, 2}, {test_send_receive, inf}
    ,{test_send_receive_2, 0}, {test_send_receive_2, 1}
    ,{test_send_receive_2, 2}, {test_send_receive_2, inf}
    ,{test_send_receive_3, 0}, {test_send_receive_3, 1}
    ,{test_send_receive_3, 2}, {test_send_receive_3, inf}
    ,{test_receive_after_no_patterns, 0}, {test_receive_after_no_patterns, 1}
    ,{test_receive_after_no_patterns, 2}, {test_receive_after_no_patterns, inf}
    ,{test_receive_after_with_pattern, 0}, {test_receive_after_with_pattern, 1}
    ,{test_receive_after_with_pattern, 2}, {test_receive_after_with_pattern, 3}
    ,{test_receive_after_with_pattern, inf}
    ,{test_receive_after_block_expr_action, 0}
    ,{test_receive_after_block_expr_action, inf}
    ,{test_after_clause_preemption, 0}, {test_after_clause_preemption, 1}
    ,{test_after_clause_preemption, 2}, {test_after_clause_preemption, 3}
    ,{test_after_clause_preemption, inf}
    ,{test_receive_after_infinity_with_pattern, 0}
    ,{test_receive_after_infinity_with_pattern, inf}
    ,{test_receive_after_infinity_no_patterns, 0}
    ,{test_receive_after_infinity_no_patterns, inf}
    ,{test_nested_send_receive_block_twice, 0}
    ,{test_nested_send_receive_block_twice, 1}
    ,{test_nested_send_receive_block_twice, 2}
    ,{test_spawn_link_race, 0}, {test_spawn_link_race, 1}
    ,{test_spawn_link_race, inf}
    ,{test_link_receive_exit, 0}, {test_link_receive_exit, 1}
    ,{test_link_receive_exit, inf}
    ,{test_spawn_link_receive_exit, 0}, {test_spawn_link_receive_exit, 1}
    ,{test_spawn_link_receive_exit, inf}
    ,{test_link_unlink, 0}, {test_link_unlink, 1}, {test_link_unlink, 2}
    ,{test_link_unlink, 3}, {test_link_unlink, inf}
    ,{test_spawn_link_unlink, 0}, {test_spawn_link_unlink, 1}
    ,{test_spawn_link_unlink, 2}, {test_spawn_link_unlink, inf}
    ,{test_spawn_link_unlink_2, 0}, {test_spawn_link_unlink_2, 1}
    ,{test_spawn_link_unlink_2, inf}
    ,{test_trap_exit_timing, 0}, {test_trap_exit_timing, 1}
    ,{test_trap_exit_timing, inf}
    ,{test_spawn_register_race, 0}, {test_spawn_register_race, 1}
    ,{test_spawn_register_race, 2}, {test_spawn_register_race, inf}
    ,{test_register_unregister, 0}, {test_register_unregister, 1}
    ,{test_register_unregister, 2}, {test_register_unregister, 3}
    ,{test_register_unregister, inf}
    ,{test_whereis, 0}, {test_whereis, 1}, {test_whereis, 2}
    ,{test_whereis, inf}
    ,{test_spawn_monitor, 0}, {test_spawn_monitor, inf}
    ,{test_spawn_opt_link_receive_exit, 0}
    ,{test_spawn_opt_link_receive_exit, 1}
    ,{test_spawn_opt_link_receive_exit, inf}
    ,{test_halt_0, 0}, {test_halt_0, inf}
    ,{test_halt_1, 0}, {test_halt_1, inf}
    ,{test_var_mod_fun, 0}, {test_var_mod_fun, 1}, {test_var_mod_fun, inf}
    ,{test_3_proc_receive_exit, 0}, {test_3_proc_receive_exit, 1}
    ,{test_3_proc_receive_exit, 2}, {test_3_proc_receive_exit, inf}
    ,{test_3_proc_send_receive, 0}, {test_3_proc_send_receive, 1}
    ,{test_3_proc_send_receive, 2}, {test_3_proc_send_receive, 3}
    ,{test_3_proc_send_receive, 4}, {test_3_proc_send_receive, 5}
    ,{test_3_proc_send_receive, 6}, {test_3_proc_send_receive, 7}
    ,{test_3_proc_send_receive, inf}].

controversial_scenario_names() ->
    [
     {test_monitor_unexisting, 0}, {test_monitor_unexisting, 1}
    ,{test_monitor_unexisting, inf}
    ,{test_spawn_link_unlink_3, 0}, {test_spawn_link_unlink_3, 1}
    ,{test_spawn_link_unlink_3, inf}
    ,{test_spawn_monitor_demonitor, 0}, {test_spawn_monitor_demonitor, 1}
    ,{test_spawn_monitor_demonitor, inf}
    ,{test_spawn_monitor_demonitor_2, 0}, {test_spawn_monitor_demonitor_2, 1}
    ,{test_spawn_monitor_demonitor_2, inf}
    ,{test_spawn_monitor_demonitor_3, 0}, {test_spawn_monitor_demonitor_3, 1}
    ,{test_spawn_monitor_demonitor_3, inf}
    ,{test_spawn_monitor_demonitor_4, 0}, {test_spawn_monitor_demonitor_4, 1}
    ,{test_spawn_monitor_demonitor_4, inf}
    ,{test_spawn_opt_monitor, 0}, {test_spawn_opt_monitor, inf}
    ].

%%%---------------------------------------
%%% Some basic concuerror testing functions
%%%
-spec test_spawn() -> 'ok'.

test_spawn() ->
    spawn(fun() -> ok end),
    ok.

-spec test_send() -> 'ok'.

test_send() ->
    Pid = spawn(fun() -> ok end),
    Pid ! foo,
    ok.

-spec test_send_2() -> 'ok'.

test_send_2() ->
    Pid = spawn(fun() -> ok end),
    foo = erlang:send(Pid, foo),
    ok.

-spec test_send_3() -> 'ok'.

test_send_3() ->
    Pid = spawn(fun() -> ok end),
    ok = erlang:send(Pid, foo, [noconnect]),
    ok.

-spec test_receive() -> no_return().

test_receive() ->
    receive _Any -> ok end.

-spec test_receive_2() -> no_return().

test_receive_2() ->
    spawn(fun() -> receive _Any -> ok end end),
    receive _Any -> ok end.

-spec test_send_receive() -> 'ok'.

test_send_receive() ->
    Pid = spawn(fun() -> receive foo -> ok end end),
    Pid ! foo,
    ok.

-spec test_send_receive_2() -> 'ok'.

test_send_receive_2() ->
    Self = self(),
    spawn(fun() -> Self ! foo end),
    receive foo -> ok end.

-spec test_send_receive_3() -> 'ok'.

test_send_receive_3() ->
    Self = self(),
    Pid = spawn(fun() -> Self ! foo, receive bar -> ok end end),
    receive foo -> Pid ! bar, ok end.

-spec test_receive_after_no_patterns() -> 'ok'.

test_receive_after_no_patterns() ->
    Self = self(),
    spawn(fun() -> Self ! foo end),
    Result = receive after 42 -> ok end,
    ?assertEqual(ok, Result).

-spec test_receive_after_with_pattern() -> 'ok'.

test_receive_after_with_pattern() ->
    Self = self(),
    spawn(fun() -> Self ! foo end),
    Result = receive _Any -> result1 after 42 -> result2 end,
    ?assertEqual(result2, Result).

-spec test_receive_after_block_expr_action() -> 'ok'.

test_receive_after_block_expr_action() ->
    Result = receive
         _Any -> result1
         after 42 ->
             foo,
             bar,
             result2
         end,
    ?assertEqual(result2, Result).

-spec test_after_clause_preemption() -> 'ok'.

test_after_clause_preemption() ->
    Self = self(),
    spawn(fun() -> Self ! foo end),
    Result = receive
         _Any -> result1
         after 42 ->
             receive
             _New -> result2
             after 43 -> result3
             end
         end,
    ?assertEqual(result3, Result).

-spec test_receive_after_infinity_with_pattern() -> 'ok'.

test_receive_after_infinity_with_pattern() ->
    Timeout = infinity,
    spawn_link(fun() -> ok end),
    Result =
    receive
        _Any -> ok
    after Timeout -> not_ok
    end,
    ?assertEqual(ok, Result).

-spec test_receive_after_infinity_no_patterns() -> 'ok'.

test_receive_after_infinity_no_patterns() ->
    Timeout = infinity,
    receive
    after Timeout -> ok
    end.

-spec test_nested_send_receive_block_twice() -> 'ok'.

test_nested_send_receive_block_twice() ->
    Self = self(),
    spawn(fun() -> (Self ! Self) ! bar end),
    receive
    bar -> receive
           Self -> ok
           end
    end.

-spec test_spawn_link_race() -> 'ok'.

test_spawn_link_race() ->
    Pid = spawn(fun() -> ok end),
    link(Pid),
    ok.

-spec test_link_receive_exit() -> 'ok'.

test_link_receive_exit() ->
    Fun = fun() -> process_flag(trap_exit, true),
           receive
               {'EXIT', _Pid, normal} -> ok
           end
      end,
    Pid = spawn(Fun),
    link(Pid),
    ok.

-spec test_spawn_link_receive_exit() -> 'ok'.

test_spawn_link_receive_exit() ->
    Fun = fun() -> process_flag(trap_exit, true),
           receive
               {'EXIT', _Pid, normal} -> ok
           end
      end,
    spawn_link(Fun),
    ok.

-spec test_link_unlink() -> 'ok'.

test_link_unlink() ->
    Self = self(),
    Fun = fun() -> process_flag(trap_exit, true),
           Self ! foo,
           receive
               {'EXIT', Self, normal} -> ok
           end
      end,
    Pid = spawn(Fun),
    link(Pid),
    unlink(Pid),
    receive foo -> ok end.

-spec test_spawn_link_unlink() -> 'ok'.

test_spawn_link_unlink() ->
    Self = self(),
    Fun = fun() -> process_flag(trap_exit, true),
           Self ! foo,
           receive
               {'EXIT', Self, normal} -> ok
           end
      end,
    Pid = spawn_link(Fun),
    unlink(Pid),
    receive foo -> ok end.

-spec test_spawn_link_unlink_2() -> 'ok'.

test_spawn_link_unlink_2() ->
    Pid = spawn_link(fun() -> foo end),
    unlink(Pid),
    Result =
    receive
        {'EXIT', Pid, normal} -> not_ok
    after 0 -> ok
    end,
    ?assertEqual(ok, Result).

-spec test_spawn_link_unlink_3() -> 'ok'.

test_spawn_link_unlink_3() ->
    process_flag(trap_exit, true),
    Pid = spawn_link(fun() -> foo end),
    unlink(Pid),
    Result =
    receive
        {'EXIT', Pid, normal} -> not_ok
    after 0 -> ok
    end,
    ?assertEqual(ok, Result).

-spec test_trap_exit_timing() -> 'ok'.

test_trap_exit_timing() ->
    process_flag(trap_exit, true),
    Pid = spawn_link(fun() -> foo end),
    process_flag(trap_exit, false),
    Result =
    receive
        {'EXIT', Pid, normal} -> not_ok
    after 0 -> ok
    end,
    ?assertEqual(ok, Result).

-spec test_spawn_register_race() -> 'ok'.

test_spawn_register_race() ->
    spawn(fun() -> foo ! bar end),
    register(foo, self()),
    receive
    bar -> ok
    end.

-spec test_register_unregister() -> 'ok'.

test_register_unregister() ->
    register(foo, self()),
    spawn(fun() -> foo ! bar end),
    unregister(foo),
    receive
    bar -> ok
    end.

-spec test_whereis() -> 'ok'.

test_whereis() ->
    Self = self(),
    Pid = spawn(fun() -> receive Any -> ?assertEqual(Self, whereis(Any)) end
        end),
    Reg = foo,
    register(Reg, self()),
    Pid ! Reg,
    ok.

-spec test_monitor_unexisting() -> 'ok'.

test_monitor_unexisting() ->
    Pid = spawn(fun() -> ok end),
    Ref = monitor(process, Pid),
    Result =
    receive
        {'DOWN', Ref, process, Pid, noproc} -> not_ok
    after 0 -> ok
    end,
    ?assertEqual(ok, Result).

-spec test_spawn_monitor() -> 'ok'.

test_spawn_monitor() ->
    {Pid, Ref} = spawn_monitor(fun() -> ok end),
    receive
    {'DOWN', Ref, process, Pid, normal} -> ok
    end.

-spec test_spawn_monitor_demonitor() -> 'ok'.

test_spawn_monitor_demonitor() ->
    {Pid, Ref} = spawn_monitor(fun() -> ok end),
    demonitor(Ref),
    Result =
    receive
        {'DOWN', Ref, process, Pid, normal} -> result1
    after 0 -> result2
    end,
    ?assertEqual(result2, Result).

-spec test_spawn_monitor_demonitor_2() -> 'ok'.

test_spawn_monitor_demonitor_2() ->
    {Pid, Ref} = spawn_monitor(fun() -> ok end),
    demonitor(Ref, []),
    Result =
    receive
        {'DOWN', Ref, process, Pid, normal} -> result1
    after 0 -> result2
    end,
    ?assertEqual(result2, Result).

-spec test_spawn_monitor_demonitor_3() -> 'ok'.

test_spawn_monitor_demonitor_3() ->
    {Pid, Ref} = spawn_monitor(fun() -> ok end),
    demonitor(Ref, [flush]),
    Result =
    receive
        {'DOWN', Ref, process, Pid, normal} -> result1
    after 0 -> result2
    end,
    ?assertEqual(result2, Result).

-spec test_spawn_monitor_demonitor_4() -> 'ok'.

test_spawn_monitor_demonitor_4() ->
    {_Pid, Ref} = spawn_monitor(fun() -> ok end),
    Result = demonitor(Ref, [info]),
    ?assertEqual(true, Result).

-spec test_spawn_monitor_demonitor_5() -> 'ok'.

test_spawn_monitor_demonitor_5() ->
    {_Pid, Ref} = spawn_monitor(fun() -> ok end),
    Result = demonitor(Ref, [flush, info]),
    ?assertEqual(true, Result).

-spec test_spawn_opt_link_receive_exit() -> 'ok'.

test_spawn_opt_link_receive_exit() ->
    Fun = fun() -> process_flag(trap_exit, true),
           receive
               {'EXIT', _Pid, normal} -> ok
           end
      end,
    spawn_opt(Fun, [link]),
    ok.

-spec test_spawn_opt_monitor() -> 'ok'.

test_spawn_opt_monitor() ->
    {Pid, Ref} = spawn_opt(fun() -> ok end, [monitor]),
    demonitor(Ref),
    receive
    {'DOWN', Ref, process, Pid, normal} -> ok
    end.

-spec test_erlang_send_3() -> 'ok'.

test_erlang_send_3() ->
    Pid = spawn(fun() -> receive foo -> ok end end),
    erlang:send(Pid, foo, [nosuspend]),
    ok.

-spec test_halt_0() -> 'ok'.

test_halt_0() ->
    halt(),
    ?assertEqual(0, 1).

-spec test_halt_1() -> 'ok'.

test_halt_1() ->
    halt("But, it's a talking dooog!"),
    ?assertEqual(0, 1).

-spec test_var_mod_fun() -> 'ok'.

test_var_mod_fun() ->
    Mod = erlang,
    Fun = spawn,
    Mod:Fun(fun() -> ok end),
    ok.

-spec test_3_proc_receive_exit() -> 'ok'.

test_3_proc_receive_exit() ->
    process_flag(trap_exit, true),
    Pid1 = spawn_link(fun() -> ok end),
    Pid2 = spawn_link(fun() -> ok end),
    receive
    {'EXIT', Pid1, normal} ->
        receive
        {'EXIT', Pid2, normal} -> ok
        end
    end.

-spec test_3_proc_send_receive() -> 'ok'.

test_3_proc_send_receive() ->
    Self = self(),
    spawn(fun() -> Self ! {self(), bar}, receive bar -> ok end end),
    spawn(fun() -> Self ! {self(), baz}, receive baz -> ok end end),
    receive
    {Who1, bar} -> Who1 ! bar
    end,
    receive
    {Who2, baz} -> Who2 ! baz
    end.
