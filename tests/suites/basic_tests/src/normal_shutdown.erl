-module(normal_shutdown).

-export([scenarios/0]).
-export([test/0]).
-export([concuerror_options/0]).

concuerror_options() ->
    [{treat_as_normal, shutdown}].

scenarios() ->
    [{test, inf, dpor}].

test() ->
    exit(shutdown).
