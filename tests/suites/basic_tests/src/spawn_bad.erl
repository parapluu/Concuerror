-module(spawn_bad).

-export([scenarios/0, test/0]).

scenarios() -> [{test, inf, dpor}].

test() -> spawn(2).
