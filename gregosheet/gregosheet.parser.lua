gregosheet = gregosheet or {}

-- Parse string into tokens: notes, delimiters, and symbols
function gregosheet.parse_melody(str)
  local music_fontid = gregosheet.music_fontid
  local std_delimiter_sequence_width_sp = gregosheet.measure_width_sp(gregosheet.std_delimiter_sequence, music_fontid)

  local tokens = {}
  local note_group = ""
  local last_type = nil

  for char in str:gmatch(".") do
    if char:match(gregosheet.notes) then
      note_group = note_group .. char
      last_type = "note"
    elseif char:match(gregosheet.delimiters) then
      if note_group ~= "" then
        table.insert(tokens, {type = "note", value = note_group, width_sp = gregosheet.measure_width_sp(note_group, music_fontid)})
        note_group = ""
      end
      if last_type ~= "delimiter" then
        table.insert(tokens, {type = "delimiter", value = gregosheet.std_delimiter_sequence, width_sp = std_delimiter_sequence_width_sp})
      end
      last_type = "delimiter"
    elseif char:match(gregosheet.symbols) then
      if note_group ~= "" then
        table.insert(tokens, {type = "note", value = note_group, width_sp = gregosheet.measure_width_sp(note_group, music_fontid)})
        note_group = ""
      end
      table.insert(tokens, {type = "symbol", value = char, width_sp = gregosheet.measure_width_sp(char, music_fontid)})
      last_type = "symbol"
    elseif char:match(gregosheet.barlines) then
      if note_group ~= "" then
        table.insert(tokens, {type = "note", value = note_group, width_sp = gregosheet.measure_width_sp(note_group, music_fontid)})
        note_group = ""
      end
      table.insert(tokens, {type = "barline", value = char, width_sp = gregosheet.measure_width_sp(char, music_fontid)})
      last_type = "barline"
    end
  end

  if note_group ~= "" then
    table.insert(tokens, {type = "note", value = note_group, width_sp = gregosheet.measure_width_sp(note_group, music_fontid)})
  end

  return tokens
end

-- Parse lyrics into syllables with metadata
function gregosheet.parse_lyrics(str)
  local syllables = {}
  local i = 1

  while i <= #str do
    local char = str:sub(i, i)

    if char == " " then
      i = i + 1
    elseif char == "-" then
      i = i + 1
    else
      -- Extract syllable
      local syllable = ""
      while i <= #str and str:sub(i, i) ~= " " and str:sub(i, i) ~= "-" do
        syllable = syllable .. str:sub(i, i)
        i = i + 1
      end

      -- Check if next non-space character is hyphen or end of string
      local word_end = (i > #str or str:sub(i, i) == " ")

      table.insert(syllables, {
        type = "lyric",
        text = syllable,
        word_end = word_end,
        width_sp = gregosheet.measure_width_sp(syllable, gregosheet.lyrics_fontid)
      })
    end
  end

  return syllables
end
