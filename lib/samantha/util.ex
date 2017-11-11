defmodule Samantha.Util do
  def binary_payload(op, data, seq_num \\ nil, event_name \\ nil) do
    payload_base(op, data, seq_num, event_name)
    |> :erlang.term_to_binary
  end
  
  defp payload_base(op, data, seq_num, event_name) do
    payload = %{"op" => op, "d" => data}
    payload
    |> update_payload(seq_num, "s", seq_num)
    |> update_payload(event_name, "t", seq_num)
  end

  defp update_payload(payload, var, key, value) do
    if var do
      Map.put(payload, key, value)
    else
      payload
    end
  end
end