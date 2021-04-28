defmodule BB.Scheduler.Kline do
  defstruct [
    :start_time,
    :close_time,
    :symbol,
    :interval,
    :open_price,
    :close_price,
    :base_volume,
    :is_closed
  ]
end
