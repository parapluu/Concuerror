-module(from_shell).

-export([ with_unknown/0
        , with_bad_entry/0
        , with_multiple_entries/0
        ]).

%%==============================================================================

with_unknown() ->
  fail = concuerror:run([unknown_option]).

with_bad_entry() ->
  fail = concuerror:run([{entry_point, ugly}]).

with_multiple_entries() ->
  fail = concuerror:run([{entry_point, one}, {entry_point, another}]).
