%%%----------------------------------------------------------------------
%%% File        : test.erl
%%% Authors     : Alkis Gotovos <el3ctrologos@hotmail.com>
%%%               Maria Christakis <christakismaria@gmail.com>
%%% Description : Tests
%%% Created     : 16 May 2010
%%%----------------------------------------------------------------------

-module(test).
-export([test_spawn/0,
	 test_send/0, test_send_2/0,
	 test_receive/0, test_receive_2/0,
	 test_send_receive/0, test_send_receive_2/0, test_send_receive_3/0,
	 test_receive_after_no_patterns/0, test_receive_after_with_pattern/0,
	 test_after_clause_preemption/0,
	 test_spawn_link_race/0, test_link_receive_exit/0,
	 test_spawn_link_receive_exit/0,
	 test_link_unlink/0, test_spawn_link_unlink/0,
	 test_spawn_link_unlink_2/0, test_spawn_link_unlink_3/0,
	 test_trap_exit_timing/0,
	 test_spawn_register_race/0, test_register_unregister/0,
	 test_whereis/0]).

-include_lib("eunit/include/eunit.hrl").

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
    erlang:send(Pid, foo),
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
    Pid ! Reg.
