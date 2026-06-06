gregosheet = gregosheet or {}

-- Accidentals table: { sharp, flat, natural } for each staff position
gregosheet.accidentals = {
  c4 = { "Ë", "ø", "“" },
  d4 = { "Ì", "a", "”" },
  e4 = { "Î", "A", "•" },
  f4 = { "Ï", "S", "–" },
  g4 = { "Ð", "Í", "—" },
  a4 = { "Ñ", "Y", "˜" },
  b4 = { "Ò", "X", "™" },
  c5 = { "þ", "C", "š" },
  d5 = { "ß", "V", "›" },
  e5 = { "ò", "B", "œ" },
  f5 = { "ô", "N", "º" },
  g5 = { "ù", "m", "»" },
}

-- Derived lookup tables (built lazily)
gregosheet.key_sig_chars = nil  -- char -> {type, position}
gregosheet.natural_chars = nil  -- position -> natural char

function gregosheet.init_accidentals()
  if gregosheet.key_sig_chars then return end
  gregosheet.key_sig_chars = {}
  gregosheet.natural_chars = {}
  for pos, chars in pairs(gregosheet.accidentals) do
    if chars[1] and chars[1] ~= "" then
      gregosheet.key_sig_chars[chars[1]] = { type = "sharp", position = pos }
    end
    if chars[2] and chars[2] ~= "" then
      gregosheet.key_sig_chars[chars[2]] = { type = "flat", position = pos }
    end
    if chars[3] and chars[3] ~= "" then
      gregosheet.natural_chars[pos] = chars[3]
    end
  end
end

--- Validate that a key signature contains only sharps or only flats.
function gregosheet.validate_key(key_str)
  if key_str == "" then return end
  gregosheet.init_accidentals()
  local has_sharp = false
  local has_flat = false
  for _, code in utf8.codes(key_str) do
    local char = utf8.char(code)
    local info = gregosheet.key_sig_chars[char]
    if not info then
      error("Invalid key signature character: '" .. char .. "'")
    end
    if info.type == "sharp" then has_sharp = true end
    if info.type == "flat" then has_flat = true end
  end
  if has_sharp and has_flat then
    error("Key signature mixes sharps and flats")
  end
end

function gregosheet.compute_clef_change(old_clef_str, new_clef_str)
  if old_clef_str == nil or old_clef_str == "" then
    return new_clef_str
  end
  if old_clef_str == new_clef_str then
    return ""
  end
  return new_clef_str
end

--- Compute the glyphs to display at a key signature change.
--- If old is empty, return new key. If new is empty, return naturals of old.
--- Otherwise return new key.
function gregosheet.compute_key_signature(old_key_str, new_key_str)
  if old_key_str == "" then
    return new_key_str
  end

  if new_key_str == "" then
    gregosheet.init_accidentals()
    local naturals_str = ""
    for _, code in utf8.codes(old_key_str) do
      local char = utf8.char(code)
      local info = gregosheet.key_sig_chars[char]
      if info and gregosheet.natural_chars[info.position] then
        naturals_str = naturals_str .. gregosheet.natural_chars[info.position]
      end
    end
    return naturals_str
  end

  return new_key_str
end
