-module(file_system_example).

-export([main/1]).

-define(NUMBLOCKS, 26).
-define(NUMINODE, 32).

thread(Tid, Parent) ->
    I = Tid rem ?NUMINODE,
    acquire_lock(i, I),
    case ets:lookup(inode, I) of
        [{I, 0}] ->
            B = (I * 2) rem ?NUMBLOCKS,
            while_loop(B, I);
        _Else -> ok
    end,
    release_lock(i, I),
    Parent ! exit.

acquire_lock(T, I) ->
    [{I, Pid}] = ets:lookup(T, I),
    Pid ! {self(), acquire},
    receive
        {Pid, acquired} -> ok
    end.

release_lock(T, I) ->
    [{I, Pid}] = ets:lookup(T, I),
    Pid ! {self(), release}.

lock() ->
    receive
        {Pid, acquire} ->
            Pid ! {self(), acquired},
            receive
                {Pid, release} ->
                    lock()
            end;
        stop -> ok
    end.

while_loop(B, I) ->
    acquire_lock(b, B),
    case ets:lookup(busy, B) of
        [{B, false}] ->
            ets:insert(busy, {B, true}),
            ets:insert(inode, {I, B+1}),
            release_lock(b, B);
        _Else ->
            release_lock(b, B),
            while_loop((B+1) rem ?NUMBLOCKS, I)
    end.

main(Threads) ->
    [ets:new(N, [public, named_table]) ||
        N <- [i, b, inode, busy]],
    init(?NUMINODE, i, inode, 0),
    init(?NUMBLOCKS, b, busy, false),
    spawn_threads(Threads),
    collect_threads(Threads),
    cleanup().

init(Slots, Lock, Data, Init) ->
    [begin
         Pid = spawn(fun lock/0),
         ets:insert(Lock, {N, Pid}),
         ets:insert(Data, {N, Init})
     end || N <- lists:seq(0, Slots - 1)].

spawn_threads(0) -> ok;
spawn_threads(N) ->
    Parent = self(),
    spawn(fun() -> thread(N, Parent) end),
    spawn_threads(N-1).

collect_threads(0) -> ok;
collect_threads(N) -> 
    receive
        exit -> collect_threads(N-1)
    end.

cleanup() ->
    dismiss_locks(?NUMINODE, i),
    dismiss_locks(?NUMBLOCKS, b).

dismiss_locks(Slots, Lock) ->
    [begin
         [{N, Pid}] = ets:lookup(Lock, N),
         Pid ! stop
     end || N <- lists:seq(0, Slots - 1)].
         
