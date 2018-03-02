-module(debug_works).

-export([test/0]).

-ifndef(N).
-define(N, 2).
-endif.

test() ->
  test(?N).

test(N) ->
  P = self(),
  Fun = fun() -> P ! self() end,
  [spawn(Fun) || _ <- lists:seq(1, N)],
  receive
    _ -> ok
  end.
