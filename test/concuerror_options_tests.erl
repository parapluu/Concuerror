-module(concuerror_options_tests).

-include_lib("eunit/include/eunit.hrl").

-define(M, concuerror_options).

%%==============================================================================

lint_option_specs_test() ->
  LintSpec =
    fun(OptionSpec) ->
        ?debugFmt("~p", [OptionSpec]),
        {Keywords, _} = ?M:get_keywords_and_related(OptionSpec),
        ?debugFmt("ok~n", [])
    end,
  lists:foreach(LintSpec, ?M:options()).
