defmodule TradeStream do
  use WebSockex

  require Logger

  alias Phoenix.PubSub

  @url "wss://stream.binance.com:9443/ws/"

  def start_link(symbol) do
    WebSockex.start_link("#{@url}#{symbol}@trade", __MODULE__, [])
  end

  def handle_frame({_type, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} ->
        handle_event(event)

      _ ->
        Logger.error("Could not parse Binance stream payload: #{msg}")
    end

    {:ok, state}
  end

  defp handle_event(%{"e" => "trade"} = event) do
    trade = %TradeStream.Event{
      type: event["e"],
      time: event["E"],
      symbol: event["s"],
      id: event["t"],
      price: Decimal.cast(event["p"]) |> elem(1),
      quantity: Decimal.cast(event["q"]) |> elem(1),
      market_maker: event["m"]
    }

    PubSub.broadcast(:trade_stream, "XRPEUR", trade)
  end

  def handle_ping({:ping, _id}, state) do
    {:reply, {:pong, "pong"}, state}
  end
end
