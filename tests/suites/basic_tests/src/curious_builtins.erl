-module(curious_builtins).

-export([scenarios/0]).
-export([test1/0,test2/0,test3/0]).

scenarios() ->
    [{T, inf, dpor} || T <- [test1,test2,test3]].

test1() ->
    true = is_list(erlang:pid_to_list(self())).

test2() ->
    true = is_number(erlang:system_info(schedulers)).

test3() ->
    true = is_list(erlang:get_stacktrace()).
