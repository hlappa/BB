defmodule BB.Handler do
  use GenServer

  alias Phoenix.PubSub

  require Logger

  @impl true
  def init(_state) do
    PubSub.subscribe(:trade_stream, "XRPEUR")

    state = %{
      trader_pid: nil,
      first_trade: true
    }

    {:ok, state}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def handle_info(msg, state) do
    if state.trader_pid != nil && !state.first_trade do
      {:noreply, state}
    else
      Logger.info("Starting new trader...")

      opts = %Trader.Opts{
        symbol: msg.symbol |> String.upcase(),
        quantity: 20,
        price: Decimal.to_float(msg.price),
        profit: Decimal.cast(1.005) |> elem(1),
        tick_size: get_tick_size(msg.symbol)
      }

      {:ok, pid} = Trader.start_link(opts)
      Logger.info("Started new trader: ")
      IO.inspect(pid)
      {:noreply, %{state | trader_pid: pid, first_trade: false}}
    end
  end

  defp get_tick_size(symbol) do
    %{"filters" => filters} =
      Binance.get_exchange_info()
      |> elem(1)
      |> Map.get(:symbols)
      |> Enum.find(&(&1["symbol"] == String.upcase(symbol)))

    %{"tickSize" => tick_size} =
      filters
      |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))

    Decimal.cast(tick_size) |> elem(1)
  end
end
