-module(race_info).

-export([test/0]).

test() ->
  P = self(),
  spawn(fun() -> P ! foo end),
  receive
    foo -> ok
  after
    0 -> ok
  end.
