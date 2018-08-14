-module(precise_demonitor).

-compile(export_all).

scenarios() ->
  [ demonitor_empty
  , demonitor_flush
  , demonitor_info
  , demonitor_flush_info
  ].

%% This test should have 3 schedulings, shown with *** comments.
demonitor_empty() ->
  {P1, Monitor} = spawn_monitor(fun() -> ok end),
  receive
    %% *** P1 exited, the monitor was delivered and is received here.
    {'DOWN', Monitor, process, P1, normal} ->
      erlang:display(got_monitor)
  after
    %% P1 may be live or not, but the monitor has not yet arrived,
    0 ->
      %% After the demonitor, the monitor can no longer be delivered.
      true = demonitor(Monitor, []),
      receive
        %% *** P1 exited and the monitor was delivered before the
        %% demonitor and is received here.
        {'DOWN', Monitor, process, P1, normal} ->
          erlang:display(monitor_already_delivered)
      after
        %% *** The monitor was not delivered before demonitor. P1 may
        %% be live or not, but no monitor will ever be delivered.
        0 ->
          erlang:display(monitor_ignored_upon_delivery)
      end,
      receive
        {'DOWN', Monitor, process, P1, normal} ->
          error(impossible)
      after
        0 ->
          ok
      end
  end.

%% This test should have 2 schedulings, shown with *** comments.
demonitor_flush() ->
  {P1, Monitor} = spawn_monitor(fun() -> ok end),
  receive
    %% *** P1 exited, the monitor was delivered and is received here.
    {'DOWN', Monitor, process, P1, normal} ->
      erlang:display(got_monitor)
  after
    %% P1 may be live or not, but the monitor has not yet arrived,
    0 ->
      %% After the demonitor, the monitor can no longer be delivered.
      %% *** Due to flush, even if it has been delivered, it is
      %% flushed.
      true = demonitor(Monitor, [flush]),
      erlang:display(monitor_removed_or_ignored_or_flushed),
      receive
        {'DOWN', Monitor, process, P1, normal} ->
          error(impossible)
      after
        0 ->
          ok
      end
  end.

%% This test should have 4 schedulings, shown with *** comments.
demonitor_info() ->
  {P1, Monitor} = spawn_monitor(fun() -> ok end),
  receive
    %% *** P1 exited, the monitor was delivered and is received here.
    {'DOWN', Monitor, process, P1, normal} ->
      erlang:display(got_monitor)
  after
    %% P1 may be live or not, but the monitor has not yet arrived,
    0 ->
      %% After the demonitor, the monitor can no longer be delivered.
      case demonitor(Monitor, [info]) of
        true ->
          erlang:display(monitor_removed_before_exit),
          %% *** The monitor had not been emitted when demonitor was
          %% executed. It will never be emitted.
          receive
            {'DOWN', Monitor, process, P1, normal} ->
              error(impossible)
          after
            0 ->
              ok
          end;
        false ->
          %% The monitor could not be removed, so it was in-flight or
          %% delivered. P1 is dead.
          false = is_process_alive(P1),
          receive
            %% *** It was delivered before the demonitor and is
            %% received here.
            {'DOWN', Monitor, process, P1, normal} ->
              erlang:display(monitor_already_delivered)
          after
            %% *** The monitor was not delivered before demonitor, so
            %% it will be ignored upon delivery.
            0 ->
              erlang:display(monitor_ignored_upon_delivery)
          end,
          receive
            {'DOWN', Monitor, process, P1, normal} ->
              error(impossible)
          after
            0 ->
              ok
          end
      end
  end.

%% This test should have 3 schedulings, shown with *** comments.
demonitor_flush_info() ->
  {P1, Monitor} = spawn_monitor(fun() -> ok end),
  receive
    %% *** P1 exited, the monitor was delivered and is received here.
    {'DOWN', Monitor, process, P1, normal} ->
      erlang:display(got_monitor)
  after
    %% P1 may be live or not, but the monitor has not yet arrived,
    0 ->
      %% After the demonitor, the monitor can no longer be delivered.
      case demonitor(Monitor, [flush, info]) of
        true ->
          %% *** The message was flushed.
          erlang:display(monitor_flushed);
        false ->
          %% *** The message had not been emitted or delivered. It
          %% will be removed or ignored upon delivery.
          erlang:display(monitor_removed_or_ignored)
      end,
      receive
        {'DOWN', Monitor, process, P1, normal} ->
          error(impossible)
      after
        0 ->
          ok
      end
  end.
