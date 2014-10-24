-module(send_after_trouble).

-export([test/0]).
-export([scenarios/0]).

scenarios() -> [{test, inf, dpor}].

test() ->
    P = self(),
    Q = spawn(fun() -> receive A -> A ! ok end end),
    S = spawn(fun() -> receive _ -> ok after 100 -> ok end end),
    Q ! S,
    S ! ok.
