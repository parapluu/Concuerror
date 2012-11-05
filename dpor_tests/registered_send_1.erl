-module(registered_send_1).

-compile(export_all).

registered_send_1() ->
    Pid = spawn(fun() -> register(child, self()),
                         receive
                             ok -> ok
                         end
                end),
    child ! ok.
                        
