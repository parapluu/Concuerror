-module(concuerror_logger_tests).

-include_lib("eunit/include/eunit.hrl").

-define(M, concuerror_logger).

%%==============================================================================

time_format_test() ->

  ?assertEqual("0s", ?M:time_string(0)),
  ?assertEqual("1s", ?M:time_string(1)),
  ?assertEqual("42s", ?M:time_string(42)),
  ?assertEqual("59s", ?M:time_string(59)),

  ?assertEqual("1m00s", ?M:time_string(1*60)),
  ?assertEqual("1m05s", ?M:time_string(1*60 + 5)),
  ?assertEqual("1m59s", ?M:time_string(1*60 + 59)),
  ?assertEqual("4m29s", ?M:time_string(4*60 + 29)),
  ?assertEqual("9m59s", ?M:time_string(9*60 + 59)),
  ?assertEqual("10m00s", ?M:time_string(10*60 + 0)),
  ?assertEqual("10m01s", ?M:time_string(10*60 + 1)),
  ?assertEqual("42m42s", ?M:time_string(42*60 + 42)),
  ?assertEqual("59m59s", ?M:time_string(59*60 + 59)),

  ?assertEqual("1h00m", ?M:time_string(60*60)),
  ?assertEqual("1h00m", ?M:time_string(60*60 + 29)),
  ?assertEqual("1h00m", ?M:time_string(60*60 + 30)),
  ?assertEqual("1h00m", ?M:time_string(60*60 + 59)),
  ?assertEqual("1h01m", ?M:time_string(60*60 + 60)),

  ?assertEqual("9h59m", ?M:time_string(9*60*60 + 59*60 + 59)),
  ?assertEqual("10h00m", ?M:time_string(9*60*60 + 59*60 + 59 + 1)),
  ?assertEqual("23h59m", ?M:time_string(23*60*60 + 59*60 + 59)),
  ?assertEqual("24h00m", ?M:time_string(24*60*60)),
  ?assertEqual("24h00m", ?M:time_string(24*60*60 + 59)),
  ?assertEqual("24h01m", ?M:time_string(24*60*60 + 60)),
  ?assertEqual("47h59m", ?M:time_string(47*60*60 + 59*60)),
  ?assertEqual("47h59m", ?M:time_string(47*60*60 + 59*60 + 59)),

  ?assertEqual("2d00h", ?M:time_string(2*24*60*60)),
  ?assertEqual("2d00h", ?M:time_string(2*24*60*60 + 59*60)),
  ?assertEqual("2d01h", ?M:time_string(2*24*60*60 + 60*60)),

  ?assertEqual("17d03h", ?M:time_string(17*24*60*60 + 3*60*60)),
  ok.

approximate_time_format_test() ->

  ?assertEqual("<1m", ?M:approximate_time_string(0)),
  ?assertEqual("<1m", ?M:approximate_time_string(1)),
  ?assertEqual("<1m", ?M:approximate_time_string(42)),
  ?assertEqual("<1m", ?M:approximate_time_string(59)),

  ?assertEqual("1m", ?M:approximate_time_string(1*60)),
  ?assertEqual("1m", ?M:approximate_time_string(1*60 + 5)),
  ?assertEqual("1m", ?M:approximate_time_string(1*60 + 59)),
  ?assertEqual("4m", ?M:approximate_time_string(4*60 + 29)),
  ?assertEqual("9m", ?M:approximate_time_string(9*60 + 59)),
  ?assertEqual("10m", ?M:approximate_time_string(10*60 + 0)),
  ?assertEqual("17m", ?M:approximate_time_string(17*60 + 1)),
  ?assertEqual("29m", ?M:approximate_time_string(29*60 + 1)),

  ?assertEqual("30m", ?M:approximate_time_string(30*60 + 1)),
  ?assertEqual("30m", ?M:approximate_time_string(36*60 + 1)),
  ?assertEqual("40m", ?M:approximate_time_string(42*60 + 42)),
  ?assertEqual("50m", ?M:approximate_time_string(59*60 + 59)),

  ?assertEqual("1h00m", ?M:approximate_time_string(60*60)),
  ?assertEqual("1h00m", ?M:approximate_time_string(60*60 + 29)),
  ?assertEqual("1h00m", ?M:approximate_time_string(60*60 + 30)),
  ?assertEqual("1h00m", ?M:approximate_time_string(60*60 + 60)),
  ?assertEqual("1h10m", ?M:approximate_time_string(60*60 + 10*60)),
  ?assertEqual("1h40m", ?M:approximate_time_string(60*60 + 42*60)),
  ?assertEqual("2h", ?M:approximate_time_string(2*60*60 + 60)),

  ?assertEqual("9h", ?M:approximate_time_string(9*60*60 + 59*60 + 59)),
  ?assertEqual("10h", ?M:approximate_time_string(9*60*60 + 59*60 + 59 + 1)),
  ?assertEqual("23h", ?M:approximate_time_string(23*60*60 + 59*60 + 59)),
  ?assertEqual("24h", ?M:approximate_time_string(24*60*60)),
  ?assertEqual("24h", ?M:approximate_time_string(24*60*60 + 59)),
  ?assertEqual("47h", ?M:approximate_time_string(47*60*60 + 59*60)),
  ?assertEqual("47h", ?M:approximate_time_string(47*60*60 + 59*60 + 59)),

  ?assertEqual("2d", ?M:approximate_time_string(48*60*60)),
  ?assertEqual("2d", ?M:approximate_time_string(48*60*60 + 59*60)),
  ?assertEqual("2d", ?M:approximate_time_string(48*60*60 + 60*60)),

  ?assertEqual("6d", ?M:approximate_time_string(6*24*60*60)),
  ?assertEqual("7d", ?M:approximate_time_string(7*24*60*60)),
  ?assertEqual("8d", ?M:approximate_time_string(8*24*60*60)),
  ?assertEqual("58d", ?M:approximate_time_string(58*24*60*60)),
  ?assertEqual("320d", ?M:approximate_time_string(320*24*60*60)),

  ?assertEqual("1y03m", ?M:approximate_time_string((12+3)*30*24*60*60)),
  ?assertEqual("7y03m", ?M:approximate_time_string((7*12+3)*30*24*60*60)),
  ?assertEqual("40y06m", ?M:approximate_time_string((40*12+6)*30*24*60*60)),

  ?assertEqual("70y", ?M:approximate_time_string((70*12+6)*30*24*60*60)),
  ?assertEqual("90y", ?M:approximate_time_string((90*12+6)*30*24*60*60)),
  ?assertEqual("100y", ?M:approximate_time_string((100*12+6)*30*24*60*60)),

  ?assertEqual("> 10000y", ?M:approximate_time_string((10001*12+6)*30*24*60*60)),
  ok.

estimator_compare_test() ->
  ?assertEqual(1800, ?M:sanitize_estimation(1783, 560)),
  ?assertEqual(1800, ?M:sanitize_estimation(1130, 1700)),
  ?assertEqual(1700, ?M:sanitize_estimation(1130, 1699)),

  ?assertEqual(unknown, ?M:sanitize_estimation(unknown, 340)),
  ?assertEqual(unknown, ?M:sanitize_estimation(unknown, 1)),

  ?assertEqual(18000, ?M:sanitize_estimation(17843, 3560)),
  ?assertEqual(18000, ?M:sanitize_estimation(11330, 17100)),
  ?assertEqual(17000, ?M:sanitize_estimation(11930, 16959)).
