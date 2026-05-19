gregosheet = gregosheet or {}

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

--- Pre-split recited notes whose syllables are wider than available line space.
--- Called before justify, modifies events and syllables in place.
function gregosheet.pre_split_recited(events, syllables, page_width_sp, clef_width)
  local available = page_width_sp - clef_width - gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, gregosheet.music_fontid)

  local i = 1
  while i <= #events do
    local event = events[i]
    if event.type == "note" and event.glyph:match(gregosheet.recited_notes) and event.syllable_idx then
      local syl = syllables[event.syllable_idx]
      if syl and syl.width_sp and syl.width_sp > available and syl.text:find(" ") then
        local syls_list = gregosheet.syllabify(syl.text:gsub(" ", "_"))
        if #syls_list >= 2 then
          local fit_count = 0
          local running_width = 0
          for si, s in ipairs(syls_list) do
            local w = gregosheet.measure_width_sp(s.text, gregosheet.lyrics_fontid)
            if s.word_start and si > 1 then
              w = w + gregosheet.measure_width_sp(" ", gregosheet.lyrics_fontid)
            end
            if running_width + w <= available then
              running_width = running_width + w
              fit_count = si
            else
              break
            end
          end

          if fit_count >= 1 and fit_count < #syls_list then
            local text1, text2 = "", ""
            for si, s in ipairs(syls_list) do
              if si <= fit_count then
                if text1 ~= "" and s.word_start then text1 = text1 .. " " end
                text1 = text1 .. s.text
              else
                if text2 ~= "" and s.word_start then text2 = text2 .. " " end
                text2 = text2 .. s.text
              end
            end

            local chunk2_recited = (#syls_list - fit_count) >= 4

            syl.text = text1
            syl.width_sp = gregosheet.measure_width_sp(text1, gregosheet.lyrics_fontid)
            syl.word_end = false

            local insert_pos = i + 1
            table.insert(events, insert_pos, {
              type = "delimiter",
              glyph = gregosheet.std_delimiter_sequence,
              width_sp = gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, gregosheet.music_fontid),
            })
            insert_pos = insert_pos + 1

            if chunk2_recited then
              local new_syl = {text = text2, width_sp = gregosheet.measure_width_sp(text2, gregosheet.lyrics_fontid), word_end = syl.word_end, comment = false}
              table.insert(syllables, new_syl)
              table.insert(events, insert_pos, {type = "note", glyph = event.glyph, width_sp = event.width_sp, syllable_idx = #syllables})
            else
              local normal_glyph = gregosheet.recited_to_normal[event.glyph] or event.glyph
              local normal_width = gregosheet.measure_width_sp(normal_glyph, gregosheet.music_fontid)
              for si = fit_count + 1, #syls_list do
                if si > fit_count + 1 then
                  table.insert(events, insert_pos, {type = "delimiter", glyph = "-", width_sp = gregosheet.measure_width_sp("-", gregosheet.music_fontid)})
                  insert_pos = insert_pos + 1
                end
                local s = syls_list[si]
                local is_word_end = (si == #syls_list) or (syls_list[si + 1] and syls_list[si + 1].word_start)
                local new_syl = {text = s.text, width_sp = gregosheet.measure_width_sp(s.text, gregosheet.lyrics_fontid), word_end = is_word_end, comment = false}
                table.insert(syllables, new_syl)
                table.insert(events, insert_pos, {type = "note", glyph = normal_glyph, width_sp = normal_width, syllable_idx = #syllables})
                insert_pos = insert_pos + 1
              end
            end
            -- Re-check in case chunk1 is still too wide
          else
            i = i + 1
          end
        else
          i = i + 1
        end
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end
  return events, syllables
end

--- Compute the right edge of an event on a line (relative to line start).
local function right_edge(event, syllables, line_start_abs, clef_width)
  local event_right = (event.start_sp - line_start_abs + clef_width) + (event.width_sp or 0)
  if event.syllable_idx then
    local syl = syllables[event.syllable_idx]
    if syl and syl.start_sp and syl.width_sp then
      local syl_right = (syl.start_sp - line_start_abs + clef_width) + syl.width_sp
      if syl_right > event_right then
        return syl_right
      end
    end
  end
  return event_right
end

--- Find raw break point: first event index (from start_idx) whose right_edge overflows.
--- Returns nil if nothing overflows (everything fits on one line).
local function find_overflow(events, syllables, start_idx, clef_width, page_width_sp)
  local line_start_abs = events[start_idx].start_sp
  -- Account for first delimiter removal: find its width and add to effective page width
  local first_delim_width = 0
  for j = start_idx, #events do
    if events[j].type == "delimiter" then
      first_delim_width = events[j].width_sp
      break
    end
  end
  local effective_page_width = page_width_sp + first_delim_width
  for i = start_idx, #events do
    local edge = right_edge(events[i], syllables, line_start_abs, clef_width)
    if edge > effective_page_width then
      gregosheet.debug_print("BREAK: overflow at event " .. i .. " type=" .. events[i].type .. " edge=" .. edge .. " page=" .. effective_page_width .. " line_start=" .. line_start_abs)
      return i
    end
  end
  return nil
end

--- Find the best break point by scanning backwards from overflow for last note that fits.
local function find_break_point(events, syllables, overflow_idx, start_idx, clef_width, page_width_sp)
  local line_start_abs = events[start_idx].start_sp
  -- Account for first delimiter removal
  local first_delim_width = 0
  for j = start_idx, #events do
    if events[j].type == "delimiter" then
      first_delim_width = events[j].width_sp
      break
    end
  end
  local effective_page_width = page_width_sp + first_delim_width
  for j = overflow_idx - 1, start_idx + 1, -1 do
    if events[j].type == "note" then
      local edge = right_edge(events[j], syllables, line_start_abs, clef_width)
      if edge <= effective_page_width then
        gregosheet.debug_print("BREAK: break_point at " .. (j+1) .. " (last fitting note=" .. j .. " edge=" .. edge .. ")")
        return j + 1
      end
    end
  end
  -- Nothing fits — force break at overflow
  return overflow_idx
end

------------------------------------------------------------------------
-- ADJUSTERS
-- Each takes (events, syllables, break_idx, start_idx) and returns:
--   new_break_idx, modified (boolean: whether events/syllables were changed)
------------------------------------------------------------------------

--- Adjuster: barline must not start a line.
--- If the new line would start with a barline (after delimiters), push the break
--- forward past the barline so it stays on the previous line.
--- Also pushes past any following floating_text, title, or piece_boundary events
--- that fit on the line.
local function adjust_barline(events, syllables, break_idx, start_idx)
  local first_real = break_idx
  while first_real <= #events and events[first_real].type == "delimiter" do
    first_real = first_real + 1
  end
  if first_real <= #events and events[first_real].type == "barline" then
    -- Push break past the barline and any non-note events that follow
    local new_break = first_real + 1
    while new_break <= #events do
      local t = events[new_break].type
      if t == "delimiter" or t == "floating_text" or t == "title" or t == "piece_boundary" then
        new_break = new_break + 1
      else
        break
      end
    end
    gregosheet.debug_print("BREAK: barline adjust, break moved from " .. break_idx .. " to " .. new_break)
    return new_break, false
  end
  return break_idx, false
end

--- Adjuster: title must fit on line.
local function adjust_title(events, syllables, break_idx, start_idx)
  -- Check if there's a title between start_idx and break_idx that doesn't fit
  -- (already handled by find_overflow since titles have width 0 but we check separately)
  -- For now, titles force breaks during find_overflow via their title_width check
  return break_idx, false
end

--- Adjuster: tone_group is atomic.
local function adjust_tone_group(events, syllables, break_idx, start_idx)
  if break_idx <= #events and events[break_idx].type == "tone_group" then
    -- Don't break inside a tone group — break before it
    return break_idx, false
  end
  return break_idx, false
end

--- Adjuster: split recited note if it overflows.
local function adjust_split_recited(events, syllables, break_idx, start_idx, clef_width, page_width_sp)
  -- Check if the event AT break_idx - 1 (last event on current line) or
  -- the overflowing event is a recited note that can be split
  local line_start_abs = events[start_idx].start_sp

  -- Find the recited note causing overflow: it's the event whose syllable overflows
  local recited_idx = nil
  for i = start_idx, math.min(break_idx, #events) do
    local ev = events[i]
    if ev.type == "note" and ev.glyph:match(gregosheet.recited_notes) and ev.syllable_idx then
      local syl = syllables[ev.syllable_idx]
      if syl and syl.start_sp and syl.width_sp and syl.text:find(" ") then
        local syl_right = (syl.start_sp - line_start_abs + clef_width) + syl.width_sp
        if syl_right > page_width_sp then
          recited_idx = i
          break
        end
      end
    end
  end

  if not recited_idx then
    return break_idx, false
  end

  local event = events[recited_idx]
  local syl = syllables[event.syllable_idx]

  -- Syllabify
  local syls = gregosheet.syllabify(syl.text:gsub(" ", "_"))
  if #syls < 2 then
    return break_idx, false
  end

  -- Find how many syllables fit on current line
  local note_x = event.start_sp - line_start_abs + clef_width
  local available = page_width_sp - note_x
  local fit_count = 0
  local running_width = 0
  for si, s in ipairs(syls) do
    local w = gregosheet.measure_width_sp(s.text, gregosheet.lyrics_fontid)
    if s.word_start and si > 1 then
      w = w + gregosheet.measure_width_sp(" ", gregosheet.lyrics_fontid)
    end
    if running_width + w <= available then
      running_width = running_width + w
      fit_count = si
    else
      break
    end
  end

  if fit_count < 1 or fit_count >= #syls then
    return break_idx, false
  end

  -- Build text for each chunk
  local text1 = ""
  local text2 = ""
  for si, s in ipairs(syls) do
    if si <= fit_count then
      if text1 ~= "" and s.word_start then text1 = text1 .. " " end
      text1 = text1 .. s.text
    else
      if text2 ~= "" and s.word_start then text2 = text2 .. " " end
      text2 = text2 .. s.text
    end
  end

  local chunk1_recited = fit_count >= 4
  local chunk2_recited = (#syls - fit_count) >= 4

  -- Modify the infinite line:
  -- Chunk 1: modify current event's syllable
  syl.text = text1
  syl.width_sp = gregosheet.measure_width_sp(text1, gregosheet.lyrics_fontid)
  syl.word_end = false

  -- Chunk 2: insert new events after current event
  local insert_pos = recited_idx + 1

  -- Insert a delimiter before chunk 2
  table.insert(events, insert_pos, {
    type = "delimiter",
    glyph = gregosheet.std_delimiter_sequence,
    width_sp = gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, gregosheet.music_fontid),
  })
  insert_pos = insert_pos + 1

  if chunk2_recited then
    -- Single recited note for chunk 2
    local new_syl = {text = text2, width_sp = gregosheet.measure_width_sp(text2, gregosheet.lyrics_fontid), word_end = syl.word_end, comment = false}
    table.insert(syllables, new_syl)
    local new_event = {type = "note", glyph = event.glyph, width_sp = event.width_sp, syllable_idx = #syllables}
    table.insert(events, insert_pos, new_event)
  else
    -- Expand chunk 2 into individual normal notes per syllable
    local normal_glyph = gregosheet.recited_to_normal[event.glyph] or event.glyph
    local normal_width = gregosheet.measure_width_sp(normal_glyph, gregosheet.music_fontid)
    for si = fit_count + 1, #syls do
      if si > fit_count + 1 then
        table.insert(events, insert_pos, {
          type = "delimiter",
          glyph = "-",
          width_sp = gregosheet.measure_width_sp("-", gregosheet.music_fontid),
        })
        insert_pos = insert_pos + 1
      end
      local s = syls[si]
      -- word_end: last syllable inherits original syl's word_end; others check next word_start
      local is_word_end
      if si == #syls then
        is_word_end = syl.word_end
      else
        is_word_end = syls[si + 1] and syls[si + 1].word_start
      end
      local new_syl = {text = s.text, width_sp = gregosheet.measure_width_sp(s.text, gregosheet.lyrics_fontid), word_end = is_word_end, comment = false}
      table.insert(syllables, new_syl)
      local new_event = {type = "note", glyph = normal_glyph, width_sp = normal_width, syllable_idx = #syllables}
      table.insert(events, insert_pos, new_event)
      insert_pos = insert_pos + 1
    end
  end

  -- Return break point after chunk 1 (the delimiter we inserted)
  return recited_idx + 1, true
end

------------------------------------------------------------------------
-- MAIN BREAK FUNCTION
------------------------------------------------------------------------

function gregosheet.break_into_systems(events, syllables)
  local page_width_sp = tex.dimen["textwidth"]
  local clef = events[1]
  local clef_width = clef.width_sp
  local current_key = clef.key or ""
  local clef_glyph = clef.glyph

  gregosheet.debug_print("BREAK: " .. #events .. " events, page_width=" .. page_width_sp .. " clef_width=" .. clef_width)

  local systems = {}
  local start_idx = 2  -- skip clef event

  -- Build global set of all paired syllable indices (rebuilt after each split)
  local function rebuild_paired()
    local paired = {}
    for _, ev in ipairs(events) do
      if ev.syllable_idx then paired[ev.syllable_idx] = true end
    end
    return paired
  end

  local iteration_limit = 200
  local iteration = 0

  while start_idx <= #events do
    iteration = iteration + 1
    if iteration > iteration_limit then
      texio.write_nl("ERROR: break_into_systems exceeded iteration limit")
      break
    end

    -- Find overflow
    local overflow_idx = find_overflow(events, syllables, start_idx, clef_width, page_width_sp)

    if not overflow_idx then
      -- Everything remaining fits on one line — last system
      break
    end

    -- Find initial break point
    local break_idx = find_break_point(events, syllables, overflow_idx, start_idx, clef_width, page_width_sp)

    -- Apply adjusters (order matters: barline first, then split_recited)
    break_idx = adjust_barline(events, syllables, break_idx, start_idx)

    local new_break, did_modify = adjust_split_recited(events, syllables, break_idx, start_idx, clef_width, page_width_sp)
    if did_modify then
      -- Reset delimiters from split point onward to standard width before re-justify
      local std_w = gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, gregosheet.music_fontid)
      for ri = new_break, #events do
        if events[ri].type == "delimiter" then
          events[ri].glyph = gregosheet.std_delimiter_sequence
          events[ri].width_sp = std_w
        end
      end
      -- Clear stale hyphen pseudo-syllables
      for si = 1, #syllables do
        if syllables[si].is_hyphen then
          syllables[si].text = ""
          syllables[si].width_sp = 0
          syllables[si].start_sp = nil
        end
      end
      -- Re-justify from the split point onward (reset prev_syl since it's a new line)
      gregosheet.justify(events, syllables, new_break, true)
      break_idx = new_break
    else
      break_idx = new_break
    end

    break_idx = adjust_tone_group(events, syllables, break_idx, start_idx)

    -- Safety: ensure progress
    if break_idx <= start_idx then
      break_idx = start_idx + 1
    end

    -- Emit system for events[start_idx .. break_idx - 1]
    local end_idx = break_idx - 1
    local line_offset = events[start_idx].start_sp

      local line_events = {}
      local line_titles = {}
      for j = start_idx, end_idx do
        local ev = events[j]
        if ev.type == "title" or (ev.type == "piece_boundary" and ev.title and ev.title ~= "") then
          table.insert(line_titles, {
            title = ev.title,
            start_sp = ev.start_sp - line_offset + clef_width,
          })
        end
        table.insert(line_events, ev)
      end

      -- Collect syllables for this line
      local paired_indices = {}
      for j = start_idx, end_idx do
        if events[j].syllable_idx then
          paired_indices[events[j].syllable_idx] = true
        end
      end

      local all_paired = rebuild_paired()
      local line_syllables = {}

      for idx, s in ipairs(syllables) do
        if paired_indices[idx] then
          local placed = {}
          for k, v in pairs(s) do placed[k] = v end
          if s.start_sp then
            placed.start_sp = s.start_sp - line_offset + clef_width
          else
            -- Compute from event position
            local cursor = clef_width
            for j = start_idx, end_idx do
              if events[j].syllable_idx == idx then
                placed.start_sp = cursor
                break
              end
              cursor = cursor + (events[j].width_sp or 0)
            end
            placed.start_sp = placed.start_sp or cursor
          end
          table.insert(line_syllables, placed)
        end
      end

      -- Unpaired syllables (comments, hyphens) by position
      local line_start_abs = (start_idx == 2) and 0 or events[start_idx].start_sp
      local line_end_abs = (break_idx <= #events) and events[break_idx].start_sp or math.huge
      for idx, s in ipairs(syllables) do
        if s.start_sp and not all_paired[idx] then
          if s.start_sp >= line_start_abs and s.start_sp < line_end_abs then
            local placed = {}
            for k, v in pairs(s) do placed[k] = v end
            placed.start_sp = s.start_sp - line_offset + clef_width
            table.insert(line_syllables, placed)
          end
        end
      end

      -- Remove first delimiter (clef already ends with "-")
      for j = 1, #line_events do
        if line_events[j].type == "delimiter" then
          local old_w = line_events[j].width_sp
          table.remove(line_events, j)
          if old_w ~= 0 then
            for _, s in ipairs(line_syllables) do
              s.start_sp = s.start_sp - old_w
            end
            for _, t in ipairs(line_titles) do
              t.start_sp = t.start_sp - old_w
            end
          end
          break
        end
      end

      -- Pad: append trailing delimiter
      local line_width = clef_width
      for _, ev in ipairs(line_events) do
        line_width = line_width + (ev.width_sp or 0)
      end
      local gap = page_width_sp - line_width
      if gap > 0 then
        local pad_glyph = get_maximal_delimiter_under_distance(gap)
        table.insert(line_events, {
          type = "delimiter",
          glyph = pad_glyph,
          width_sp = gregosheet.measure_width_sp(pad_glyph, gregosheet.music_fontid),
        })
      end

      table.insert(systems, {
        clef = clef,
        events = line_events,
        syllables = line_syllables,
        titles = line_titles,
      })

      -- Handle key signature at line break
      -- Check if the next line starts with (or near) a piece_boundary
      local next_boundary = nil
      for j = break_idx, math.min(break_idx + 3, #events) do
        if events[j].type == "piece_boundary" then
          next_boundary = events[j]
          break
        end
      end

      -- Update current key from any piece_boundary on this line
      local old_key = current_key
      for _, ev in ipairs(line_events) do
        if ev.type == "piece_boundary" and ev.new_key then
          current_key = ev.new_key
        end
      end

      -- Determine clef for next system
      local next_clef_key = current_key

      if next_boundary then
        local naturals = next_boundary.naturals or ""
        local new_key = next_boundary.new_key or ""

        if naturals ~= "" then
          -- Try to fit naturals at end of current line (excluding trailing pad)
          local naturals_width = gregosheet.measure_width_sp(naturals, gregosheet.music_fontid)
          local line_width = clef_width
          local pad_idx = nil
          for li = 1, #line_events do
            line_width = line_width + (line_events[li].width_sp or 0)
          end
          -- Subtract trailing pad delimiter if present
          if #line_events > 0 and line_events[#line_events].type == "delimiter" then
            line_width = line_width - line_events[#line_events].width_sp
            pad_idx = #line_events
          end
          if line_width + naturals_width <= page_width_sp then
            -- Naturals fit: insert after last barline/note with a "-" separator
            -- Find insertion point (after last barline or note)
            local insert_at = #line_events + 1
            for li = #line_events, 1, -1 do
              if line_events[li].type == "barline" or line_events[li].type == "note" then
                insert_at = li + 1
                break
              end
            end
            -- Remove trailing pad if present
            if pad_idx and pad_idx >= insert_at then
              table.remove(line_events, pad_idx)
            end
            -- Insert delimiter + naturals
            local dash_w = gregosheet.measure_width_sp("-", gregosheet.music_fontid)
            table.insert(line_events, insert_at, {type = "delimiter", glyph = "-", width_sp = dash_w})
            table.insert(line_events, insert_at + 1, {type = "symbol", glyph = naturals, width_sp = naturals_width})
            -- Re-pad to fill remaining space
            local total = clef_width
            for _, ev in ipairs(line_events) do total = total + (ev.width_sp or 0) end
            local gap = page_width_sp - total
            if gap > 0 then
              local pad_glyph = get_maximal_delimiter_under_distance(gap)
              table.insert(line_events, {type = "delimiter", glyph = pad_glyph, width_sp = gregosheet.measure_width_sp(pad_glyph, gregosheet.music_fontid)})
            end
            next_clef_key = new_key
          else
            -- Naturals don't fit on old line
            if new_key == "" then
              -- Case 4: only naturals (going to no key) — render in next clef only
              next_clef_key = naturals
            else
              -- Omit naturals, next clef has only new key
              next_clef_key = new_key
            end
          end
          -- Mark piece_boundary as handled by clef (render will skip it)
          next_boundary.keysig_in_clef = true
          next_boundary.naturals = ""
        else
          -- No naturals: next clef has the new key, mark as handled
          next_clef_key = new_key
          next_boundary.keysig_in_clef = true
        end

        current_key = new_key
      end

      -- Rebuild clef for next system
      local clef_value = clef_glyph .. next_clef_key .. "-"
      clef = {
        type = "clef",
        glyph = clef_glyph,
        key = next_clef_key,
        value = clef_value,
        width_sp = gregosheet.measure_width_sp(clef_value, gregosheet.music_fontid),
      }
      clef_width = clef.width_sp

      gregosheet.debug_print("BREAK: emit system " .. #systems .. ", events " .. start_idx .. "-" .. end_idx .. ", break_idx=" .. break_idx)
      start_idx = break_idx
  end

  -- Emit final system (remaining events that fit)
  if start_idx <= #events then
    local line_offset = events[start_idx].start_sp
    local line_events = {}
    local line_titles = {}
    for j = start_idx, #events do
      local ev = events[j]
      if ev.type == "title" or (ev.type == "piece_boundary" and ev.title and ev.title ~= "") then
        table.insert(line_titles, {
          title = ev.title,
          start_sp = ev.start_sp - line_offset + clef_width,
        })
      end
      table.insert(line_events, ev)
    end

    local paired_indices = {}
    for j = start_idx, #events do
      if events[j].syllable_idx then
        paired_indices[events[j].syllable_idx] = true
      end
    end

    local all_paired = rebuild_paired()
    local line_syllables = {}
    for idx, s in ipairs(syllables) do
      if paired_indices[idx] then
        local placed = {}
        for k, v in pairs(s) do placed[k] = v end
        if s.start_sp then
          placed.start_sp = s.start_sp - line_offset + clef_width
        else
          local cursor = clef_width
          for j = start_idx, #events do
            if events[j].syllable_idx == idx then
              placed.start_sp = cursor
              break
            end
            cursor = cursor + (events[j].width_sp or 0)
          end
          placed.start_sp = placed.start_sp or cursor
        end
        table.insert(line_syllables, placed)
      end
    end

    local line_start_abs = (start_idx == 2) and 0 or events[start_idx].start_sp
    for idx, s in ipairs(syllables) do
      if s.start_sp and not all_paired[idx] then
        if s.start_sp >= line_start_abs then
          local placed = {}
          for k, v in pairs(s) do placed[k] = v end
          placed.start_sp = s.start_sp - line_offset + clef_width
          table.insert(line_syllables, placed)
        end
      end
    end

    -- Remove first delimiter (clef already ends with "-")
    for j = 1, #line_events do
      if line_events[j].type == "delimiter" then
        local old_w = line_events[j].width_sp
        table.remove(line_events, j)
        if old_w ~= 0 then
          for _, s in ipairs(line_syllables) do
            s.start_sp = s.start_sp - old_w
          end
          for _, t in ipairs(line_titles) do
            t.start_sp = t.start_sp - old_w
          end
        end
        break
      end
    end

    table.insert(systems, {
      clef = clef,
      events = line_events,
      syllables = line_syllables,
      titles = line_titles,
    })
  end

  gregosheet.debug_print("BREAK: " .. #systems .. " systems")
  return systems
end
