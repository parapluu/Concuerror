%%%----------------------------------------------------------------------
%%% File        : ced.hrl
%%% Author      : Alkis Gotovos <el3ctrologos@hotmail.com>
%%% Description : EUnit-style assertion macros for CED.
%%% Created     : 29 May 2010
%%%----------------------------------------------------------------------

-ifdef(NOASSERT).
%% The plain assert macro should be defined to do nothing if this file
%% is included when debugging/testing is turned off.
-ifndef(assert).
-define(assert(BoolExpr), ok).
-endif.
-else.
%% The assert macro is written the way it is so as not to cause warnings
%% for clauses that cannot match, even if the expression is a constant.
-undef(assert).
-define(assert(BoolExpr),
	((fun () ->
                  case (BoolExpr) of
                      true -> ok;
                      __V -> erlang:error({assertion_violation,
                                           [{module, ?MODULE},
                                            {line, ?LINE},
                                            {expression, (??BoolExpr)},
                                            {expected, true},
                                            {value, case __V of
                                                        false -> __V;
                                                        _ -> {not_a_boolean,__V}
                                                    end}]})
                  end
	  end)())).

-define(assertEqual(Expect, Expr),
        ((fun (__X) ->
                  case (Expr) of
                      __X -> ok;
                      __V -> erlang:error({assertion_violation,
                                           [{module, ?MODULE},
                                            {line, ?LINE},
                                            {expression, (??Expr)},
                                            {expected, __X},
                                            {value, __V}]})
                  end
          end)(Expect))).
-endif.
