defmodule Samantha.InternalSupervisor do
  use Supervisor

  def start_link(_) do
    Supervisor.start_link __MODULE__, [], name: __MODULE__
  end

  def init(_) do
    children = [
      # whatever
    ]
    supervise(children, [strategy: :one_for_one])
  end

  def start_child(child) do
    Supervisor.start_child __MODULE__, child
  end
end