-module(unregister_deadlocked).

-export([scenarios/0]).
-export([test1/0]).

scenarios() ->
    [{test1,inf,dpor}].

test1() ->
    whereis(one),
    spawn(fun() ->
                  register(one, self()),
                  receive after infinity -> ok end
          end),
    one ! boo.
