-module(application_check).

-export([test/0]).

-export([scenarios/0]).
-export([exceptional/0]).

-concuerror_options_forced([{timeout, 10000}]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, dpor}].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd = "grep \"Your test communicates with the 'application_controller' process.\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

%%------------------------------------------------------------------------------

test() ->
  application:start(crypto),
  application:get_env(crypto).
