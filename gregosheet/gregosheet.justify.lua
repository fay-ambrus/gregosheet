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

--- Recompute start_sp and music_cursor from a given index forward.
local function recompute_positions(events, from_idx, up_to_idx)
  local cursor = events[from_idx].start_sp + events[from_idx].width_sp
  for j = from_idx + 1, up_to_idx do
    events[j].start_sp = cursor
    cursor = cursor + (events[j].width_sp or 0)
  end
  return cursor
end

--- Compute the syllable's starting x-position under a note.
local function compute_syllable_start(syl, note_event, note_x)
  if syl.width_sp > note_event.width_sp and not note_event.glyph:match(gregosheet.recited_notes) then
    return note_x + (note_event.width_sp / 2) - (syl.width_sp / 2)
  else
    return note_x
  end
end

--- Place a syllable, checking overlap with prev_syl. If overlap, widen delimiter.
--- Returns the updated music_cursor.
local function place_syllable(syl, event_idx, events, prev_syl, space_width_sp, music_cursor)
  if not prev_syl then
    return music_cursor
  end

  local prev_end = prev_syl.start_sp + prev_syl.width_sp
  if prev_syl.word_end then
    prev_end = prev_end + space_width_sp
  end

  local gap = syl.start_sp - prev_end
  if gap < 0 then
    local delim_idx = find_preceding_delimiter(events, event_idx)
    if delim_idx then
      local needed = events[delim_idx].width_sp - gap
      widen_delimiter(events[delim_idx], needed)
      music_cursor = recompute_positions(events, delim_idx, event_idx)
      -- Recompute syllable position after widening
      if events[event_idx].syllable_idx then
        syl.start_sp = compute_syllable_start(syl, events[event_idx], events[event_idx].start_sp)
      else
        syl.start_sp = events[event_idx].start_sp
      end
    end
  end

  return music_cursor
end

--- Justify the event stream on an infinite-width line.
---
--- @param events table[]  Measured event list (note events have .syllable_idx)
--- @param syllables table[]  Measured syllable list (comments interleaved)
--- @return table[]  events (with adjusted delimiter widths)
--- @return table[]  syllables (with start_sp assigned, hyphens may be inserted)
function gregosheet.justify(events, syllables)
  local space_width_sp = gregosheet.measure_width_sp(" ", gregosheet.lyrics_fontid)
  local hyphen_width_sp = gregosheet.measure_width_sp("-", gregosheet.lyrics_fontid)

  local music_cursor = 0
  local prev_syl = nil  -- last placed syllable (for overlap detection)
  local next_syl_to_place = 1  -- index into syllables for unplaced comments

  gregosheet.debug_print("JUSTIFY: " .. #events .. " events, " .. #syllables .. " syllables")

  for i, event in ipairs(events) do
    event.start_sp = music_cursor
    music_cursor = music_cursor + (event.width_sp or 0)

    gregosheet.debug_print("JUSTIFY: [" .. i .. "] type=" .. event.type .. " glyph=" .. (event.glyph or "") .. " w=" .. (event.width_sp or 0) .. " cursor=" .. music_cursor .. " syl_idx=" .. (event.syllable_idx or "-"))

    if event.syllable_idx then
      -- Before placing this note's syllable, place any preceding comment syllables
      while next_syl_to_place < event.syllable_idx do
        local comment_syl = syllables[next_syl_to_place]
        if comment_syl.comment then
          comment_syl.start_sp = event.start_sp
          music_cursor = place_syllable(comment_syl, i, events, prev_syl, space_width_sp, music_cursor)
          if prev_syl then
            comment_syl.start_sp = event.start_sp
          end
          prev_syl = comment_syl
          gregosheet.debug_print("JUSTIFY:   comment '" .. comment_syl.text .. "' at " .. comment_syl.start_sp)
        end
        next_syl_to_place = next_syl_to_place + 1
      end

      -- Place the note's syllable
      local syl = syllables[event.syllable_idx]
      syl.start_sp = compute_syllable_start(syl, event, event.start_sp)

      -- Resolve overlap
      music_cursor = place_syllable(syl, i, events, prev_syl, space_width_sp, music_cursor)
      -- Recompute after potential widening
      syl.start_sp = compute_syllable_start(syl, event, event.start_sp)

      gregosheet.debug_print("JUSTIFY:   syl[" .. event.syllable_idx .. "] '" .. syl.text .. "' at " .. syl.start_sp .. " w=" .. syl.width_sp)

      -- Hyphenation
      if prev_syl and not prev_syl.word_end and syl.text ~= "" then
        local gap = syl.start_sp - (prev_syl.start_sp + prev_syl.width_sp)

        if gap > gregosheet.tolerable_syllable_gap_sp then
          if gap < hyphen_width_sp then
            local delim_idx = find_preceding_delimiter(events, i)
            if delim_idx then
              local needed = events[delim_idx].width_sp + hyphen_width_sp - gap
              widen_delimiter(events[delim_idx], needed)
              music_cursor = recompute_positions(events, delim_idx, i)
              syl.start_sp = compute_syllable_start(syl, event, event.start_sp)
            end
          end

          local hyphen_pos = (prev_syl.start_sp + prev_syl.width_sp + syl.start_sp - hyphen_width_sp) / 2
          table.insert(syllables, {
            text = "-",
            start_sp = hyphen_pos,
            width_sp = hyphen_width_sp,
            word_end = false,
            comment = false,
            is_hyphen = true,
          })
        end
      end

      if syl.text ~= "" then
        prev_syl = syl
      end
      next_syl_to_place = event.syllable_idx + 1

    elseif event.type == "floating_text" then
      -- \addtext: place as comment syllable at current position
      local syl = {
        text = event.text,
        start_sp = event.start_sp,
        width_sp = gregosheet.measure_width_sp(event.text, gregosheet.lyrics_fontid),
        word_end = true,
        comment = true,
      }
      -- Resolve overlap
      music_cursor = place_syllable(syl, i, events, prev_syl, space_width_sp, music_cursor)
      syl.start_sp = event.start_sp
      table.insert(syllables, syl)
      prev_syl = syl
    end
  end

  -- Place any remaining comment syllables at end
  while next_syl_to_place <= #syllables do
    local syl = syllables[next_syl_to_place]
    if syl.comment and not syl.start_sp then
      syl.start_sp = music_cursor
    end
    next_syl_to_place = next_syl_to_place + 1
  end

  return events, syllables
end
