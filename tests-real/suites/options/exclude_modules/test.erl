-module(test).

-export([test/0]).

-export([scenarios/0]).

-concuerror_options_forced([{ignore_error, deadlock}]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, optimal}].

%%------------------------------------------------------------------------------

test() ->
  excluded:foo(),
  receive after infinity -> ok end.
