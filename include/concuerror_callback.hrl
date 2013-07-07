-record(concuerror_info, {
          'after-timeout'            :: infinite | integer(),
          escaped = nonexisting      :: term(),
          ets_tables                 :: ets:tid(),
          links = []                 :: ordset:ordset(pid()),
          logger                     :: pid(),
          messages_new = queue:new() :: queue(),
          messages_old = queue:new() :: queue(),
          monitors = []              :: ordset:ordset({reference(), pid()}),
          next_event = none          :: 'none' | event(),
          scheduler                  :: pid(),
          stack = []                 :: [term()],
          status = dead              :: 'running' | 'exiting' | 'dead',
          trap_exit = false          :: boolean()
         }).

-type instrumented_tags() :: 'apply' | 'call' | 'receive'.
