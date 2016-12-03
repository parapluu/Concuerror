-module(ignore_error_3).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced(
   [ {depth_bound, 10}
   , {ignore_error, depth_bound}
   , {ignore_error, deadlock}
   ]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    P = self(),
    loop(10),
    spawn(fun() -> exit(boom) end),
    receive after infinity -> ok end.

loop(0) -> ok;
loop(N) ->
    self() ! ok,
    loop(N-1).
