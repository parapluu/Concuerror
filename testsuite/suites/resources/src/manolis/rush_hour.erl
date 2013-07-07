-module(rush_hour).

-export([solve/3, solve/2, print/2, print_path/2, translate/1, toml/2,
	 test_2workers/0, test_2workers_small/0, test_3workers/0, test/2]).
-export([next_entries/2, winning/2, reverse_step/2,
	 compress/2, get_decomp_key/2, decompress/3]).
-export([test_2workers_benchmark/0]).

%% TODO: validate input? (in intermediate form?)
%% TODO: visible hash?
%% TODO: separate hash handling from closed set name
%% TODO: Astar
%% TODO: distributed hash table (closed + open set)
%% TODO: batch assign work
%% TODO: open set as hashtable (easy to find duplicates)
%% TODO: use a queue from stdlib for open set(s)

-type direction() :: 'x' | 'y'.
-type position() :: 0..1023.
-type length() :: 2..1024.
-type distance() :: 0..1023 | 'inf'.
-type move_range() :: {distance(),distance()}.
-type move() :: -1023..1023.

-type x_point() :: position().
-type x_car() :: {x_point(),length()}.
-type point() :: {position(),position()}.
-type car() :: {point(),direction(),length()}.
-type tag() :: 0..1023.
-type tagged_car() :: {tag(),car()}.
-type room() :: {length(),length(),point()}.
-type state() :: [tagged_car()].
-type backstep() :: {tag(),move()}.
-type hashentry() :: {state(),backstep()}.
-type answer_S() :: non_neg_integer() | -1.
-type answer() :: {answer_S(),[state()]}.

-type imm_car() :: {point(), point()}.
-type imm_tagged_car() :: {tag(), imm_car()}.
-type imm_state() :: [imm_tagged_car()].
-type comp_car() :: point().
-type comp_state1() :: [comp_car()].
-type bin_car() :: binary().
-type comp_state2() :: [bin_car()].
-type comp_state3() :: binary().
-type comp_state() :: state() | comp_state1() | comp_state2() | comp_state3().
-type comp_level() :: 0..3.
-type decomp_key() :: [{tag(),direction(),length()}].

-type option() :: {_,_}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PropEr predicates
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% -include_lib("proper/include/proper.hrl").

%% -export([all_states_are_solvable_prop/0, all_states_are_solvable_prop/1,
%% 	 all_states_are_solvable_in_fewer_moves/2]).

%% state(Room) ->
%%     ?SIZED(Size, state(Size, Room)).

%% state(0, {Width,Height,{ExitX,ExitY}}) ->
%%     ?LET(Dir, union([x,y]),
%% 	 case Dir of
%% 	     x -> ?LET(Y, range(0,Height-2), [{0,{{ExitX,Y},x,2}}]);
%% 	     y -> ?LET(X, range(0,Width-2), [{0,{{X,ExitY},y,2}}])
%% 	 end);
%% state(N, Room = {Width,Height,_Exit}) ->
%%     ?LETSHRINK(
%% 	[Smaller], [state(N-1, Room)],
%% 	begin
%% 	    {0,ZeroCar} = lists:keyfind(0, 1, Smaller),
%% 	    Cars = all_cars(Width, Height, Smaller, 2),
%% 	    NiceCars = [C || C <- Cars, doesnt_block(ZeroCar, C)],
%% 	    case NiceCars of
%% 		[] -> Smaller;
%% 		_  -> ?LET(Car, oneof(NiceCars), [{N,Car} | Smaller])
%% 	    end
%% 	end
%%     ).

%% %% This is too strict, situations like this: oxxo00o@ should be allowed.
%% doesnt_block({{ZeroX,ZeroY},ZeroDir,_ZeroLen}, {{X,Y},Dir,_Len}) ->
%%     ZeroDir =/= Dir orelse
%%     case Dir of
%% 	x -> ZeroX =/= X;
%% 	y -> ZeroY =/= Y
%%     end.

