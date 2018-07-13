-module(concuerror_options_tests).

-include_lib("eunit/include/eunit.hrl").

-define(M, concuerror_options).

%%==============================================================================

lint_option_specs_test_() ->
  LintSpec =
    fun(OptionSpec) ->
        fun() ->
            {Keywords, _} = ?M:get_keywords_and_related(OptionSpec),
            OptionName = element(1, OptionSpec),
            ?assertEqual(
               {OptionName, Keywords},
               {OptionName, lists:usort(Keywords)}
              )
        end
    end,
  lists:map(LintSpec, ?M:options()).
