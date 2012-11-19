-module(trace_the_sender).

-export([trace_the_sender/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

trace_the_sender() ->
    spawn_extra(),
    Receiver = spawn(fun receive_two/0),
    XSignal = YSignal = ZSignal = ok,
    ChainLinkX = spawn(wait_then_send(XSignal, Receiver, x)),
    ChainLinkY = spawn(wait_then_send(YSignal, ChainLinkX, XSignal)),
    ChainLinkZ = spawn(wait_then_send(ZSignal, ChainLinkY, YSignal)),
    ChainLinkZ ! ZSignal,
    Receiver ! main,
    ok.

spawn_extra() ->
    spawn(fun() -> ok end).

receive_two() ->
    receive
        Pat1 ->
            receive
                Pat2 ->
                    [Pat1, Pat2]
            end
    end.

wait_then_send(Signal, Recipient, Msg) ->
    fun() -> receive Signal -> Recipient ! Msg end end.
