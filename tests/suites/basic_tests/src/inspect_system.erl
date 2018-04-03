-module(inspect_system).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
  {group_leader, _} = process_info(whereis(kernel_sup), group_leader).
