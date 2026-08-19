# Elixir reference runner — Erlang :re (PCRE2) engine
# Uses only stdlib (no Jason dependency) — parses/emits JSON manually
# via Erlang's :json module (OTP 27+).
#
# stdin: JSON array of {id, pattern, testText, flags}
# stdout: JSON object of {id: {matches: [{match, index}], error}}

input = IO.read(:stdio, :eof)
entries = :json.decode(input)

results =
  Enum.reduce(entries, %{}, fn e, acc ->
    try do
      flags_str = Map.get(e, "flags", "")
      opts = [:unicode]
      opts = if String.contains?(flags_str, "i"), do: [:caseless | opts], else: opts
      opts = if String.contains?(flags_str, "m"), do: [:multiline | opts], else: opts
      opts = if String.contains?(flags_str, "s"), do: [:dotall | opts], else: opts
      opts = if String.contains?(flags_str, "x"), do: [:extended | opts], else: opts

      {:ok, rx} = :re.compile(e["pattern"], opts)

      # Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
      # and matches the bridge's behavior.
      matches =
        case :re.run(e["testText"], rx, [:global, {:capture, :first, :index}]) do
          {:match, captured} ->
            Enum.map(captured, fn [{start, len}] ->
              %{"match" => binary_part(e["testText"], start, len), "index" => start}
            end)
          :nomatch -> []
        end

      # `:null`, NOT `nil`. Erlang's :json encodes the atoms true/false/
      # null as JSON literals and every OTHER atom as a string — and
      # Elixir's `nil` is just the atom `nil`, so it serialised as the
      # string "nil". The consumer treats any truthy `error` as "the
      # reference engine failed", so all 256 working entries were skipped
      # as errors and elixir had ZERO corpus coverage while looking fine.
      Map.put(acc, e["id"], %{"matches" => matches, "error" => :null})
    rescue
      err ->
        Map.put(acc, e["id"], %{"matches" => [], "error" => Exception.message(err)})
    catch
      :error, reason ->
        Map.put(acc, e["id"], %{"matches" => [], "error" => inspect(reason)})
    end
  end)

IO.write(:stdio, :json.encode(results))
