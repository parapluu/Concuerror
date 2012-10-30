-module(same_messages).

-compile(export_all).

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
