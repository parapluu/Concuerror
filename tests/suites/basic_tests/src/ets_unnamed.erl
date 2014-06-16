-module(ets_unnamed).

-export([scenarios/0]).
-export([test1/0,test2/0,test3/0]).

scenarios() ->
    [{T, inf, dpor} || T <- [test1,test2,test3]].

test1() ->
    F = fun() -> ets:new(table, [private]) end,
    spawn(F),
    spawn(F),
    spawn(F).

test2() ->
    F =
        fun() ->
                T = ets:new(table, [private]),
                ets:insert(T, {1,2}),
                ets:insert(T, {1,3})
        end,
    spawn(F),
    spawn(F),
    spawn(F).

test3() ->
    F =
        fun() ->
                T = ets:new(table, [private]),
                ets:insert(T, {1,2}),
                ets:insert(T, {1,3}),
                register(tabler, self())
        end,
    spawn(F),
    spawn(F),
    spawn(F).

