-record(concuerror_info, {
          'after-timeout'            :: infinite | integer(),
          escaped_pdict = []         :: term(),
          ets_tables                 :: ets_tables(),
          exit_reason = normal       :: term(),
          links                      :: links(),
          logger                     :: pid(),
          messages_new = queue:new() :: queue(),
          messages_old = queue:new() :: queue(),
          monitors                   :: monitors(),
          next_event = none          :: 'none' | event(),
          processes                  :: processes(),
          scheduler                  :: pid(),
          stack = []                 :: [term()],
          stacktop = 'none'          :: 'none' | tuple(),
          status = exited            :: 'exited'| 'exiting' | 'running' | 'waiting',
          trap_exit = false          :: boolean()
         }).

-type instrumented_tags() :: 'apply' | 'call' | 'receive'.
