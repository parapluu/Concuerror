-module(send_named_vs_send).

-export([send_named_vs_send/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

send_named_vs_send() ->
    register(name, self()),
    spawn(fun() -> spawn(fun() -> catch name ! message_1 end) end),
    spawn(fun() ->
                  unregister(name),
                  register(name, self()),
                  spawn(fun() -> catch name ! message_2 end),
                  receive
                      message_2 -> ok;
                      message_1 -> throw(error)
                  end
          end),
    receive
        _ -> ok
    end,
    receive
    after
        infinity -> never
    end.
