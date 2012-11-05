-module(registered_send_3).

-compile(export_all).

registered_send_3() ->
    Pid =
        spawn(fun() ->
                  receive
                      ok -> ok
                  end
              end),
    Pid ! ok,
    register(child, Pid),
    child ! foo.
                        
