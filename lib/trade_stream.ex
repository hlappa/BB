defmodule TradeStream do
  use WebSockex

  import Logger

  alias Phoenix.PubSub

  @url "wss://stream.binance.com:9443/ws/"

  def start_link(symbol, state) do
    WebSockex.start_link("#{@url}#{symbol}@trade", __MODULE__, state)
  end

  def handle_frame({_type, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} ->
        handle_event(event)

      _ ->
        log(:error, "Something went wrong with Binance stream")
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

    PubSub.broadcast(:trade_stream, "xrp", trade)
  end
end
