-module(processes).

-export([test1/0, test2/0]).
-export([scenarios/0]).

-concuerror_options_forced([{symbolic_names, false}]).

scenarios() -> [{T, inf, dpor} || T <- [test1, test2]].

test1() ->
    Fun = fun() -> ok end,
    spawn(Fun),
    spawn(Fun),
    processes().

test2() ->
    Fun = fun() -> ok end,
    FFun = fun() -> spawn(Fun) end,
    spawn(Fun),
    spawn(FFun),
    processes(),
    throw(foo).
