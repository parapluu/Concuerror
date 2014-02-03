-record(concuerror_info, {
          'after-timeout'            :: infinite | integer(),
          escaped = nonexisting      :: term(),
          ets_tables                 :: ets_tables(),
          exit_reason = normal       :: term(),
          links = []                 :: ordset:ordset(pid()),
          logger                     :: pid(),
          messages_new = queue:new() :: queue(),
          messages_old = queue:new() :: queue(),
          monitors = []              :: ordset:ordset({reference(), pid()}),
          next_event = none          :: 'none' | event(),
          processes                  :: processes(),
          scheduler                  :: pid(),
          stack = []                 :: [term()],
          status = exited            :: 'exited'| 'exiting' | 'running' | 'waiting',
          trap_exit = false          :: boolean()
         }).

-type instrumented_tags() :: 'apply' | 'call' | 'receive'.
