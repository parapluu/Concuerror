-module(test).
-export([test1/0, test2/0, test3/0, test4/0, test5/0]).

-spec test1() -> 'ok'.
    
test1() ->
    Self = self(),
    spawn(fun() -> foo1(Self) end),
    receive _Any -> ok end.

foo1(Pid) ->
    Pid ! 42.

-spec test2() -> 'ok'.

test2() ->
    spawn(fun() -> foo21() end),
    spawn(fun() -> foo22() end),
    ok.

foo21() ->
    spawn(fun() -> foo22() end).

foo22() ->
    42.

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

-spec test4() -> no_return().

test4() ->
    spawn(fun() -> foo4() end),
    receive _Any -> ok end.

foo4() ->
    receive _Any -> ok end.

-spec test5() -> no_return().

test5() ->
    Self = self(),
    spawn(fun() -> foo1(Self) end),
    receive 43 -> ok end.
