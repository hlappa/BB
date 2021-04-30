defmodule Trader do
  use GenServer, restart: :temporary

  require Logger

  def start_link(%Trader.Opts{} = opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(%Trader.Opts{} = opts) do
    state = %{
      opts: opts,
      buy_order_id: nil,
      buy_order_timestamp: nil,
      sell_order_id: nil,
      sell_order_timestamp: nil,
      stop_loss_order_id: nil,
      stop_loss_order_timestamp: nil,
      stop_loss: false
    }

    send(self(), :execute_buy)

    {:ok, state}
  end

  @impl true
  def handle_info(:trigger_stop_loss, state) do
    Logger.info("Triggering stop-loss!")
    {:noreply, %{state | stop_loss: true}}
  end

  @impl true
  def handle_info(:end_stop_loss, state) do
    Logger.info("Ending stop-loss phase!")
    {:noreply, %{state | stop_loss: false}}
  end

  @impl true
  def handle_info({:ssl_closed, _}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:execute_buy, state) do
    with {:ok, order} <-
           Binance.order_limit_buy(state.opts.symbol, state.opts.quantity, state.opts.price) do
      Logger.info(
        "Buy order placed for #{order.symbol}@#{order.price} with quantity of #{
          state.opts.quantity
        }"
      )

      Process.sleep(6000)

      send(self(), :monitor_buy_order)

      {:noreply,
       %{
         state
         | buy_order_id: order.order_id,
           buy_order_timestamp: order.transact_time
       }}
    else
      {:error, reason} ->
        Logger.error("Buy order failed: #{reason}")
        {:noreply, state, {:stop, "Buy order failed"}}
    end
  end

  @impl true
  def handle_info(:monitor_buy_order, state) do
    with {:ok, order} <-
           Binance.get_order(state.opts.symbol, state.buy_order_timestamp, state.buy_order_id) do
      case order.status do
        "FILLED" ->
          Logger.info(
            "Buy order filled for #{order.symbol}@#{order.price} with quantity of #{
              state.opts.quantity
            }"
          )

          send(self(), :execute_sell)

          {:noreply, state}

        _ ->
          Process.sleep(500)
          send(self(), :monitor_buy_order)
          {:noreply, state}
      end
    else
      {:error, reason} ->
        Logger.error("Order monitoring error:#{reason}")
        Process.sleep(500)
        {:noreply, state, {:continue, :monitor_buy_order}}
    end
  end

  @impl true
  def handle_info(:execute_sell, state) do
    sell_price = calculate_sell_price(state.opts.price, state.opts.profit, state.opts.tick_size)

    with {:ok, order} <-
           Binance.order_limit_sell(state.opts.symbol, state.opts.quantity, sell_price) do
      Logger.info(
        "Sell order placed for #{order.symbol}@#{order.price} with quantity of #{
          state.opts.quantity
        }"
      )

      Process.sleep(6000)

      send(self(), :monitor_sell_order)

      {:noreply,
       %{state | sell_order_id: order.order_id, sell_order_timestamp: order.transact_time}}
    else
      {:error, reason} -> Logger.error("Sell order failed: #{reason}")
    end
  end

  @impl true
  def handle_info(:monitor_sell_order, state) do
    Process.sleep(500)

    case state.stop_loss do
      true ->
        with {:ok, _resp} <-
               Binance.cancel_order(
                 state.opts.symbol,
                 state.sell_order_timestamp,
                 state.sell_order_id
               ),
             {:ok, order} <- Binance.order_market_sell(state.opts.symbol, state.opts.quantity) do
          Logger.info("Sell order cancelled and stop-loss in progress...")
          Process.send(state.handler_pid, {:halt_trading}, [])

          send(self(), :monitor_stop_loss_order)

          {:noreply,
           %{
             state
             | stop_loss_order_id: order.order_id,
               stop_loss_order_timestamp: order.transact_time
           }}
        else
          {:error, reason} ->
            Logger.error("Could not execute stop-loss: #{reason}")
            send(self(), :monitor_sell_order)
            {:noreply, state}
        end

      false ->
        with {:ok, order} <-
               Binance.get_order(
                 state.opts.symbol,
                 state.sell_order_timestamp,
                 state.sell_order_id
               ) do
          case order.status do
            "FILLED" ->
              Logger.info(
                "Sell order filled for #{order.symbol}@#{order.price} with quantity of #{
                  state.opts.quantity
                }"
              )

              Logger.info("Trading cycle completed. Terminating trader!")

              {:stop, {:shutdown, :trade_finished}, state}

            _ ->
              Process.sleep(500)
              send(self(), :monitor_sell_order)
              {:noreply, state}
          end
        else
          {:error, reason} ->
            Logger.error("Order monitoring error:#{reason}")
            send(self(), :monitor_sell_order)
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(:monitor_stop_loss_order, state) do
    with {:ok, order} <-
           Binance.get_order(
             state.opts.symbol,
             state.stop_loss_order_timestamp,
             state.stop_loss_order_id
           ) do
      case order.status do
        "FILLED" ->
          Logger.info("Stop-loss fulfilled. Trading cycle completed.")
          {:stop, {:shutdown, :trade_finished}, state}

        _ ->
          Process.sleep(500)
          send(self(), :monitor_stop_loss_order)
          {:noreply, state}
      end
    else
      {:error, reason} ->
        Logger.error("Order monitoring error: #{reason}")
        Process.sleep(500)
        send(self(), :monitor_stop_loss_order)
        {:noreply, state}
    end
  end

  defp calculate_sell_price(price, profit, tick) do
    fee = Decimal.cast(1.001) |> elem(1)
    buy_price = Decimal.cast(price) |> elem(1)

    original_net_price = Decimal.mult(buy_price, fee)
    net_target = Decimal.mult(original_net_price, profit)
    gross_target = Decimal.mult(net_target, fee)

    Decimal.div_int(gross_target, tick) |> Decimal.mult(tick) |> Decimal.to_float()
  end
end
