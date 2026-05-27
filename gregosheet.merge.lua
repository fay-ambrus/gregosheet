gregosheet = gregosheet or {}

--- Extract leading symbols (clef + key sig) from a token list.
--- The first character of the first symbol is the clef,
--- remaining characters (same token or subsequent symbol tokens) are key sig.
---
--- @param tokens table[]  Token list (modified in place)
--- @return string clef  Clef glyph (first symbol character)
--- @return string key  Key signature chars (remaining symbols)
function gregosheet.extract_leading_symbols(tokens)
  if #tokens == 0 or tokens[1].type ~= "symbol" then
    error("Melody must start with a clef character")
  end

  local first_token = table.remove(tokens, 1)
  local clef_code = utf8.codepoint(first_token.glyph)
  local clef = utf8.char(clef_code)

  if not gregosheet.code_in_array(clef_code, gregosheet.clefs_codes) then
    error("Invalid clef character: '" .. clef .. "'")
  end

  local key = utf8.len(first_token.glyph) > 1
    and first_token.glyph:sub(utf8.offset(first_token.glyph, 2)) or ""

  gregosheet.validate_key(key)

  return clef, key
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

  local old_clef = ""
  local old_key = ""
  local first_piece = true
  local pending_comment = nil

  for _, piece in ipairs(parsed_pieces) do
    if piece.type ~= "floating_text" then
      local piece_melody_tokens = piece.melody_tokens or {}
      local clef, key = gregosheet.extract_leading_symbols(piece_melody_tokens)

      if not first_piece then
        table.insert(events, {type = "delimiter", glyph = "-", fixed = true})
      end
      first_piece = false

      table.insert(events, {
        type = "piece_boundary",
        title = piece.title or "",
        glyph = gregosheet.compute_clef_change(old_clef, clef) .. gregosheet.compute_key_signature(old_key, key),
        clef = clef,
        key = key
      })

      --table.insert(events, {type = "delimiter", glyph = "-", fixed = true})

      if pending_comment ~= nil then
        table.insert(syllables, {text = pending_comment, word_end = true, comment = true})
        table.insert(events, {type = "delimiter", glyph = "", fixed = true})
        table.insert(events, {type = "comment", syllable_idx = #syllables, width_sp = 0, glyph = ""})
      end
      pending_comment = nil

      old_clef = clef
      old_key = key

      -- Fix the leading delimiter or insert one if missing
      if #piece_melody_tokens > 0 and piece_melody_tokens[1].type == "delimiter" then
        piece_melody_tokens[1].glyph = "-"
        piece_melody_tokens[1].fixed = true
      else
        table.insert(piece_melody_tokens, 1, {type = "delimiter", glyph = "-", fixed = true})
      end

      -- Pair this piece's syllables with its notes
      local piece_syllables = piece.lyric_syllables or {}
      local syl_idx = 1

      for _, token in ipairs(piece_melody_tokens) do
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
          -- Flush comment syllables as events before the paired note
          while syl_idx <= #piece_syllables and piece_syllables[syl_idx].comment do
            table.insert(syllables, piece_syllables[syl_idx])
            if #events == 0 or events[#events].type ~= "delimiter" then
              table.insert(events, {type = "delimiter", glyph = "", fixed = true})
            end
            table.insert(events, {type = "comment", syllable_idx = #syllables, width_sp = 0, glyph = ""})
            table.insert(events, {type = "delimiter", glyph = "", fixed = true})
            syl_idx = syl_idx + 1
          end
        end

        table.insert(events, token)

        if should_pair then

          -- Pair next non-comment syllable with this event
          if syl_idx <= #piece_syllables then
            table.insert(syllables, piece_syllables[syl_idx])
            token.syllable_idx = #syllables
            syl_idx = syl_idx + 1
          else
            table.insert(syllables, {text = "", word_end = true, comment = false})
          end
        end
      end

      -- Flush remaining comment syllables at end of piece
      while syl_idx <= #piece_syllables and piece_syllables[syl_idx].comment do
        table.insert(syllables, piece_syllables[syl_idx])
        if #events == 0 or events[#events].type ~= "delimiter" then
          table.insert(events, {type = "delimiter", glyph = "", fixed = true})
        end
        table.insert(events, {type = "comment", syllable_idx = #syllables, width_sp = 0, glyph = ""})
        table.insert(events, {type = "delimiter", glyph = "", fixed = true})
        syl_idx = syl_idx + 1
      end

      -- Insert tone_group after this piece's events (if tone provided)
      if piece.tone_melody and piece.tone_melody ~= "" then
        local tone_tokens = gregosheet.parse_melody(piece.tone_melody)
        gregosheet.extract_leading_symbols(tone_tokens)
        local first_note = true
        for _, t in ipairs(tone_tokens) do
          if t.type == "delimiter" then
            t.glyph = "-"
            t.fixed = true
          end
          table.insert(events, t)
          if t.type == "note" then
            if first_note then
              table.insert(syllables, {text = piece.tone_label or "", word_end = true, tone = true})
              first_note = false
            else
              table.insert(syllables, {text = "", word_end = true, tone = true})
            end
            t.syllable_idx = #syllables
          end
        end
      end

    else
      pending_comment = piece.text
    end

    if #syllables > 0 then
      syllables[#syllables].word_end = true -- last syllable is always word end
    end
  end

  -- Debug: log all events in order
  for i, ev in ipairs(events) do
    local extra = ""
    if ev.glyph and ev.glyph ~= "" then extra = " glyph=" .. ev.glyph end
    if ev.syllable_idx then extra = extra .. " syl=" .. ev.syllable_idx end
    if ev.title and ev.title ~= "" then extra = extra .. " title=" .. ev.title end
    gregosheet.debug_print("MERGE [" .. i .. "] " .. ev.type .. extra)
  end

  return events, syllables
end
