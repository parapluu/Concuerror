-module(bad_dictionary).

-compile(export_all).

scenarios() ->
  [ bad_put
  , bad_get
  , bad_erase
  ].

bad_put() ->
  BadFun =
    fun() ->
        erlang:put(key, value),
        erlang:put(key, value, extra_arg_bad)
    end,
  spawn_monitor(BadFun).

bad_get() ->
  BadFun =
    fun() ->
        erlang:get(key),
        erlang:get(key, extra_arg_bad)
    end,
  spawn_monitor(BadFun).

bad_erase() ->
  BadFun =
    fun() ->
        erlang:erase(key),
        erlang:erase(key, value)
    end,
  spawn_monitor(BadFun).
