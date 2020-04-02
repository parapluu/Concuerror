-module(autocomplete_short).

-export([test/0]).

test() ->
  OptionSpec = concuerror_options:options(),
  OptsRaw = ["-" ++ [Short] || {_, _, Short, _, _, _} <- OptionSpec, Short =/= undefined],
  Opts = lists:sort(OptsRaw),
  autocomplete_common:test("./autocomplete.sh concuerror -", Opts).
