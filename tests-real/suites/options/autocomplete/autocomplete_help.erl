-module(autocomplete_help).

-export([test/0]).

test() ->
  OptionSpec = concuerror_options:options(),
  OptsRaw = [Keywords || {_, Keywords, _, _, _, _} <- OptionSpec],
  Opts = lists:usort(lists:append([[all, progress, attributes] | OptsRaw])),
  Keywords = [atom_to_list(K) || K <- Opts],
  autocomplete_common:test("./autocomplete.sh --help ''", Keywords, [no_sort_check]).
