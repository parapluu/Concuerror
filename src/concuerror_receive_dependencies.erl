%% -*- erlang-indent-level: 2 -*-

%%% @doc Conditional dependencies for sends, based on receives
%%%
%%% Ideas:
%%%
%%% - This feature will be turned on and off via an entry in the
%%%   process dictionary, for convenience.
%%%
%%% - We will store receive patterns in an ETS table owned by the
%%%   scheduler.
%%%
%%% - Since race detection happens on full traces, we will allow any
%%%   send to wakeup a sleeping send and accurately detect
%%%   dependencies for it in the end.
%%%
%%% - We need to take care to erase 'receive' info when backtracking.

-module(concuerror_receive_dependencies).

%%==============================================================================

-export([initialise/1, store/2, reset/1, dependent_delivery/2]).

%%==============================================================================

-include("concuerror.hrl").

%%==============================================================================

-spec initialise(boolean()) -> ok.

initialise(UseReceivePatterns) ->
  put(use_receive_patterns, UseReceivePatterns),
  case UseReceivePatterns of
    true ->
      use_receive_patterns = ets:new(use_receive_patterns, [named_table]),
      ok;
    false ->
      ok
  end.

%%==============================================================================

-spec store(message_id(), receive_pattern_fun()) -> ok.

store(MessageId, PatternFun) ->
  case get(use_receive_patterns) of
    false -> ok;
    true ->
      ets:insert(use_receive_patterns, {MessageId, PatternFun}),
      ok
  end.

%%==============================================================================

-spec reset(message_id()) -> ok.

reset(MessageId) ->
  case get(use_receive_patterns) of
    false -> ok;
    true ->
      ets:delete(use_receive_patterns, MessageId),
      ok
  end.

%%==============================================================================

-spec dependent_delivery(message_id(), term()) -> boolean().

dependent_delivery(MessageId, Data) ->
  case get(use_receive_patterns) of
    false -> true;
    true ->
      case ets:lookup(use_receive_patterns, MessageId) of
        [] -> false;
        [{MessageId, Pats}] ->
          case Pats(Data) of
            true -> {true, MessageId};
            false -> false
          end
      end
  end.
