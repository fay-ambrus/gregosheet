gregosheet = gregosheet or {}

-- Debug flag (toggle with \gregosheetdebug in LaTeX)
gregosheet.debug = false

function gregosheet.debug_print(msg)
  if gregosheet.debug then
    texio.write_nl(msg)
  end
end

-- Constants
gregosheet.delimiter_s = "¨"
gregosheet.delimiter_m = "-"
gregosheet.delimiter_l = "_"
gregosheet.std_delimiter_sequence = "---"
gregosheet.tolerable_syllabel_gap_sp = 73000

-- Code tables
gregosheet.notes = "[ðñ0123456789öüó^qwertzuiopõúÝÞQWERTZUIOPÕÚÔasdfghjkléáûØÙASDFGHJKLÉÁÛ`íyxcvbnmzZŸ¡¢£¥¦©ª«¬àâãäåæćçèêëìîï\\][¨~‚ƒ…†‡ˆ‰Š‹Œ’’Ç°±²³´µ¾¸¹×Ô]"
gregosheet.recited_notes = "[[Ÿ¡¢£¥¦©ª«¬]"
gregosheet.delimiters = "[-_*]"
gregosheet.symbols = "[sM>#&@{}<¿À÷øÍYXCVBNÈÊËÌÎÏÐÑÒßòôþùý“”•–—˜™š›œº»]"
gregosheet.barlines = "[,.?:;¼ÿ®−§'\"+!%/=()ÖÜÓ]"


-- Convert pattern strings to arrays of UTF-8 codes for more efficient matching
gregosheet.notes_codes = {}
gregosheet.delimiters_codes = {}
gregosheet.symbols_codes = {}
gregosheet.barlines_codes = {}

-- Helper function to convert pattern string to array of UTF-8 codes
function pattern_to_codes(pattern)
  local codes = {}
  for _, code in utf8.codes(pattern) do
    table.insert(codes, code)
  end
  return codes
end

-- Helper function to check if a UTF-8 code is in an array of codes
function code_in_array(code, code_array)
  for _, c in ipairs(code_array) do
    if c == code then
      return true
    end
  end
  return false
end

-- Measure text width in scaled points
function gregosheet.measure_width_sp(text, fontid)
  if not text or text == "" then return 0 end

  local head, last

  for _, c in utf8.codes(text) do
    local g = node.new("glyph")
    g.font = fontid
    g.char = c
    if not head then
      head = g
    else
      last.next = g
      g.prev = last
    end
    last = g
  end

  return node.hpack(head).width
end

-- Accidentals table: { sharp, flat, natural } for each staff position
-- Fill in GuidoHU characters for each position
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

-- Delimiter widths (initialized lazily)
gregosheet.w_s = nil
gregosheet.w_m = nil
gregosheet.w_l = nil

function gregosheet.init_delimiter_widths()
  if gregosheet.w_s then return end
  gregosheet.w_s = gregosheet.measure_width_sp(gregosheet.delimiter_s, gregosheet.music_fontid)
  gregosheet.w_m = gregosheet.measure_width_sp(gregosheet.delimiter_m, gregosheet.music_fontid)
  gregosheet.w_l = gregosheet.measure_width_sp(gregosheet.delimiter_l, gregosheet.music_fontid)
end