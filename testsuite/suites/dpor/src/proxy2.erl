-module(proxy2).

-export([proxy2/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

proxy2() ->
    C = self(),
    B = proxy(100, C),
    _A = spawn(fun() ->
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
