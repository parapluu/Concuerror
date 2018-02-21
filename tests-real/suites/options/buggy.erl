-module(buggy).

-export([test/0]).

test() ->
  P = self(),
  spawn(fun() -> P ! foo end),
  spawn(fun() -> P ! bar end),
  receive
    Msg ->
      true = Msg =:= foo
  end.
