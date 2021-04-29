defmodule BB.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: :trade_stream},
      {BB.Handler, name: :bb_handler},
      {TradeStream, "xrpeur"},
      {DynamicSupervisor, strategy: :one_for_one, name: :dynamic_trade_supervisor},
      {BB.Scheduler, "xrpeur"}
    ]

    opts = [strategy: :one_for_one, name: BB.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
