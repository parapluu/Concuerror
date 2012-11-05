-module(registered_2).

-compile(export_all).

registered_2() ->
    Pid = spawn(fun() ->
                        register(parent, self())
                end),
    register(parent, self()),
    register(child, Pid).
