-module(registered_1).

-export([registered_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

registered_1() ->
    register(parent, self()),
    Pid = spawn(fun() -> receive
                             go -> ok
                         end,
                         register(parent, self())
                end),
    Pid ! go.
