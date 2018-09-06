-module(system_non_instant_delivery).

-compile(export_all).

-concuerror_options_forced([{instant_delivery, false}]).

%%------------------------------------------------------------------------------

scenarios() ->
  [ test
  ].

%%------------------------------------------------------------------------------

%% This test checks that replies from io server can be non-instant.

test() ->
  Fun =
    fun() ->
        User = erlang:group_leader(),
        M = erlang:monitor(process, User),
        P = self(),
        Command = {put_chars, unicode, io_lib, format, ["Hello world!", []]},
        Request = {io_request, P, M, Command},
        User ! Request,
        receive
          {io_reply, M, ok} -> ok
        after
          0 ->
            receive
              {io_reply, M, ok} -> ok
            end
        end,
        demonitor(M, [flush]),
        spawn(fun() -> P ! ok end),
        receive
          ok -> ok
        after
          0 -> ok
        end
    end,
  spawn(Fun),
  exit(died_to_show_trace).
