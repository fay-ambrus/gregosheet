gregosheet = gregosheet or {}

--- Extract leading symbols (clef + key sig) from a token list.
--- Consumes tokens from the front until a non-symbol is found.
---
--- @param tokens table[]  Token list (modified in place)
--- @return string glyph  Clef glyph (first symbol char(s))
--- @return string key  Key signature chars (remaining symbols)
local function extract_leading_symbols(tokens)
  local glyph = ""
  local key = ""
  local first = true

  while #tokens > 0 and tokens[1].type == "symbol" do
    if first then
      glyph = table.remove(tokens, 1).glyph
      first = false
    else
      key = key .. table.remove(tokens, 1).glyph
    end
  end

  return glyph, key
end

--- Merge multiple parsed pieces into a single event list and syllable list.
--- Syllables are paired per-piece: each piece's syllables are assigned only
--- to that piece's notes. Extra syllables are dropped; missing syllables
--- leave notes without lyrics.
--- Tone groups are inserted inline after their piece's events.
---
--- @param parsed_pieces table[]
--- @return table[] events
--- @return table[] syllables
function gregosheet.merge(parsed_pieces)
  local events = {}
  local syllables = {}

  local current_key = ""
  local first_piece = true

  for _, piece in ipairs(parsed_pieces) do
    -- Handle floating_text entries
    if piece.type == "floating_text" then
      table.insert(events, {type = "floating_text", text = piece.text})

    else
      local tokens = {}
      for _, t in ipairs(piece.melody_tokens) do
        table.insert(tokens, {type = t.type, glyph = t.glyph})
      end

      if first_piece then
        local glyph, key = extract_leading_symbols(tokens)
        current_key = key
        table.insert(events, {type = "clef", glyph = glyph, key = key})

        if piece.title and piece.title ~= "" then
          table.insert(events, {type = "title", title = piece.title})
        end

        first_piece = false
      else
        local _, new_key = extract_leading_symbols(tokens)

        table.insert(events, {type = "delimiter", glyph = "-"})

        local naturals = ""
        if new_key ~= current_key then
          naturals = gregosheet.compute_naturals(current_key, new_key)
          current_key = new_key
        end

        table.insert(events, {
          type = "piece_boundary",
          title = piece.title or "",
          new_key = new_key,
          naturals = naturals,
        })
      end

      -- Pair this piece's syllables with its notes
      local piece_syllables = piece.lyric_syllables or {}
      local syl_idx = 1

      for _, token in ipairs(tokens) do
        table.insert(events, token)

        -- Determine if this event should consume a syllable
        local should_pair = false
        if token.type == "note" then
          should_pair = true
        elseif token.type == "barline" then
          -- Barlines only consume '*': peek past comments
          local peek = syl_idx
          while peek <= #piece_syllables and piece_syllables[peek].comment do
            peek = peek + 1
          end
          if peek <= #piece_syllables and piece_syllables[peek].text == "*" then
            should_pair = true
          end
        end

        if should_pair then
          -- Flush comment syllables before the paired one
          while syl_idx <= #piece_syllables and piece_syllables[syl_idx].comment do
            table.insert(syllables, piece_syllables[syl_idx])
            syl_idx = syl_idx + 1
          end

          -- Pair next non-comment syllable with this event
          if syl_idx <= #piece_syllables and not piece_syllables[syl_idx].comment then
            table.insert(syllables, piece_syllables[syl_idx])
            token.syllable_idx = #syllables
            syl_idx = syl_idx + 1
          else
            table.insert(syllables, {text = "", word_end = true, comment = false})
            token.syllable_idx = #syllables
          end
        end
      end

      -- Flush remaining comment syllables at end of piece
      while syl_idx <= #piece_syllables and piece_syllables[syl_idx].comment do
        table.insert(syllables, piece_syllables[syl_idx])
        syl_idx = syl_idx + 1
      end

      -- Insert tone_group after this piece's events (if tone provided)
      if piece.tone_melody and piece.tone_melody ~= "" then
        local tone_tokens = gregosheet.parse_melody(piece.tone_melody)
        extract_leading_symbols(tone_tokens)
        table.insert(events, {
          type = "tone_group",
          events = tone_tokens,
          label = piece.tone_label or "",
        })
      end
    end
  end

  return events, syllables
end
