-module(proxy).

-export([proxy/0]).
-export([scenarios/0]).

-concuerror_options_forced([{depth_bound, 1000}, {instant_delivery, false}]).

scenarios() -> [{?MODULE, inf, dpor}].

proxy() ->
    C = self(),
    B = proxy(100, C),
    _A = spawn(fun() ->
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
