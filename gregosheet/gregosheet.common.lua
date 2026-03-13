gregosheet = gregosheet or {}

-- Constants
gregosheet.delimiter_s = "¨"
gregosheet.delimiter_m = "-"
gregosheet.delimiter_l = "_"
gregosheet.std_delimiter_sequence = "---"
gregosheet.tolerable_syllabel_gap_sp = 73000

-- Code tables
gregosheet.notes = "[ðñ0123456789öüó%^qwertzuiopõúÝÞQWERTZUIOPÕÚÔasdfghjkléáûØÙASDFGHJKLÉÁÛ`íyxcvbnmzZŸ¡¢£¥¦©ª«¬àâãäåæçèêëìîï%]%[¨~‚ƒ…†‡ˆ‰Š‹Œ‘’]"
gregosheet.recited_notes = "[%[Ÿ¡¢£¥¦©ª«¬]"
gregosheet.delimiters = "[%-_*]"
gregosheet.symbols = "[¼ÿ®−§'\"+!%%/=()ÖÜÓ%sM>#&@{}<¿À÷øÍYXCVBNÈÊËÌÎÏÐÑÒßòôùý“”•–—˜™š›œº»]"
gregosheet.barlines = "[,.?:;]"

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