-module(excluded).

-export([foo/0]).

foo() ->
  P = self(),
  spawn(fun() -> P ! msg1 end),
  spawn(fun() -> P ! msg2 end),
  receive
    _ ->
      receive
        _ ->
          ok
      end
  end.
