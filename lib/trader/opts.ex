defmodule Trader.Opts do
  defstruct [:quantity, :price, :symbol, :tick_size, :profit, :scheduler_pid, :handler_pid]
end
