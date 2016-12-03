-module(bad_attribute_1).

-export([test/0]).

-concuerror_options(unknown_unknown).

test() ->
  ok.