%% all_cars(Width, Height, State, Len) ->
%%     [ {{X,Y1}, x, Len}
%%      || X <- lists:seq(0,Width-1),
%% 	Y1 <- lists:seq(0,Height-Len),
%% 	begin
%% 	    Y2 = Y1 + Len - 1,
%% 	    Squares = [{X,Y} || Y <- lists:seq(Y1,Y2)],
%% 	    lists:all(
%% 		fun({_T,C}) ->
%% 		    lists:all(fun(P) -> not touches(C,P) end, Squares)
%% 		end,
%% 		State
%% 	    )
%% 	end
%%     ] ++
%%     [ {{X1,Y}, y, Len}
%%      || Y <- lists:seq(0,Height-1),
%% 	X1 <- lists:seq(0,Width-Len),
%% 	begin
%% 	    X2 = X1 + Len - 1,
%% 	    Squares = [{X,Y} || X <- lists:seq(X1,X2)],
%% 	    lists:all(
%% 		fun({_T,C}) ->
%% 		    lists:all(fun(P) -> not touches(C,P) end, Squares)
%% 		end,
%% 		State
%% 	    )
%% 	end
%%     ].

%% all_states_are_solvable_prop() ->
%%     Room = {6,6,{5,2}},
%%     all_states_are_solvable_prop(Room).

%% all_states_are_solvable_prop(Room) ->
%%     ?FORALL(State,
%% 	    ?SIZED(Size, resize(Size div 5, state(Room))),
%% 	    solve(Room, State, []) >= 0).

%% all_states_are_solvable_in_fewer_moves(Room, MaxMoves) ->
%%     ?FORALL(State,
%% 	    ?SIZED(Size, resize(Size div 4, state(Room))),
%% 	    begin
%% 		Sol = solve(Room, State, []),
%% 		Sol =< MaxMoves
%% 	    end).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Compression functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec compress(state(), CompLevel :: comp_level()) -> comp_state().
compress(State, 0) ->
    State;
compress(State, 1) ->
    lists:map(fun({_T,{P,_D,_L}}) -> P end, State);
compress(State, 2) ->
    BinarizePoint = fun({_T,{{X,Y},_D,_L}}) -> <<X:12,Y:12>> end,
    lists:map(BinarizePoint, State);
compress(State, 3) ->
    list_to_binary(compress(State, 2)).

-spec get_decomp_key(state(), comp_level()) -> decomp_key().
get_decomp_key(State, _CompLevel) ->
    lists:map(fun({T,{_P,D,L}}) -> {T,D,L} end, State).

-spec decompress(comp_state(), decomp_key(), comp_level()) -> state().
decompress(CompState, _DecompKey, 0) ->
    CompState;
decompress(CompState, DecompKey, 1) ->
    F = fun(P, {T,D,L}) -> {T,{P,D,L}} end,
    lists:zipwith(F, CompState, DecompKey);
decompress(CompState, DecompKey, 2) ->
    UnBinarizePoint = fun(<<X:12,Y:12>>) -> {X,Y} end,
    decompress(lists:map(UnBinarizePoint, CompState), DecompKey, 1);
decompress(CompState, DecompKey, 3) ->
    decompress(binary_to_points(CompState, []), DecompKey, 1).

-spec binary_to_points(comp_state3(), comp_state1()) -> comp_state1().
binary_to_points(<<>>, Acc) ->
    lists:reverse(Acc);
