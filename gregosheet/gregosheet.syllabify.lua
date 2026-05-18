gregosheet = gregosheet or {}

local function is_vowel(char)
  return char:match("[aáeéiíoóöőuúüűAÁEÉIÍOÓÖŐUÚÜŰ]")
end

--- Syllabify a Hungarian text string.
--- Handles _ as space (word boundary).
---
--- @param text string  Text with _ as spaces (e.g. "Uram,_segíts_meg")
--- @return table[]  List of {text=string, word_start=boolean}
function gregosheet.syllabify(text)
  -- Replace _ with space
  local display = text:gsub("_", " ")

  local result = {}

  for word in display:gmatch("%S+") do
    local word_start = true

    -- Replace digraphs/trigraphs with single tokens for counting
    local clean = word:gsub("dzs", "\1")
    clean = clean:gsub("cs", "\2")
    clean = clean:gsub("dz", "\3")
    clean = clean:gsub("gy", "\4")
    clean = clean:gsub("ly", "\5")
    clean = clean:gsub("ny", "\6")
    clean = clean:gsub("sz", "\7")
    clean = clean:gsub("ty", "\8")
    clean = clean:gsub("zs", "\9")

    local chars = {}
    for _, c in utf8.codes(clean) do
      table.insert(chars, utf8.char(c))
    end

    local current = ""
    local i = 1

    while i <= #chars do
      local char = chars[i]
      current = current .. char

      if is_vowel(char) then
        local consonants = ""
        local j = i + 1

        while j <= #chars and not is_vowel(chars[j]) do
          consonants = consonants .. chars[j]
          j = j + 1
        end

        if consonants == "" then
          -- Restore digraphs and add syllable
          local syl = current:gsub("\1", "dzs"):gsub("\2", "cs"):gsub("\3", "dz")
            :gsub("\4", "gy"):gsub("\5", "ly"):gsub("\6", "ny")
            :gsub("\7", "sz"):gsub("\8", "ty"):gsub("\9", "zs")
          table.insert(result, {text = syl, word_start = word_start})
          word_start = false
          current = ""
        elseif j > #chars then
          current = current .. consonants
          local syl = current:gsub("\1", "dzs"):gsub("\2", "cs"):gsub("\3", "dz")
            :gsub("\4", "gy"):gsub("\5", "ly"):gsub("\6", "ny")
            :gsub("\7", "sz"):gsub("\8", "ty"):gsub("\9", "zs")
          table.insert(result, {text = syl, word_start = word_start})
          word_start = false
          current = ""
        else
          local cons_chars = {}
          for _, c in utf8.codes(consonants) do
            table.insert(cons_chars, utf8.char(c))
          end
          if #cons_chars == 1 then
            local syl = current:gsub("\1", "dzs"):gsub("\2", "cs"):gsub("\3", "dz")
              :gsub("\4", "gy"):gsub("\5", "ly"):gsub("\6", "ny")
              :gsub("\7", "sz"):gsub("\8", "ty"):gsub("\9", "zs")
            table.insert(result, {text = syl, word_start = word_start})
            word_start = false
            current = cons_chars[1]
          else
            for k = 1, #cons_chars - 1 do
              current = current .. cons_chars[k]
            end
            local syl = current:gsub("\1", "dzs"):gsub("\2", "cs"):gsub("\3", "dz")
              :gsub("\4", "gy"):gsub("\5", "ly"):gsub("\6", "ny")
              :gsub("\7", "sz"):gsub("\8", "ty"):gsub("\9", "zs")
            table.insert(result, {text = syl, word_start = word_start})
            word_start = false
            current = cons_chars[#cons_chars]
          end
        end

        i = j
      else
        i = i + 1
      end
    end

    if current ~= "" then
      local syl = current:gsub("\1", "dzs"):gsub("\2", "cs"):gsub("\3", "dz")
        :gsub("\4", "gy"):gsub("\5", "ly"):gsub("\6", "ny")
        :gsub("\7", "sz"):gsub("\8", "ty"):gsub("\9", "zs")
      table.insert(result, {text = syl, word_start = word_start})
    end
  end

  return result
end
