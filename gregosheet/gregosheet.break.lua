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

--- Break a justified event stream into lines (systems).
---
--- @param events table[]  Justified event list (widths and start_sp are final)
--- @param syllables table[]  Justified syllable list (start_sp assigned)
--- @return table[]  systems, each: {clef, events[], syllables[], titles[]}
function gregosheet.break_into_systems(events, syllables)
  local page_width_sp = tex.dimen["textwidth"]

  -- Extract clef (always first event)
  local clef = events[1]
  local clef_width = clef.width_sp

  gregosheet.debug_print("BREAK: " .. #events .. " events, page_width=" .. page_width_sp .. " clef_width=" .. clef_width)

  -- Collect line break points: indices into events where each new line starts
  local line_starts = {2}
  local cursor = clef_width

  for i = 2, #events do
    local event = events[i]

    if event.type == "tone_group" then
      -- Tone groups are atomic: never split
      if cursor + event.width_sp > page_width_sp then
        table.insert(line_starts, i)
        cursor = clef_width + event.width_sp
      else
        cursor = cursor + event.width_sp
      end

    elseif event.type == "title" then
      local title_width = gregosheet.measure_width_sp(event.title, gregosheet.lyrics_fontid)
      if cursor > clef_width and cursor + title_width > page_width_sp then
        table.insert(line_starts, i)
        cursor = clef_width
      end

    elseif event.type == "piece_boundary" and event.title ~= "" then
      local title_width = gregosheet.measure_width_sp(event.title, gregosheet.lyrics_fontid)
      if cursor > clef_width and cursor + title_width > page_width_sp then
        table.insert(line_starts, i)
        cursor = clef_width + (event.width_sp or 0)
      else
        cursor = cursor + (event.width_sp or 0)
      end

    else
      if cursor + (event.width_sp or 0) > page_width_sp then
        table.insert(line_starts, i)
        gregosheet.debug_print("BREAK: line break at event " .. i .. " type=" .. event.type .. " cursor=" .. cursor)
        cursor = clef_width + (event.width_sp or 0)
      else
        cursor = cursor + (event.width_sp or 0)
      end
    end
  end

  -- Build systems from line break points
  local systems = {}
  for line_idx = 1, #line_starts do
    local start_i = line_starts[line_idx]
    local end_i = (line_idx < #line_starts) and (line_starts[line_idx + 1] - 1) or #events

    local line_offset = events[start_i].start_sp

    -- Collect events and titles for this line
    local line_events = {}
    local line_titles = {}
    for i = start_i, end_i do
      local event = events[i]
      if event.type == "title" or (event.type == "piece_boundary" and event.title and event.title ~= "") then
        table.insert(line_titles, {
          title = event.title,
          start_sp = event.start_sp - line_offset + clef_width,
        })
      end
      table.insert(line_events, event)
    end

    -- Collect syllables whose start_sp falls within this line's range
    local line_syllables = {}
    local line_start_sp = events[start_i].start_sp
    local line_end_sp = (line_idx < #line_starts) and events[line_starts[line_idx + 1]].start_sp or math.huge

    for _, syl in ipairs(syllables) do
      if syl.start_sp and syl.start_sp >= line_start_sp and syl.start_sp < line_end_sp then
        local placed = {}
        for k, v in pairs(syl) do placed[k] = v end
        placed.start_sp = syl.start_sp - line_offset + clef_width
        table.insert(line_syllables, placed)
      end
    end

    -- Pad interior lines: stretch last delimiter to fill page width
    if line_idx < #line_starts then
      local line_width = clef_width
      for _, ev in ipairs(line_events) do
        line_width = line_width + (ev.width_sp or 0)
      end
      local gap = page_width_sp - line_width
      if gap > 0 then
        for j = #line_events, 1, -1 do
          if line_events[j].type == "delimiter" then
            local new_width = line_events[j].width_sp + gap
            line_events[j].glyph = get_maximal_delimiter_under_distance(new_width)
            line_events[j].width_sp = gregosheet.measure_width_sp(line_events[j].glyph, gregosheet.music_fontid)
            break
          end
        end
      end
    end

    table.insert(systems, {
      clef = clef,
      events = line_events,
      syllables = line_syllables,
      titles = line_titles,
    })
  end

  gregosheet.debug_print("BREAK: " .. #systems .. " systems, " .. #line_starts .. " line breaks")

  return systems
end
