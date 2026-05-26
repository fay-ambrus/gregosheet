require("spec.spec_helper")

describe("measure_events", function()
  before_each(function()
    gregosheet.measure_width_sp = function(text, _)
      if not text or text == "" then return 0 end
      return utf8.len(text) * 100
    end
    gregosheet.music_fontid = 1
    gregosheet.w_m = 100
  end)

  it("normalizes non-fixed delimiters to std_delimiter_sequence", function()
    local events = {
      {type = "delimiter", glyph = "-"},
      {type = "delimiter", glyph = "_"},
      {type = "delimiter", glyph = "----", fixed = true},
    }
    gregosheet.measure_events(events)
    assert.are.equal("---", events[1].glyph)
    assert.are.equal("---", events[2].glyph)
    assert.are.equal("----", events[3].glyph)
  end)
end)
