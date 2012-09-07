-module(test).

-export([independent_receivers/0, simple_spawn/0, spawn_and_send/0, many_spawn/0,
         receiver/0, not_really_blocker/0]).

independent_receivers() ->
    Parent = self(),
    Rec1 = spawn(fun() -> receiver(Parent) end),
    Rec2 = spawn(fun() -> receiver(Parent) end),
    Snd1 = spawn(fun() -> sender(Rec1) end),
    Snd2 = spawn(fun() -> sender(Rec2) end),
    receive
        ok ->
            receive
                ok -> done
            end
    end.

sender(Pid) ->
    Pid ! ok.

receiver(Parent) ->
    receive
        ok -> Parent ! ok
    end.

simple_spawn() ->
    spawn(fun() -> ok end).

spawn_and_send() ->
    spawn(fun() -> ok end) ! ok.
    
many_spawn() ->
    Fun = fun() -> ok end,
    spawn(Fun),
    spawn(Fun),
    spawn(Fun).

receiver() ->
    spawn(fun() -> receive ok -> ok end end) ! ok.

not_really_blocker() ->
    spawn(fun() -> receive ok -> ok after 10 -> ok end end) ! ok.

