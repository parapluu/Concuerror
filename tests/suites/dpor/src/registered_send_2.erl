-module(registered_send_2).

-export([registered_send_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

registered_send_2() ->
    Pid = spawn(fun() -> ok end),
    register(child, Pid).
