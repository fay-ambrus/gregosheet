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
      assert.are.equal("-*", delim.glyph)
    end)

    it("deletes delimiter when line already fills page", function()
      local delim = {type = "delimiter", glyph = "-", width_sp = 100}
      gregosheet.pad_line(delim, 1200, 1200)
      assert.are.equal("", delim.glyph)
    end)

    it("adds star when gap is already <= w_star", function()
      local delim = {type = "delimiter", glyph = "-", width_sp = 100}
      gregosheet.pad_line(delim, 1000, 1200)
      assert.are.equal("*", delim.glyph)
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
      assert.are.equal(2, gregosheet.find_break_delimiter(events, 5))
    end)
  end)

  describe("collect_line_syllables", function()
    it("collects syllables referenced by events", function()
      local events = {
        {type = "note", glyph = "1", syllable_idx = 2},
        {type = "delimiter", glyph = "-"},
        {type = "note", glyph = "2", syllable_idx = 3},
      }
      local syllables = {
        {text = "x", start_sp = 0, word_end = true},
        {text = "a", start_sp = 100, word_end = false},
        {text = "b", start_sp = 300, word_end = true},
        {text = "c", start_sp = 500, word_end = true},
      }
      local result = gregosheet.collect_line_syllables(events, syllables, 3)
      assert.are.equal(2, #result)
      assert.are.equal("a", result[1].text)
      assert.are.equal("b", result[2].text)
    end)

    it("includes hyphens between collected syllables", function()
      local events = {
        {type = "note", glyph = "1", syllable_idx = 1},
        {type = "delimiter", glyph = "-"},
        {type = "note", glyph = "2", syllable_idx = 3},
      }
      local syllables = {
        {text = "Do", start_sp = 0, word_end = false},
        {text = "-", start_sp = 150, is_hyphen = true},
        {text = "mi", start_sp = 300, word_end = true},
      }
      local result = gregosheet.collect_line_syllables(events, syllables, 3)
      assert.are.equal(3, #result)
      assert.are.equal("Do", result[1].text)
      assert.is_true(result[2].is_hyphen)
      assert.are.equal("mi", result[3].text)
    end)

    it("returns copies, not references to originals", function()
      local events = {
        {type = "note", glyph = "1", syllable_idx = 1},
      }
      local syllables = {
        {text = "a", start_sp = 100, word_end = true},
      }
      local result = gregosheet.collect_line_syllables(events, syllables, 1)
      result[1].start_sp = nil
      assert.are.equal(100, syllables[1].start_sp)
    end)

    it("returns empty when no events have syllable_idx", function()
      local events = {
        {type = "delimiter", glyph = "-"},
        {type = "piece_boundary", glyph = "M-", clef = "M", key = ""},
      }
      local syllables = {{text = "a", start_sp = 0}}
      local result = gregosheet.collect_line_syllables(events, syllables, 2)
      assert.are.equal(0, #result)
    end)

    it("appends hyphen to last syllable if not word_end", function()
      local events = {
        {type = "note", glyph = "1", syllable_idx = 1},
      }
      local syllables = {
        {text = "Do", start_sp = 0, word_end = false},
        {text = "mi", start_sp = 300, word_end = true},
      }
      local result = gregosheet.collect_line_syllables(events, syllables, 1)
      assert.are.equal(1, #result)
      assert.are.equal("Do-", result[1].text)
    end)

    it("does not collect unreferenced syllables even if in index range", function()
      local events = {
        {type = "note", glyph = "1", syllable_idx = 1},
        {type = "delimiter", glyph = "---"},
        {type = "note", glyph = "2", syllable_idx = 4},
      }
      local syllables = {
        {text = "a", start_sp = 0, word_end = true},
        {text = "x", word_end = true},           -- unreferenced, no start_sp
        {text = "y", start_sp = nil, word_end = true},  -- unreferenced, nil start_sp
        {text = "b", start_sp = 400, word_end = true},
      }
      local result = gregosheet.collect_line_syllables(events, syllables, 3)
      assert.are.equal(2, #result)
      assert.are.equal("a", result[1].text)
      assert.are.equal("b", result[2].text)
    end)
  end)

  describe("find_recited_split_point", function()
    it("returns nil for single-syllable text", function()
      assert.is_nil(gregosheet.find_recited_split_point("hello", 500))
    end)

    it("returns nil when all syllables fit", function()
      -- "Do-mi-nus" = 3 syllables, each ~300sp, available = 1000
      assert.is_nil(gregosheet.find_recited_split_point("Do_mi_nus", 1000))
    end)

    it("splits at the syllable boundary that fits", function()
      -- "Do_mi_nus" = 3 syllables, each 200sp (2 chars * 100), available = 250
      local fit_count, text1, text2 = gregosheet.find_recited_split_point("Dominus", 250)
      assert.are.equal(1, fit_count)
      assert.are.equal("Do", text1)
      assert.are.equal("minus", text2)
    end)

    it("returns nil when nothing fits", function()
      assert.is_nil(gregosheet.find_recited_split_point("Do_mi_nus", 50))
    end)
  end)

  describe("handle_recited_split", function()
    it("returns false for text that does not need splitting", function()
      local events = {
        {type = "note", glyph = "Ÿ", width_sp = 100, syllable_idx = 1, start_sp = 0},
      }
      local syllables = {
        {text = "hello", width_sp = 500, word_end = true},
      }
      assert.is_false(gregosheet.handle_recited_split(events, syllables, 1, 1000))
    end)

    it("keeps chunk1 as recited when >= 4 syllables fit", function()
      local events = {
        {type = "note", glyph = "Ÿ", width_sp = 100, syllable_idx = 1, start_sp = 0},
      }
      local syllables = {
        {text = "Lorem_ipsum_dolor_sit_amet", width_sp = 2600, word_end = true},
      }
      local result = gregosheet.handle_recited_split(events, syllables, 1, 1500)
      assert.is_true(result)
      assert.are.equal("Ÿ", events[1].glyph)
      assert.are.equal("Lorem ipsum do", syllables[1].text)
    end)

    it("expands chunk1 to individual notes when < 4 syllables fit", function()
      local events = {
        {type = "note", glyph = "Ÿ", width_sp = 100, syllable_idx = 1, start_sp = 0},
      }
      local syllables = {
        {text = "Lorem_ipsum_dolor_sit_amet", width_sp = 2600, word_end = true},
      }
      local result = gregosheet.handle_recited_split(events, syllables, 1, 500)
      assert.is_true(result)

      assert.are.equal("1", events[1].glyph)
      assert.are.equal("Lo", syllables[1].text)
      assert.are.is_false(syllables[1].word_end)

      assert.are.equal("1", events[3].glyph)
      assert.are.equal("rem", syllables[2].text)
      assert.are.is_true(syllables[2].word_end)

      assert.are.equal("Ÿ", events[5].glyph)
      assert.are.equal("ipsum dolor sit amet", syllables[3].text)
      assert.are.is_true(syllables[3].word_end)
    end)

    it("appends chunk2 events at end of list", function()
      local events = {
        {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1, start_sp = 0},
        {type = "delimiter", glyph = "---", width_sp = 300},
        {type = "note", glyph = "Ÿ", width_sp = 100, syllable_idx = 2, start_sp = 400},
        {type = "delimiter", glyph = "---", width_sp = 300},
        {type = "note", glyph = "3", width_sp = 100, syllable_idx = 3, start_sp = 800},
      }
      local syllables = {
        {text = "x", width_sp = 100, word_end = true},
        {text = "Lorem_ipsum_dolor_sit_amet", width_sp = 2600, word_end = true},
        {text = "y", width_sp = 100, word_end = true},
      }
      gregosheet.handle_recited_split(events, syllables, 3, 800)
      -- Note "3" should still be after chunk2 events
      local note3_idx = nil
      for i, ev in ipairs(events) do
        if ev.type == "note" and ev.glyph == "3" then note3_idx = i end
      end
      assert.is_not_nil(note3_idx)
      assert.are.equal(#events, note3_idx)
    end)

    it("maintains correct syllable_idx references after split", function()
      local events = {
        {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1, start_sp = 0},
        {type = "delimiter", glyph = "---", width_sp = 300},
        {type = "note", glyph = "Ÿ", width_sp = 100, syllable_idx = 2, start_sp = 400},
        {type = "delimiter", glyph = "---", width_sp = 300},
        {type = "note", glyph = "3", width_sp = 100, syllable_idx = 3, start_sp = 800},
      }
      local syllables = {
        {text = "x", width_sp = 100, word_end = true},
        {text = "Lorem_ipsum_dolor", width_sp = 2600, word_end = true},
        {text = "y", width_sp = 100, word_end = true},
      }
      gregosheet.handle_recited_split(events, syllables, 3, 800)

      assert.are.equal("x", syllables[1].text)
      assert.is_not_nil(syllables[1].width_sp)

      assert.are.equal("Lo", syllables[2].text)
      assert.is_not_nil(syllables[2].width_sp)

      assert.are.equal("rem ipsum dolor", syllables[3].text)
      assert.is_not_nil(syllables[3].width_sp)

      assert.are.equal("y", syllables[4].text)
      assert.is_not_nil(syllables[4].width_sp)
    end)
  end)

  describe("break_into_systems", function()
    it("emits single system when everything fits", function()
      tex.dimen["textwidth"] = 2000
      local events = {
        {type = "piece_boundary", glyph = "M", clef = "M", key = "", width_sp = 100, title = ""},
        {type = "delimiter", glyph = "-", width_sp = 100, fixed = true},
        {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
      }
      local syllables = {
        {text = "a", width_sp = 100, word_end = true},
      }
      local systems = gregosheet.break_into_systems(events, syllables)
      assert.are.equal(1, #systems)
    end)

    it("splits into two systems when content overflows", function()
      tex.dimen["textwidth"] = 600
      local events = {
        {type = "piece_boundary", glyph = "M", clef = "M", key = "", width_sp = 100, title = ""},
        {type = "delimiter", glyph = "---", width_sp = 300},
        {type = "note", glyph = "1", width_sp = 100, syllable_idx = 1},
        {type = "delimiter", glyph = "---", width_sp = 300},
        {type = "note", glyph = "2", width_sp = 100, syllable_idx = 2},
        {type = "delimiter", glyph = "---", width_sp = 300},
        {type = "note", glyph = "3", width_sp = 100, syllable_idx = 3},
      }
      local syllables = {
        {text = "a", width_sp = 100, word_end = true},
        {text = "b", width_sp = 100, word_end = true},
        {text = "c", width_sp = 100, word_end = true},
      }
      local systems = gregosheet.break_into_systems(events, syllables)

      assert.are.equal(3, #systems)

      assert.are.equal("piece_boundary", systems[1].events[1].type)
      assert.are.equal("delimiter", systems[1].events[2].type)
      assert.are.equal("note", systems[1].events[3].type)
      assert.are.equal("delimiter", systems[1].events[4].type)

      assert.is_true(systems[1].events[4].glyph:find("%*") ~= nil)

      assert.are.equal("a", systems[1].syllables[1].text)

      assert.are.equal("piece_boundary", systems[2].events[1].type)
      assert.are.equal("note", systems[2].events[2].type)
      assert.are.equal("delimiter", systems[2].events[3].type)

      assert.is_true(systems[2].events[3].glyph:find("%*") ~= nil)

      assert.are.equal("b", systems[2].syllables[1].text)

      assert.are.equal("piece_boundary", systems[2].events[1].type)
      assert.are.equal("note", systems[3].events[2].type)
      
      assert.are.equal("c", systems[3].syllables[1].text)
    end)
  end)
end)
