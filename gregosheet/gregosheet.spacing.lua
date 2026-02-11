gregosheet = gregosheet or {}

local function extract_clef(melody)
  local music_fontid = gregosheet.music_fontid
  local clef_value = ""

  while #melody > 0 and melody[1].type ~= "note" do
    local token = table.remove(melody, 1)
    if token.type == "symbol" then
      clef_value = clef_value .. token.value
    end
  end

  clef_value = clef_value .. "-"

  return {
    type = "symbol",
    value = clef_value,
    width_sp = gregosheet.measure_width_sp(clef_value, music_fontid)
  }
end

local function calculate_horizontal_position(system, idx)
  if idx == nil then
    idx = #system.melody
  end
  local i = 1
  local horizontal_position_sp = system.clef.width_sp
  while i <= idx and i <= #system.melody do
    horizontal_position_sp = horizontal_position_sp + system.melody[i].width_sp
    i = i + 1
  end
  return horizontal_position_sp
end

-- Calculate the starting position for a lyric under a note
local function calculate_lyric_starting_position(lyric, token, system)
  local horizontal_position_sp = calculate_horizontal_position(system)
  if lyric.width_sp >= token.width_sp and not token.value:match(gregosheet.recited_notes) then
    return horizontal_position_sp + (token.width_sp / 2) - (lyric.width_sp / 2)
  else
    return horizontal_position_sp
  end
end

-- Get minimal delimiter combination wider than distance_sp
local function get_minimal_delimiter_over_distance(distance_sp)
  -- Use as many large delimiters as possible
  local n_l = math.floor(distance_sp / gregosheet.w_l)
  local remaining = distance_sp - n_l * gregosheet.w_l

  if remaining <= 0 then
    return string.rep(gregosheet.delimiter_l, n_l + 1)
  end

  -- Check combinations with minimal count
  if remaining < gregosheet.w_s then
    return string.rep(gregosheet.delimiter_l, n_l) .. gregosheet.delimiter_s
  elseif remaining < gregosheet.w_m then
    -- Compare: l+s vs m
    if gregosheet.w_s > remaining then
      return string.rep(gregosheet.delimiter_l, n_l) .. gregosheet.delimiter_s
    else
      return string.rep(gregosheet.delimiter_l, n_l) .. gregosheet.delimiter_m
    end
  elseif remaining < gregosheet.w_l then
    -- Try: l+m, l+s, m+s, or just add another l
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

-- Get maximal delimiter combination smaller than distance_sp
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

local function recompute_delimiter_width(delimiter, target_width_sp, mode)
  assert(mode == "min" or mode == "max", "mode must be 'min' or 'max'")

  if mode == "min" then
    delimiter.value = get_minimal_delimiter_over_distance(target_width_sp)
  else
    delimiter.value = get_maximal_delimiter_under_distance(target_width_sp)
  end

  delimiter.width_sp = gregosheet.measure_width_sp(delimiter.value, gregosheet.music_fontid)
end


local function find_last_token_before_note(system, token_type, start_idx)
  if not start_idx then
    start_idx = #system.melody
  end
  for j = start_idx, 1, -1 do
    if system.melody[j].type == token_type then
      return j
    elseif system.melody[j].type == "note" then
      return nil
    end
  end
  return nil
end

