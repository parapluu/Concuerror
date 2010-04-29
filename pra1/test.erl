-module(test).
-export([test1/0, test2/0]).

-spec test1() -> 'ok'.
    
test1() ->
    Self = self(),
    %% spawn
    spawn(fun() -> foo1(Self) end),
    %% receive
    receive _Any -> ok end.

foo1(Pid) ->
    %% send
    Pid ! 42.

-spec test2() -> 'ok'.

test2() ->
    %% spawn
    spawn(fun() -> foo21() end),
    %% spawn
    spawn(fun() -> foo22() end),
    ok.

foo21() ->
    %% spawn
    spawn(fun() -> foo22() end).

foo22() ->
    42.
