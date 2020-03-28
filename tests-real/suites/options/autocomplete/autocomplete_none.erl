-module(autocomplete_none).

-export([test/0]).

test() ->
  OptionSpec = concuerror_options:options(),
  OptsRaw = ["--" ++ atom_to_list(Long) || {Long, _, _, _, _, _} <- OptionSpec],
  Opts = lists:sort(OptsRaw),
  autocomplete_common:test("./autocomplete.sh concuerror ''", Opts).
