-module(halt_support).

-export([test/0]).

-export([scenarios/0]).
-export([exceptional/0]).

scenarios() -> [{test, inf, optimal}].

exceptional() ->
  fun(_Expected, Actual) ->
      String =
        "Concuerror does not do race analysis for calls to erlang:halt",
      Cmd = "grep \"" ++ String ++ "\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

%%------------------------------------------------------------------------------

test() ->
  spawn(fun() -> io:format("Will never be shown") end),
  erlang:halt(0).
