-module(test).

-export([independent_receivers/0, simple_spawn/0, spawn_and_send/0, many_spawn/0,
         receiver/0, not_really_blocker/0, spawn/0, three_send/0,
         crasher/0, crasher2/0,
         blocker/0, blocking_trace/0,
         receiver_trace/0]).

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
    Fun = fun() -> spawn(fun() -> ok end) end,
    many(Fun, 3).

receiver() ->
    spawn(fun() -> receive ok -> ok end end) ! ok.

not_really_blocker() ->
    spawn(fun() -> receive ok -> ok after 0 -> ok end end) ! ok.

spawn() ->
    Fun = fun() -> spawn(fun() -> ok end) end,
    many(2, Fun).

three_send() ->
    Fun = fun() -> spawn(fun() -> ok end) ! ok end,
    many(Fun, 3).

crasher() ->
    spawn(fun() -> this() end).

this() ->
    will().

will() ->
    crash().

crasher2() ->
    spawn(fun() -> this2() end).

this2() ->
    will2().

will2() ->
    badarith().

blocking_trace() ->
    Pid = spawn(fun() -> ok end),
    Pid ! ok,
    Pid ! ok,
    Pid ! ok,
    Pid ! ok,
    blocker().

receiver_trace() ->
    receiver(),
    blocker().

%%------------------------------------------------------------------------------
%% Small Testing Parts
%%------------------------------------------------------------------------------

blocker() ->
    receive
        Pat -> Pat
    end.

crash() ->
    throw(boom).

badarith() ->
    1/0.

many(Fun, 0) -> ok;
many(Fun, N) -> Fun(), many(Fun, N-1).
