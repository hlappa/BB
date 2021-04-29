defmodule BB.Handler do
  use GenServer

  alias Phoenix.PubSub

  require Logger

  @impl true
  def init(_state) do
    symbol = Application.fetch_env!(:bb, :symbol)
    PubSub.subscribe(:trade_stream, symbol)

    state = %{
      symbol: symbol,
      trader_ref: nil,
      trader_pid: nil,
      trade: false,
      first_trade: true
    }

    {:ok, state}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  def continue_trading do
    GenServer.cast(self(), :continue_trading)
  end

  def halt_trading do
    GenServer.cast(self(), :halt_trading)
  end

  @impl true
  def handle_cast(:continue_trading, state) do
    {:noreply, %{state | trade: true}}
  end

  @impl true
  def handle_cast(:halt_trading, state) do
    {:noreply, %{state | trade: false}}
  end

  @impl true
  def handle_info(%TradeStream.Event{} = msg, state) do
    if (state.trader_ref != nil && !state.first_trade) || !state.trade do
      {:noreply, state}
    else
      tick = get_tick_size(state.symbol)

      opts = %Trader.Opts{
        symbol: state.symbol,
        quantity: Application.fetch_env!(:bb, :quantity),
        price: calculate_buy_price(msg.price, tick),
        profit: Decimal.cast(1.0025) |> elem(1),
        tick_size: tick
      }

      {ref, pid} = start_new_trader(opts)
      Logger.info("Started new trader!")
      {:noreply, %{state | trader_ref: ref, trader_pid: pid, first_trade: false}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, %{state | trader_ref: nil}}
  end

  defp start_new_trader(%Trader.Opts{} = opts) do
    {:ok, pid} = DynamicSupervisor.start_child(:dynamic_trade_supervisor, {Trader, opts})

    ref = Process.monitor(pid)
    {ref, pid}
  end

  defp calculate_buy_price(current_price, tick) do
    reduction = Decimal.cast(0.99975) |> elem(1)

    Decimal.mult(current_price, reduction)
    |> Decimal.div_int(tick)
    |> Decimal.mult(tick)
    |> Decimal.to_float()
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