binary_to_points(<<X:12,Y:12,Rest/binary>>, Acc) ->
    binary_to_points(Rest, [{X,Y} | Acc]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Game Logic
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec rev_dir(direction()) -> direction().
rev_dir('x') -> 'y';
rev_dir('y') -> 'x'.

-spec min_dist(distance(), distance()) -> distance().
min_dist(inf, Y) -> Y;
min_dist(X, inf) -> X;
min_dist(X, Y) -> erlang:min(X, Y).

-spec between(x_point(), x_point(), length()) -> boolean().
between(A, B, LenB) ->
    B =< A andalso A =< B + LenB - 1.

-spec touches(car(), point()) -> boolean().
touches({{_X,Y1},'x',Len}, {_X,Y2}) ->
    between(Y2,Y1,Len);
touches({{X1,_Y},'y',Len}, {X2,_Y}) ->
    between(X2,X1,Len);
touches(_Car, _Point) ->
    false.

-spec x_max_move_vs_other(x_car(), x_car()) -> move_range().
x_max_move_vs_other({X1,Len1}, {X2,Len2}) ->
    case X1 < X2 of
	true  -> {inf,X2 - X1 - Len1};
	false -> {X1 - X2 - Len2,inf}
    end.

-spec max_move_vs_other(car(), car()) -> move_range().
max_move_vs_other({{_X,Y1},'x',Len1}, {{_X,Y2},'x',Len2}) ->
    x_max_move_vs_other({Y1,Len1}, {Y2,Len2});
max_move_vs_other({{_X1,_Y1},'x',_Len1}, {{_X2,_Y2},'x',_Len2}) ->
    {inf,inf};
max_move_vs_other({{X1,Y1},'x',Len1}, {{X2,Y2},'y',Len2}) ->
    case between(X1, X2, Len2) of
	true  -> x_max_move_vs_other({Y1,Len1}, {Y2,1});
	false -> {inf,inf}
    end;
max_move_vs_other({{X1,Y1},'y',Len1}, {{X2,Y2},Dir2,Len2}) ->
    max_move_vs_other({{Y1,X1},'x',Len1}, {{Y2,X2},rev_dir(Dir2),Len2}).

-spec max_move_vs_one(tagged_car(), tagged_car()) -> move_range().
max_move_vs_one({_Tag, _}, {_Tag, _}) ->
    {inf,inf};
max_move_vs_one({_TagA,CarA}, {_TagB,CarB}) ->
    max_move_vs_other(CarA, CarB).

-spec max_move_vs_room(tagged_car(), room()) -> move_range().
max_move_vs_room({_Tag,{{_X,Y},'x',Len}}, {_Width, Height, _Exit}) ->
    {Y,Height - Y - Len};
max_move_vs_room({_Tag,{{X,_Y},'y',Len}}, {Width, _Height, _Exit}) ->
    {X,Width - X - Len}.

-spec max_move(tagged_car(), room(), state()) -> move_range().
max_move(TCar, Room, Cars) ->
    F = fun(TC) -> max_move_vs_one(TCar, TC) end,
    G = fun({L1,R1}, {L2,R2}) -> {min_dist(L1,L2),min_dist(R1,R2)} end,
    MaxMoves = lists:map(F, Cars),
    lists:foldl(G, max_move_vs_room(TCar, Room), MaxMoves).

-spec all_moves(move_range()) -> [move()].
all_moves({L,R}) ->
    lists:seq(-1, -L, -1) ++ lists:seq(1, R, 1).

-spec apply_move(tagged_car(), move()) -> tagged_car().
apply_move({Tag,{{X,Y},'x',Len}}, Move) ->
    {Tag,{{X,Y + Move},'x',Len}};
apply_move({Tag,{{X,Y},'y',Len}}, Move) ->
    {Tag,{{X + Move,Y},'y',Len}}.

-spec move_one_car(tagged_car(), state(), move()) -> state().
move_one_car(TCar, Cars, Move) ->
    {Tag,_Car} = TCar,
    lists:keyreplace(Tag, 1, Cars, apply_move(TCar, Move)).

-spec next_entries_by_one(tagged_car(), room(), state()) -> [hashentry()].
next_entries_by_one(TCar, Room, Cars) ->
    {Tag,_Car} = TCar,
    Moves = all_moves(max_move(TCar, Room, Cars)),
    [{move_one_car(TCar, Cars, M), {Tag, -M}} || M <- Moves].

-spec next_entries(room(), state()) -> [hashentry()].
next_entries(Room, Cars) ->
    lists:flatmap(fun(TC) -> next_entries_by_one(TC, Room, Cars) end, Cars).

-spec winning(room(), state()) -> boolean().
winning({_Width, _Height, Exit}, Cars) ->
    {0,Car} = lists:keyfind(0, 1, Cars),
    touches(Car, Exit).

-spec reverse_step(state(), backstep()) -> state().
reverse_step(Cars, {Tag, Move}) ->
    TCar = lists:keyfind(Tag, 1, Cars),
    move_one_car(TCar, Cars, Move).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% General Invocation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec solve(room(), state(), [option()]) -> answer() | answer_S().
solve(Room, Cars, Opts) ->
    search:bfs(Room, Cars, ?MODULE, Opts).

-spec solve(string(), [option()]) -> answer() | answer_S().
solve(Test, Opts) ->
    {Room, Cars} = translate(Test),
    solve(Room, Cars, Opts).

-spec test_2workers() -> answer() | answer_S().
test_2workers() ->
    Target = {4, 4, {3, 2}},
    State = [{0, {{0, 2}, y, 2}}, {1, {{2, 0}, y, 2}}, {2, {{3, 1}, x, 2}}],
    Options = [],
    solve(Target, State, Options).

-spec test_2workers_small() -> answer() | answer_S().
test_2workers_small() ->
    Target = {3, 3, {1, 2}},
    State = [{0, {{1, 0}, x, 1}}
             , {1, {{0, 1}, y, 1}}
             , {2, {{2, 1}, y, 1}}
             , {3, {{1, 2}, y, 1}}
             , {4, {{2, 2}, y, 1}}
            ],
    Options = [],
    solve(Target, State, Options).

-spec test_2workers_benchmark() -> answer() | answer_S().
test_2workers_benchmark() ->
    Target = {3, 3, {1, 2}},
    State = [{0, {{1, 0}, x, 1}}
             , {1, {{0, 1}, y, 1}}
             , {2, {{2, 1}, y, 1}}
             , {3, {{1, 2}, y, 1}}
             , {4, {{2, 2}, y, 1}}
             , {5, {{0, 0}, x, 1}}
             , {6, {{0, 2}, x, 1}}
            ],
    Options = [{workers, 4}],
    solve(Target, State, Options).

-spec test_3workers() -> answer() | answer_S().
test_3workers() ->
    Target = {4, 4, {3, 2}},
    State = [{0, {{0, 2}, y, 2}}, {1, {{2, 0}, y, 2}}, {2, {{3, 1}, x, 2}}],
    Options = [{workers, 3}],
    solve(Target, State, Options).

-spec test(non_neg_integer(), [option()]) -> answer() | answer_S().
test(0, Opts) -> % solution: 8
    solve({6,6,{5,2}}, [{0,{{1,2},y,2}}, {1,{{0,0},y,2}}, {2,{{0,1},x,3}}, {3,{{0,4},x,2}}, {4,{{3,1},x,3}}, {5,{{5,0},x,3}}, {6,{{4,4},y,2}}, {7,{{2,5},y,3}}], Opts);
test(1, Opts) -> % solution: 43
    solve({6,6,{5,2}}, [{0,{{0,2},y,2}}, {1,{{0,0},y,2}}, {2,{{2,0},x,2}}, {3,{{4,0},y,2}}, {4,{{4,1},y,2}}, {5,{{2,2},x,2}}, {6,{{3,3},y,2}}, {7,{{5,2},x,2}}, {8,{{0,3},x,3}}, {9,{{1,4},y,2}}, {10,{{1,5},y,2}}, {11,{{3,4},x,2}}, {12,{{5,4},x,2}}], Opts);
test(2, Opts) -> % solution: 51
    solve({6,6,{5,2}}, [{1,{{0,0},x,3}}, {2,{{1,0},y,2}}, {3,{{1,1},x,2}}, {4,{{2,1},x,2}}, {5,{{4,0},x,2}}, {6,{{5,1},x,3}}, {0,{{3,2},y,2}}, {7,{{0,3},y,3}}, {8,{{0,5},y,2}}, {9,{{2,4},x,2}}, {10,{{3,3},x,2}}, {11,{{3,5},y,2}}, {12,{{4,4},y,2}}], Opts);
test(3, Opts) -> % solution: 49
    solve({6,6,{5,2}}, [{0,{{2,2},y,2}}, {1,{{0,1},x,2}}, {2,{{1,4},x,2}}, {3,{{2,3},x,2}}, {4,{{3,0},x,2}}, {5,{{4,0},x,3}}, {6,{{5,0},x,3}}, {13,{{0,0},y,3}}, {14,{{1,1},y,2}}, {16,{{0,3},y,2}}, {17,{{4,4},y,2}}, {18,{{2,5},y,2}}, {24,{{4,5},y,2}}], Opts);
test(4, Opts) -> % solution: 7
    solve({9,9,{8,3}}, [{33,{{3,4},x,2}},{32,{{2,0},x,2}},{31,{{4,7},x,2}},{30,{{2,8},y,2}},{29,{{7,5},y,2}},{28,{{0,0},y,2}},{27,{{4,0},y,2}},{26,{{0,1},y,2}},{25,{{7,6},y,2}},{24,{{5,3},y,2}},{23,{{2,6},x,2}},{22,{{2,3},y,2}},{21,{{6,8},y,2}},{20,{{5,5},y,2}},{19,{{6,0},y,2}},{18,{{7,1},x,2}},{17,{{0,6},x,2}},{16,{{0,3},x,2}},{15,{{5,1},y,2}},{14,{{1,4},y,2}},{13,{{5,6},y,2}},{12,{{7,3},x,2}},{11,{{1,6},x,2}},{10,{{0,8},y,2}},{9,{{5,7},x,2}},{8,{{4,5},x,2}},{7,{{1,5},y,2}},{6,{{4,2},y,2}},{5,{{1,2},y,2}},{4,{{3,0},x,2}},{3,{{3,6},x,2}},{2,{{4,4},y,2}},{1,{{6,7},y,2}},{0,{{8,7},x,2}}], Opts);
test(5, Opts) -> % solution: 11 but needs a lot of time and memory
    solve({12,12,{11,5}}, [{0,{{1,5},y,3}}, {1,{{0,5},x,7}}, {2,{{5,3},x,4}}, {3,{{3,2},y,3}}, {4,{{2,1},x,4}}, {5,{{1,0},y,2}}, {6,{{3,7},x,3}}, {7,{{4,8},y,4}}, {8,{{8,7},x,4}}, {9,{{7,0},x,5}}, {10,{{8,4},y,4}}, {11,{{1,10},y,4}}, {12,{{5,9},x,3}}, {13,{{7,11},y,4}}, {14,{{9,5},x,6}}], Opts).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Input/Output
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

-spec print(room(), state()) -> 'ok'.
print(Room, Cars) ->
    print({0,-1}, Room, Cars).

-spec print({0..1 | length(),-1..1 | length()}, room(), state()) -> 'ok'.
print({_X,_Height}, {_Width,_Height,_Exit}, _Cars) ->
    io:format("~n", []);
print({Width,Y}, {Width,Height,Exit}, Cars) ->
    io:format("|~n+~s~n", [lists:flatten(lists:duplicate(Width, "--+"))]),
    print({0,Y + 1}, {Width,Height,Exit}, Cars);
print({0,-1}, {Width,Height,Exit}, Cars) ->
    io:format("+~s~n", [lists:flatten(lists:duplicate(Width, "--+"))]),
    print({0,0}, {Width,Height,Exit}, Cars);
print({X,Y}, Room, Cars) ->
    CarOnSquare = fun({_N,C}) -> touches(C, {X,Y}) end,
    io:format("|", []),
    case lists:filter(CarOnSquare, Cars) of
	[] ->
	    {_Width,_Height,Exit} = Room,
	    case {X,Y} =:= Exit of
		true  -> io:format("@@", []);
		false -> io:format("  ", [])
	    end;
	[{Num,_Coords}] ->
	    io:format("~2b", [Num])
	    %% TODO: allow more digits
    end,
    print({X + 1,Y}, Room, Cars).

-spec print_path(room(), [state()]) -> _.
print_path(Room, States) ->
    lists:foreach(fun(S) -> print(Room, S) end, States).

-spec parse_testcase(string()) -> {room(), imm_state()}.
parse_testcase(Test) ->
    Test2 = re:replace(Test, "[[:alpha:];_]", "", [{return,list},global]),
    {R1, S1} = lists:splitwith(fun(C) -> C =/= $[ end, Test2),
    R2 = "{" ++ R1,
    R3 = re:replace(R2, "([0-9])(\\s+)([0-9])", "\\1,\\3",
		    [{return,list},global]),
    R4 = re:replace(R3, "([0-9])(\\s+)\\(", "\\1,{", [{return,list},global]),
    R5 = re:replace(R4, "\\)", "}}", [{return,list},global]),
    S2 = re:replace(S1, "\\)(\\s*)\\)", "}}}", [{return,list},global]),
    S3 = re:replace(S2, "\\)(\\s*),(\\s*)\\(", "},{", [{return,list},global]),
    S4 = re:replace(S3, "\\}(\\s*),(\\s*)\\(", "},{", [{return,list}, global]),
    S5 = re:replace(S4, "\\[(\\s*)\\(", "[{", [{return,list}, global]),
    S6 = re:replace(S5, "\\(", "{{", [{return,list}, global]),
    {ok,Tokens,_} = erl_scan:string("{" ++ R5 ++ "," ++ S6 ++ "}."),
    {ok,Term} = erl_parse:parse_term(Tokens),
    Term.

-spec translate_car(imm_car()) -> car().
translate_car({{X,Y1},{X,Y2}}) ->
    {{X,erlang:min(Y1,Y2)},'x',abs(Y2 - Y1) + 1};
translate_car({{X1,Y},{X2,Y}}) ->
    {{erlang:min(X1,X2),Y},'y',abs(X2 - X1) + 1}.

-spec translate_state(imm_state()) -> state().
translate_state(ImmState) ->
    lists:map(fun({T,C}) -> {T,translate_car(C)} end, ImmState).

-spec translate(string()) -> {room(), state()}.
translate(Test) ->
    {Room,ImmState} = parse_testcase(Test),
    {Room,translate_state(ImmState)}.

-spec toml(room(), state()) -> string().
toml({Width,Height,{ExitX,ExitY}}, [TCar | Rest]) ->
    Str1 = io_lib:format("rush_hour ~b ~b (~b,~b) [",
			 [Width,Height,ExitX,ExitY]),
    Str2 = print_tagged_car(TCar),
    Str3 = lists:flatten([", " ++ print_tagged_car(T) || T <- Rest]),
    Str1 ++ Str2 ++ Str3 ++ "];~n".

-spec print_tagged_car(tagged_car()) -> string().
print_tagged_car({Tag,{{X,Y},Dir,Len}}) ->
    Args = case Dir of
	       x -> [Tag, X, Y, X, Y+Len-1];
	       y -> [Tag, X, Y, X+Len-1, Y]
	   end,
    io_lib:format("(~b,(~b,~b),(~b,~b))", Args).
