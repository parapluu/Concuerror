-module(indexer_example).

-export([indexer_example/0]).
-export([main/1]).
-export([indexer12/0, indexer15/0]).
-export([scenarios/0]).

scenarios() -> []. %%[{?MODULE, inf, dpor}].

-define(size, 128).
-define(max, 4).

%% this is needed for the dpor test suite
indexer_example() ->
    main(15).

indexer12() ->
    main(12).

indexer15() ->
    main(15).

thread(Tid) ->
    thread(Tid, 0).

thread(Tid, M) ->
    case getmsg(M, Tid) of
        stop -> ok;
        {W, NewM} ->
            H = hash(W),
            while_cas_table(H, W),
            thread(Tid, NewM)
    end.

getmsg(M, Tid) ->
    case M < ?max of
        true ->
            NewM = M + 1,
            {NewM * 11 + Tid, NewM};
        false ->
            stop
    end.

hash(W) ->
    (W * 7) rem ?size.

while_cas_table(H, W) ->
    case ets:insert_new(table, {H, W}) of
        false -> while_cas_table((H + 1) rem ?size, W);
        true -> ok
    end.

main(Threads) ->
    ets:new(table, [public, named_table]),
    spawn_threads(Threads-1),
    receive
    after
        infinity -> ok
    end.

spawn_threads(-1) -> ok;
spawn_threads(N) ->
    spawn(fun() -> thread(N) end),
    spawn_threads(N-1).
