gregosheet = gregosheet or {}

------------------------------------------------------------------------
-- Pad a line to fill page width using * overlap logic.
-- Extends the break delimiter with "-" chars until the gap is <= w_star,
-- then appends "*" placed w_m from the line end.
--
-- @param break_delim_event  The delimiter event at the break point
-- @param line_width_sp      Current line width (clef + events up to break)
-- @param page_width_sp      Target page width
------------------------------------------------------------------------
function gregosheet.pad_line(break_delim_event, line_width_sp, page_width_sp)
  local gap = page_width_sp - line_width_sp
  break_delim_event.glyph = ""
  break_delim_event.width_sp = 0
  if gap > 0 then
    while gap > gregosheet.w_star do
      break_delim_event.glyph = break_delim_event.glyph .. gregosheet.delimiter_m
      gap = gap - gregosheet.w_m
    end

    break_delim_event.glyph = break_delim_event.glyph .. gregosheet.delimiter_star
    break_delim_event.width_sp = gregosheet.measure_width_sp(break_delim_event.glyph, gregosheet.music_fontid)
  end
end

------------------------------------------------------------------------
-- Find the break delimiter: scan back from overflow for the break point.
-- If overflow IS a delimiter, use it.
-- Otherwise find last delimiter before overflow.
-- Exception: delimiter immediately before a barline is skipped.
--
-- @param events       Event list
-- @param overflow_idx Index of overflowing event
-- @return number      Index of the break delimiter
------------------------------------------------------------------------
function gregosheet.find_break_delimiter(events, overflow_idx)
  local start = overflow_idx
  if events[overflow_idx].type == "delimiter" then
    start = overflow_idx
  else
    start = overflow_idx - 1
  end

  for i = start, 1, -1 do
    if events[i].type == "delimiter" then
      -- Check if this delimiter is immediately before a barline
      local next_real = i + 1
      while next_real <= #events and events[next_real].type == "delimiter" do
        next_real = next_real + 1
      end
      if next_real <= #events and events[next_real].type == "barline" then
        -- Skip this delimiter, continue scanning back
      else
        return i
      end
    end
  end
  -- Fallback: break at overflow
  return overflow_idx
end

