-module(test).

-export([scenarios/0]).
-export([test1/0]).

scenarios() ->
    [{test1, 0}, {test1, inf}].

test1() ->
    thread_ring:test1().
