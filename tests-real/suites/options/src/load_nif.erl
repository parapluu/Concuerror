-module(load_nif).
-export([test/0]).

-on_load(init/0).

init() ->
  catch erlang:load_nif("", no),
  ok.

test() ->
  ok.
