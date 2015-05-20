-module(erlang_display_string).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
  [{test, inf, dpor}].

test() ->
  erlang:display_string("Foo"),
  receive after infinity -> ok end.
