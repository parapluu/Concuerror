-module(same_messages).

-export([same_messages/0]).

same_messages() ->
    Parent = self(),
    spawn(fun() -> Parent ! one end),
    spawn(fun() -> Parent ! one end),
    receive
        One ->
            receive
                Two ->
                    [one, one] = [One, Two]
            end
    end.
