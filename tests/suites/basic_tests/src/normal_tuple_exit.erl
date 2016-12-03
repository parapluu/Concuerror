-module(normal_tuple_exit).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{treat_as_normal, undef}]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    non:existing().
