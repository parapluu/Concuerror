%% -*- erlang-indent-level: 2 -*-

%% This module will never be instrumented. Function instrumented/3 should:
%%  - return the result of a call, if it is called from a non-Concuerror process
%%  - grab concuerror_info and continue to concuerror_callback

-module(concuerror_inspect).

%% Interface to instrumented code:
-export([instrumented/3, hijack/2]).

-include("concuerror.hrl").

%%------------------------------------------------------------------------------

-spec instrumented(Tag      :: instrumented_tag(),
                   Args     :: [term()],
                   Location :: term()) -> Return :: term().

instrumented(Tag, Args, Location) ->
  Ret =
    case erase(concuerror_info) of
      undefined ->
        receive
          {hijack, I} ->
            concuerror_callback:hijack_backend(I),
            retry
        after
          0 -> doit
        end;
      Info -> concuerror_callback:instrumented_top(Tag, Args, Location, Info)
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
    retry -> instrumented(Tag, Args, Location);
    skip_timeout -> 0;
    {didit, Res} -> Res;
    unhijack ->
      erase(concuerror_info),
      instrumented(Tag, Args, Location);
    {error, Reason} -> error(Reason)
  end.

-spec hijack(atom(), term()) -> ok.

hijack(Name, Info) ->
  Name ! {hijack, Info},
  ok.
