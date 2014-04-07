-module(timeout).

-export([scenarios/0]).
-export([concuerror_options/0]).
-export([test1/0, test2/0]).

concuerror_options() ->
    [{timeout, 1000}].

scenarios() ->
    [{T, inf, dpor, crash} || T <-[test1, test2]].

test1() ->
    loop().

test2() ->
    process_flag(trap_exit, true),
    loop().

loop() ->
    loop().
