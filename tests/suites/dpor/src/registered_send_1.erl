-module(registered_send_1).

-export([registered_send_1/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

registered_send_1() ->
    Parent = self(),
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
