-module(source_killer).

-export([test/0]).
-export([scenarios/0]).

-concuerror_options_forced([{ignore_error, deadlock}]).

scenarios() -> [{test, inf, T} || T <- [source, dpor]].

test() ->
    ets:new(table, [public, named_table]),
    P = spawn(fun() -> ets:lookup(table, v), ets:lookup(table, k) end),
    spawn(fun() -> ets:insert(table, {k,1}) end),
    spawn(fun() -> ets:lookup(table, k), exit(P, kill) end),
    receive after infinity -> ok end.
