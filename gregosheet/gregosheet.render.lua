gregosheet = gregosheet or {}

local function render_tone(tone_str, tone_start_sp)
  tex.sprint("\\hbox to 0pt{")
  tex.sprint("\\hskip" .. tone_start_sp .. "sp")
  tex.sprint("\\textcolor{red}{")
  tex.sprint(-2, tone_str)
  tex.sprint("}\\hss}")
end

function gregosheet.render(systems)
  for sys_idx, system in ipairs(systems) do
    -- Render titles above music (only if this system has any)
    if system.titles and #system.titles > 0 then
      tex.sprint("\\hbox to 0pt{")
      tex.sprint("\\fontsize{\\lyricfontsize}{12}\\selectfont\\lyricfont")
      for _, title in ipairs(system.titles) do
        if title.title ~= "" then
          tex.sprint("\\hbox to 0pt{")
          tex.sprint("\\hskip" .. title.start_sp .. "sp")
          tex.sprint("\\textcolor{red}{\\MakeUppercase{")
          tex.sprint(-2, title.title)
          tex.sprint("}}\\hss}")
        end
      end
      tex.sprint("\\hss}")
      tex.sprint("\\nopagebreak\\vskip\\lyricvskip")
    end

    tex.sprint("\\noindent")

    -- Create music hbox
    tex.sprint("\\hbox{")
    tex.sprint("\\fontsize{\\musicfontsize}{24}\\selectfont\\MusicFont")
    tex.sprint(system.clef.value)

    for i, token in ipairs(system.melody) do
      tex.sprint(-2, token.value)
    end
    tex.sprint("}")

    -- Create lyrics line with absolute positioning
    tex.sprint("\\nopagebreak\\vskip\\lyricvskip")
    tex.sprint("\\hbox to 0pt{")
    tex.sprint("\\fontsize{\\lyricfontsize}{12}\\selectfont\\lyricfont")

    for i, lyric in ipairs(system.lyrics) do
      if lyric.start_sp then
        tex.sprint("\\hbox to 0pt{")
        tex.sprint("\\hskip" .. lyric.start_sp .. "sp")
        if lyric.text == "*" or lyric.text == "ANT." or lyric.text == "REF." or lyric.comment then
          tex.sprint("\\textcolor{red}{")
          tex.sprint(-2, lyric.text)
          tex.sprint("}")
        else
          tex.sprint(-2, lyric.text)
        end
        tex.sprint("\\hss}")
      end
    end

    -- Add tone on current line if it fits
    if system.tone and not system.tone.new_line then
      render_tone(system.tone.tone_str, system.tone.start_sp)
    end

    tex.sprint("\\hss}")

    -- Add tone on new line if it doesn't fit
    if system.tone and system.tone.new_line then
      render_tone(system.tone.tone_str, system.tone.start_sp)
    end

    if sys_idx < #systems then
      tex.sprint("\\vskip\\systemvskip")
    end
  end
end
