-module(proxy).

-export([proxy/0]).

proxy() ->
    C = self(),
    B = proxy(100, C),
    A = spawn(fun() ->
                      C ! hello,
                      B ! world
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
