%%% @private
%%% @doc
%%% The instrumenter replaces interesting operations with calls
%%% to inspect/3
-module(concuerror_inspect).

%% Interface to instrumented code:
-export([start_inspection/1, stop_inspection/0, inspect/3, explain_error/1]).

-export_type([instrumented_tag/0]).

%%------------------------------------------------------------------------------

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-type instrumented_tag() :: 'apply' | 'call' | 'receive'.

%%------------------------------------------------------------------------------

-spec start_inspection(term()) -> 'ok'.

start_inspection(Info) ->
  NewDict = erase(),
  put(concuerror_info, {under_concuerror, Info, NewDict}),
  ok.

-spec stop_inspection() -> 'false' | {'true', term()}.

stop_inspection() ->
  case get(concuerror_info) of
    {under_concuerror, Info, Dict} ->
      erase(concuerror_info),
      _ = [put(K, V) || {K, V} <- Dict],
      {true, Info};
    _ -> false
  end.

%%  Function inspect/3 should:
%%  - return the result of a call, if it is called from a non-Concuerror process
%%  - grab concuerror_info and continue to concuerror_callback, otherwise
-spec inspect(Tag      :: instrumented_tag(),
              Args     :: [term()],
              Location :: term()) -> Return :: term().

inspect(Tag, Args, Location) ->
  Ret =
    case stop_inspection() of
      false -> doit;
      {true, Info} ->
        {R, NewInfo} =
          concuerror_callback:instrumented(Tag, Args, Location, Info),
        start_inspection(NewInfo),
        R
    end,
  case Ret of
    doit ->
      case {Tag, Args} of
        {apply, [Fun, ApplyArgs]} ->
          erlang:apply(Fun, ApplyArgs);
        {call, [Module, Name, CallArgs]} ->
          erlang:apply(Module, Name, CallArgs);
        {'receive', [_, Timeout]} ->
          Timeout
      end;
    {didit, Res} -> Res;
    {error, Reason} ->
      StackTop =
        case {Tag, Args} of
          {apply, Args} ->
            {erlang, apply, Args, Location};
          {call, [Module, Name, CallArgs]} ->
            {Module, Name, CallArgs, Location}
        end,
      erlang:raise(error, Reason, [StackTop|get_stacktrace()]);
    {skip_timeout, CreateMessage} ->
      assert_no_messages(),
      case CreateMessage of
        false -> ok;
        {true, D} -> self() ! D
      end,
      0
  end.

assert_no_messages() ->
  receive
    Msg -> exit(self(), {?MODULE, {pending_message, self(), Msg}})
  after
    0 -> ok
  end.

get_stacktrace() ->
  {_, Trace} = erlang:process_info(self(), current_stacktrace),
  [T || T <- Trace, not_concuerror_module(element(1, T))].

not_concuerror_module(Atom) ->
  case atom_to_list(Atom) of
    "concuerror" ++ _ -> false;
    _ -> true
  end.

-spec explain_error(term()) -> string().

explain_error({pending_message, Proc, Msg}) ->
  io_lib:format(
    "A process (~w) had a message (~w) in it's mailbox when it"
    " shouldn't." ++ ?notify_us_msg, [Proc, Msg]).
