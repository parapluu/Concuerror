%%%----------------------------------------------------------------------
%%% File        : test.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Tests
%%% Created     : 16 May 2010
%%%----------------------------------------------------------------------

-module(test).
-export([test01/0, test02/0, test03/0, test04/0,
	 test05/0, test06/0, test07/0, test08/0,
	 test09/0, test10/0, test11/0, test12/0,
         test13/0, test14/0, test15/0, test16/0,
	 test17/0, test18/0, test19/0, test20/0,
         test21/0, test22/0, test23/0, test24/0,
         test25/0, test26/0, test27/0, test28/0]).

-include("ced.hrl").

%% Normal, 2 proc: Simple send-receive.
-spec test01() -> 'ok'.

test01() ->
    ?assert(foo1() =:= ok).

foo1() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    receive _Any -> ok end.

foo1_1(Pid) ->
    Pid ! 42.

%% Normal, 3 proc: Only spawns.
-spec test02() -> 'ok'.

test02() ->
    ?assert(foo2() =:= ok).

foo2() ->
    spawn(fun() -> foo2_1() end),
    spawn(fun() -> foo2_2() end),
    ok.

foo2_1() ->
    spawn(fun() -> foo2_2() end).

foo2_2() ->
    42.

%% Normal, 3 proc: Simple send-receive.
-spec test03() -> 'ok'.

test03() ->
    ?assert(foo3() =:= ok).

foo3() ->
    Self = self(),
    spawn(fun() -> foo3_1(Self) end),
    spawn(fun() -> foo3_2(Self) end),
    receive
	_Any1 -> ok
    end,
    receive
	_Any2 -> ok
    end.

foo3_1(Pid) ->
    Pid ! msg1.

foo3_2(Pid) ->
    Pid ! msg2.

%% Deadlock, 2 proc: Both receiving.
-spec test04() -> no_return().

test04() ->
    ?assert(foo4() =:= ok).

foo4() ->
    spawn(fun() -> foo4_1() end),
    receive _Any -> ok end.

foo4_1() ->
    receive _Any -> ok end.

%% Deadlock, 2 proc: Sending 42, expecting to receive 43.
-spec test05() -> no_return().

test05() ->
    ?assert(foo5() =:= ok).

foo5() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    receive 43 -> ok end.

%% Normal, 2 proc: Nested send.
-spec test06() -> 'ok'.

test06() ->
    ?assert(foo6() =:= ok).

foo6() ->
    Self = self(),
    spawn(fun() -> foo6_1(Self) end),
    receive
	Any -> receive
		   Any -> ok
	       end
    end.

foo6_1(Pid) ->
    Pid ! Pid ! 42.

%% Normal, 2 proc: Nested send-receive.
-spec test07() -> 'ok'.

test07() ->
    ?assert(foo7() =:= ok).

foo7() ->
    Self = self(),
    Pid = spawn(fun() -> foo7_1(Self) end),
    Msg = hello,
    Pid ! Msg,
    receive
	Msg -> ok
    end.

foo7_1(Pid) ->
    Pid ! receive
	      Any -> Any
	  end.

%% Race, 2 proc: Classic spawn-link race.
-spec test08() -> 'ok'.

test08() ->
    ?assert(foo8() =:= ok).

foo8() ->
    Self = self(),
    Pid = spawn(fun() -> foo1_1(Self) end),
    link(Pid),
    receive
	_Any -> ok
    end.

%% Normal, 2 proc: Like test1/0, but using function from other file.
-spec test09() -> 'ok'.

test09() ->
    ?assert(foo9() =:= ok).

foo9() ->
    Self = self(),
    spawn(fun() -> test_aux:bar(Self) end),
    receive _Any -> ok end.

%% Assertion violation, 3 proc: 
-spec test10() -> 'ok'.

test10() ->
    Self = self(),
    spawn(fun() -> foo3_1(Self) end),
    spawn(fun() -> foo3_2(Self) end),
    receive
	Msg -> ?assert(Msg =:= msg1)
    end.

%% Normal, 2 proc: Simple receive-after with no patterns.
-spec test11() -> 'ok'.

test11() ->
    ?assert(foo11() =:= ok).

foo11() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    receive after 42 -> ok end,
    receive _Any -> ok end.

%% Normal, 2 proc: Call to erlang:spawn.
-spec test12() -> 'ok'.

test12() ->
    ?assert(foo12() =:= ok).

foo12() ->
    Self = self(),
    erlang:spawn(fun() -> foo1_1(Self) end),
    receive _Any -> ok end.

%% Normal, 2 proc: Call to erlang:yield.
-spec test13() -> 'ok'.

test13() ->
    ?assert(foo13() =:= ok).

foo13() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    erlang:yield(),
    receive _Any -> ok end.

