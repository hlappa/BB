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

  def handle_frame({_type, msg}, state) do
    kline =
      with {:ok, kline_event} <- Jason.decode(msg) do
        handle_event(kline_event)
      else
        _ -> Logger.error("Could not parse kline event: #{msg}")
      end

    if kline.is_closed do
      new_kline_list = [kline | state.klines] |> Enum.slice(0, 3)
      {:ok, %{state | klines: new_kline_list}}
    else
      {:ok, state}
    end
  end

  def handle_info({:set_buy_price, price}, state) do
    IO.inspect(price)
    {:ok, %{state | buy_price: price}}
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

  def handle_ping({:ping, _id}, state) do
    {:reply, {:pong, "pong"}, state}
  end
end
