-module(process_info).

-compile(export_all).

scenarios() ->
  [{T, inf, dpor} ||
    T <- [ test1
         , test2
         , test3
         , test_messages
         , test_message_queue_len
         , test_mql_flush
         ]].

test1() ->
    Fun = fun() -> register(foo, self()) end,
    P = spawn(Fun),
    exit(process_info(P, registered_name)).

test2() ->
    Fun = fun() -> register(foo, self()) end,
    P = spawn(Fun),
    exit(process_info(P, [registered_name, group_leader])).

test3() ->
  {P, _} = spawn_monitor(fun() -> ok end),
  receive
    _ -> ok
  end,
  undefined = process_info(P, [registered_name, group_leader]).

test_messages() ->
  test_with_messages([messages]).

test_message_queue_len() ->
  test_with_messages([message_queue_len]).

test_with_messages(Info) ->
  Fun =
    fun() ->
        receive {ok, _} -> ok end,
        receive after infinity -> ok end
    end,
  P = spawn(Fun),
  Fun2 =
    fun() ->
        P ! {bar, self()},
        P ! {ok, self()}
    end,
  Fun3 =
    fun() ->
        P ! {ok, self()}
    end,
  spawn(Fun2),
  spawn(Fun3),
  Fun4 =
    fun() ->
        process_info(P, Info)
    end,
  spawn(Fun4).

test_mql_flush() ->
  Fun =
    fun() ->
        {P, M} = spawn_monitor(fun() -> ok end),
        demonitor(M, [flush]),
        receive after infinity -> ok end
    end,
  P = spawn(Fun),
  Fun2 =
    fun() ->
        process_info(P, message_queue_len)
    end,
  spawn(Fun2).
