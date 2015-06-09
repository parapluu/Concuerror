-module(bank_example).
-export([test/0]).

test() ->
  Bank = self(),
  register(bank, Bank),
  _Customer = spawn(fun customer/0),
  TaxOffice = spawn(fun tax_office/0),
  _Robber   = spawn(fun() -> robber(TaxOffice) end),
  receive money -> TaxOffice ! bank_got_money end.

customer() ->
  bank ! money.

tax_office() ->
  receive _Msg -> money_changed_hands end.

robber(TaxOffice) ->
  unregister(bank),
  register(bank, self()),
  receive
    money -> TaxOffice ! robber_got_money
  after
    10000 -> robbery_failed
  end.