------------------------------------------------------------------------
-- Collect syllables for a line (events 1..end_idx).
------------------------------------------------------------------------
function gregosheet.collect_line_syllables(events, syllables, end_idx)
  local line_syllables = {}

  -- Collect indices directly referenced by line events
  local referenced = {}
  for i = 1, end_idx do
    if events[i].syllable_idx then
      referenced[events[i].syllable_idx] = true
    end
  end

  -- Find range for hyphens (between first and last referenced)
  local first_idx = math.huge
  local last_idx = 0
  for idx in pairs(referenced) do
    if idx < first_idx then first_idx = idx end
    if idx > last_idx then last_idx = idx end
  end

  if last_idx == 0 then return line_syllables end

  -- Collect referenced syllables + hyphens with start_sp in range
  for i = first_idx, last_idx do
    if referenced[i] or (syllables[i].is_hyphen and syllables[i].start_sp) then
      local copy = {}
      for k, v in pairs(syllables[i]) do copy[k] = v end
      table.insert(line_syllables, copy)
    end
  end

  if #line_syllables > 0 and not line_syllables[#line_syllables].word_end then
    line_syllables[#line_syllables].text = line_syllables[#line_syllables].text .. "-"
  end

  return line_syllables
end

------------------------------------------------------------------------
-- Collect titles from events on this line.
------------------------------------------------------------------------
function gregosheet.collect_line_titles(events, end_idx)
  local titles = {}
  for i = 1, end_idx do
    local ev = events[i]
    if ev.title and ev.title ~= "" then
      table.insert(titles, {
        title = ev.title,
        start_sp = ev.start_sp or 0,
      })
    end
  end
  return titles
end

------------------------------------------------------------------------
-- Find the syllable split point for a recited note.
-- Returns fit_count, text1, text2, syls or nil if can't split.
------------------------------------------------------------------------
function gregosheet.find_recited_split_point(syl_text, available_width)
  local syls = gregosheet.syllabify(syl_text:gsub(" ", "_"))
  if #syls < 2 then return nil end

  local fit_count = 0
  local running_width = 0
  for si, s in ipairs(syls) do
    local w = gregosheet.measure_width_sp(s.text, gregosheet.lyrics_fontid)
    if s.word_start and si > 1 then
      w = w + gregosheet.space_width_sp
    end
    if running_width + w <= available_width then
      running_width = running_width + w
      fit_count = si
    else
      break
    end
  end

  if fit_count < 1 or fit_count >= #syls then return nil end

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

  -- Append hyphen if split is mid-word
  if not syls[fit_count + 1].word_start then
    text1 = text1 .. "-"
  end

  return fit_count, text1, text2, syls
end

------------------------------------------------------------------------
-- Handle recited note splitting when it overflows.
------------------------------------------------------------------------
function gregosheet.handle_recited_split(events, syllables, recited_idx, width_limit_sp)
  local event = events[recited_idx]
  local orig_syl_idx = event.syllable_idx
  local syl = syllables[orig_syl_idx]

  local note_x = event.start_sp or 0
  local available = width_limit_sp - note_x

  local fit_count, text1, text2, syls = gregosheet.find_recited_split_point(syl.text, available)
  if not fit_count then return false end

  local normal_glyph = gregosheet.recited_to_normal[event.glyph] or event.glyph
  local normal_width = gregosheet.measure_width_sp(normal_glyph, gregosheet.music_fontid)
  local chunk2_count = #syls - fit_count

  -- Modify chunk1 syllable in place (trim text)
  syl.text = text1
  syl.width_sp = gregosheet.measure_width_sp(text1, gregosheet.lyrics_fontid)
  syl.word_end = false

  -- If chunk1 < 4 syllables, expand the recited note to individual notes
  if fit_count < 4 then
    -- Replace the recited note with expanded individual notes
    table.remove(events, recited_idx)
    local insert_pos = recited_idx

    -- Replace the original syllable with first expanded syllable
    syl.text = syls[1].text
    syl.width_sp = gregosheet.measure_width_sp(syls[1].text, gregosheet.lyrics_fontid)
    syl.word_end = (fit_count == 1) and false or (syls[2] and syls[2].word_start or false)

    -- Insert first note pointing to original syllable
    table.insert(events, insert_pos, {
      type = "note", glyph = normal_glyph,
      width_sp = normal_width, syllable_idx = orig_syl_idx,
    })
    insert_pos = insert_pos + 1

    -- Insert remaining chunk1 syllables (2..fit_count) right after orig_syl_idx
    for si = 2, fit_count do
      table.insert(events, insert_pos, {
        type = "delimiter", glyph = gregosheet.std_delimiter_sequence,
        width_sp = gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, gregosheet.music_fontid),
      })
      insert_pos = insert_pos + 1

      local is_word_end = (si == fit_count) and false or (syls[si + 1] and syls[si + 1].word_start or false)
      local new_syl_idx = orig_syl_idx + si - 1
      table.insert(syllables, new_syl_idx, {
        text = syls[si].text,
        width_sp = gregosheet.measure_width_sp(syls[si].text, gregosheet.lyrics_fontid),
        word_end = is_word_end,
        comment = false,
      })
      -- Fix syllable_idx for all events pointing >= new_syl_idx
      for _, ev in ipairs(events) do
        if ev.syllable_idx and ev.syllable_idx >= new_syl_idx and ev ~= events[insert_pos] then
          ev.syllable_idx = ev.syllable_idx + 1
        end
      end
      table.insert(events, insert_pos, {
        type = "note", glyph = normal_glyph,
        width_sp = normal_width, syllable_idx = new_syl_idx,
      })
      insert_pos = insert_pos + 1
    end
  end

  -- Insert chunk2 after chunk1
  -- Find the position right after chunk1's last event
  local chunk2_pos = recited_idx + 1
  if fit_count < 4 then
    -- chunk1 was expanded: skip past all the expanded events
    chunk2_pos = recited_idx + fit_count * 2 - 1  -- notes + delimiters
  end

  -- Insert break delimiter
  table.insert(events, chunk2_pos, {
    type = "delimiter", glyph = gregosheet.std_delimiter_sequence,
    width_sp = gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, gregosheet.music_fontid),
  })
  chunk2_pos = chunk2_pos + 1

  -- Insert chunk2 syllable(s) right after chunk1's syllables
  local chunk2_syl_start = orig_syl_idx + 1
  if fit_count < 4 then
    chunk2_syl_start = orig_syl_idx + fit_count
  end
  if chunk2_count >= 4 then
    -- Single recited note for chunk2
    table.insert(syllables, chunk2_syl_start, {
      text = text2,
      width_sp = gregosheet.measure_width_sp(text2, gregosheet.lyrics_fontid),
      word_end = true,
      comment = false,
    })
    -- Fix syllable_idx for events pointing >= chunk2_syl_start
    for _, ev in ipairs(events) do
      if ev.syllable_idx and ev.syllable_idx >= chunk2_syl_start then
        ev.syllable_idx = ev.syllable_idx + 1
      end
    end
    table.insert(events, chunk2_pos, {
      type = "note", glyph = event.glyph,
      width_sp = event.width_sp, syllable_idx = chunk2_syl_start,
    })
  else
    -- Expand chunk2 to individual notes
    for si = fit_count + 1, #syls do
      if si > fit_count + 1 then
        table.insert(events, chunk2_pos, {
          type = "delimiter", glyph = gregosheet.std_delimiter_sequence,
          width_sp = gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, gregosheet.music_fontid),
        })
        chunk2_pos = chunk2_pos + 1
      end
      local is_word_end = (si == #syls) or (syls[si + 1] and syls[si + 1].word_start or false)
      local syl_insert_idx = chunk2_syl_start + (si - fit_count - 1)
      table.insert(syllables, syl_insert_idx, {
        text = syls[si].text,
        width_sp = gregosheet.measure_width_sp(syls[si].text, gregosheet.lyrics_fontid),
        word_end = is_word_end,
        comment = false,
      })
      -- Fix syllable_idx for events pointing >= syl_insert_idx
      for _, ev in ipairs(events) do
        if ev.syllable_idx and ev.syllable_idx >= syl_insert_idx then
          ev.syllable_idx = ev.syllable_idx + 1
        end
      end
      table.insert(events, chunk2_pos, {
        type = "note", glyph = normal_glyph,
        width_sp = normal_width, syllable_idx = syl_insert_idx,
      })
      chunk2_pos = chunk2_pos + 1
    end
  end

  return true
end

------------------------------------------------------------------------
-- Main break loop.
------------------------------------------------------------------------
function gregosheet.break_into_systems(events, syllables)
  local page_width_sp = tex.dimen["textwidth"]
  local systems = {}

  local iteration_limit = 200
  local iteration = 0

  while #events > 0 do
    iteration = iteration + 1
    if iteration > iteration_limit then
      texio.write_nl("ERROR: break_into_systems exceeded iteration limit")
      break
    end

    -- Step 1: justify until overflow
    local overflow_idx, last_clef, last_key = gregosheet.justify(events, syllables, page_width_sp)

    if not overflow_idx then
      -- Everything fits — emit last line (no padding)
      table.insert(systems, {
        events = events,
        syllables = gregosheet.collect_line_syllables(events, syllables, #events),
        titles = gregosheet.collect_line_titles(events, #events),
      })
      break
    end

    -- Step 2: handle recited note overflow
    local overflow_event = events[overflow_idx]
    -- Step 2a: handle tone text overflow (split text only, never break notes)
    -- Step 2: handle recited note overflow (tone overflow handled as post-break fixup)
    if overflow_event.type == "note"
      and overflow_event.syllable_idx
      and overflow_event.glyph:match(gregosheet.recited_notes)
    then
      local syl = syllables[overflow_event.syllable_idx]
      if syl and syl.text then
        gregosheet.debug_print("SPLIT BEFORE: overflow_idx=" .. overflow_idx .. " text='" .. syl.text .. "'")
        for i, ev in ipairs(events) do
          gregosheet.debug_print("  ev[" .. i .. "] " .. ev.type .. " glyph=" .. (ev.glyph or "") .. " syl_idx=" .. tostring(ev.syllable_idx or ""))
        end
        local handled = gregosheet.handle_recited_split(
          events, syllables, overflow_idx, page_width_sp
        )
        gregosheet.debug_print("SPLIT AFTER: handled=" .. tostring(handled))
        for i, ev in ipairs(events) do
          gregosheet.debug_print("  ev[" .. i .. "] " .. ev.type .. " glyph=" .. (ev.glyph or "") .. " syl_idx=" .. tostring(ev.syllable_idx or ""))
        end
        for i, s in ipairs(syllables) do
          gregosheet.debug_print("  syl[" .. i .. "] '" .. (s.text or "") .. "' start_sp=" .. tostring(s.start_sp))
        end
        if handled then
          for _, ev in ipairs(events) do ev.start_sp = nil end
          for _, s in ipairs(syllables) do s.start_sp = nil end
          overflow_idx, last_clef, last_key = gregosheet.justify(events, syllables, page_width_sp)
          if not overflow_idx then
            table.insert(systems, {
              events = events,
              syllables = gregosheet.collect_line_syllables(events, syllables, #events),
              titles = gregosheet.collect_line_titles(events, #events),
            })
            break
          end
        end
      end
    end

    -- Step 3: find break delimiter
    local break_idx = gregosheet.find_break_delimiter(events, overflow_idx)

    -- Safety: ensure progress
    if break_idx < 1 then break_idx = 1 end

    -- Step 4: emit the line (events 1..break_idx-1, break delimiter becomes trailing pad)
    local end_idx = break_idx - 1
    if end_idx < 1 then
      end_idx = 1
      break_idx = 2
    end

    -- Post-break fixup: split overflowing tone texts
    for i = 1, end_idx do
      if events[i].syllable_idx then
        local syl = syllables[events[i].syllable_idx]
        if syl and syl.tone_overflow then
          local note_x = events[i].start_sp or 0
          local available = page_width_sp - note_x
          local fit_count, text1, text2 = gregosheet.find_recited_split_point(syl.text, available)
          if fit_count then
            syl.text = text1
            syl.width_sp = gregosheet.measure_width_sp(text1, gregosheet.lyrics_fontid)
            syl.tone_overflow = nil
            -- Find first tone note after break_idx and put text2 on it
            local target_idx = break_idx
            if events[target_idx] and events[target_idx].type == "delimiter" then
              target_idx = target_idx + 1
            end
            for j = target_idx, #events do
              if events[j].type == "note" and events[j].syllable_idx then
                local next_syl = syllables[events[j].syllable_idx]
                if next_syl and next_syl.tone and next_syl.text == "" then
                  next_syl.text = text2
                  next_syl.width_sp = gregosheet.measure_width_sp(text2, gregosheet.lyrics_fontid)
                  break
                end
              end
            end
          end
        end
      end
    end

    -- Post-break fixup: split overflowing titles
    for i = 1, end_idx do
      local ev = events[i]
      if ev.type == "piece_boundary" and ev.title and ev.title ~= "" then
        local title_start = ev.start_sp or 0
        local title_width = gregosheet.measure_width_sp(ev.title, gregosheet.lyrics_fontid)
        if title_start + title_width > page_width_sp then
          local available = page_width_sp - title_start
          local fit_count, text1, text2 = gregosheet.find_recited_split_point(ev.title, available)
          if fit_count then
            ev.title = text1
            -- Put text2 on the first event after break_idx (next line's first token)
            local target = break_idx + 1
            if target <= #events then
              if not events[target].title or events[target].title == "" then
                events[target].title = text2
              end
            end
          else
            -- Can't split — move whole title to next line
            local target = break_idx + 1
            if target <= #events then
              if not events[target].title or events[target].title == "" then
                events[target].title = ev.title
              end
            end
            ev.title = ""
          end
        end
      end
    end

    -- Compute line width
    local line_width = 0
    for i = 1, end_idx do
      line_width = line_width + (events[i].width_sp or 0)
    end

    -- The break delimiter itself becomes the trailing pad
    local break_delim = events[break_idx]
    gregosheet.pad_line(break_delim, line_width, page_width_sp)

    -- Build line events (1..end_idx + the padded break delimiter)
    local line_events = {}
    for i = 1, end_idx do
      table.insert(line_events, events[i])
    end
    table.insert(line_events, break_delim)

    table.insert(systems, {
      events = line_events,
      syllables = gregosheet.collect_line_syllables(events, syllables, end_idx),
      titles = gregosheet.collect_line_titles(events, end_idx),
    })

    -- Step 5: remove emitted events + break delimiter from the list
    for i = 1, break_idx do
      table.remove(events, 1)
    end

    -- Step 6: if next line doesn't start with a piece_boundary, prepend one
    if #events == 0 then break end
    if events[1].type ~= "piece_boundary" then
      local new_glyph = (last_clef or "") .. (last_key or "") .. "-"
      table.insert(events, 1, {
        type = "piece_boundary",
        title = "",
        glyph = new_glyph,
        clef = last_clef or "",
        key = last_key or "",
        width_sp = gregosheet.measure_width_sp(new_glyph, gregosheet.music_fontid),
      })
    end

    -- Reset start_sp on remaining events and their syllables
    for _, ev in ipairs(events) do
      ev.start_sp = nil
      if ev.syllable_idx and syllables[ev.syllable_idx] then
        syllables[ev.syllable_idx].start_sp = nil
      end
    end
  end

  return systems
end
