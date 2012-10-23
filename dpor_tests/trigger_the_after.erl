-module(trigger_the_after).

-compile(export_all).

trigger_the_after() ->
    Receiver = spawn(fun receive_two/0),
    spawn(sender(Receiver, two)),
    spawn(sender(Receiver, one)),
    1/0.

    

receive_two() ->
    receive
        one ->
            receive
                two -> throw(both)                    
            after
                100 -> throw(one)
            end
    end.

sender(Receiver, Msg) ->
    fun() -> Receiver ! Msg end.
