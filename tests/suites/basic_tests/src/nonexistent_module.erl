-module(nonexistent_module).

-export([test/0]).

-export([scenarios/0]).
-export([exceptional/0]).

-concuerror_options_forced([]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, optimal}].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd = "grep \"Could not load module 'nonexistent_module_42'\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

%%------------------------------------------------------------------------------

test() ->
  nonexistent_module_42:test().
