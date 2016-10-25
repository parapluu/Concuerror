-module(readers_no_preempt).
-export([scenarios/0,test/0]).

scenarios() ->
  [{test, B, DPOR, BoundType} ||
    B <- [0, 1, 2],
    DPOR <- [optimal, source, persistent],
    BoundType <- [bpor, delay],
    DPOR =/= optimal orelse BoundType =/= bpor
  ].

test() -> readers(3).

readers(N) ->
    ets:new(tab, [public, named_table]),
    Writer = fun() -> ets:insert(tab, {x, 42}) end,
    Reader = fun() -> ets:lookup(tab, x) end,
    spawn(Writer),
    [spawn(fun() -> Reader() end) || _ <- lists:seq(1, N)],
    receive after infinity -> deadlock end.
