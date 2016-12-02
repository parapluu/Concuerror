-module(depth_bound).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{keep_going, false}, {depth_bound, 10}]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    process_flag(trap_exit, true),
    test().
