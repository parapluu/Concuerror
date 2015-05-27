-include("src/concuerror_version.hrl").

%%------------------------------------------------------------------------------
-ifdef(SENSITIVE_DEBUG).
-define(display(A), erlang:display({A, ?MODULE, ?LINE})).
-else.
-define(display(A, B),
        io:format(standard_error,
                  "# ~p ~p l~p: "++A++"~n",
                  [self(), ?MODULE, ?LINE|B])).
-define(display(A), ?display("~w",[A])).
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
-type scheduler() :: pid().
-type logger()    :: pid().
-type options()   :: proplists:proplist().
-type scheduling() :: 'oldest' | 'newest' | 'round_robin'.
-type bound()     :: 'infinity' | non_neg_integer().
-type scheduling_bound_type() :: 'preemption' | 'delay' | 'none'.
-define(opt(A,O),proplists:get_value(A,O)).
%%------------------------------------------------------------------------------
%% Logger verbosity
-define(lquiet,    0).
-define(lerror,    1).
-define(lwarning,  2).
-define(ltip,      3).
-define(linfo,     4).
-define(ltiming,   5).
-define(ldebug,    6).
-define(ltrace,    7).
-define(MAX_VERBOSITY, ?ltrace).
-type log_level() :: ?lquiet..?MAX_VERBOSITY.
%%------------------------------------------------------------------------------
-define(nonunique, none).

-define(log(Logger, Level, Tag, Format, Data),
        concuerror_logger:log(Logger, Level, Tag, Format, Data)).

-define(log(Logger, Level, Format, Data),
        ?log(Logger, Level, ?nonunique, Format, Data)).

-define(error(Logger, Format, Data),
        ?log(Logger, ?lerror, Format, Data)).

-ifdef(DEV).
-define(debug(Logger, Format, Data),
        ?log(Logger, ?ldebug, Format, Data)).
-define(trace(Logger, Format, Data),
        ?log(Logger, ?ltrace, Format, Data)).
-define(has_dev, true).
-else.
-define(debug(Logger, Format, Data),ok).
-define(trace(Logger, Format, Data),ok).
-define(has_dev, false).
-endif.

-define(unique(Logger, Type, Format, Data),
        ?log(Logger, Type, {?MODULE, ?LINE}, Format, Data)).

-define(time(Logger, Tag),
        concuerror_logger:time(Logger, Tag)).

