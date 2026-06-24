-module(more_stacktrace).

-export([test/0, do_not_blame_me/0]).

test() ->
  erlang:display().

do_not_blame_me() ->
  self() ! ok,
  exit(abnormal).
