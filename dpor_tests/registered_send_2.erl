-module(registered_send_2).

-compile(export_all).

registered_send_2() ->
    Pid = spawn(fun() -> ok end),
    register(child, Pid).
                        
