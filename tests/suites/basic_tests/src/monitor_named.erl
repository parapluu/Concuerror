-module(monitor_named).

-export([scenarios/0]).
-export([test/0]).

scenarios() ->
    [{test, inf, dpor}].

test() ->
    C = spawn(fun() -> receive quit -> ok end end),
    true = register(child, C),
    Ref = monitor(process, child),
    true = unregister(child),
    C ! quit,
    receive
        {'DOWN',Ref, process, {child,_}, normal} -> ok
    end.
