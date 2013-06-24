-module(my_send_after).

-export([scenarios/0]).

-export([my_send_after/0]).

scenarios() ->
    [{my_send_after, inf, R} || R <- [dpor, full]].

my_send_after() ->
    P1 = spawn(fun() -> receive _ -> ok end end),
    spawn(fun() -> P1 ! ok end),
    spawn(fun() -> erlang:send_after(50, P1, ok) end),
    receive after infinity -> ok end.

