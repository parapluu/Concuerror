-module(six).

-export([test/0]).

test() ->
  P = self(),
  F = fun(M) -> fun() -> P ! M end end,
  spawn(F(a)),
  spawn(F(b)),
  spawn(F(c)),
  _ = receive _ -> ok end,
  _ = receive _ -> ok end,
  _ = receive _ -> ok end.
