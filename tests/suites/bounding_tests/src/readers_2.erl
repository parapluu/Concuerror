-module(readers_2).
-export([scenarios/0,test/0]).

scenarios() -> [{test, B, dpor} || B <- [0, 1, 2, 3, 4, 5, 6, 7]].

test() -> readers(6).

readers(N) ->
    ets:new(tab, [public, named_table]),
    Writer = fun() -> ets:insert(tab, {x, 42}) end,
    Reader = fun(I) -> ets:lookup(tab, x) end,
    [spawn(fun() -> Reader(I) end) || I <- lists:seq(1, N)],
    spawn(Writer),
    receive after infinity -> deadlock end.
