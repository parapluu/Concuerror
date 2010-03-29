-module(examples).
-compile(export_all).

% ----------------------------------------------------------------
% from Hans' thesis

procA() ->
  PidB = spawn(fun procB/0),
  PidB ! a,
  process_flag(trap_exit, true),
  link(PidB),
  receive
    {'EXIT',_,Why} -> Why
  end.

procB() ->
  receive
    a -> exit(kill)
  end.

% ----------------------------------------------------------------
% example 0

example0() ->
  spawn(fun () ->
    self() ! apa,
    receive apa -> io:format("it worked~n") end
  end),
  ok.

% ----------------------------------------------------------------
% example 1

example1() ->
  Pid1 = self(),
  spawn(fun () ->
    Pid1 ! apa
  end),
  receive
    Msg -> io:format("got it: ~p~n",[Msg])
  end.

% ----------------------------------------------------------------
% example 2

example2() ->
  Pid = self(),
  senders(Pid,[a,b,c,d]),
  collect().

senders(_,[]) ->
  ok;

senders(Pid,[X|Xs]) ->
  spawn(fun () ->
    Pid ! X
  end),
  senders(Pid,Xs).  

collect() ->
  receive
    a -> io:format("got a!~n")
  end,
  receive
    b -> io:format("got b!~n")
  end,
  receive
    c -> io:format("got c!~n")
  end,
  receive
    d -> io:format("got d!~n")
  end.

% ----------------------------------------------------------------
% example 3

example3() ->
  C = spawn(fun() ->
        receive
          Msg -> io:format("C got: ~p.~n",[Msg])
        end,
        receive
          Msg2 -> io:format("C got: ~p.~n",[Msg2])
        end
      end),
  B = spawn(fun() ->
        receive
          Msg -> C ! Msg
        end
      end),
  _A = spawn(fun() ->
         C ! hello,
         B ! world
       end),
  ok.

% ----------------------------------------------------------------
% example 4

example4() ->
  B = spawn(fun() ->
        receive
          a       -> io:format("got a!~n")
          after 0 -> receive
                       b -> io:format("got b!~n")
                     end
        end
      end),
  B ! b,
  B ! a.

% ----------------------------------------------------------------
% example 5

example5() ->
  B = spawn(fun() ->
        receive
          {divide,N} -> 1/N
        end
      end),
  process_flag(trap_exit,true),
  link(B),
  B ! {divide,0},
  receive
    {'EXIT',_,Msg} -> io:format("Got ~p!~n",[Msg])
  end.

% ----------------------------------------------------------------
% example 6

example6() ->
  Pid1 = spawn(fun() ->
                exit(suicide)
               end),
  Pid2 = spawn(fun() ->
                receive a -> ok end
               end),
  Pid1 ! a,
  Pid2 ! a.

% ----------------------------------------------------------------
% example 7

example7() ->
    Pid1 = spawn(fun() ->
		   file:write_file("a.txt",<<"a">>)
		 end),
    Pid2 = spawn(fun() ->
		   file:write_file("a.txt",<<"b">>)
		 end),
    ok.

% ----------------------------------------------------------------
% example 8

write_race() ->
    Pid = spawn(fun() ->
		   file:write_file("a.txt",<<"a">>)
		 end),
    file:write_file("a.txt",<<"b">>).

% ----------------------------------------------------------------
% example 9

killing_time() ->
  Witness  = spawn(fun receiving/0),
  Victim   = spawn(fun () -> Witness ! a, Witness ! b end),
  Murderer = spawn(fun () -> exit(Victim, die_die_die) end).

receiving() ->
  receive
    Msg -> io:format("~s~n", [Msg]),
    receiving()
  end.

% ----------------------------------------------------------------
% example 10 
% Testing receive after X

% receive_afterX() ->
% 	Proc1  = spawn(fun() -> receive ok -> ok end end),
% 	_Proc2 = spawn(fun() -> exit(Proc1,foo), receive after 10 -> ok end end),
% 	Ref = erlang:monitor(process,Proc1),
% 	receive 
% 		{'DOWN',Ref,process,Proc1,Reason} ->
% 			io:format("Reason: ~p\n",[Reason]),
% 			Proc1 ! ok
% 	end.

% ----------------------------------------------------------------
% example 11 
% The spawn, register, whereis example

spawn_register_where() ->
	Reg = spawn(fun() -> simple_reg([]) end),
	Proc1  = spawn(fun() -> receive ok -> ok end end),
	ok = do_reg(Reg,x,Proc1),
	exit(Proc1,foo), timer:sleep(10),%receive after 10 -> ok end,
	Res = do_whereis(Reg,x),
	do_stop(Reg),
	Res.
		

simple_reg(Reg) ->
	receive
		{'DOWN',_,_,Pid,_} ->
			simple_reg([X || X = {Pid1,_} <- Reg,
							 Pid /= Pid1]);
		{reg,From,Pid,Name} ->
			From ! {reg,reg_ok},
			erlang:monitor(process,Pid),
			simple_reg([{Pid,Name} | Reg]);
		{whereis,From,Name} ->
			case [Pid || {Pid,Name1} <- Reg,
						 Name1 == Name] of
				[] -> 
					From ! {reg,undefined};
				[Pid] -> 
					From ! {reg,Pid}
			end,
			simple_reg(Reg);
		{stop,From} ->
			From ! {reg,stop_ok}
	end.

do_reg(Reg,Name,Pid) ->
	Reg ! {reg,self(),Pid,Name},
	receive 
		{reg,reg_ok} ->
			ok
	end.

do_whereis(Reg,Name) ->
	Reg ! {whereis,self(),Name},
	receive 
		{reg,Res} ->
			Res
	end.

do_stop(Reg) ->
	Reg ! {stop,self()},
	receive 
		{reg,stop_ok} ->
			ok
	end.
