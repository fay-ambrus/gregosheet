require("spec.spec_helper")

describe("extract_leading_symbols", function()
  before_each(function()
    gregosheet.init_codes()
  end)

  it("errors when no symbol token present", function()
    local tokens = {{type = "note", glyph = "123"}}
    assert.has_error(function()
      gregosheet.extract_leading_symbols(tokens)
    end)
  end)

  it("errors on invalid clef character", function()
    local tokens = {{type = "symbol", glyph = "s"}}
    assert.has_error(function()
      gregosheet.extract_leading_symbols(tokens)
    end, "Invalid clef character: 's'")
  end)

  it("extracts clef", function()
    local tokens = {{type = "symbol", glyph = "M"}, {type = "note", glyph = "12"}}
    local clef, key = gregosheet.extract_leading_symbols(tokens)
    assert.are.equal("M", clef)
    assert.are.equal("", key)
    assert.are.equal(1, #tokens)
  end)

  it("extracts key from same token", function()
    local tokens = {{type = "symbol", glyph = "MXB"}, {type = "note", glyph = "12"}}
    local clef, key = gregosheet.extract_leading_symbols(tokens)
    assert.are.equal("M", clef)
    assert.are.equal("XB", key)
    assert.are.equal(1, #tokens)
    assert.are.equal("note", tokens[1].type)
  end)

end)

describe("merge", function()
    before_each(function()
        gregosheet.init_codes()
    end)

    local function make_piece(melody, lyrics, opts)
        opts = opts or {}
        return {
            melody_tokens = gregosheet.parse_melody(melody),
            lyric_syllables = gregosheet.parse_lyrics(lyrics),
            title = opts.title or "",
            tone_melody = opts.tone_melody,
            tone_label = opts.tone_label,
        }
    end

    it("converts clef and key signature", function()
        local piece1 = make_piece("MXB-1w-1t-.", "a-b")
        local piece2 = make_piece("M-3r-.", "b")
        local events, _ = gregosheet.merge({piece1, piece2})

        -- piece boundary1
        assert.are.equal("piece_boundary", events[1].type)
        assert.are.equal("MXB", events[1].glyph)
        assert.are.equal("M", events[1].clef)
        assert.are.equal("XB", events[1].key)
        assert.are.equal("", events[1].title)

        assert.are.equal("delimiter", events[8].type)

        -- piece boundary2
        assert.are.equal("piece_boundary", events[9].type)
        assert.are.equal("™œ", events[9].glyph)
        assert.are.equal("M", events[9].clef)
        assert.are.equal("", events[9].key)
        assert.are.equal("", events[9].title)
    end)

    it("pairs syllables with notes", function()
        local _, syllables = gregosheet.merge({make_piece("MXB-1w-1t-.", "a-b")})
        
        assert.are.equal(2, #syllables)

        assert.are.equal("a", syllables[1].text)
        assert.is_false(syllables[1].word_end)
        assert.is_false(syllables[1].comment)

        assert.are.equal("b", syllables[2].text)
        assert.is_true(syllables[2].word_end)
        assert.is_false(syllables[2].comment)
    end)

    it("inserts empty syllable when lyrics run out", function()
        local _, syllables = gregosheet.merge({make_piece("M-12-34-56", "a")})
        
        assert.are.equal(3, #syllables)

        assert.are.equal("a", syllables[1].text)
        assert.is_true(syllables[1].word_end)

        assert.are.equal("", syllables[2].text)
        assert.is_true(syllables[2].word_end)
        
        assert.are.equal("", syllables[3].text)
        assert.is_true(syllables[3].word_end)
    end)

    it("does not insert excess syllables", function()
        local piece1 = make_piece("MX-0q-1-.", "Ör-ven-dez-zünk")
        local piece2 = make_piece("M-3r-.", "b")
        local _, syllables = gregosheet.merge({piece1, piece2})
        
        assert.are.equal(3, #syllables)

        assert.are.equal("Ör", syllables[1].text)
        assert.is_false(syllables[1].word_end)

        assert.are.equal("ven", syllables[2].text)
        assert.is_true(syllables[2].word_end)
        
        assert.are.equal("b", syllables[3].text)
        assert.is_true(syllables[3].word_end)
    end)

    it("handles floating_text", function()
        local piece = make_piece("MXB-1w-3r.", "a-b")
        local events, syllables = gregosheet.merge({
            {type = "floating_text", text = "T.P."},
            piece
        })

        assert.are.equal("piece_boundary", events[1].type)
        assert.are.equal("delimiter", events[2].type)
        assert.are.equal("comment", events[3].type)
        assert.are.equal("T.P.", syllables[events[3].syllable_idx].text)
        assert.are.equal("delimiter", events[2].type)
    end)

    it("puts * under barlines", function()
        local piece = make_piece("MXB-1w-3r-,,-4f2-3r-.", "a-b * c-d")
        local _, syllables = gregosheet.merge({piece})

        assert.are.equal(5, #syllables)
        
        assert.are.equal("a", syllables[1].text)
        assert.are.equal("b", syllables[2].text)    
        assert.are.equal("*", syllables[3].text)
        assert.are.equal("c", syllables[4].text)
        assert.are.equal("d", syllables[5].text)
    end)

    it("inserts tone label on first note and empty on rest", function()
        local _, syllables = gregosheet.merge({
            make_piece("M-12", "a", {tone_melody = "M-34-56", tone_label = "8. szó tónus"})
        })
        local tone_syls = {}
        for _, s in ipairs(syllables) do
            if s.tone then table.insert(tone_syls, s) end
        end
        assert.are.equal(2, #tone_syls)
        assert.are.equal("8. szó tónus", tone_syls[1].text)
        assert.are.equal("", tone_syls[2].text)
    end)

    it("fixes tone delimiters to single dash", function()
        local events, _ = gregosheet.merge({
            make_piece("M-12-,,", "a", {tone_melody = "M-7--7-6-7-5---4-.", tone_label = "x"})
        })
        for _, e in ipairs(events) do
            if e.type == "delimiter" and e.fixed then
                assert.are.equal("-", e.glyph)
            end
        end
    end)

  it("creates comment events", function()
    local piece = make_piece("M-12-34", "<T.P.> a-b")
    local events, syllables = gregosheet.merge({piece})

    assert.are.equal("piece_boundary", events[1].type)

    assert.are.equal("delimiter", events[2].type)
    assert.is_true(events[2].fixed)

    assert.are.equal("comment", events[3].type)
    local comment_syl = syllables[events[3].syllable_idx]
    assert.are.equal("T.P.", comment_syl.text)
    assert.is_true(comment_syl.comment)

    assert.are.equal("delimiter", events[4].type)
    assert.is_true(events[4].fixed)

    assert.are.equal("note", events[5].type)
  end)

  it("comments do not consume notes", function()
    local piece = make_piece("M-12-34", "<T.P.> a-b")
    local events, syllables = gregosheet.merge({piece})

    assert.are.equal("piece_boundary", events[1].type)
    assert.are.equal("delimiter", events[2].type)

    local syl = syllables[events[3].syllable_idx]
    assert.are.equal("T.P.", syl.text)
    assert.is_true(syl.comment)

    syl = syllables[events[5].syllable_idx]
    assert.are.equal("a", syl.text)
    assert.is_false(syl.comment)

    syl = syllables[events[7].syllable_idx]
    assert.are.equal("b", syl.text)
    assert.is_false(syl.comment)
  end)
end)
