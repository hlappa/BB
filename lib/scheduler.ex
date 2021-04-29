defmodule BB.Scheduler do
  use WebSockex

  require Logger

  @url "wss://stream.binance.com:9443/ws/"

  def start_link(symbol, handler_pid) do
    WebSockex.start("#{@url}#{String.downcase(symbol)}@kline_3m", __MODULE__, %{
      buy_price: nil,
      handler_pid: handler_pid,
      trader_pid: nil,
      klines: []
    })
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

      if state.trader_pid != nil do
        case stop_loss do
          true -> Process.send(state.trader_pid, {:trigger_stop_loss}, [])
          false -> Process.send(state.trader_pid, {:end_stop_loss}, [])
        end
      end

      case trade do
        true -> Process.send(state.handler_pid, {:continue_trading}, [])
        false -> Process.send(state.handler_pid, {:halt_trading}, [])
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
  def handle_info({:set_trader_pid, pid}, state) do
    {:ok, %{state | trader_pid: pid}}
  end

  @impl true
  def handle_ping({:ping, _id}, state) do
    {:reply, {:pong, "pong"}, state}
  end

  @impl true
  def terminate(close_reason, _state) do
    Logger.error(close_reason)
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
    kline_pairs = Enum.map(klines, fn x -> {x.open_price, x.close_price} end)
    directions = Enum.map(kline_pairs, fn y -> determine_direction(y) end)

    case directions do
      [:up] ->
        false

      [:down] ->
        true

      [:up, :down] ->
        false

      [:down, :up] ->
        true

      [:up, :up] ->
        false

      [:down, :down] ->
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

    term =
      case Decimal.negative?(difference) do
        true ->
          :down

        false ->
          :up
      end

    term
  end

  defp calculate_difference(a, b) do
    a_dec = Decimal.cast(a) |> elem(1)
    b_dec = Decimal.cast(b) |> elem(1)

    Decimal.sub(a_dec, b_dec) |> Decimal.mult(100) |> Decimal.div(a_dec)
  end
end
