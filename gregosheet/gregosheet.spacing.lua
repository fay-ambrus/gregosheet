gregosheet = gregosheet or {}

local function extract_clef(melody)
  local music_fontid = gregosheet.music_fontid
  local clef_glyph = ""
  local key_sig = ""
  local piece_start = nil

  while #melody > 0 and melody[1].type ~= "note" do
    local token = table.remove(melody, 1)
    if token.piece_start then
      piece_start = token.piece_start
    end
    if token.type == "symbol" then
      if clef_glyph == "" then
        clef_glyph = token.value
      else
        key_sig = key_sig .. token.value
      end
    end
  end

  -- Transfer piece_start to first remaining token
  if piece_start and #melody > 0 then
    melody[1].piece_start = melody[1].piece_start or piece_start
  end

  local clef_value = clef_glyph .. key_sig .. "-"

  return {
    type = "symbol",
    value = clef_value,
    width_sp = gregosheet.measure_width_sp(clef_value, music_fontid),
    glyph = clef_glyph,
    key = key_sig,
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
    if last_delimiter_idx == 0 then
      last_delimiter_idx = 1
      texio.write_nl("Inserting delimiter at position " .. last_delimiter_idx)
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

local function is_lyric_overfull(lyric)
  return lyric.start_sp + lyric.width_sp > tex.dimen["textwidth"]
end

-- Measure the title width
local function measure_title_width(piece_start)
  if not piece_start then return 0 end
  if piece_start.title ~= "" then
    return gregosheet.measure_width_sp(piece_start.title, gregosheet.lyrics_fontid)
  end
  return 0
end

function gregosheet.spacing_compute(melody, lyrics, tone)
  gregosheet.init_delimiter_widths()

  gregosheet.debug_print("DEBUG: spacing_compute called with " .. #melody .. " melody tokens, " .. #lyrics .. " lyrics")

  local space_width_sp = gregosheet.measure_width_sp(" ", gregosheet.lyrics_fontid)
  local hyphen_width_sp = gregosheet.measure_width_sp("-", gregosheet.lyrics_fontid)
  local page_width_sp = tex.dimen["textwidth"]

  local clef = extract_clef(melody)

  local systems = {}
  local system = {clef = clef, melody = {}, lyrics = {}, titles = {}}
  local lyric_index = 1
  local melody_idx = 1
  local out_of_lyrics = false
  local new_system_counter = 0
  local last_token_idx = 1
  local system_break = false
  local first_piece_seen = false

  while melody_idx <= #melody do
    local token = melody[melody_idx]
    local previous_token = system.melody[#system.melody]
    local lyric_overfull = false

    gregosheet.debug_print("DEBUG: Processing token " .. melody_idx .. ": type=" .. token.type .. " value=" .. tostring(token.value))
    if last_token_idx ~= melody_idx then
      new_system_counter = 0
    end
    last_token_idx = melody_idx

    -- Update key signature at piece boundaries (skip first piece, handled by extract_clef)
    if token.piece_start then
      if not first_piece_seen then
        first_piece_seen = true
      else
        -- Collect new key signature from consecutive symbols
        local new_key = ""
        if token.type == "symbol" then
          new_key = token.value
          local j = melody_idx + 1
          while j <= #melody and melody[j].type == "symbol" do
            new_key = new_key .. melody[j].value
            j = j + 1
          end
        end

        -- Update clef for line breaks (only new key)
        local old_key = clef.key or ""
        local naturals = gregosheet.compute_naturals(old_key, new_key)

        -- Prepend naturals to the current token
        if naturals ~= "" then
          token.value = naturals .. token.value
          token.width_sp = gregosheet.measure_width_sp(token.value, gregosheet.music_fontid)
        end

        local clef_value = clef.glyph .. new_key .. "-"
        clef = {
          type = "symbol",
          value = clef_value,
          width_sp = gregosheet.measure_width_sp(clef_value, gregosheet.music_fontid),
          glyph = clef.glyph,
          key = new_key,
        }
      end
    end

    -- Check if this token starts a new piece with a title
    if token.piece_start and token.piece_start.title ~= "" then
      local title_width = measure_title_width(token.piece_start)
      local horizontal_position_sp = calculate_horizontal_position(system)

      -- If title doesn't fit on current line, force a system break
      if horizontal_position_sp > 0 and horizontal_position_sp + title_width > page_width_sp then
        -- Pad current system to fill the line
        local gap_to_page_end_sp = page_width_sp - horizontal_position_sp
        table.insert(system.melody, {
          type = "delimiter",
          value = "",
          width_sp = 0
        })
        recompute_delimiter_width(system.melody[#system.melody], gap_to_page_end_sp, "max")

        table.insert(systems, system)
        local next_clef = clef
        if gregosheet.clef_mode == "first" then
          next_clef = {type = "symbol", value = "-", width_sp = gregosheet.measure_width_sp("-", gregosheet.music_fontid)}
        end
        system = {clef = next_clef, melody = {}, lyrics = {}, titles = {}}
      end
    end

    -- Record title position in current system
    if token.piece_start and token.piece_start.title ~= "" then
      local horizontal_position_sp = calculate_horizontal_position(system)
      table.insert(system.titles, {
        title = token.piece_start.title,
        start_sp = horizontal_position_sp,
      })
    end

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

    -- If we are out of lyrics, delimiters become shorter
    if token.type == "delimiter" and out_of_lyrics and not system_break then
      token.value = "--"
      token.width_sp = gregosheet.measure_width_sp(token.value, gregosheet.music_fontid)
    end

    local lyric = lyrics[lyric_index]
    local previous_lyric = system.lyrics[#system.lyrics]

    if lyric then
      gregosheet.debug_print("DEBUG: Current lyric " .. lyric_index .. ": text='" .. lyric.text .. "' word_end=" .. tostring(lyric.word_end))
    end

    -- Handle floating lyrics (from \addtext) - place at current position, don't consume a note
    if lyric and lyric.floating then
      local horizontal_position_sp = calculate_horizontal_position(system)
      lyric.start_sp = horizontal_position_sp
      -- Check overlap with previous lyric
      if previous_lyric then
        local prev_end_sp = previous_lyric.start_sp + previous_lyric.width_sp + space_width_sp
        if lyric.start_sp < prev_end_sp then
          lyric.start_sp = prev_end_sp
        end
      end
      lyric.word_end = true
      table.insert(system.lyrics, lyric)
      lyric_index = lyric_index + 1
      lyric = lyrics[lyric_index]
      previous_lyric = system.lyrics[#system.lyrics]
    end

    if token.type == "note" or (token.type == "barline" and lyric and (lyric.text == "*" or lyric.text == "ANT." or lyric.text == "REF.")) then
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
          gregosheet.debug_print("DEBUG: Lyric overlap detected, gap_sp=" .. gap_sp .. ", adjusting delimiter")
          local last_delimiter_idx = find_or_insert_delimiter(system)
          local last_delimiter = system.melody[last_delimiter_idx]
          recompute_delimiter_width(last_delimiter, last_delimiter.width_sp - gap_sp, "min")
          lyric.start_sp = calculate_lyric_starting_position(lyric, token, system)
        end
      else
        out_of_lyrics = true
        gregosheet.debug_print("DEBUG: Out of lyrics!")
      end

      -- Check if lyric is overfull
      if lyric then
        lyric_overfull = is_lyric_overfull(lyric)
      end

      -- Hyphenation
      if lyric and previous_lyric and not previous_lyric.word_end then
        if lyric_overfull then
          previous_lyric.text = previous_lyric.text .. "-"
          previous_lyric.width_sp = gregosheet.measure_width_sp(previous_lyric.text, gregosheet.lyrics_fontid)
        else
          local gap_sp = lyric.start_sp - (previous_lyric.start_sp + previous_lyric.width_sp)
          if gap_sp > gregosheet.tolerable_syllabel_gap_sp then
            if gap_sp < hyphen_width_sp then
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
      gregosheet.debug_print("DEBUG: System break needed at melody_idx=" .. melody_idx .. ", horizontal_pos=" .. horizontal_position_sp .. ", page_width=" .. page_width_sp)
      system_break = true
      if new_system_counter < 16 then
        new_system_counter = new_system_counter + 1
      else
        texio.write_nl("ERROR: Too many system breaks, possible infinite loop. Exiting.")
        os.exit()
      end
      local gap_to_page_end_sp = page_width_sp - horizontal_position_sp
      if token.type == "delimiter" then
        local old_width = token.width_sp
        recompute_delimiter_width(token, gap_to_page_end_sp, "max")
      else
        table.insert(system.melody, {
          type = "delimiter",
          value = "",
          width_sp = 0
        })
        recompute_delimiter_width(system.melody[#system.melody], gap_to_page_end_sp, "max")

        table.insert(systems, system)
        local next_clef = clef
        if gregosheet.clef_mode == "first" then
          next_clef = {type = "symbol", value = "-", width_sp = gregosheet.measure_width_sp("-", gregosheet.music_fontid)}
        end
        system = {clef = next_clef, melody = {}, lyrics = {}, titles = {}}
      end
    else
      system_break = false
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
