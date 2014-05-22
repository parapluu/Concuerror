-module(process_info).

-export([test1/0]).
-export([scenarios/0]).

scenarios() -> [{T, inf, dpor} || T <- [test1]].

test1() ->
    Fun = fun() -> register(foo, self()) end,
    P = spawn(Fun),
    exit(process_info(P, registered_name)).
