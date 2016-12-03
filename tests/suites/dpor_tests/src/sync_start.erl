-module(sync_start).

-export([sync_start/0, sync_start/1]).
-export([scenarios/0]).

-concuerror_options_forced([{instant_delivery, false}]).

scenarios() -> [{?MODULE, inf, dpor}].

sync_start() ->
    sync_start(2).

sync_start(N) ->
    Parent = self(),
    Pids = [spawn(fun() -> worker(I, Parent) end) || I <- lists:seq(1,N)],
    ets:new(table, [named_table, public]),
    ets:insert(table, {pids, Pids}),
    [P ! ok || P <- Pids],
    [receive ok -> ok end || _ <- Pids],
    Results = [ets:lookup_element(table, P, 2) || P <- Pids],
    Results = lists:seq(1,N),
    receive
        deadlock -> ok
    end.

worker(I, Parent) ->
    receive
        ok ->
            Pids = ets:lookup_element(table, pids, 2),
            [P ! ok || P <- Pids, P =/= self()],
            [receive ok -> ok end || P <- Pids, P =/= self()],
            ets:insert(table, {self(), I}),
            Parent ! ok
    end.
