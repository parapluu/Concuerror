-module(autocomplete_common).

-export([test/2, test/3]).

-include_lib("stdlib/include/assert.hrl").

test(Command, Data) ->
  test(Command, Data, []).

test(Command, Data, Options) ->
  try
    main(Command, Data, Options)
  catch
    C:R ->
      io:format(standard_error, "Class: ~p~nReason: ~p~n", [C, R]),
      halt(1)
  end.

main(Command, DataRaw, Options) ->
  AutoOutput = os:cmd(Command),
  AutoTokens = string:tokens(AutoOutput, " \n"),
  Auto = usort(AutoTokens, Options),

  Data = usort(DataRaw, []),

  io:format(standard_error, "Auto -- Data : ~p~n", [Auto -- Data]),
  io:format(standard_error, "Data -- Auto : ~p~n", [Data -- Auto]),

  ?assertEqual(Data, Auto).

usort(List, Options) ->
  USort = lists:usort(List),
  Sort = lists:usort(List),
  ?assertEqual(USort, Sort),
  case lists:member(no_sort_check, Options) of
    true -> ok;
    false -> ?assertEqual(USort, List)
  end,
  USort.
