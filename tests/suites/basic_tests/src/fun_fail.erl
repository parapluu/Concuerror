-module(fun_fail).

-export([scenarios/0]).
-export([test1/0,test2/0,test3/0]).

scenarios() ->
    [{T, inf, dpor} || T <- [test1,test2,test3]].

test1() ->
    A = ban,
    A(foo).

test2() ->
    A = fun() -> ok end,
    A(foo).

test3() ->
    A = 1,
    A:foo(blip).
