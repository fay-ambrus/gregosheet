gregosheet = gregosheet or {}

--- Measure text width in scaled points using LuaTeX font metrics.
---
--- @param text string
--- @param fontid number  LuaTeX font ID
--- @return number  Width in scaled points (sp)
function gregosheet.measure_width_sp(text, fontid)
  if not text or text == "" then return 0 end

  local head, last

  for _, c in utf8.codes(text) do
    local g = node.new("glyph")
    g.font = fontid
    g.char = c
    if not head then
      head = g
    else
      last.next = g
      g.prev = last
    end
    last = g
  end

  return node.hpack(head).width
end

--- Attach width_sp to every event in the event list.
---
--- @param events table[]  Event list from merge step
function gregosheet.measure_events(events)
  local music_fontid = gregosheet.music_fontid
  local std_width = gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, music_fontid)

  for _, event in ipairs(events) do
    if event.type == "note" or event.type == "symbol" or event.type == "barline" or event.type == "delimiter" then
      event.width_sp = gregosheet.measure_width_sp(event.glyph, music_fontid)
    elseif event.type == "clef" then
      event.value = event.glyph .. (event.key or "") .. "-"
      event.width_sp = gregosheet.measure_width_sp(event.value, music_fontid)
    elseif event.type == "tone_group" then
      -- Measure sub-events with tight "-" delimiters
      local total = 0
      for i, sub in ipairs(event.events) do
        sub.width_sp = gregosheet.measure_width_sp(sub.glyph, music_fontid)
        total = total + sub.width_sp
        if i < #event.events then
          total = total + gregosheet.w_m  -- tight "-" delimiter
        end
      end
      event.width_sp = total
    elseif event.type == "piece_boundary" then
      -- Naturals have width if present
      event.width_sp = gregosheet.measure_width_sp(event.naturals or "", music_fontid)
    elseif event.type == "title" or event.type == "floating_text" then
      event.width_sp = 0  -- titles/floating text don't consume horizontal music space
    end
  end
end

--- Attach width_sp to every syllable in the syllable list.
---
--- @param syllables table[]  Syllable list from merge step
function gregosheet.measure_syllables(syllables)
  local lyrics_fontid = gregosheet.lyrics_fontid
  for _, syl in ipairs(syllables) do
    syl.width_sp = gregosheet.measure_width_sp(syl.text, lyrics_fontid)
  end
end
