gregosheet = gregosheet or {}

--- Parse a melody string into a list of tokens.
--- Pure function: no font access, no width measurement.
---
--- @param str string  The melody string (GuidoHU encoded)
--- @return table[]  List of tokens, each: {type, glyph}
---   type: "note" | "delimiter" | "symbol" | "barline"
---   glyph: string (the raw character(s))
function gregosheet.parse_melody(str)
  local tokens = {}
  local group = ""
  local group_type = nil

  for _, code in utf8.codes(str) do
    local char = utf8.char(code)
    local char_type
    if gregosheet.code_in_array(code, gregosheet.notes_codes) then
      char_type = "note"
    elseif gregosheet.code_in_array(code, gregosheet.delimiters_codes) then
      char_type = "delimiter"
    elseif gregosheet.code_in_array(code, gregosheet.symbols_codes) then
      char_type = "symbol"
    elseif gregosheet.code_in_array(code, gregosheet.barlines_codes) then
      char_type = "barline"
    end

    if char_type == group_type then
      group = group .. char
    else
      if group ~= "" then
        table.insert(tokens, {type = group_type, glyph = group})
      end
      group = char
      group_type = char_type
    end
  end

  if group ~= "" then
    table.insert(tokens, {type = group_type, glyph = group})
  end

  return tokens
end

--- Parse a lyrics string into a list of syllables.
--- Pure function: no font access, no width measurement.
---
--- @param str string  The lyrics string (space/hyphen separated)
--- @return table[]  List of syllables, each: {text, word_end, comment}
---   text: string (the syllable text, underscores replaced with spaces)
---   word_end: boolean (true if followed by space or end of string)
---   comment: boolean (true if wrapped in < >, rendered red, doesn't consume a note)
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
      local syllable = ""
      while i <= #str and str:sub(i, i) ~= " " and str:sub(i, i) ~= "-" do
        syllable = syllable .. str:sub(i, i)
        i = i + 1
      end

      local word_end = (i > #str or str:sub(i, i) == " ")
      local comment = false

      if syllable:sub(1, 1) == "<" and syllable:sub(-1) == ">" then
        comment = true
        syllable = syllable:sub(2, -2)
      end

      -- @ is an empty syllable (consumes a note, renders nothing)
      if syllable == "@" then
        syllable = ""
      end

      -- Replace _ with space for display
      syllable = syllable:gsub("_", " ")

      table.insert(syllables, {
        text = syllable,
        word_end = word_end,
        comment = comment,
      })
    end
  end

  return syllables
end
