-ifdef(NOASSERT).
%% The plain assert macro should be defined to do nothing if this file
%% is included when debugging/testing is turned off.
-ifndef(assert).
-define(assert(BoolExpr),ok).
-endif.
-else.
%% The assert macro is written the way it is so as not to cause warnings
%% for clauses that cannot match, even if the expression is a constant.
-undef(assert).
-define(assert(BoolExpr),
	((fun () ->
	    try (BoolExpr) of
		true -> ok;
		__V -> .erlang:error({assertion_failed,
				      [{module, ?MODULE},
				       {line, ?LINE},
				       {expression, (??BoolExpr)},
				       {expected, true},
				       {value, case __V of false -> __V;
						   _ -> {not_a_boolean,__V}
					       end}]})
	    catch
		Class:_ -> .erlang:error({assertion_failed,
				      [{module, ?MODULE},
				       {line, ?LINE},
				       {expression, (??BoolExpr)},
				       {expected, true},
				       {value, Class}]})
		end
	  end)())).
-endif.
