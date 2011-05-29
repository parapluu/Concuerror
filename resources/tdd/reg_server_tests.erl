%%%----------------------------------------------------------------------
%%% Author      : Alkis Gotovos <alkisg@softlab.ntua.gr>
%%% Description : Generic registration server tests
%%%----------------------------------------------------------------------

-module(reg_server_tests).

-include_lib("eunit/include/eunit.hrl").
-include("reg_server.hrl").

-export([start_stop_test/0, ping_test/0, multiple_stops_test/0,
	 multiple_concurrent_stops_test/0, ping_failure_test/0,
	 ping_concurrent_failure_test/0, multiple_starts_test/0,
	 multiple_concurrent_starts_test/0, attach_test/0,
	 max_attached_proc_test/0, detach_test/0, detach_attach_test/0,
	 detach_non_attached_test/0, detach_on_exit_test/0]).


start_stop_test() ->
    ?assertEqual(ok, reg_server:start()),
    ?assertEqual(ok, reg_server:stop()).

ping_test() ->
    reg_server:start(),
    ?assertEqual(pong, reg_server:ping()),
    ?assertEqual(pong, reg_server:ping()),
    reg_server:stop().

multiple_stops_test() ->
    reg_server:start(),
    ?assertEqual(ok, reg_server:stop()),
    ?assertEqual(server_down, reg_server:stop()).

multiple_concurrent_stops_test() ->
    Self = self(),
    reg_server:start(),
    spawn(fun() -> Self ! reg_server:stop() end),
    spawn(fun() -> Self ! reg_server:stop() end),
    ?assertEqual(lists:sort([ok, server_down]),
		 lists:sort(receive_two())).

ping_failure_test() ->
    ?assertEqual(server_down, reg_server:ping()),
    reg_server:start(),
    reg_server:stop(),
    ?assertEqual(server_down, reg_server:ping()).

ping_concurrent_failure_test() ->
    reg_server:start(),
    spawn(fun() ->
		  R = reg_server:ping(),
		  Results = [pong, server_down],
		  ?assertEqual(true, lists:member(R, Results))
	  end),
    reg_server:stop().

multiple_starts_test() ->
    reg_server:start(),
    ?assertEqual(already_started, reg_server:start()),
    reg_server:stop().

multiple_concurrent_starts_test() ->
    Self = self(),
    spawn(fun() -> Self ! reg_server:start() end),
    spawn(fun() -> Self ! reg_server:start() end),
    ?assertEqual(lists:sort([already_started, ok]),
		 lists:sort(receive_two())),
    reg_server:stop().

attach_test() ->
    Self = self(),
    reg_server:start(),
    RegNum1 = reg_server:attach(),
    spawn(fun() ->
		  RegNum2 = reg_server:attach(),
		  ?assertEqual(RegNum2, reg_server:ping()),
		  ?assertEqual(false, RegNum1 =:= RegNum2),
		  Self ! done
	  end),
    ?assertEqual(RegNum1, reg_server:ping()),
    receive done -> reg_server:stop() end.

already_attached_test() ->
    reg_server:start(),
    RegNum = reg_server:attach(),
    ?assertEqual(RegNum, reg_server:attach()),
    reg_server:stop().

max_attached_proc_test() ->
    reg_server:start(),
    Ps = [spawn_attach() || _ <- lists:seq(1, ?MAX_ATTACHED)],
    ?assertEqual(server_full, reg_server:attach()),
    lists:foreach(fun(Pid) -> Pid ! ok end, Ps),
    reg_server:stop().

detach_test() ->
    reg_server:start(),
    reg_server:attach(),
    reg_server:detach(),
    ?assertEqual(pong, reg_server:ping()),
    reg_server:stop().

detach_attach_test() ->
    Self = self(),
    reg_server:start(),
    Ps = [spawn_attach() || _ <- lists:seq(1, ?MAX_ATTACHED - 1)],
    LastProc = spawn(fun() ->
			     RegNum = reg_server:attach(),
			     reg_server:detach(),
			     Self ! RegNum,
			     receive ok -> ok end
		     end),
    receive RegNum -> ok end,
    ?assertEqual(RegNum, reg_server:attach()),
    lists:foreach(fun(Pid) -> Pid ! ok end, [LastProc|Ps]),
    reg_server:stop().

detach_non_attached_test() ->
    reg_server:start(),
    ?assertEqual(ok, reg_server:detach()),
    reg_server:stop().

detach_on_exit_test() ->
    Self = self(),
    reg_server:start(),
    Ps = [spawn_attach() || _ <- lists:seq(1, ?MAX_ATTACHED - 1)],
    process_flag(trap_exit, true),
    LastProc = spawn_link(fun() ->
				  Self ! reg_server:attach()
			  end),
    receive RegNum -> ok end,
    receive {'EXIT', LastProc, normal} -> ok end,
    ?assertEqual(RegNum, reg_server:attach()),
    lists:foreach(fun(Pid) -> Pid ! ok end, [LastProc|Ps]),
    reg_server:stop().

%%%----------------------------------------------------------------------
%%% Helpers
%%%----------------------------------------------------------------------

receive_two() ->
    receive
	Result1 ->
	    receive
		Result2 ->
		    [Result1, Result2]
	    end
    end.

attach_and_wait(Target) ->
    reg_server:attach(),
    Target ! done,
    receive ok -> ok end.

spawn_attach() ->
    Self = self(),
    Pid = spawn(fun() -> attach_and_wait(Self) end),
    receive done -> Pid end.
