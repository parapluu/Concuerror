-module(test_instr).
-export([test1/0, test2/0, test3/0]).

test1() ->
    Self = self(),
    %% spawn replacement
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo1(Self) end) end),
    receive
	_Any -> ok
    end.

foo1(Pid) ->
    Pid ! msg.

test2() ->
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo21() end) end),
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo22() end) end).

foo21() ->
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo22() end) end).

foo22() ->
    42.

test3() ->
    Self = self(),
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo31(Self) end) end),
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo32(Self) end) end),
    sched:rep_yield(),
    receive
	_Any1 -> ok
    end,
    sched:rep_yield(),
    receive
	_Any2 -> ok
    end.

foo31(Pid) ->
    sched:rep_yield(),
    Pid ! msg1.

foo32(Pid) ->
    sched:rep_yield(),
    Pid ! msg2.
