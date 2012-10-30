-module(receive_and_after).

-compile(export_all).

receive_and_after() ->
    spawn(fun p1/0) ! enable.

p1() ->
    receive
        enable -> throw(kaboom)
    after
        10 ->
            throw(boom)
    end.
