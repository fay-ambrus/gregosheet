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
  c5 = { "ţ", "C", "š" },
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

-- Compute naturals needed when changing key signature
function gregosheet.compute_naturals(old_key_str, new_key_str)
  gregosheet.init_accidentals()

  local old_sigs = {}
  local new_sigs = {}
  local old_type = nil
  local new_type = nil

  for _, code in utf8.codes(old_key_str) do
    local char = utf8.char(code)
    local info = gregosheet.key_sig_chars[char]
    if info then
      old_type = info.type
      old_sigs[info.position] = true
    end
  end

  for _, code in utf8.codes(new_key_str) do
    local char = utf8.char(code)
    local info = gregosheet.key_sig_chars[char]
    if info then
      new_type = info.type
      new_sigs[info.position] = true
    end
  end

  if old_type == nil then
    return ""
  end

  local naturals_str = ""

  if new_type == nil or old_type ~= new_type then
    -- Type changed or going to none: naturalize ALL old positions
    for pos, _ in pairs(old_sigs) do
      if gregosheet.natural_chars[pos] then
        naturals_str = naturals_str .. gregosheet.natural_chars[pos]
      end
    end
  else
    -- Same type: naturalize only removed positions
    for pos, _ in pairs(old_sigs) do
      if not new_sigs[pos] and gregosheet.natural_chars[pos] then
        naturals_str = naturals_str .. gregosheet.natural_chars[pos]
      end
    end
  end

  return naturals_str
end
