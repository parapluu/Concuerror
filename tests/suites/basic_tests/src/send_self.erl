-module(send_self).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    self() ! ok,
    receive
        ok -> ok
    after
        0 -> error(self_messages_are_delivered_instantly)
    end.
