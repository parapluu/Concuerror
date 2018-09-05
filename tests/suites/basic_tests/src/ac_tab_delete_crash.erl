-module(ac_tab_delete_crash).

-compile(export_all).

scenarios() ->
  [ {test, inf, dpor, crash}
  ].

exceptional() ->
  fun(_Expected, Actual) ->
      Cmd = "grep \"Only insert and delete write operations are supported for public ETS tables owned by 'system' processes.\" ",
      [_,_,_|_] = os:cmd(Cmd ++ Actual),
      true
  end.

%%------------------------------------------------------------------------------

%% This test exercises code for restoring the state of public tables
%% not owned by any process under Concuerror.  This code might become
%% useful again if e.g. support for application:start is added back.

test() ->
  ets:delete_all_objects(ac_tab).
