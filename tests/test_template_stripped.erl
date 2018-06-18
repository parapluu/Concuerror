%%% See test_template.erl for more details.

-module(test_template_stripped).

-export([test/0]).

-export([scenarios/0]).
-export([exceptional/0]).

-concuerror_options_forced([]).

%%------------------------------------------------------------------------------

scenarios() -> [{test, inf, optimal}].

exceptional() ->
  fun(_Expected, _Actual) ->
      false
  end.

%%------------------------------------------------------------------------------

test() ->
  ok.
