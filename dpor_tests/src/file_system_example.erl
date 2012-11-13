-module(file_system_example).

-export([file_system_example/0]).
-export([test14/0, test16/0, test18/0, test24/0]).

-define(NUMBLOCKS, 26).
-define(NUMINODE, 32).

file_system_example() ->
    main(16).

test14() ->
    main(14).

test16() ->
    main(16).

test18() ->
    main(18).

test24() ->
    main(24).

thread(Name, Tid) ->
    I = Tid rem ?NUMINODE,
    acquire_lock(Name, i, I),
    case ets:lookup(inode, I) of
        [{I, 0}] ->
            B = (I * 2) rem ?NUMBLOCKS,
            while_loop(Name, B, I);
        _Else -> ok
    end,
    release_lock(i, I).

acquire_lock(N, T, I) ->
    lock_name(T, I) ! {N, acquire},
    receive
        acquired -> ok
    end.

release_lock(T, I) ->
     lock_name(T, I) ! concuerror_sched:lock_release_atom().

lock() ->
    receive
        {Pid, acquire} ->
            Pid ! acquired,
            ReleaseAtom = concuerror_sched:lock_release_atom(),
            receive
                ReleaseAtom -> lock()
            end;
        stop -> ok
    end.

while_loop(N, B, I) ->
    acquire_lock(N, b, B),
    case ets:lookup(busy, B) of
        [{B, false}] ->
            ets:insert(busy, {B, true}),
            ets:insert(inode, {I, B+1}),
            release_lock(b, B);
        _Else ->
            release_lock(b, B),
            while_loop(N, (B+1) rem ?NUMBLOCKS, I)
    end.

main(Threads) ->
    [ets:new(N, [public, named_table]) || N <- [inode, busy]],
    init(?NUMINODE, i, inode, 0),
    init(?NUMBLOCKS, b, busy, false),
    spawn_threads(Threads),
    receive
    after
        infinity -> ok
    end.

lock_name(Type, I) ->
    String = lists:flatten(io_lib:format("lock_~p_~p",[Type, I])),
    list_to_atom(String).

thread_name(I) ->
    String = lists:flatten(io_lib:format("thread_~p",[I])),
    list_to_atom(String).

init(Slots, Lock, Data, Init) ->
    [begin
         Pid = spawn(fun lock/0),
         register(lock_name(Lock, N), Pid),
         ets:insert(Data, {N, Init})
     end || N <- lists:seq(0, Slots - 1)].

spawn_threads(0) -> ok;
spawn_threads(N) ->
    Pid = spawn(fun() ->
                        Name = thread_name(N),
                        register(Name, self()),
                        thread(Name, N)
                end),
    spawn_threads(N-1).
