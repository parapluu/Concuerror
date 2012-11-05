-module(proxy2).

-export([proxy2/0]).

proxy2() ->
    C = self(),
    B = proxy(100, C),
    A = spawn(fun() ->
                      B ! world,
                      C ! hello
              end),
    receive Msg1 -> ok end,
    receive Msg2 -> ok end,
    {Msg1, Msg2}.

proxy(0, Pid) ->
    Pid;
proxy(N, Pid) ->
    Proxy = proxy(N-1, Pid),
    proxy(Proxy).

proxy(Pid) ->
    spawn(fun() ->
                  receive Msg -> Pid ! Msg end
          end).
