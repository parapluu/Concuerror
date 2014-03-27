-module(receive_order).

-export([scenarios/0]).
-export([test1/0,test2/0,test3/0]).

scenarios() ->
    [{T, inf, dpor} || T <- [test1,test2, test3]].

test1() -> test(a, b).

test2() -> test(b, a).

test(F, S) ->
    P = spawn(fun() -> receive a -> receive B -> B = b end end end),
    spawn(fun() -> P ! F end),
    spawn(fun() -> P ! S end).

test3() ->
    P = spawn(fun() -> receive a -> receive b -> receive C -> C = c end end end end),
    spawn(fun() -> P ! b end),
    spawn(fun() -> P ! c, P ! a end).
