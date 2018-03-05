-module(bad_attribute_4).

-export([test/0]).

-concuerror_options_forced([keep_going, keep_going]).

test() ->
  ok.
