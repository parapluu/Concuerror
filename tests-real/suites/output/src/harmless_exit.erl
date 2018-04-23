-module(harmless_exit).

-export([test/0]).

test() ->
  process_flag(trap_exit, true),
  spawn_link(fun() -> exit(abnormal) end),
  receive
    _ -> ok
  end.
