-module(etsi).

-export([etsi/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

etsi() ->
    ets:new(table, [public, named_table]),
    ets:insert(table, {x, 0}),
    ets:insert(table, {y, 0}),
    ets:insert(table, {z, 0}),
    spawn(fun() -> fun_1() end),
    spawn(fun() -> fun_2() end),
    spawn(fun() -> fun_3() end),
    receive
    after
        infinity -> ok
    end.

fun_1() -> fun_abc(x, y, z).
fun_2() -> fun_abc(y, z, x).
fun_3() -> fun_abc(z, x, y).

fun_abc(A, B, C) ->
    [{A, V}] = ets:lookup(table, A),
    case V of
        0 -> ets:insert(table, {B, 1});
        1 -> ets:insert(table, {C, 0})
    end,
    receive
    after
        infinity -> ok
    end.
