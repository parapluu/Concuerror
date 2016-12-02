-module(last_zero).

-export([scenarios/0, test/0]).

-concuerror_options_forced([{scheduling, oldest}]).

scenarios() -> [{test, inf, R} || R <- [dpor,source]].

test() ->
    last_zero(5).

last_zero(N) ->
    ets:new(table, [public, named_table]),
    lists:foreach(fun(X) -> ets:insert(table, {X, 0}) end, lists:seq(0,N)),
    spawn(fun() -> reader(N) end),
    lists:foreach(fun(X) -> spawn(fun() -> writer(X) end) end, lists:seq(1,N)),
    receive after infinity -> ok end.

reader(0) -> ok;
reader(N) ->
    [{N, R}] = ets:lookup(table, N),
    case R of
        0 -> ok;
        _ -> reader(N-1)
    end.

writer(X) ->
    [{_, R}] = ets:lookup(table, X-1),
    ets:insert(table, {X, R+1}).
