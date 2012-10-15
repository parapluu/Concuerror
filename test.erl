-module(test).

-export([independent_receivers/0, simple_spawn/0, spawn_and_send/0, many_spawn/0,
         receiver/0, not_really_blocker/0, spawn/0, three_send/0,
         crasher/0, crasher2/0,
         blocker/0]).

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
    spawn(fun() -> receive ok -> ok after 0 -> ok end end) ! ok.

spawn() ->
    Fun = fun() -> ok end,
    spawn(Fun),
    spawn(Fun).

three_send() ->
    Fun = fun() -> ok end,
    spawn(Fun) ! ok,
    spawn(Fun) ! ok,
    spawn(Fun) ! ok.
    
crasher() ->
    spawn(fun() -> this() end).

this() ->
    will().

will() ->
    crash().

crash() ->
    throw(boom).

crasher2() ->
    spawn(fun() -> this2() end).

this2() ->
    will2().

will2() ->
    crash2().

crash2() ->
    1/0.

blocker() ->
    receive
        Pat -> Pat
    end.
