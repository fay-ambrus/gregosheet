require("spec.spec_helper")

describe("break", function()
  before_each(function()
    gregosheet.recited_notes = "[Ÿ¡¢£¥¦©ª«¬]"
    gregosheet.init_codes()
    gregosheet.measure_width_sp = function(text, _)
      if not text or text == "" then return 0 end
      local w = 0
      for _, code in utf8.codes(text) do
        local ch = utf8.char(code)
        if ch == gregosheet.delimiter_l then w = w + 200
        elseif ch == gregosheet.delimiter_m then w = w + 100
        elseif ch == gregosheet.delimiter_s then w = w + 50
        elseif ch == gregosheet.delimiter_star then w = w + 300
        else w = w + 100
        end
      end
      return w
    end
    gregosheet.music_fontid = 1
    gregosheet.lyrics_fontid = 2
    gregosheet.w_s = 50
    gregosheet.w_m = 100
    gregosheet.w_l = 200
    gregosheet.w_star = 300
    gregosheet.space_width_sp = 100
    gregosheet.hyphen_width_sp = 100
    gregosheet.tolerable_syllable_gap_sp = 300
  end)

  describe("pad_line", function()
    it("adds dashes and star to fill the gap", function()
      local delim = {type = "delimiter", glyph = "-", width_sp = 100}
      gregosheet.pad_line(delim, 800, 1200)
      -- gap = 400. Add "-" until gap <= 300: one dash (gap becomes 300). Then add "*".
      assert.are.equal("-" .. "-" .. "*", delim.glyph)
    end)

    it("does nothing when line already fills page", function()
      local delim = {type = "delimiter", glyph = "-", width_sp = 100}
      gregosheet.pad_line(delim, 1200, 1200)
      assert.are.equal("-", delim.glyph)
    end)

    it("adds only star when gap is already <= w_star", function()
      local delim = {type = "delimiter", glyph = "-", width_sp = 100}
      gregosheet.pad_line(delim, 1000, 1200)
      -- gap = 200 <= 300 (w_star), just add "*"
      assert.are.equal("-*", delim.glyph)
    end)
  end)

  describe("find_break_delimiter", function()
    it("returns overflow index if it is a delimiter", function()
      local events = {
        {type = "note", glyph = "1"},
        {type = "delimiter", glyph = "---"},
        {type = "note", glyph = "2"},
      }
      assert.are.equal(2, gregosheet.find_break_delimiter(events, 2))
    end)

    it("scans back to find last delimiter before overflow", function()
      local events = {
        {type = "note", glyph = "1"},
        {type = "delimiter", glyph = "---"},
        {type = "note", glyph = "2"},
        {type = "delimiter", glyph = "---"},
        {type = "note", glyph = "3"},
      }
      assert.are.equal(4, gregosheet.find_break_delimiter(events, 5))
    end)

    it("skips delimiter immediately before a barline", function()
      local events = {
        {type = "note", glyph = "1"},
        {type = "delimiter", glyph = "---"},
        {type = "note", glyph = "2"},
        {type = "delimiter", glyph = "-"},
        {type = "barline", glyph = ","},
        {type = "delimiter", glyph = "--"},
        {type = "note", glyph = "3"},
      }
      -- Overflow at 7 (note "3"). Scan back: delimiter at 6 is after barline (ok).
      -- But delimiter at 4 is before barline → skip. Go to delimiter at 2.
      assert.are.equal(6, gregosheet.find_break_delimiter(events, 7))
    end)
  end)

  describe("break_into_systems", function()
    it("emits single system when everything fits", function()
      tex.dimen["textwidth"] = 2000
      local events = {
        {type = "piece_boundary", glyph = "M-", clef = "M", key = "", width_sp = 200, title = ""},
        {type = "delimiter", glyph = "-", width_sp = 100, fixed = true},
        {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      }
      local syllables = {
        {text = "a", width_sp = 100, word_end = true},
      }
      local systems = gregosheet.break_into_systems(events, syllables)
      assert.are.equal(1, #systems)
    end)
  end)
end)
