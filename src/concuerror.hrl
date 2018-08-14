-include("concuerror_otp_version.hrl").

%%------------------------------------------------------------------------------
-ifdef(BEFORE_OTP_19).
-define(join(Strings, Sep), string:join(Strings, Sep)).
-else.
-define(join(Strings, Sep), lists:join(Sep, Strings)).
-endif.
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
-type assume_racing_opt() :: {boolean(), logger() | 'ignore'}.
%%------------------------------------------------------------------------------
-define(opt(A,O), proplists:get_value(A,O)).
-define(opt(A,O,D), proplists:get_value(A,O,D)).
%%------------------------------------------------------------------------------
%% Logger levels
-define(lquiet,    0).
-define(lerror,    1).
-define(lwarning,  2).
-define(ltip,      3).
-define(linfo,     4).
-define(ltiming,   5).
-define(ldebug,    6).
-define(ltrace,    7).
-define(MAX_LOG_LEVEL, ?ltrace).
%%------------------------------------------------------------------------------
-define(nonunique, none).

-define(log(Logger, Level, Tag, Format, Data),
        concuerror_logger:log(Logger, Level, Tag, Format, Data)).

-define(log(Logger, Level, Format, Data),
        ?log(Logger, Level, ?nonunique, Format, Data)).

-define(error(Logger, Format, Data),
        ?log(Logger, ?lerror, Format, Data)).

-ifdef(DEV).
-define(dev_log(Logger, Level, Format, Data),
        ?log(Logger, Level, "(~-25w@~4w) " ++ Format, [?MODULE, ?LINE| Data])).
-define(debug(Logger, Format, Data), ?dev_log(Logger, ?ldebug, Format, Data)).
-define(trace(Logger, Format, Data), ?dev_log(Logger, ?ltrace, Format, Data)).
-define(has_dev, true).
-else.
-define(debug(Logger, Format, Data),ok).
-define(trace(Logger, Format, Data),ok).
-define(has_dev, false).
-endif.

-define(unique(Logger, Level, Param, Format, Data),
        ?log(Logger, Level, {?MODULE, ?LINE, Param}, Format, Data)).

-define(unique(Logger, Level, Format, Data),
        ?unique(Logger, Level, none, Format, Data)).

-define(time(Logger, Tag),
        concuerror_logger:time(Logger, Tag)).

-define(
   autoload_and_log(Module, Logger),
   case concuerror_loader:load(Module) of
     already_done -> ok;
     {ok, Warn} ->
       ?log(Logger, ?linfo,
            "Automatically instrumented module ~p~n", [Module]),
       _ = [?log(Logger, ?lwarning, W, []) || W <- Warn],
       ok;
     fail ->
       ?log(Logger, ?lwarning,
            "Could not load module '~p'. Check '-h input'.~n", [Module]),
       ok
   end).

-define(pretty_s(I,E), concuerror_io_lib:pretty_s({I,E#event{location = []}},5)).
-define(pretty_s(E), ?pretty_s(0,E)).
%%------------------------------------------------------------------------------
-define(crash(Reason), exit({?MODULE, Reason})).
-define(notify_us_msg,
        "~nPlease notify the developers, as this is a bug of Concuerror.").
%%------------------------------------------------------------------------------
-type timers()       :: ets:tid().

-define(notify_none, 1).
%%------------------------------------------------------------------------------
-type processes() :: ets:tid().
-type symbolic_name() :: string().

-define(process_name_none, 0).
-define(new_process(Pid, Symbolic),
        {Pid, exited, ?process_name_none, ?process_name_none, undefined, Symbolic, 0, regular}).
-define(new_system_process(Pid, Name, Type),
        {Pid, running, Name, Name, undefined, "P." ++ atom_to_list(Name), 0, Type}).
-define(process_pat_pid(Pid),                {Pid,      _,    _, _, _, _, _,    _}).
-define(process_pat_pid_name(Pid, Name),     {Pid,      _, Name, _, _, _, _,    _}).
-define(process_pat_pid_status(Pid, Status), {Pid, Status,    _, _, _, _, _,    _}).
-define(process_pat_pid_kind(Pid, Kind),     {Pid,      _,    _, _, _, _, _, Kind}).
-define(process_status, 2).
-define(process_name, 3).
-define(process_last_name, 4).
-define(process_leader, 5).
-define(process_symbolic, 6).
-define(process_children, 7).
-define(process_kind, 8).
-define(process_match_name_to_pid(Name),
        {'$1',   '_', Name, '_', '_', '_', '_', '_'}).
-define(process_match_symbol_to_pid(Symbol),
        {'$1',   '_', '_', '_', '_', Symbol, '_', '_'}).

-define(process_match_active(),
        { {'$1', '$2', '_', '_', '_', '_', '_', '_'}
        , [ {'=/=', '$2', exited}
          , {'=/=', '$2', exiting}
          ]
        , ['$1']
        }).
%%------------------------------------------------------------------------------
-type label() :: reference().

-type mfargs() :: {atom(), atom(), [term()]}.

-type location() :: 'exit' | [non_neg_integer() | {file, string()}].

-type index() :: non_neg_integer().

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

-type message_id() :: {pid(), pos_integer()} | 'hidden'.

-record(message, {
          data    :: term(),
          id      :: message_id()
         }).

-type message() :: #message{}.

-type receive_pattern_fun() :: fun((term()) -> boolean()).
-type receive_info() ::
        'undefined' |
        'not_received' |
        {pos_integer() | 'system', receive_pattern_fun()}.

-record(message_event, {
          cause_label      :: label(),
          instant = true   :: boolean(),
          killing = false  :: boolean(),
          message          :: message(),
          receive_info     :: receive_info(),
          recipient        :: pid(),
          sender = self()  :: pid(),
          trapping = false :: boolean(),
          type = message   :: 'message' | 'exit_signal'
         }).

-type message_event() :: #message_event{}.

-record(receive_event, {
          %% clause_location :: location(),
          message            :: message() | 'after',
          receive_info       :: receive_info(),
          recipient = self() :: pid(),
          timeout = infinity :: timeout(),
          trapping = false   :: boolean()
         }).

-type receive_event() :: #receive_event{}.

-record(exit_event, {
          actor = self()            :: pid() | reference(),
          last_status = running     :: running | waiting,
          exit_by_signal = false    :: boolean(),
          links = []                :: [pid()],
          monitors = []             :: [{reference(), pid()}],
          name = ?process_name_none :: ?process_name_none | atom(),
          reason = normal           :: term(),
          stacktrace = []           :: [term()],
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
          actor         :: 'undefined' | actor(),
          event_info    :: 'undefined' | event_info(),
          label         :: 'undefined' | label(),
          location = [] :: location(),
          special = []  :: [term()] %% XXX: Specify
         }).

-type event() :: #event{}.
