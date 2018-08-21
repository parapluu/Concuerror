-module(safeops_coverage).

-compile(export_all).

scenarios() ->
  [ test
  ].

test() ->
  erlang:adler32("42"),
  [1, 2, 3, 4] = erlang:append([1, 2], [3, 4]),
  erlang:bump_reductions(10),
  erlang:crc32("42"),
  erlang:decode_packet(raw, <<"foo">>, []),
  {c} = erlang:delete_element(1, {b, c}),
  erlang:external_size(42),
  erlang:garbage_collect(),
  {b, c} = erlang:insert_element(1, {c}, b),
  true = erlang:is_builtin(erlang, is_builtin, 3),
  {a, a, a} = erlang:make_tuple(3, a),
  [1, 2] = erlang:subtract([1, 2, 3], [3]).
