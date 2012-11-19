-module(registered_2).

-export([registered_2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

registered_2() ->
    Pid = spawn(fun() ->
                        register(parent, self())
                end),
    register(parent, self()),
    register(child, Pid).
