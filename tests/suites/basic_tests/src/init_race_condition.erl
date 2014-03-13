%% A late reply from init could be registered as unblocking the respective child
%% but not be previously instrumented. This bug appears on bigger machines.

-module(init_race_condition).

-export([scenarios/0]).
-export([test/0]).

scenarios() -> [{test, inf, dpor}].

get_arguments() ->
    init ! {self(), get_arguments},
    receive
        {init, Rep} -> Rep
    end.

test() ->
    [ spawn(fun() -> get_arguments() end) || _ <- lists:seq(1, 2) ].
