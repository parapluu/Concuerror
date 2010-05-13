-module(test).
-export([test1/0, test2/0, test3/0, test4/0,
	 test5/0, test6/0, test7/0, test8/0]).

%% Normal, 2 proc: Simple send-receive.
-spec test1() -> 'ok'.

test1() ->
    Self = self(),
    spawn(fun() -> foo1(Self) end),
    receive _Any -> ok end.

foo1(Pid) ->
    Pid ! 42.

%% Normal, 3 proc: Only spawns.
-spec test2() -> 'ok'.

test2() ->
    spawn(fun() -> foo21() end),
    spawn(fun() -> foo22() end),
    ok.

foo21() ->
    spawn(fun() -> foo22() end).

foo22() ->
    42.

%% Normal, 3 proc: Simple send-receive.
-spec test3() -> 'ok'.

test3() ->
    Self = self(),
    spawn(fun() -> foo31(Self) end),
    spawn(fun() -> foo32(Self) end),
    receive
	_Any1 -> ok
    end,
    receive
	_Any2 -> ok
    end.

foo31(Pid) ->
    Pid ! msg1.

foo32(Pid) ->
    Pid ! msg2.

%% Deadlock, 2 proc: Both receiving.
-spec test4() -> no_return().

test4() ->
    spawn(fun() -> foo4() end),
    receive _Any -> ok end.

foo4() ->
    receive _Any -> ok end.

%% Deadlock, 2 proc: Sending 42, expecting to receive 43.
-spec test5() -> no_return().

test5() ->
    Self = self(),
    spawn(fun() -> foo1(Self) end),
    receive 43 -> ok end.

%% Normal, 2 proc: Nested send.
-spec test6() -> 'ok'.

test6() ->
    Self = self(),
    spawn(fun() -> foo6(Self) end),
    receive
	Any -> receive
		   Any -> ok
	       end
    end.

foo6(Pid) ->
    Pid ! Pid ! 42.

%% Normal, 2 proc: Nested send-receive.
-spec test7() -> 'ok'.

test7() ->
    Self = self(),
    Pid = spawn(fun() -> foo7(Self) end),
    Msg = hello,
    Pid ! Msg,
    receive
	Msg -> ok
    end.

foo7(Pid) ->
    Pid ! receive
	      Any -> Any
	  end.

%% Race, 2 proc: Classic spawn-link race.
-spec test8() -> 'ok'.

test8() ->
    Self = self(),
    Pid = spawn(fun() -> foo1(Self) end),
    link(Pid),
    receive
	Any -> ok
    end.
