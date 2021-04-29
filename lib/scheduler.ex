defmodule BB.Scheduler do
  use WebSockex

  require Logger

  @url "wss://stream.binance.com:9443/ws/"

  def start_link(symbol) do
    WebSockex.start_link("#{@url}#{symbol}@kline_3m", __MODULE__, %{buy_price: nil, klines: []})
  end

  def set_buy_price(price) do
    send(self(), {:set_buy_price, price})
  end

  @impl true
  def handle_frame({_type, msg}, state) do
    kline =
      with {:ok, kline_event} <- Jason.decode(msg) do
        handle_event(kline_event)
      else
        _ -> Logger.error("Could not parse kline event: #{msg}")
      end

    if kline.is_closed && state.buy_price != nil do
      new_kline_list = [kline | state.klines] |> Enum.slice(0, 3)
      stop_loss = calculate_stop_loss(new_kline_list, state.buy_price)
      trade = calculate_trading_halt(new_kline_list)

      case stop_loss do
        true -> Trader.trigger_stop_loss()
        false -> Trader.end_stop_loss()
      end

      case trade do
        true -> BB.Handler.continue_trading()
        false -> BB.Handler.halt_trading()
      end

      {:ok, %{state | klines: new_kline_list}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_info({:set_buy_price, price}, state) do
    {:ok, %{state | buy_price: price}}
  end

  @impl true
  def handle_ping({:ping, _id}, state) do
    {:reply, {:pong, "pong"}, state}
  end

  defp handle_event(%{"e" => "kline"} = kline_event) do
    kline_data = kline_event["k"]

    %BB.Scheduler.Kline{
      start_time: kline_data["t"],
      close_time: kline_data["T"],
      symbol: kline_data["s"],
      interval: kline_data["i"],
      open_price: kline_data["o"],
      close_price: kline_data["c"],
      base_volume: kline_data["v"],
      is_closed: kline_data["x"]
    }
  end

  def calculate_stop_loss(klines, price) do
    prices = Enum.map(klines, fn x -> x.close_price end)
    lowest = Enum.min(prices)
    difference = calculate_difference(lowest, price) |> Decimal.to_float()
    treshold = -2.0

    difference <= treshold
  end

  def calculate_trading_halt(klines) do
    directions =
      Enum.map(klines, fn x -> {x.open_price, x.close_price} end)
      |> Enum.map(fn y -> determine_direction(y) end)

    case directions do
      [:up] ->
        false

      [:down] ->
        true

      [:up, :down] ->
        false

      [:down, :up] ->
        true

      [:down, :down, :down] ->
        true

      [:down, :down, :up] ->
        true

      [:down, :up, :up] ->
        true

      [:up, :up, :up] ->
        false

      [:up, :up, :down] ->
        false

      [:up, :down, :down] ->
        false

      [:up, :down, :up] ->
        false

      [:down, :up, :down] ->
        true
    end
  end

  defp determine_direction(prices) do
    open = elem(prices, 0)
    close = elem(prices, 1)
    difference = calculate_difference(open, close)

    case Decimal.negative?(difference) do
      true ->
        :down

      false ->
        :up
    end
  end

  defp calculate_difference(a, b) do
    ((a - b) * 100 / a) |> Decimal.cast() |> elem(1)
  end
end