local function find_or_insert_delimiter(system, note_idx)
  if not note_idx then
    note_idx = #system.melody
  end
  local last_delimiter_idx = find_last_token_before_note(system, "delimiter", note_idx)
  if not last_delimiter_idx then
    last_delimiter_idx = #system.melody
    local previous_token = system.melody[#system.melody - 1]
    if previous_token and previous_token.type == "symbol" then
      last_delimiter_idx = #system.melody - 1
    end
    table.insert(system.melody, last_delimiter_idx, {
      type = "delimiter",
      value = "",
      width_sp = 0,
      start_sp = calculate_horizontal_position(system, last_delimiter_idx)
    })
  end
  return last_delimiter_idx
end

local function rollback_computations_after(system, system_idx)
  local lyric_idx = nil
  -- Rollback added melodies
  for i = system_idx + 1, #system.melody do
    local token = system.melody[i]
    if (token.type == "note" or token.type == "barline") and token.lyric and lyric_idx then
      lyric_idx = token.lyric
    end
    system.melody[i] = nil
  end
  -- Rollback added lyrics
  if lyric_idx then
    for i = 1, #system.lyrics do
      if system.lyrics[i] >= lyric_idx then
        system.lyrics[i] = nil
      end
    end
  end
  -- Find melody idx
  local melody_idx = 1
  for i = system_idx, 1, -1 do
    if system.melody[i].melody_idx then
      melody_idx = system.melody[i].melody_idx
      break
    end
  end

  return melody_idx, lyric_idx
end

local function is_lyric_overfull(lyric)
  return lyric.start_sp + lyric.width_sp > tex.dimen["textwidth"]
end

function gregosheet.spacing_compute(melody, lyrics, tone)
  gregosheet.init_delimiter_widths()

  local space_width_sp = gregosheet.measure_width_sp(" ", gregosheet.lyrics_fontid)
  local hyphen_width_sp = gregosheet.measure_width_sp("-", gregosheet.lyrics_fontid)
  local page_width_sp = tex.dimen["textwidth"]

  local clef = extract_clef(melody)

  local systems = {}
  local system = {clef = clef, melody = {}, lyrics = {}}
  local lyric_index = 1
  local melody_idx = 1

  while melody_idx <= #melody do
    local token = melody[melody_idx]
    local previous_token = system.melody[#system.melody]
    local lyric_overfull = false


    -- Barlines have default delimiters around them
    if token.type == "barline" then
      if previous_token and previous_token.type == "delimiter" then
        previous_token.value = "-"
        previous_token.width_sp = gregosheet.measure_width_sp(previous_token.value, gregosheet.music_fontid)
      end
      local next_token = melody[melody_idx + 1]
      if next_token and next_token.type == "delimiter" then
        next_token.value = "--"
        next_token.width_sp = gregosheet.measure_width_sp(next_token.value, gregosheet.music_fontid)
      end
    end

    local lyric = lyrics[lyric_index]
    local previous_lyric = system.lyrics[#system.lyrics]

    if token.type == "note" or (token.type == "barline" and lyric and lyric.text == "*") then
      -- Place lyric under notes or * under barline.
      if lyric then
        -- Compute the starting position of the lyric
        local token_pos = calculate_horizontal_position(system)
        lyric.start_sp = calculate_lyric_starting_position(lyric, token, system)

        -- Check if lyric overlaps with previous one or if it is not on the page
        local gap_sp = 0
        if previous_lyric then
          local prev_end_sp = previous_lyric.start_sp + previous_lyric.width_sp
          if previous_lyric.word_end then
            prev_end_sp = prev_end_sp + space_width_sp
          end
          gap_sp = lyric.start_sp - prev_end_sp
        else
          gap_sp = lyric.start_sp
        end

        if gap_sp < 0 then
          -- More spacing is needed in the last delimiter
          local last_delimiter_idx = find_or_insert_delimiter(system)
          local last_delimiter = system.melody[last_delimiter_idx]
          recompute_delimiter_width(last_delimiter, last_delimiter.width_sp - gap_sp, "min")
          lyric.start_sp = calculate_lyric_starting_position(lyric, token, system)
        end
      end

      -- Check if lyric is overfull
      if lyric then
        lyric_overfull = is_lyric_overfull(lyric)
      end

      -- Hyphenation
      if lyric and previous_lyric and not previous_lyric.word_end then
        if lyric_overfull then
          -- If lyric is overfull force hyphen to the end of the last syllabel
          previous_lyric.text = previous_lyric.text .. "-"
          previous_lyric.width_sp = gregosheet.measure_width_sp(previous_lyric.text, gregosheet.lyrics_fontid)
        else
          -- Insert hyphen
          local gap_sp = lyric.start_sp - (previous_lyric.start_sp + previous_lyric.width_sp)
          if gap_sp > gregosheet.tolerable_syllabel_gap_sp then
            if gap_sp < hyphen_width_sp then
              -- Last delimiter has to be somewhat increased
              local last_delimiter_idx = find_or_insert_delimiter(system)
              local last_delimiter = system.melody[last_delimiter_idx]
              local needed_delimiter_width_sp = last_delimiter.width_sp + hyphen_width_sp - gap_sp
              recompute_delimiter_width(last_delimiter, needed_delimiter_width_sp, "min")
              lyric.start_sp = calculate_lyric_starting_position(lyric, token, system)
            end

            table.insert(system.lyrics, {
              type = "hyphen",
              text = "-",
              width_sp = hyphen_width_sp,
              start_sp = (previous_lyric.start_sp + previous_lyric.width_sp + lyric.start_sp - hyphen_width_sp) / 2,
              word_end = false
            })
          end
        end
      end
    end

    -- Handle systems
    local horizontal_position_sp = calculate_horizontal_position(system)
    if horizontal_position_sp + token.width_sp > page_width_sp or lyric_overfull then
      local gap_to_page_end_sp = page_width_sp - horizontal_position_sp
      -- Handle different types of previous tokens
      if token.type == "delimiter" then
        -- More spacing is needed in the last delimiter
        local old_width = token.width_sp
        recompute_delimiter_width(token, gap_to_page_end_sp, "max")
      elseif token.type == "barline" then
        -- Push the last note to the new system
        local last_note_idx = find_last_token_before_note(system, "note")
        local delimiter_idx = find_or_insert_delimiter(system, last_note_idx)
        local delimiter = system.melody[delimiter_idx]
        local needed_delimiter_width_sp = page_width_sp - delimiter.start_sp
        recompute_delimiter_width(delimiter, needed_delimiter_width_sp, "max")
        melody_idx, lyric_idx = rollback_computations_after(system, delimiter_idx)
      else
        -- There is need for a new finishing delimiter
        table.insert(system.melody, {
          type = "delimiter",
          value = "",
          width_sp = 0
        })
        recompute_delimiter_width(system.melody[#system.melody], gap_to_page_end_sp, "max")

        table.insert(systems, system)
        system = {clef = clef, melody = {}, lyrics = {}}
      end
    else
      if lyric and lyric.start_sp then
        table.insert(system.lyrics, lyric)
        token.lyric = lyric_index
        lyric_index = lyric_index + 1
      end
      table.insert(system.melody, token)
      melody_idx = melody_idx + 1
    end
  end

  -- Add tone in last system
  if tone and tone ~= "" then
    local last_lyric = system.lyrics[#system.lyrics]
    local tone_start_sp = 0

    if last_lyric then
      local last_lyric_end = last_lyric.start_sp + last_lyric.width_sp
      tone_start_sp = last_lyric_end + space_width_sp * 5
    end

    system.tone = {
      tone_str = tone,
      new_line = tone_start_sp + gregosheet.measure_width_sp(tone, gregosheet.lyrics_fontid) >= calculate_horizontal_position(system),
      start_sp = tone_start_sp
    }
  end

  table.insert(systems, system)

  return systems
end
