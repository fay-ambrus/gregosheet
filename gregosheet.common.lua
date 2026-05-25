gregosheet = gregosheet or {}

-- Debug
gregosheet.debug = false

function gregosheet.debug_print(msg)
  if gregosheet.debug then
    texio.write_nl(msg)
  end
end

-- Delimiter characters
gregosheet.delimiter_s = "¨"
gregosheet.delimiter_m = "-"
gregosheet.delimiter_l = "_"
gregosheet.std_delimiter_sequence = "---"

-- Lyric gap tolerance (sp) — below this, no hyphen is inserted
gregosheet.tolerable_syllable_gap_sp = 73000

-- Character classification patterns (GuidoHU)
gregosheet.notes = "[ðñ0123456789öüó^qwertzuiopõúÝÞQWERTZUIOPÕÚÔasdfghjkléáûØÙASDFGHJKLÉÁÛ`íyxcvbnmzZŸ¡¢£¥¦©ª«¬àâãäåæćçèêëìîï\\][¨~‚ƒ…†‡ˆ‰Š‹Œ''Ç°±²³´µ¾¸¹×Ô]"
gregosheet.recited_notes = "[Ÿ¡¢£[¥¦©ª«¬]"

-- Mapping from recited note glyph to corresponding normal (single) note glyph
gregosheet.recited_to_normal = {
  ["Ÿ"] = "1",
  ["¡"] = "2",
  ["¢"] = "3",
  ["£"] = "4",
  ["["] = "5",
  ["¥"] = "6",
  ["¦"] = "7",
  ["©"] = "8",
  ["ª"] = "9",
  ["«"] = "ö",
  ["¬"] = "ü",
}
gregosheet.delimiters = "[-_*]"
gregosheet.symbols = "[sM>#&@{}<¿À÷øÍYXCVBNÈÊËÌÎÏÐÑÒßòôþùý\u{201c}\u{201d}\u{2022}\u{2013}\u{2014}\u{02dc}\u{2122}\u{0161}\u{203a}\u{0153}\u{00ba}\u{00bb}]"
gregosheet.barlines = "[,.?:;¼ÿ®−§'\"+!%/=()ÖÜÓ]"

-- Code arrays (populated on first use by parse)
gregosheet.notes_codes = {}
gregosheet.delimiters_codes = {}
gregosheet.symbols_codes = {}
gregosheet.barlines_codes = {}

--- Convert a character class pattern string to an array of UTF-8 codepoints.
function gregosheet.pattern_to_codes(pattern)
  local codes = {}
  for _, code in utf8.codes(pattern) do
    table.insert(codes, code)
  end
  return codes
end

--- Check if a UTF-8 codepoint is in a code array.
function gregosheet.code_in_array(code, code_array)
  for _, c in ipairs(code_array) do
    if c == code then return true end
  end
  return false
end

--- Initialize code arrays from pattern strings (call once before parsing).
function gregosheet.init_codes()
  gregosheet.notes_codes = gregosheet.pattern_to_codes(gregosheet.notes)
  gregosheet.delimiters_codes = gregosheet.pattern_to_codes(gregosheet.delimiters)
  gregosheet.symbols_codes = gregosheet.pattern_to_codes(gregosheet.symbols)
  gregosheet.barlines_codes = gregosheet.pattern_to_codes(gregosheet.barlines)
end

-- Delimiter widths in sp (initialized lazily after font is available)
gregosheet.w_s = nil
gregosheet.w_m = nil
gregosheet.w_l = nil

--- Initialize delimiter widths from font metrics. Call after music_fontid is set.
function gregosheet.init_delimiter_widths()
  if gregosheet.w_s then return end
  gregosheet.w_s = gregosheet.measure_width_sp(gregosheet.delimiter_s, gregosheet.music_fontid)
  gregosheet.w_m = gregosheet.measure_width_sp(gregosheet.delimiter_m, gregosheet.music_fontid)
  gregosheet.w_l = gregosheet.measure_width_sp(gregosheet.delimiter_l, gregosheet.music_fontid)
  gregosheet.debug_print("DELIMITERS: w_s=" .. gregosheet.w_s .. " w_m=" .. gregosheet.w_m .. " w_l=" .. gregosheet.w_l)
end
