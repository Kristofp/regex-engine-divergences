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
      # Elixir's `u` modifier is `[:unicode, :ucp]` (Regex.compile/2). `:unicode` is already on for every row (the
      # app's sidecar does the same: without it `:re` reads the UTF-8 text as bytes); `u` adds `:ucp`, which makes
      # `\w`, `\d`, `\b` Unicode-aware. Until task E6's fix round (2026-11-20) `u` was ignored, so
      # flag-u-unicode-word-elixir recorded "caf" with the flag on and off where real `~r/\w+/u` gives "café".
      opts = if String.contains?(flags_str, "u"), do: [:ucp | opts], else: opts
      opts = if String.contains?(flags_str, "i"), do: [:caseless | opts], else: opts
      opts = if String.contains?(flags_str, "m"), do: [:multiline | opts], else: opts
      opts = if String.contains?(flags_str, "s"), do: [:dotall | opts], else: opts
      opts = if String.contains?(flags_str, "x"), do: [:extended | opts], else: opts

      # A HARD MATCH HERE WAS THE BUG. `:re.compile` returns `{:error, reason}`
      # for an invalid pattern, which is an ordinary outcome for a fuzz corpus —
      # but `{:ok, rx} = ...` turns it into a MatchError, so the rescue clause
      # below recorded Elixir's crash dump as the "error". Measured 2026-09-11:
      # 903 of the 7,000 entries, every one reading
      # `no match of right hand side value: {:error, {~c"...` — the reason was
      # in there, wrapped in a stack-trace artifact that says nothing about the
      # pattern.
      #
      # `throw` rather than a nested case so the rest of this function keeps its
      # straight-line shape; the catch below turns it into a clean message.
      rx =
        case :re.compile(e["pattern"], opts) do
          {:ok, compiled} ->
            compiled

          {:error, {reason, at}} ->
            throw({:compile_error, "#{reason} at offset #{at}"})

          {:error, reason} ->
            throw({:compile_error, inspect(reason)})
        end

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
      :throw, {:compile_error, message} ->
        # An invalid pattern, reported in :re's own words — see the compile site.
        Map.put(acc, e["id"], %{"matches" => [], "error" => message})

      :error, reason ->
        Map.put(acc, e["id"], %{"matches" => [], "error" => inspect(reason)})
    end
  end)

IO.write(:stdio, :json.encode(results))
