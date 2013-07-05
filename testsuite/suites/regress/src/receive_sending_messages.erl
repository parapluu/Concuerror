-module(receive_sending_messages).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    process_flag(trap_exit, true),
    P = self(),
    spawn(fun() -> P ! ok end),
    receive
        Msg ->
            concuerror_rep:uninstrumented_send(P, normal)
    end.
