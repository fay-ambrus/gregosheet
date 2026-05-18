gregosheet = gregosheet or {}

--- Main entry point. Called from gregosheet.sty via Lua.
--- Orchestrates the full pipeline: parse → merge → measure → justify → break → render.
---
--- @param pieces table[]  Each: {melody, lyrics, tone_melody?, tone_label?, title}
---                         or {type="floating_text", text=string}
function gregosheet.main(pieces)

  -- 1. Parse each piece's melody and lyrics (pure, no font)
  gregosheet.init_codes()
  local parsed_pieces = {}
  for _, piece in ipairs(pieces) do
    if piece.type == "floating_text" then
      table.insert(parsed_pieces, piece)
    else
      table.insert(parsed_pieces, {
        melody_tokens = gregosheet.parse_melody(piece.melody),
        lyric_syllables = gregosheet.parse_lyrics(piece.lyrics),
        tone_melody = piece.tone_melody or nil,
        tone_label = piece.tone_label or nil,
        title = piece.title or "",
      })
    end
  end

  -- 2. Merge into single event list + syllable list
  --    (tone_groups are inline events in the stream)
  local events, syllables = gregosheet.merge(parsed_pieces)

  -- 3. Measure (attach width_sp to events and syllables)
  gregosheet.init_delimiter_widths()
  gregosheet.measure_events(events)
  gregosheet.measure_syllables(syllables)

  -- 4. Justify on infinite line (resolve overlaps, widen delimiters, place lyrics)
  events, syllables = gregosheet.justify(events, syllables)

  -- 5. Break into systems (greedy line-breaking, pad interior lines)
  local systems = gregosheet.break_into_systems(events, syllables)

  -- 6. Render to TeX
  gregosheet.render(systems)
end
