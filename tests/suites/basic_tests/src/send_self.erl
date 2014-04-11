-module(send_self).

-export([scenarios/0]).
-export([test1/0, test2/0, test3/0]).

scenarios() ->
    [{T, inf, dpor} || T <- [test1,test2,test3]].

test1() ->
    self() ! ok,
    receive
        ok -> ok
    after
        0 -> error(self_messages_are_delivered_instantly)
    end.

test2() ->
    P = self(),
    spawn(fun() -> P ! two end),
    P ! one,
    receive
        A -> throw(A)
    end.

test3() ->
    P = self(),
    spawn(fun() -> P ! two end),
    P ! one,
    receive
        one -> throw(one)
    end.
