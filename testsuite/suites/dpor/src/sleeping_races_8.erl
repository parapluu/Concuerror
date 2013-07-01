-module(sleeping_races_8).

-export([sleeping_races_8/0,
         sleeping_races_8/1]).

-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

sleeping_races_8() ->
    sleeping_races_8(4).

sleeping_races_8(N) ->
    ets:new(table, [public, named_table]),
    lists:foreach(fun(X) -> ets:insert(table, {X, 0}) end,
                  lists:seq(0,N)),
    spawn(fun() -> reader(N) end),
    lists:foreach(fun(X) -> spawn(fun() -> [{_, R}] = ets:lookup(table, X-1),
                                           ets:insert(table, {X, R+1})
                                  end) end,
                  lists:seq(1,N)),
    receive after infinity -> ok end.

reader(0) -> ok;
reader(N) ->
    [{N, R}] = ets:lookup(table, N),
    case R of
        0 -> ok;
        _ -> reader(N-1)
    end.
