-module(io_format_3).

-export([scenarios/0]).
-export([test/0]).
-export([concuerror_options/0]).

concuerror_options() ->
    [{non_racing_system, user}].

scenarios() ->
    [{test, inf, dpor}].

test() ->
    P = self(),
    spawn(
      fun() -> P ! ok,
               io:format("Child~n")
      end),
    receive
        ok -> io:format("Parent~n")
    after
        0 -> ok
    end,
    receive after infinity -> ok end.
