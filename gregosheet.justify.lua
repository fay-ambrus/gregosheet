gregosheet = gregosheet or {}

-- Delimiter utilities

local function get_minimal_delimiter_over_distance(distance_sp)
  local n_l = math.floor(distance_sp / gregosheet.w_l)
  local remaining = distance_sp - n_l * gregosheet.w_l

  if remaining <= 0 then
    return string.rep(gregosheet.delimiter_l, n_l + 1)
  end

  if remaining < gregosheet.w_s then
    return string.rep(gregosheet.delimiter_l, n_l) .. gregosheet.delimiter_s
  elseif remaining < gregosheet.w_m then
    if gregosheet.w_s > remaining then
      return string.rep(gregosheet.delimiter_l, n_l) .. gregosheet.delimiter_s
    else
      return string.rep(gregosheet.delimiter_l, n_l) .. gregosheet.delimiter_m
    end
  elseif remaining < gregosheet.w_l then
    if gregosheet.w_m > remaining then
      return string.rep(gregosheet.delimiter_l, n_l) .. gregosheet.delimiter_m
    elseif gregosheet.w_m + gregosheet.w_s > remaining then
      return string.rep(gregosheet.delimiter_l, n_l) .. gregosheet.delimiter_m .. gregosheet.delimiter_s
    else
      return string.rep(gregosheet.delimiter_l, n_l + 1)
    end
  end

  return string.rep(gregosheet.delimiter_l, n_l + 1)
end

local function get_maximal_delimiter_under_distance(distance_sp)
  if distance_sp <= 0 then
    return ""
  end

  local n_l = math.floor(distance_sp / gregosheet.w_l)
  local remaining = distance_sp - n_l * gregosheet.w_l
  local n_m = math.floor(remaining / gregosheet.w_m)
  remaining = remaining - n_m * gregosheet.w_m
  local n_s = math.floor(remaining / gregosheet.w_s)

  return string.rep(gregosheet.delimiter_l, n_l) .. string.rep(gregosheet.delimiter_m, n_m) .. string.rep(gregosheet.delimiter_s, n_s)
end

--- Widen a delimiter event to at least target_width_sp.
local function widen_delimiter(event, target_width_sp)
  event.glyph = get_minimal_delimiter_over_distance(target_width_sp)
  event.width_sp = gregosheet.measure_width_sp(event.glyph, gregosheet.music_fontid)
end

--- Find the last delimiter event before index `idx` (scanning backwards).
--- Stops if it hits a note.
local function find_preceding_delimiter(events, idx)
  for i = idx - 1, 1, -1 do
    if events[i].type == "delimiter" then
      return i
    elseif events[i].type == "note" then
      return nil
    end
  end
  return nil
end

--- Recompute start_sp from a given index forward up to up_to_idx.
local function recompute_positions(events, from_idx, up_to_idx)
  local cursor = events[from_idx].start_sp + events[from_idx].width_sp
  for j = from_idx + 1, up_to_idx do
    events[j].start_sp = cursor
    cursor = cursor + (events[j].width_sp or 0)
  end
  return cursor
end

--- Compute the syllable's starting x-position under a note.
local function compute_syllable_start(syl, note_event)
  local note_x = note_event.start_sp
  if syl.tone then
    return note_x
  end
  local glyph = note_event.glyph or ""
  local is_recited = glyph ~= "" and gregosheet.code_in_array(utf8.codepoint(glyph), gregosheet.recited_notes_codes or {})
  if syl.width_sp > (note_event.width_sp or 0) and not is_recited then
    return note_x + (note_event.width_sp / 2) - (syl.width_sp / 2)
  else
    return note_x
  end
end

--- Place a syllable, checking overlap with prev_syl. If overlap, widen delimiter.
--- Returns the updated music_cursor.
local function place_syllable(syl, event_idx, events, prev_syl, music_cursor)
  if not prev_syl then
    return music_cursor
  end

  local prev_end = prev_syl.start_sp + prev_syl.width_sp
  if prev_syl.word_end then
    prev_end = prev_end + gregosheet.space_width_sp
  end

  local gap = syl.start_sp - prev_end
  if gap < 0 then
    local delim_idx = find_preceding_delimiter(events, event_idx)
    if delim_idx then
      local needed = events[delim_idx].width_sp - gap
      widen_delimiter(events[delim_idx], needed)
      music_cursor = recompute_positions(events, delim_idx, event_idx)
      if events[event_idx].syllable_idx then
        syl.start_sp = compute_syllable_start(syl, events[event_idx])
      else
        syl.start_sp = events[event_idx].start_sp
      end
    end
  end

  return music_cursor
end

