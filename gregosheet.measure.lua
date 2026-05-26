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
    if event.type == "note" or event.type == "symbol" or event.type == "barline" then
      event.width_sp = gregosheet.measure_width_sp(event.glyph, music_fontid)
    elseif event.type == "delimiter" then
      if not event.fixed then
        event.glyph = gregosheet.std_delimiter_sequence
        event.width_sp = std_width
      else
        event.width_sp = gregosheet.measure_width_sp(event.glyph, music_fontid)
      end
    elseif event.type == "piece_boundary" then
      event.width_sp = gregosheet.measure_width_sp(event.glyph or "", music_fontid)
    elseif event.type == "title" or event.type == "floating_text" then
      event.width_sp = 0
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
