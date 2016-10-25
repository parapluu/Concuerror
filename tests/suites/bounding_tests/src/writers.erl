-module(writers).
-export([scenarios/0,test/0]).

scenarios() -> [{test, B, dpor} || B <- [0, 1, 2, 3, 4, 5, 6, 7]].

test() -> writers(6).

writers(N) ->
  ets:new(tab, [public, named_table]),
  Writer = fun(I) -> ets:insert(tab, {x, I}) end,
  [spawn(fun() -> Writer(I) end) || I <- lists:seq(1, N)],
  receive after infinity -> deadlock end.
