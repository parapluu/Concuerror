-module(ac_tab_insert).

-compile(export_all).

scenarios() ->
  [ test
  ].

%% This test exercises code for restoring the state of public tables
%% not owned by any process under Concuerror.  This code might become
%% useful again if e.g. support for application:start is added back.

test() ->
  [] = ets:lookup(ac_tab, fake),
  true = ets:insert(ac_tab, {fake, value}),
  [{fake, value}] = ets:lookup(ac_tab, fake),
  true = ets:delete(ac_tab, fake),
  [] = ets:lookup(ac_tab, fake),
  true = ets:insert(ac_tab, {fake, value}),
  [{fake, value}] = ets:lookup(ac_tab, fake),
  P = self(),
  spawn(fun() -> P ! ok end),
  receive
    ok -> ok
  after
    0 -> ok
  end.
