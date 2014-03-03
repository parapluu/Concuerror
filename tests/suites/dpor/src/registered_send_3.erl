-module(registered_send_3).

-export([registered_send_3/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

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
