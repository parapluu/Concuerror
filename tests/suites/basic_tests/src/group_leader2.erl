-module(group_leader2).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    UserPid = whereis(user),
    UserPid = group_leader(),
    group_leader(self(), self()),
    true = self() =:= group_leader(),
    Fun =
        fun() ->
                case flip_coin() of
                    true -> io:format("Block");
                    false -> ok
                end
        end,
    Fun(),
    spawn(Fun),
    group_leader(UserPid, self()),
    UserPid = group_leader(),
    io:format("All fine").

flip_coin() ->
    P = self(),
    spawn(fun() -> P ! ok end),
    receive
        ok -> true
    after
        0 -> receive ok -> false end
    end.
