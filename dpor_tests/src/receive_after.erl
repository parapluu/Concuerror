-module(receive_after).

-export([receive_after/0]).

receive_after() ->
    P = self(),
    P1 =
        spawn(fun() ->
                      P ! ok,
                      receive
                          Sth -> saved
                      after
                          0 -> throw(boom)
                      end
              end),
    P1 ! ok,
    receive
        ok -> ok
    end.