--- Justify events until the line overflows width_limit_sp.
--- Places syllables, resolves overlaps, widens delimiters.
--- Always starts from event 1 (break removes previous lines before calling).
---
--- @param events table[]  Measured event list
--- @param syllables table[]  Measured syllable list
--- @param width_limit_sp number  Line width limit (overflow threshold)
--- @return number overflow_idx|nil  Index of the event that overflowed (nil if everything fits)
--- @return number music_cursor  Current cursor position at end of justification
function gregosheet.justify(events, syllables, width_limit_sp)
  local prev_syl = nil
  local music_cursor = 0
  local last_clef = nil
  local last_key = nil

  -- Find first syllable index
  local next_syl_to_place = #syllables + 1
  for i = 1, #events do
    if events[i].syllable_idx then
      next_syl_to_place = events[i].syllable_idx
      break
    end
  end

  for i = 1, #events do
    local event = events[i]

    -- Enforce fixed delimiters around barlines
    if event.type == "barline" then
      if i > 1 and events[i - 1].type == "delimiter" and not events[i - 1].fixed then
        local old_w = events[i - 1].width_sp
        events[i - 1].glyph = "-"
        events[i - 1].width_sp = gregosheet.measure_width_sp("-", gregosheet.music_fontid)
        music_cursor = music_cursor + (events[i - 1].width_sp - old_w)
      end
      if i < #events and events[i + 1].type == "delimiter" and not events[i + 1].fixed then
        events[i + 1].glyph = "--"
        events[i + 1].width_sp = gregosheet.measure_width_sp("--", gregosheet.music_fontid)
      end
    end

    event.start_sp = music_cursor
    music_cursor = music_cursor + (event.width_sp or 0)

    -- Track last piece_boundary clef/key
    if event.type == "piece_boundary" then
      last_clef = event.clef
      last_key = event.key
    end

    -- Check overflow
    if music_cursor > width_limit_sp then
      return i, last_clef, last_key
    end

    if event.syllable_idx then
      -- Flush preceding comment syllables
      while next_syl_to_place < event.syllable_idx do
        local comment_syl = syllables[next_syl_to_place]
        if comment_syl.comment then
          comment_syl.start_sp = event.start_sp
          music_cursor = place_syllable(comment_syl, i, events, prev_syl, music_cursor)
          comment_syl.start_sp = event.start_sp
          prev_syl = comment_syl
        end
        next_syl_to_place = next_syl_to_place + 1
      end

      -- Place the note's syllable
      local syl = syllables[event.syllable_idx]
      syl.start_sp = compute_syllable_start(syl, event)

      -- Resolve overlap (skip for tone syllables — they extend freely)
      if not syl.tone then
        music_cursor = place_syllable(syl, i, events, prev_syl, music_cursor)
        syl.start_sp = compute_syllable_start(syl, event)
      end

      -- Check overflow (music or lyrics)
      local syl_right = syl.start_sp + syl.width_sp
      if music_cursor > width_limit_sp or syl_right > width_limit_sp then
        if syl.tone then
          syl.tone_overflow = true
        else
          return i, last_clef, last_key
        end
      end

      -- Hyphenation
      if prev_syl and not prev_syl.word_end and syl.text ~= "" then
        local gap = syl.start_sp - (prev_syl.start_sp + prev_syl.width_sp)
        if gap > gregosheet.tolerable_syllable_gap_sp then
          if gap < gregosheet.hyphen_width_sp then
            local delim_idx = find_preceding_delimiter(events, i)
            if delim_idx then
              local needed = events[delim_idx].width_sp + gregosheet.hyphen_width_sp - gap
              widen_delimiter(events[delim_idx], needed)
              music_cursor = recompute_positions(events, delim_idx, i)
              syl.start_sp = compute_syllable_start(syl, event)
            end
          end
          local hyphen_pos = (prev_syl.start_sp + prev_syl.width_sp + syl.start_sp - gregosheet.hyphen_width_sp) / 2
          local insert_at = event.syllable_idx
          table.insert(syllables, insert_at, {
            text = "-",
            start_sp = hyphen_pos,
            width_sp = gregosheet.hyphen_width_sp,
            word_end = false,
            comment = false,
            is_hyphen = true,
          })
          -- Fix up syllable_idx on all events pointing at or after insert_at
          for _, ev in ipairs(events) do
            if ev.syllable_idx and ev.syllable_idx >= insert_at then
              ev.syllable_idx = ev.syllable_idx + 1
            end
          end
        end
      end

      if syl.text ~= "" then
        prev_syl = syl
      end
      next_syl_to_place = event.syllable_idx + 1

    elseif event.type == "floating_text" then
      local syl = {
        text = event.text,
        start_sp = event.start_sp,
        width_sp = gregosheet.measure_width_sp(event.text, gregosheet.lyrics_fontid),
        word_end = true,
        comment = true,
      }
      music_cursor = place_syllable(syl, i, events, prev_syl, music_cursor)
      syl.start_sp = event.start_sp
      table.insert(syllables, syl)
      prev_syl = syl
    end
  end

  -- No overflow — everything fits
  return nil, last_clef, last_key
end
