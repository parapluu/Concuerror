-module(group_leader3).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{ignore_error, deadlock}]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
  P = spawn(fun() -> receive after infinity -> ok end end),
  spawn(fun() -> group_leader(self(), P) end),
  process_info(P, group_leader).
