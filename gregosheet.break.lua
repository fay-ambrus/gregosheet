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
  local first_syllable_idx = math.huge
  local last_syllable_idx = 0

  for i = 1, end_idx do
    if events[i].syllable_idx then
      if events[i].syllable_idx < first_syllable_idx then
        first_syllable_idx = events[i].syllable_idx
      end
      if events[i].syllable_idx > last_syllable_idx then
        last_syllable_idx = events[i].syllable_idx
      end
    end
  end

  if last_syllable_idx == 0 then return line_syllables end

  for i = first_syllable_idx, last_syllable_idx do
    local copy = {}
    for k, v in pairs(syllables[i]) do copy[k] = v end
    table.insert(line_syllables, copy)
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
    if ev.type == "piece_boundary" and ev.title and ev.title ~= "" then
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

  return fit_count, text1, text2, syls
end

------------------------------------------------------------------------
-- Handle recited note splitting when it overflows.
------------------------------------------------------------------------
function gregosheet.handle_recited_split(events, syllables, recited_idx, width_limit_sp)
  local event = events[recited_idx]
  local syl = syllables[event.syllable_idx]

  local note_x = event.start_sp or 0
  local available = width_limit_sp - note_x

  local fit_count, text1, text2, syls = gregosheet.find_recited_split_point(syl.text, available)
  if not fit_count then return false end

  local normal_glyph = gregosheet.recited_to_normal[event.glyph] or event.glyph
  local normal_width = gregosheet.measure_width_sp(normal_glyph, gregosheet.music_fontid)

  -- Handle chunk1
  local chunk1_end = recited_idx  -- will be updated if expanded
  if fit_count >= 4 then
    syl.text = text1
    syl.width_sp = gregosheet.measure_width_sp(text1, gregosheet.lyrics_fontid)
    syl.word_end = false
  else
    -- Expand chunk1 to individual notes
    table.remove(events, recited_idx)
    local insert_pos = recited_idx
    for si = 1, fit_count do
      if si > 1 then
        table.insert(events, insert_pos, {
          type = "delimiter", glyph = "-",
          width_sp = gregosheet.measure_width_sp("-", gregosheet.music_fontid),
        })
        insert_pos = insert_pos + 1
      end
      local is_word_end = (si == fit_count) and false or (syls[si + 1] and syls[si + 1].word_start or false)
      table.insert(syllables, {
        text = syls[si].text,
        width_sp = gregosheet.measure_width_sp(syls[si].text, gregosheet.lyrics_fontid),
        word_end = is_word_end,
        comment = false,
      })
      table.insert(events, insert_pos, {
        type = "note", glyph = normal_glyph,
        width_sp = normal_width, syllable_idx = #syllables,
      })
      insert_pos = insert_pos + 1
    end

    -- Remove the original syllable
    local orig_syl_idx = event.syllable_idx
    table.remove(syllables, orig_syl_idx)
    for _, ev in ipairs(events) do
      if ev.syllable_idx and ev.syllable_idx > orig_syl_idx then
        ev.syllable_idx = ev.syllable_idx - 1
      end
    end

    -- Re-justify to see how many expanded notes actually fit
    for _, ev in ipairs(events) do ev.start_sp = nil end
    for _, s in ipairs(syllables) do s.start_sp = nil end
    local new_overflow = gregosheet.justify(events, syllables, width_limit_sp)

    if new_overflow then
      -- Move overflowing expanded notes back to chunk2
      local moved_back = 0
      for i = new_overflow, insert_pos - 1 do
        if i <= #events and events[i].type == "note" and events[i].glyph == normal_glyph then
          moved_back = moved_back + 1
        end
      end
      if moved_back > 0 then
        fit_count = fit_count - moved_back
        text2 = ""
        for si = fit_count + 1, #syls do
          if text2 ~= "" and syls[si].word_start then text2 = text2 .. " " end
          text2 = text2 .. syls[si].text
        end
        for i = 1, moved_back do
          if new_overflow <= #events then
            local ev = events[new_overflow]
            if ev.syllable_idx then
              table.remove(syllables, ev.syllable_idx)
              for _, e2 in ipairs(events) do
                if e2.syllable_idx and e2.syllable_idx > ev.syllable_idx then
                  e2.syllable_idx = e2.syllable_idx - 1
                end
              end
            end
            table.remove(events, new_overflow)
          end
          if new_overflow > 1 and events[new_overflow - 1] and events[new_overflow - 1].type == "delimiter" then
            table.remove(events, new_overflow - 1)
            new_overflow = new_overflow - 1
          end
        end
      end
    end
    -- After expansion (and possible move-back), find last chunk1 event
    chunk1_end = recited_idx
    for i = recited_idx, #events do
      if events[i].type == "note" and events[i].glyph == normal_glyph then
        chunk1_end = i
      elseif events[i].type ~= "delimiter" then
        break
      end
    end
  end

  -- Handle chunk2
  local chunk2_count = #syls - fit_count
  local chunk2_insert_pos = chunk1_end + 1

  table.insert(events, chunk2_insert_pos, {
    type = "delimiter", glyph = gregosheet.std_delimiter_sequence,
    width_sp = gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, gregosheet.music_fontid),
  })
  chunk2_insert_pos = chunk2_insert_pos + 1

  if chunk2_count >= 4 then
    table.insert(syllables, {
      text = text2,
      width_sp = gregosheet.measure_width_sp(text2, gregosheet.lyrics_fontid),
      word_end = syl.word_end or true,
      comment = false,
    })
    table.insert(events, chunk2_insert_pos, {
      type = "note", glyph = event.glyph,
      width_sp = event.width_sp, syllable_idx = #syllables,
    })
  else
    -- Expand chunk2 to individual notes
    for si = fit_count + 1, #syls do
      if si > fit_count + 1 then
        table.insert(events, chunk2_insert_pos, {
          type = "delimiter", glyph = "-",
          width_sp = gregosheet.measure_width_sp("-", gregosheet.music_fontid),
        })
        chunk2_insert_pos = chunk2_insert_pos + 1
      end
      local is_word_end = (si == #syls) and (syl.word_end or true) or (syls[si + 1] and syls[si + 1].word_start or false)
      table.insert(syllables, {
        text = syls[si].text,
        width_sp = gregosheet.measure_width_sp(syls[si].text, gregosheet.lyrics_fontid),
        word_end = is_word_end,
        comment = false,
      })
      table.insert(events, chunk2_insert_pos, {
        type = "note", glyph = normal_glyph,
        width_sp = normal_width, syllable_idx = #syllables,
      })
      chunk2_insert_pos = chunk2_insert_pos + 1
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
    if overflow_event.type == "note"
      and overflow_event.syllable_idx
      and overflow_event.glyph:match(gregosheet.recited_notes)
    then
      local syl = syllables[overflow_event.syllable_idx]
      if syl and syl.text and syl.text:find(" ") then
        local handled = gregosheet.handle_recited_split(
          events, syllables, overflow_idx, page_width_sp
        )
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
