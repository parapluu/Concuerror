-module(foo).

-export([foo/0]).

foo() ->
    P = self(),
    spawn(fun() -> P ! a end),
    spawn(fun() -> P ! b end),
    spawn(fun() -> P ! c end),
    receive
        V -> V
    after
        0 -> bloo
    end.
