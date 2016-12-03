-module(bad_attribute_3).

-export([test/0]).

-concuerror_options([symbolic_names, keep_going, keep_going]).

test() ->
  ok.
