-module(normal_tuple_exit).

-export([scenarios/0]).
-export([test/0]).
-export([concuerror_options/0]).

concuerror_options() ->
    [{treat_as_normal, undef}].

scenarios() ->
    [{test, inf, dpor}].

test() ->
    non:existing().
