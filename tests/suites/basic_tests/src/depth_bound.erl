-module(depth_bound).

-export([scenarios/0]).
-export([concuerror_options/0]).
-export([test/0]).

concuerror_options() ->
    [{ignore_first_crash, false}, {depth_bound, 10}].

scenarios() ->
    [{test, inf, dpor, crash}].

test() ->
    process_flag(trap_exit, true),
    test().
