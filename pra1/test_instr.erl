-module(test_instr).
-export([test1/0, test2/0]).

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
    Self = self(),
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo21(Self) end) end),
    sched:rep_spawn(fun() -> spawn(fun() -> link(whereis(sched)), foo22(Self) end) end),
    sched:rep_yield(),
    receive
	_Any1 -> ok
    end,
    sched:rep_yield(),
    receive
	_Any2 -> ok
    end.

foo21(Pid) ->
    sched:rep_yield(),
    Pid ! msg1.

foo22(Pid) ->
    sched:rep_yield(),
    Pid ! msg2.
