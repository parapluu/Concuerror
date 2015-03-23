-module(inspect_system).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor, crash}].

test() ->
  {group_leader, GL} = process_info(whereis(kernel_sup), group_leader).
