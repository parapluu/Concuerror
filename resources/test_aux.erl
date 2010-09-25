-module(test_aux).
-export([bar/1]).

-spec bar(pid()) -> 'ok'.

bar(Pid) ->
  Pid ! 42,
  ok.
