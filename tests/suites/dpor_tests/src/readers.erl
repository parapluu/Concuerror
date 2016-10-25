-module(readers).
-export([scenarios/0,test/0]).

scenarios() -> [{test, inf, DPOR} || DPOR <- [optimal, persistent, source]].

test() -> readers(6).

readers(N) ->
    ets:new(tab, [public, named_table]),
    Writer = fun() -> ets:insert(tab, {x, 42}) end,
    Reader = fun(I) -> ets:lookup(tab, I), ets:lookup(tab, x) end,
    spawn(Writer),
    [spawn(fun() -> Reader(I) end) || I <- lists:seq(1, N)],
    receive after infinity -> deadlock end.
