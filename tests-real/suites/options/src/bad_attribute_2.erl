-module(bad_attribute_2).

-export([test/0]).

-concuerror_options_forced(version).

test() ->
  ok.