-define(pretty_s(I,E), concuerror_printer:pretty_s({I,E#event{location = []}},5)).
-define(pretty_s(E), ?pretty_s(0,E)).
%%------------------------------------------------------------------------------
-define(crash(Reason), exit({?MODULE, Reason})).
-define(crash(Reason, Scheduler), exit(Scheduler, {?MODULE, Reason})).
-define(notify_us_msg,
        "~nPlease notify the developers, as this is a bug of Concuerror.").
%%------------------------------------------------------------------------------
-type message_info() :: ets:tid().
-type timers()       :: ets:tid().

-define(new_message_info(Id), {Id, undefined, undefined}).
-define(message_sent, 2).
-define(message_delivered, 3).

-define(notify_none, 1).
%%------------------------------------------------------------------------------
-type ets_tables() :: ets:tid().

-define(ets_name_none, 0).
-define(new_ets_table(Tid, Protection),
        {Tid, unknown, unknown, Protection, unknown, true}).
-define(new_system_ets_table(Tid, Protect),
        {Tid, Tid, self(), Protect, unknown, true}).
-define(ets_name, 2).
-define(ets_owner, 3).
-define(ets_protection, 4).
-define(ets_heir, 5).
-define(ets_alive, 6).
-define(ets_match_owner_to_name_heir(Owner), {'_', '$1', Owner, '_', '$2', true}).
-define(ets_match_name(Name), {'$1', Name, '$2', '$3', '_', true}).
-define(ets_match_mine(), {'_', '_', self(), '_', '_', '_'}).
%%------------------------------------------------------------------------------
-type processes() :: ets:tid().
-type symbolic_name() :: string().

-define(process_name_none, 0).
-define(new_process(Pid, Symbolic),
        {Pid, running, ?process_name_none, undefined, Symbolic, 0, regular}).
-define(new_system_process(Pid, Name, Type),
        {Pid, running, Name, undefined, atom_to_list(Name), 0, Type}).
-define(process_pat_pid(Pid),                {Pid,      _,    _, _, _, _,    _}).
-define(process_pat_pid_name(Pid, Name),     {Pid,      _, Name, _, _, _,    _}).
-define(process_pat_pid_status(Pid, Status), {Pid, Status,    _, _, _, _,    _}).
-define(process_pat_pid_kind(Pid, Kind),     {Pid,      _,    _, _, _, _, Kind}).
-define(process_status, 2).
-define(process_name, 3).
-define(process_leader, 4).
-define(process_symbolic, 5).
-define(process_children, 6).
-define(process_kind, 7).
-define(process_match_name_to_pid(Name),
        {'$1',   '_', Name, '_', '_', '_', '_'}).
-define(process_match_symbol_to_pid(Symbol),
        {'$1',   '_', '_', '_', Symbol, '_', '_'}).

-define(active_processes(P),
        lists:sort(
          ets:select(
            P,
            [{{'$1', '$2', '_', '_', '_', '_', '_'},
              [{'=/=', '$2', exited}],
              ['$1']}]))).
%%------------------------------------------------------------------------------
-type links() :: ets:tid().

-define(links(Pid1, Pid2), [{Pid1, Pid2, active}, {Pid2, Pid1, active}]).
-define(links_match_mine(), {self(), '_', '_'}).
%%------------------------------------------------------------------------------
-type monitors() :: ets:tid().

-define(monitor(Ref, Target, As, Status),{Target, {Ref, self(), As}, Status}).
-define(monitors_match_mine(), {self(), '_', '_'}).
-define(monitor_match_to_target_source_as(Ref), {'$1', {Ref, '$2', '$3'}, active}).
%%------------------------------------------------------------------------------
-type modules() :: ets:tid().
%%------------------------------------------------------------------------------
-type label() :: reference().

-type mfargs() :: {atom(), atom(), [term()]}.
-type receive_pattern_fun() :: fun((term()) -> boolean()).

-type location() :: 'exit' | [non_neg_integer() | {file, string()}].

-type index() :: non_neg_integer().

-record(message, {
          data            :: term(),
          id = make_ref() :: reference(),
          xxx = 0         :: 0 %% UGLY! Added to differ from the {message,_,_} tuple
         }).

-type message() :: #message{}.

-record(builtin_event, {
          actor = self()   :: pid(),
          extra            :: term(),
          exiting = false  :: boolean(),
          mfargs           :: mfargs(),
          result           :: term(),
          status = ok      :: 'ok' | {'crashed', term()} | 'unknown',
          trapping = false :: boolean()
         }).

-type builtin_event() :: #builtin_event{}.

-record(message_event, {
          cause_label      :: label(),
          instant = true   :: boolean(),
          message          :: message(),
          recipient        :: pid(),
          sender = self()  :: pid(),
          trapping = false :: boolean(),
          type = message   :: 'message' | 'exit_signal'
         }).

-type message_event() :: #message_event{}.

-record(receive_event, {
          %% clause_location :: location(),
          message            :: message() | 'after',
          patterns           :: receive_pattern_fun(),
          recipient = self() :: pid(),
          timeout = infinity :: timeout(),
          trapping = false   :: boolean()
         }).

-type receive_event() :: #receive_event{}.

-record(exit_event, {
          actor = self()            :: pid() | reference(),
          links = []                :: [pid()],
          monitors = []             :: [{reference(), pid()}],
          name = ?process_name_none :: ?process_name_none | atom(),
          reason = normal           :: term(),
          stacktrace = []           :: [term()],
          status = running          :: running | waiting,
          trapping = false          :: boolean()
         }).

-type exit_event() :: #exit_event{}.

-type event_info() ::
        builtin_event() |
        exit_event()    |
        message_event() |
        receive_event().

-type channel() :: {pid(), pid()}.
-type actor() :: pid() | channel().

-define(is_channel(A), is_tuple(A)).

-record(event, {
          actor        :: actor(),
          event_info   :: event_info(),
          label        :: label(),
          location     :: location(),
          special = [] :: [term()] %% XXX: Specify
         }).

-type event() :: #event{}.

-type instrumented_tag() :: 'apply' | 'call' | 'receive'.

-type concuerror_warnings() ::
        'none' | {[concuerror_warning_info()], [event()]}.

-type concuerror_warning_info() ::
        'fatal' |
        {'crash', {index(), pid(), term(), [term()]}} |
        {'deadlock', [pid()]} |
        {'depth_bound', pos_integer()} |
        'sleep_set_block'.

%%------------------------------------------------------------------------------

-define(RACE_FREE_BIFS,
        [{erlang, N, A} ||
            {N, A} <-
                [
                 {atom_to_list,1},
                 {'bor', 2},
                 {binary_to_list, 1},
                 {binary_to_term, 1},
                 {bump_reductions, 1}, %% XXX: This may change
                 {dt_append_vm_tag_data, 1},
                 {dt_spread_tag, 1},
                 {dt_restore_tag,1},
                 {error, 1},
                 {error, 2},
                 {exit, 1},
                 {float_to_list, 1},
                 {function_exported, 3},
                 {integer_to_list,1},
                 {iolist_size, 1},
                 {iolist_to_binary, 1},
                 {list_to_atom, 1},
                 {list_to_binary, 1},
                 {list_to_integer, 1},
                 {list_to_tuple, 1},
                 {make_fun, 3},
                 {make_tuple, 2},
                 {md5, 1},
                 {phash, 2},
                 {phash2, 1},
                 {raise, 3},
                 {ref_to_list,1},
                 {setelement, 3},
                 {term_to_binary, 1},
                 {throw, 1},
                 {tuple_to_list, 1}
                ]]
        ++ [{error_logger, N, A} ||
               {N, A} <-
                   [
                    {warning_map, 0}
                   ]]
        ++ [{file, N, A} ||
               {N, A} <-
                   [
                    {native_name_encoding, 0}
                   ]]
        ++ [{lists, N, A} ||
               {N, A} <-
                   [
                    {keyfind, 3},
                    {keymember, 3},
                    {keysearch, 3},
                    {member, 2},
                    {reverse, 2}
                   ]]
        ++ [{net_kernel, N, A} ||
               {N, A} <-
                   [
                    {dflag_unicode_io, 1}
                   ]]
        ++ [{prim_file, N, A} ||
               {N, A} <-
                   [
                    {internal_name2native, 1}
                   ]]
       ).
