-module(diff_obs).

-export([test/0, scenarios/0]).

scenarios() ->
  [{test, inf, optimal}].

p() ->
  main ! {x, 0}.

q() ->
  main ! {y, 0}.

r() ->
  main ! {x, 1}.

s() ->
  main ! o.

test() ->
  register(main, self()),
  [spawn(F) || F <- [fun p/0, fun q/0, fun r/0, fun s/0]],
  receive
    o -> receive {x, _} -> ok end
  after
    0 -> receive {_, _} -> ok end
  end,
  receive after infinity -> ok end.
