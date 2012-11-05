-module(registered_send_1).

-export([registered_send_1/0]).

registered_send_1() ->
    Parent = self(),
    Pid =
        spawn(fun() ->
                      Parent ! ok,
                      register(child, self()),
                      receive
                          ok -> ok
                      end
                end),
    receive
        ok -> child ! ok
    end.
                        
