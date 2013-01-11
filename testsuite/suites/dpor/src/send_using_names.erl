-module(send_using_names).

-export([send_using_names/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

send_using_names() ->
    Self = self(),
    Name = name,
    register(Name, Self),
    spawn(fun() -> Self ! msg1 end),
    spawn(fun() -> Name ! msg2 end),
    receive
        Msg1 ->
            receive
                Msg2 ->
                    [Msg1, Msg2] = [msg1, msg2]
            end
    end.
