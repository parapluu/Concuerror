-module(registered_1).

-compile(export_all).

registered_1() ->
    register(parent, self()),
    Pid = spawn(fun() -> receive
                             go -> ok
                         end,
                         register(parent, self())
                end),
    Pid ! go.                        
