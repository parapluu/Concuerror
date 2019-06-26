%%% See test_template.erl for more details.

-module(test_template_stripped).

-export([test/0]).

-export([scenarios/0]).
-export([exceptional/0]).

-concuerror_options_forced([]).

%%------------------------------------------------------------------------------

scenarios() ->
  %% [{test, inf, optimal}].
  [{T, inf, optimal} ||
    {T, 0} <-
      ?MODULE:module_info(exports)
      , T =/= exceptional
      , T =/= scenarios
      , T =/= module_info
  ].

exceptional() ->
  fun(_Expected, _Actual) ->
      false
  end.

%%------------------------------------------------------------------------------

test() ->
  ok.
