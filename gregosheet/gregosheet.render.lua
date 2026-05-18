gregosheet = gregosheet or {}

function gregosheet.render(systems)
  for sys_idx, system in ipairs(systems) do
    -- Render titles above music
    if system.titles and #system.titles > 0 then
      tex.sprint("\\hbox to 0pt{")
      tex.sprint("\\fontsize{\\lyricfontsize}{12}\\selectfont\\lyricfont")
      for _, title in ipairs(system.titles) do
        tex.sprint("\\hbox to 0pt{")
        tex.sprint("\\hskip" .. title.start_sp .. "sp")
        tex.sprint("\\textcolor{red}{\\MakeUppercase{")
        tex.sprint(-2, title.title)
        tex.sprint("}}\\hss}")
      end
      tex.sprint("\\hss}")
      tex.sprint("\\nopagebreak\\vskip\\lyricvskip")
    end

    tex.sprint("\\noindent")

    -- Render music line
    tex.sprint("\\hbox{")
    tex.sprint("\\fontsize{\\musicfontsize}{24}\\selectfont\\MusicFont")
    tex.sprint(-2, system.clef.value)

    for _, event in ipairs(system.events) do
      if event.type == "tone_group" then
        -- Render tone notes with tight "-" delimiters
        for j, sub in ipairs(event.events) do
          tex.sprint(-2, sub.glyph)
          if j < #event.events then
            tex.sprint(-2, gregosheet.delimiter_m)
          end
        end
      elseif event.glyph then
        tex.sprint(-2, event.glyph)
      end
    end
    tex.sprint("}")

    -- Render lyrics line
    tex.sprint("\\nopagebreak\\vskip\\lyricvskip")
    tex.sprint("\\hbox to 0pt{")
    tex.sprint("\\fontsize{\\lyricfontsize}{12}\\selectfont\\lyricfont")

    for _, syl in ipairs(system.syllables) do
      if syl.start_sp and syl.text ~= "" then
        tex.sprint("\\hbox to 0pt{")
        tex.sprint("\\hskip" .. math.floor(syl.start_sp) .. "sp")
        if syl.comment or syl.text == "*" then
          tex.sprint("\\textcolor{red}{")
          tex.sprint(-2, syl.text)
          tex.sprint("}")
        else
          tex.sprint(-2, syl.text)
        end
        tex.sprint("\\hss}")
      end
    end

    -- Render tone group labels in the lyrics line
    for _, event in ipairs(system.events) do
      if event.type == "tone_group" and event.label ~= "" then
        tex.sprint("\\hbox to 0pt{")
        tex.sprint("\\hskip" .. math.floor(event.start_sp or 0) .. "sp")
        tex.sprint("\\textcolor{red}{")
        tex.sprint(-2, event.label)
        tex.sprint("}\\hss}")
      end
    end

    tex.sprint("\\hss}")

    if sys_idx < #systems then
      tex.sprint("\\vskip\\systemvskip")
    end
  end
end
