defmodule Trader do
  use GenServer

  require Logger

  def start_link(%Trader.Opts{} = opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(%Trader.Opts{} = opts) do
    state = %{
      opts: opts,
      status: :initial,
      buy_order_id: nil,
      sell_order_id: nil
    }

    {:ok, state, {:continue, :execute_buy}}
  end

  @impl true
  def handle_continue(:execute_buy, state) do
    # TODO: Execute buy order here
    Logger.info(
      "Order placed for #{state.opts.symbol}@#{state.opts.price} with quantity of #{
        state.opts.quantity
      }"
    )

    GenServer.cast(self(), :monitor_buy_order)

    {:noreply, %{state | buy_order_id: "fakeId", status: :buy_order_created}}
  end

  @impl true
  def handle_cast(:monitor_buy_order, state) do
    IO.inspect(state.buy_order_id)
    {:noreply, state}
  end
end
