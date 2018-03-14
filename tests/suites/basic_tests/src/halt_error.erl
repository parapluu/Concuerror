-module(halt_error).

-export([test1/0, test2/0]).

-export([scenarios/0]).

scenarios() -> [{T, inf, optimal} || T <- [test1, test2]].

%%------------------------------------------------------------------------------

test1() ->
  spawn(fun() -> io:format("Will never be shown") end),
  erlang:halt(1).

test2() ->
  spawn(fun() -> halt(0) end),
  io:format("Will be shown").
