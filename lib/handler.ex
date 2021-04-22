defmodule BB.Handler do
  use GenServer

  alias Phoenix.PubSub

  @impl true
  def init(_state) do
    {:ok, PubSub.subscribe(:trade_stream, "xrp")}
  end

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [])
  end

  @impl true
  def handle_info(msg, state) do
    IO.inspect(msg)
    {:noreply, state}
  end
end
