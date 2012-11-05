-module(independent_receivers).

-export([independent_receivers/0]).

independent_receivers() ->
    Parent = self(),
    Rec1 = spawn(fun() -> receiver(Parent, 1) end),
    Rec2 = spawn(fun() -> receiver(Parent, 2) end),
    Snd1 = spawn(fun() -> sender(Rec1) end),
    Snd2 = spawn(fun() -> sender(Rec2) end),
    receive
        _Msg1 ->
            receive
                _Msg2 -> done
            end
    end.

sender(Pid) ->
    Pid ! ok.

receiver(Parent, N) ->
    receive
        ok -> Parent ! N
    end.
