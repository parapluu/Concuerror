%% -define(DEBUG, true).

%%------------------------------------------------------------------------------
-ifdef(SENSITIVE_DEBUG).
-define(display(A), erlang:display({A, ?MODULE, ?LINE})).
-else.
-define(display(A), io:format(standard_error, "~p\n", [A])).
-define(display(A, B), io:format(standard_error, A, B)).
-endif.
%%------------------------------------------------------------------------------
-ifdef(DEBUG_FLAGS).
-ifndef(DEBUG).
-define(DEBUG, true).
-endif.
-endif.
%%------------------------------------------------------------------------------
-ifdef(DEBUG).
-define(debug(A), ?display(A)).
-define(debug(A, B), ?display(A, B)).
-define(if_debug(A), A).
-else.
-define(debug(_A), ok).
-define(debug(_A, _B), ok).
-define(if_debug(_A), ok).
-endif.
%%------------------------------------------------------------------------------
-ifdef(DEBUG_FLAGS).
-define(debug_flag(A, B),
        case (?DEBUG_FLAGS band A) =/= 0 of
            true -> ?display(B);
            false -> ok
        end).
-define(debug_flag(A, B, C),
        case (?DEBUG_FLAGS band A) =/= 0 of
            true ->?display(B, C);
            false -> ok
        end).
-else.
-define(debug_flag(_A, _B), ?debug(_B)).
-define(debug_flag(_A, _B, _C), ?debug(_B, _C)).
-endif.
%%------------------------------------------------------------------------------
-ifdef(CHECK_ASSERTIONS).
-define(assert(A, B), A = B).
-else.
-define(assert(_A, _B), ok).
-endif.
%%------------------------------------------------------------------------------

%% Logger verbosity
-define(lerror, 0).
-define(lwarn, 1).
-define(linfo, 2).
-define(ldebug, 3).
-define(ltrace, 4).

-define(MAX_VERBOSITY, ?ltrace).
-define(DEFAULT_VERBOSITY, ?linfo).

-define(log(Logger, Level, Format, Data),
        concuerror_logger:log(Logger, Level, Format, Data)).

-define(mf_log(Logger, Level, Format, Data),
        concuerror_logger:log(Logger, Level, "~p:~p " ++ Format,
                              [?MODULE, ?LINE|Data])).

-define(info(Logger, Format, Data),
        ?log(Logger, ?linfo, Format, Data)).

-define(debug(Logger, Format, Data),
        ?mf_log(Logger, ?ldebug, Format, Data)).

-define(trace(Logger, Format, Data),
        ?mf_log(Logger, ?ltrace, Format, Data)).

-define(trace_nl(Logger, Format, Data),
        ?log(Logger, ?ltrace, Format, Data)).

%% Scheduler's timeout
-define(MINIMUM_TIMEOUT, 500).
-define(TICKER_TIMEOUT, 500).
%%------------------------------------------------------------------------------

-type options() :: proplists:proplist().

-type label() :: reference().

-type mfargs() :: {atom(), atom(), [term()]}.
-type receive_pattern_fun() :: fun((term()) -> boolean()).

-type location() :: {non_neg_integer(), string()}.

-type index() :: non_neg_integer().

-record(message, {
          data       :: term(),
          message_id :: reference()
         }).

-type message() :: #message{}.

-record(builtin_event, {
          actor = self() :: pid(),
          mfa            :: mfargs(),
          result         :: term()
         }).

-type builtin_event() :: #builtin_event{}.

-record(message_event, {
          cause_label     :: label(),
          message         :: message(),
          patterns = none :: 'none' | receive_pattern_fun(),
          recipient       :: pid(),
          sender = self() :: pid(),
          trapping        :: boolean(),
          type = message  :: 'message' | 'exit_signal'
         }).

-type message_event() :: #message_event{}.

-record(receive_event, {
          %% clause_location :: location(),
          message            :: message() | 'after',
          patterns           :: receive_pattern_fun(),
          recipient = self() :: pid(),
          timeout            :: timeout(),
          trapping           :: boolean
         }).

-type receive_event() :: #receive_event{}.

-record(exit_event, {
          actor = self() :: pid(),
          reason         :: term(),
          stacktrace     :: [term()]
         }).

-type exit_event() :: #exit_event{}.

-type event_info() :: builtin_event() |
                      exit_event()    |
                      message_event() |
                      receive_event().

-record(event, {
          actor        :: pid() | {pid(), pid()}, %% Pair: message from/to
          event_info   :: event_info(),
          label        :: label(),
          location     :: location(),
          special = [] :: [term()] %% XXX: Specify
         }).

-type event() :: #event{}.

-type concuerror_warning() :: 'none' | {[concuerror_warning_info()], [event()]}.

-type concuerror_warning_info() :: {'crash', pid(), index()} |
                                   {'deadlock', [pid()]} |
                                   {'sleep_set_block', [pid()]}.

-type message_info() :: ets:tid().
-define(new_message_info(Id), {Id, undefined, undefined, undefined}).
-define(message_pattern, 2).
-define(message_sent, 3).
-define(message_delivered, 4).

-type ets_tables() :: ets:tid().
-define(new_ets_table(Tid, Protection), {Tid, unknown, Protection, unknown}).
-define(ets_owner, 2).
-define(ets_protection, 3).
-define(ets_heir, 4).

%%------------------------------------------------------------------------------

-define(RACE_FREE_BIFS,
        [{erlang, N, A} ||
            {N, A} <-
                [
                 {'bor', 2},
                 {binary_to_list, 1},
                 {binary_to_term, 1},
                 {bump_reductions, 1}, %% XXX: This may change
                 {dt_spread_tag, 1},
                 {error, 1},
                 {exit, 1},
                 {float_to_list, 1},
                 {iolist_size, 1},
                 {iolist_to_binary, 1},
                 {list_to_atom, 1},
                 {list_to_integer, 1},
                 {list_to_tuple, 1},
                 {make_fun, 3},
                 {make_tuple, 2},
                 {md5, 1},
                 {phash, 2},
                 {setelement, 3},
                 {term_to_binary, 1},
                 {throw, 1},
                 {tuple_to_list, 1}
                ]]
        ++ [{lists, N, A} ||
               {N, A} <-
                   [
                    {keyfind, 3},
                    {keysearch, 3},
                    {member, 2},
                    {reverse, 2}
                   ]]
        ++ [{file, N, A} ||
               {N, A} <-
                   [
                    {native_name_encoding, 0}
                   ]]
        ++ [{prim_file, N, A} ||
               {N, A} <-
                   [
                    {internal_name2native, 1}
                   ]]
       ).
