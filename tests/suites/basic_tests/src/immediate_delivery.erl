-module(immediate_delivery).

-export([test1/0, test2/0, test3/0]).
-export([scenarios/0]).

-concuerror_options_forced([{instant_delivery, true}]).

scenarios() ->
    [{T, inf, dpor} ||
        {T,0} <- ?MODULE:module_info(exports),
        T =/= scenarios,
        T =/= concuerror_options,
        T =/= module_info
    ].

test1() ->
    P = self(),
    C1 = spawn(fun() ->
                       receive
                           p ->
                               receive
                                   c -> ok
                               end;
                           c -> error(fault)
                       end
               end),
    C1 ! p,
    spawn(fun() -> C1 ! c end).

test2() ->
    P = self(),
    C1 = spawn(fun() ->
                       receive
                           p ->
                               receive
                                   c -> ok
                               end;
                           c -> error(fault)
                       end
               end),
    spawn(fun() -> C1 ! c end),
    C1 ! p.

test3() ->
    Fun = fun() -> io:format("Foo") end,
    Fun(),
    spawn(Fun),
    Fun(),
    spawn(Fun).    
