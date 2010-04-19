-module(test_instr).
-export([test1/0, test2/0]).

test1() ->
    Self = self(),
    sched:yield(),
    spawn(fun() -> foo1(Self) end),
    receive
	_Any -> ok
    end.

foo1(Pid) ->
    Pid ! msg.

test2() ->
    Self = self(),
    sched:yield(),
    spawn(fun() -> foo21(Self) end),
    sched:yield(),
    spawn(fun() -> foo22(Self) end),
    receive
	_Any1 -> ok
    end,
    receive
	_Any2 -> ok
    end.

foo21(Pid) ->
    Pid ! msg1.

foo22(Pid) ->
    Pid ! msg2.
