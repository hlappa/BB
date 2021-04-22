defmodule Trader do
  use GenServer

  defstruct [:status]

  @impl true
  def handle_call(:buy, %Trader.Opts{} = opts, state) do
  end
end
