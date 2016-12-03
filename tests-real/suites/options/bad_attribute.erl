-module(bad_attribute).

-export([test/0]).

-concuerror_options(unknown_unknown).

test() ->
  ok.
