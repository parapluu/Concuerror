-module(transparent_instrumentation).

-export([test/0]).
-export([scenarios/0]).

scenarios() ->
  [{test, inf, dpor}].

test() ->

  concuerror_callback:module_info(),

  undefined = get(concuerror_info),

  put(concuerror_info, something),
  something = get(concuerror_info),

  erase(concuerror_info),

  false = process_flag(trap_exit, true),

  undefined = get(concuerror_info),

  put(concuerror_info, something),

  true = process_flag(trap_exit, false),

  something = get(concuerror_info),

  something = erase(concuerror_info),
  undefined = get(concuerror_info),

  false = process_flag(trap_exit, true).
