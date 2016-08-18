-module(os_timestamp).

-export([test/0]).
-export([scenarios/0]).

scenarios() -> [{test, inf, dpor}].

test() ->
  os:timestamp(),
  receive after infinity -> ok end.
