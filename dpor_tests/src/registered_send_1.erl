-module(registered_send_1).

-export([registered_send_1/0]).

registered_send_1() ->
    Pid = spawn(fun() -> register(child, self()),
                         receive
                             ok -> ok
                         end
                end),
    child ! ok.
                        
