defmodule TradeStream.Event do
  defstruct [:type, :time, :symbol, :id, :price, :quantity, :market_maker]
end
