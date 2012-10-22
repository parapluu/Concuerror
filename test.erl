-module(test).

-export([independent_receivers/0, simple_spawn/0, spawn_and_send/0, many_spawn/0,
         receiver/0, not_really_blocker/0, spawn/0, three_send/0,
         crasher/0, crasher2/0,
         blocker/0, blocking_trace/0,
         receiver_trace/0, two_receiver_trace/0, two_receiver_trace_2/0, two_receiver_trace_3/0,
         two_receiver_trace_flat/0,
         afterer/0, after_crasher/0,
         opt_afterer/0, opt_after_crasher/0,
         spawner_trace/0, spawner_trace_2/0, spawner_trace_3/0, spawner_trace_4/0, spawner_trace_5/0,
         independent_receivers_blocker/0,
         not_really_blocker/0, not_really_blocker_crasher/0,
         trace_the_receives/0]).

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

spawn() ->
    Fun = fun() -> spawn(fun() -> ok end) end,
    many(Fun, 2).

many_spawn() ->
    Fun = fun() -> spawn(fun() -> ok end) end,
    many(Fun, 3).

receiver() ->
    spawn(fun() -> receive ok -> ok end end) ! ok.

not_really_blocker() ->
    spawn(fun() -> receive ok -> ok after 0 -> ok end end) ! ok.

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

two_receiver_trace_flat() ->
    _Pid1 = spawn(fun() -> ok end),
    Pid2 = spawn(fun() -> receive ok -> ok end end),
    Pid2 ! ok,
    receive
        Pat -> Pat
    end.

two_receiver_trace() ->
    spawn(fun() -> ok end),
    receiver_trace().

spawner_trace() ->
    spawn(),
    blocker().

spawner_trace_2() ->
    many_spawn(),
    blocker().

spawner_trace_3() ->
    many_spawn(),
    crasher().

spawner_trace_4() ->
    spawn(),
    crasher().

spawner_trace_5() ->
    spawn(fun() -> ok end),
    crasher().

two_receiver_trace_2() ->
    spawn(fun() -> ok end),
    receiver(),
    spawn(fun() -> ok end),
    crasher2().

two_receiver_trace_3() ->
    receiver(),
    receiver(),
    crasher().

after_crasher() ->
    afterer(),
    crasher().

opt_after_crasher() ->
    opt_afterer(),
    crasher().

independent_receivers_blocker() ->
    independent_receivers(),
    blocker().    

not_really_blocker_crasher() ->
    not_really_blocker(),
    crasher().

%%------------------------------------------------------------------------------
%% Small Testing Parts
%%------------------------------------------------------------------------------

opt_afterer() ->
    Ref = make_ref(),
    receive
        Ref -> ok
    after
        10 -> ok
    end.

blocker() ->
    receive
        Pat -> Pat
    end.

afterer() ->
    spawn(),
    receive
    after 50 ->
            ok
    end.

crash() ->
    throw(boom).

badarith() ->
    1/0.

many(Fun, 0) -> ok;
many(Fun, N) -> Fun(), many(Fun, N-1).

trace_the_receives() ->
    spawn(fun() -> ok end),
    X = spawn(fun() ->
                      receive
                          Pat1 ->
                              receive
                                  Pat2 ->
                                      [Pat1, Pat2]
                              end
                      end
              end),
    Y = spawn(fun() ->
                      receive
                          ok ->
                              X ! y
                      end
              end),
    Z = spawn(fun() ->
                      receive
                          ok ->
                              Y ! ok
                      end
              end),
    W = spawn(fun() -> Z ! ok end),
    X ! main.
                      
