-module(spawned_sender_crasher).

-compile(export_all).

spawned_sender_crasher() ->
    Receiver = spawn(fun receive_two/0),
    spawn(sender(Receiver, one)),
    spawn(sender(Receiver, two)).

    

receive_two() ->
    receive
        Pat1 ->
            receive
                Pat2 ->
                    [one, two] = [Pat1, Pat2],
                    [two, one] = [Pat1, Pat2]
            end
    end.

sender(Receiver, Msg) ->
    fun() -> Receiver ! Msg end.
