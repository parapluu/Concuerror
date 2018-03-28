-module(deadlock).

-export([test/0]).

test() ->
  P = self(),
  spawn(fun() -> P ! foo end),
  receive
    bar -> ok
  end.
