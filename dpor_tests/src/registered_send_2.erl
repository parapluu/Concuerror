-module(registered_send_2).

-export([registered_send_2/0]).

registered_send_2() ->
    Pid = spawn(fun() -> ok end),
    register(child, Pid).
                        
