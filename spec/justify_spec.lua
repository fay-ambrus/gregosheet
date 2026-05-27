require("spec.spec_helper")

describe("justify", function()
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
    gregosheet.space_width_sp = 100
    gregosheet.hyphen_width_sp = 100
    gregosheet.tolerable_syllable_gap_sp = 300
  end)

  it("centers text wider than its glyph", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
    }
    local syllables = {
      {text = "Dom", width_sp = 300, word_end = true},
    }
    gregosheet.justify(events, syllables, math.huge)
    assert.are.equal(-100, syllables[1].start_sp)
  end)

  it("left-aligns text narrower than its glyph", function()
    local events = {
      {type = "note", glyph = "123", width_sp = 300, syllable_idx = 1},
    }
    local syllables = {
      {text = "a", width_sp = 100, word_end = true},
    }
    gregosheet.justify(events, syllables, math.huge)
    assert.are.equal(0, syllables[1].start_sp)
  end)

  it("left-aligns text under a recited note", function()
    local events = {
      {type = "note", glyph = "Ÿ", width_sp = 100, syllable_idx = 1},
    }
    local syllables = {
      {text = "long recited text", width_sp = 1700, word_end = true},
    }
    gregosheet.justify(events, syllables, math.huge)
    assert.are.equal(0, syllables[1].start_sp)
  end)

  it("elongates delimiters to resolve lyric overlap", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      {type = "delimiter", glyph = "---", width_sp = 300},
      {type = "note", glyph = "2", width_sp = 100, syllable_idx = 2},
    }
    local syllables = {
      {text = "longword", width_sp = 800, word_end = true},
      {text = "b", width_sp = 100, word_end = true},
    }
    gregosheet.justify(events, syllables, math.huge)
    local first_end = syllables[1].start_sp + syllables[1].width_sp
    assert.is_true(syllables[2].start_sp >= first_end)
  end)

  it("inserts hyphen when gap exceeds tolerable limit", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      {type = "delimiter", glyph = "------", width_sp = 600},
      {type = "note", glyph = "2", width_sp = 100, syllable_idx = 2},
    }
    local syllables = {
      {text = "Do", width_sp = 100, word_end = false},
      {text = "mi", width_sp = 100, word_end = true},
    }
    gregosheet.justify(events, syllables, math.huge)

    assert.are.equal(3, #syllables)
    assert.falsy(syllables[1].is_hyphen)
    assert.are.equal("Do", syllables[1].text)

    assert.is_true(syllables[2].is_hyphen)
    assert.are.equal("-", syllables[2].text)
    assert.are.equal(350, syllables[2].start_sp)

    assert.falsy(syllables[3].is_hyphen)
    assert.are.equal("mi", syllables[3].text)
  end)

  it("does not insert hyphen when gap is under limit", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      {type = "delimiter", glyph = "--", width_sp = 200},
      {type = "note", glyph = "2", width_sp = 100, syllable_idx = 2},
    }
    local syllables = {
      {text = "Do", width_sp = 100, word_end = false},
      {text = "mi", width_sp = 100, word_end = true},
    }
    gregosheet.justify(events, syllables, math.huge)

    assert.are.equal(2, #syllables)
    assert.falsy(syllables[1].is_hyphen)
    assert.are.equal("Do", syllables[1].text)

    assert.falsy(syllables[2].is_hyphen)
    assert.are.equal("mi", syllables[2].text)
  end)

  it("recognizes overflow of music and returns correct index", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      {type = "delimiter", glyph = "---", width_sp = 300},
      {type = "note", glyph = "2", width_sp = 100, syllable_idx = 2},
    }
    local syllables = {
      {text = "a", width_sp = 100, word_end = true},
      {text = "b", width_sp = 100, word_end = true},
    }
    local overflow_idx = gregosheet.justify(events, syllables, 350)
    assert.are.equal(2, overflow_idx)
  end)

  it("recognizes overflow of lyrics and returns correct index", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
    }
    local syllables = {
      {text = "verylongtext", width_sp = 1200, word_end = true},
    }
    local overflow_idx = gregosheet.justify(events, syllables, 500)
    assert.are.equal(1, overflow_idx)
  end)

  it("enforces fixed delimiters around barlines", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      {type = "delimiter", glyph = "---", width_sp = 300},
      {type = "barline", glyph = ",", width_sp = 100},
      {type = "delimiter", glyph = "---", width_sp = 300},
      {type = "note", glyph = "2", width_sp = 100, syllable_idx = 2},
    }
    local syllables = {
      {text = "a", width_sp = 100, word_end = true},
      {text = "b", width_sp = 100, word_end = true},
    }
    gregosheet.justify(events, syllables, math.huge)
    assert.are.equal("-", events[2].glyph)
    assert.are.equal("--", events[4].glyph)
  end)

  it("does not enforce fixed delimiters when delimiters are already fixed", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      {type = "delimiter", glyph = "---", width_sp = 300, fixed = true},
      {type = "barline", glyph = ".", width_sp = 100},
      {type = "delimiter", glyph = "-", width_sp = 300, fixed = true},
    }
    local syllables = {
      {text = "a", width_sp = 100, word_end = true},
    }
    gregosheet.justify(events, syllables, math.huge)
    assert.are.equal("---", events[2].glyph)
    assert.are.equal("-", events[4].glyph)
  end)

  it("places comment centered under its zero-width event", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      {type = "delimiter", glyph = "---", width_sp = 300},
      {type = "comment", glyph = "", width_sp = 0, syllable_idx = 2},
      {type = "delimiter", glyph = "", width_sp = 0},
      {type = "note", glyph = "2", width_sp = 100, syllable_idx = 3},
    }
    local syllables = {
      {text = "a", width_sp = 100, word_end = true},
      {text = "T.P.", width_sp = 400, word_end = true, comment = true},
      {text = "b", width_sp = 100, word_end = true},
    }
    gregosheet.justify(events, syllables, math.huge)
    assert.are.equal(200, syllables[2].start_sp)
  end)

  it("places psalm tone text left-aligned under its note", function()
    local events = {
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      {type = "delimiter", glyph = "-", width_sp = 100, fixed = true},
      {type = "note", glyph = "2", width_sp = 100, syllable_idx = 2},
    }
    local syllables = {
      {text = "a", width_sp = 100, word_end = true},
      {text = "8. tónus", width_sp = 800, word_end = true, tone = true},
    }
    gregosheet.justify(events, syllables, math.huge)
    assert.are.equal(200, syllables[2].start_sp)
  end)
end)

  it("returns last clef and key from piece boundaries", function()
    local events = {
      {type = "piece_boundary", glyph = "MXB", clef = "M", key = "XB", width_sp = 300, title = ""},
      {type = "delimiter", glyph = "-", width_sp = 100, fixed = true},
      {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      {type = "piece_boundary", glyph = "N", clef = "N", key = "", width_sp = 100, title = ""},
      {type = "delimiter", glyph = "-", width_sp = 100, fixed = true},
      {type = "note", glyph = "2", width_sp = 100, syllable_idx = 2},
    }
    local syllables = {
      {text = "a", width_sp = 100, word_end = true},
      {text = "b", width_sp = 100, word_end = true},
    }
    local _, last_clef, last_key = gregosheet.justify(events, syllables, math.huge)
    assert.are.equal("N", last_clef)
    assert.are.equal("", last_key)
  end)
