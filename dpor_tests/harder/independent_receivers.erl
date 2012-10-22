-module(independent_receivers).

-compile(export_all).

independent_receivers() ->
    Parent = self(),
    Rec1 = spawn(fun() -> receiver(Parent) end),
    Rec2 = spawn(fun() -> receiver(Parent) end),
    Snd1 = spawn(fun() -> sender(Rec1) end),
    Snd2 = spawn(fun() -> sender(Rec2) end),
    receive
        ok ->
            receive
                ok -> done
            end
    end.

sender(Pid) ->
    Pid ! ok.

receiver(Parent) ->
    receive
        ok -> Parent ! ok
    end.
