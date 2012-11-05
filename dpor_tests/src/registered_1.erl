-module(registered_1).

-export([registered_1/0]).

registered_1() ->
    register(parent, self()),
    Pid = spawn(fun() -> receive
                             go -> ok
                         end,
                         register(parent, self())
                end),
    Pid ! go.                        
