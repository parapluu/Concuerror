-module(file_system_example).

-export([file_system_example/0]).

-define(NUMBLOCKS, 26).
-define(NUMINODE, 32).

file_system_example() ->
    main(18).

thread(Name, Tid, Parent) ->
    I = Tid rem ?NUMINODE,
    RPid = acquire_lock(Name, i, I),
    case ets:lookup(inode, I) of
        [{I, 0}] ->
            B = (I * 2) rem ?NUMBLOCKS,
            while_loop(Name, B, I);
        _Else -> ok
    end,
    release_lock(RPid),
    Parent ! exit.

acquire_lock(N, T, I) ->
    lock_name(T, I) ! {N, acquire},
    receive
        {RPid, acquired} -> RPid
    end.

release_lock(RPid) ->
    RPid ! release.

lock() ->
    receive
        {Pid, acquire} ->
            {RPid, Mon} = spawn_monitor(fun release/0),
            Pid ! {RPid, acquired},
            receive
                {'DOWN', Mon, process, RPid, normal} -> lock()
            end;
        stop -> ok
    end.

release() ->
    receive
        release -> ok
    end.

while_loop(N, B, I) ->
    RPid = acquire_lock(N, b, B),
    case ets:lookup(busy, B) of
        [{B, false}] ->
            ets:insert(busy, {B, true}),
            ets:insert(inode, {I, B+1}),
            release_lock(RPid);
        _Else ->
            release_lock(RPid),
            while_loop(N, (B+1) rem ?NUMBLOCKS, I)
    end.

main(Threads) ->
    [ets:new(N, [public, named_table]) || N <- [inode, busy]],
    init(?NUMINODE, i, inode, 0),
    init(?NUMBLOCKS, b, busy, false),
    spawn_threads(Threads),
    collect_threads(Threads),
    cleanup(),
    receive
        never -> ok
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
    Parent = self(),
    Pid = spawn(fun() ->
                    Name = thread_name(N),
                    register(Name, self()),
                    thread(Name, N, Parent)
                end),
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
    [lock_name(Lock, N) ! stop || N <- lists:seq(0, Slots - 1)].
         
