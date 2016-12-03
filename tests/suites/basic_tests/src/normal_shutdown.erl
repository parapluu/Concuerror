-module(normal_shutdown).

-export([scenarios/0]).
-export([test/0]).

-concuerror_options_forced([{treat_as_normal, shutdown}]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    exit(shutdown).