%% Normal, 2 proc: Simple send-receive/after.
-spec test14() -> 'ok'.

test14() ->
    ?assert(foo14() =:= ok).

foo14() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    receive
        42 -> ok
    after 42 ->
            gazonk
    end.

%% Normal, 2 proc: Spawn link, trap_exit and receive exit message.
-spec test15() -> 'ok'.

test15() ->
    process_flag(trap_exit, true),
    Child = spawn_link(fun() -> ok end),
    receive
	{'EXIT', Child, normal} -> ok
    end.

%% Normal, 2 proc: Spawn link, trap_exit and receive exit message.
%% Same as above, but with catch-all instead of specific pattern.
-spec test16() -> 'ok'.

test16() ->
    process_flag(trap_exit, true),
    spawn_link(fun() -> ok end),
    receive
	_Exit -> ok
    end.

%% Deadlock/Normal, 2 proc: Spawn link, trap_exit and receive exit message.
%% Same as above, but trap_exit is set to false before receive.
-spec test17() -> 'ok'.

test17() ->
    process_flag(trap_exit, true),
    spawn_link(fun() -> ok end),
    process_flag(trap_exit, false),
    receive
	_Exit -> ok
    end.

%% Assertion violation/Normal, 3 proc: Testing interleaving of process exits
%% and trap_exit.
test18() ->
    Self = self(),
    spawn(fun() -> foo18(Self) end),
    spawn(fun() -> foo18(Self) end),
    process_flag(trap_exit, true),
    N = flush_mailbox(0),
    ?assertEqual(2, N).

foo18(Parent) ->
    link(Parent),
    ok.

flush_mailbox(N) ->
    receive
	_ -> flush_mailbox(N + 1)
    after 0 -> N
    end.

%% Deadlock/Normal, 2 proc: Spawn link, trap_exit, unlink
%% and receive exit message.
-spec test19() -> 'ok'.

test19() ->
    process_flag(trap_exit, true),
    Pid = spawn_link(fun() -> ok end),
    unlink(Pid),
    receive
	_Exit -> ok
    end.

%% Normal, 2 proc: Spawn, monitor and receive down message.
-spec test20() -> 'ok'.

test20() ->
    Ref = monitor(process, Pid = spawn(fun() -> ok end)),
    receive
	{'DOWN', Ref, process, Pid, _Info} -> ok
    end.

%% Deadlock/Normal, 2 proc: Spawn, monitor and receive down message.
%% Same as above, but demonitor is called before receive.
-spec test21() -> 'ok'.

test21() ->
    Ref = monitor(process, spawn(fun() -> ok end)),
    demonitor(Ref),
    receive
	_Down -> ok
    end.

%% Assertion violation/Normal, 3 proc: Testing interleaving of process deaths
%% and monitor.
test22() ->
    Pid1 = spawn(fun() -> ok end),
    Pid2 = spawn(fun() -> ok end),
    monitor(process, Pid1),
    monitor(process, Pid2),
    N = flush_mailbox(0),
    ?assertEqual(2, N).

%% Assertion violation/Normal, 3 proc: Testing interleaving of process deaths
%% and monitor.
%% Same as above, but spawn_monitor/1 is called instead of spawn/1
%% and monitor/2.
test23() ->
    spawn_monitor(fun() -> ok end),
    spawn_monitor(fun() -> ok end),
    N = flush_mailbox(0),
    ?assertEqual(2, N).

%% Normal, 2 proc: Simple send-receive with registered process.
-spec test24() -> 'ok'.

test24() ->
    ?assert(foo24() =:= ok).

foo24() ->
    register(self, self()),
    spawn(fun() -> foo1_1(self) end),
    receive _Any -> ok end.

%% Normal, 2 proc: Simple send-receive with registered process.
%% Same as above, but the message is sent using the pid
%% instead of the registered name.
-spec test25() -> 'ok'.

test25() ->
    ?assert(foo25() =:= ok).

foo25() ->
    register(self, self()),
    spawn(fun() -> foo1_1(whereis(self)) end),
    receive _Any -> ok end.


%% Exception/Normal, 2 proc: Simple send-receive with registered process.
%% Same as above, but the process is also unregistered.
-spec test26() -> 'ok'.

test26() ->
    register(self, self()),
    spawn(fun() -> foo1_1(whereis(self)) end),
    unregister(self),
    receive _Any -> ok end.

%% Normal, 2 proc: The first process halts before receiving.
-spec test27() -> no_return().

test27() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    erlang:halt(),
    receive _Any -> ok end.

%% Normal, 2 proc: Same as above, but using halt/1.
-spec test28() -> no_return().

test28() ->
    Self = self(),
    spawn(fun() -> foo1_1(Self) end),
    erlang:halt("Halt!"),
    receive _Any -> ok end.
