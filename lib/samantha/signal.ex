defmodule Samantha.Signal do
  require Logger

  @behaviour :gen_event

  def swap_handlers do
    # Added for my sanity - probably not needed
    :os.set_signal :sighup, :handle
    :os.set_signal :sigquit, :handle
    :os.set_signal :sigabrt, :handle
    :os.set_signal :sigalrm, :handle
    :os.set_signal :sigterm, :handle
    :os.set_signal :sigusr1, :handle
    :os.set_signal :sigusr2, :handle
    :os.set_signal :sigchld, :handle
    :os.set_signal :sigstop, :handle
    :os.set_signal :sigtstp, :handle
    # Actually swap the signal handlers
    :gen_event.swap_sup_handler :erl_signal_server, {:erl_signal_handler, []}, {Samantha.Signal, []}
  end

  def init(args) do
    Logger.info "Starting samantha signal handler..."
    {:ok, args}
  end

  def handle_call(req, state) do
    Logger.warn "Unhandled call: #{inspect req, pretty: true}"
    {:ok, :ok, state}
  end

  def handle_event(:sigterm, state) do
    Logger.warn "Got SIGTERM"
    :timer.sleep 4000
    Logger.warn "Slept for 4 seconds!"
    :init.stop()
    {:ok, state}
  end

  def handle_event(event, state) do
    Logger.warn "Unhandled event: #{inspect event, pretty: true}"
    {:ok, state}
  end

  def handle_info(msg, state) do
    Logger.warn "Unhandled :info: #{inspect msg, pretty: true}"
  end

  def terminate(_, _) do
    Logger.warn "Signal handler terminating!"
  end
end