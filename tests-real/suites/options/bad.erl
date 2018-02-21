-module(bad).

-export([test/1). %% This has a typo and won't compile.

test() ->
  ok.
