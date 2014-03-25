-module(receive_with_guard).

-export([receive_with_guard/0]).
-export([scenarios/0]).

scenarios() -> [{?MODULE, inf, dpor}].

receive_with_guard() ->
    P1 =
        spawn(fun() ->
                      receive
                          W when is_atom(W) -> ok
                      end
              end),
    P1 ! 10.
