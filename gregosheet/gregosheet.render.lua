gregosheet = gregosheet or {}

function gregosheet.render(systems)
  for sys_idx, system in ipairs(systems) do
    tex.sprint("\\noindent")

    -- Create music hbox
    tex.sprint("\\hbox{")
    tex.sprint("\\fontsize{\\musicfontsize}{24}\\selectfont\\MusicFont")
    tex.sprint(system.clef.value)

    for i, token in ipairs(system.melody) do
      tex.sprint(token.value)
    end
    tex.sprint("}")

    -- Create lyrics line with absolute positioning
    tex.sprint("\\vskip\\lyricvskip")
    tex.sprint("\\hbox to 0pt{")
    tex.sprint("\\fontsize{\\lyricfontsize}{12}\\selectfont\\lyricfont")

    for i, lyric in ipairs(system.lyrics) do
      if lyric.start_sp then
        tex.sprint("\\hbox to 0pt{")
        tex.sprint("\\hskip" .. lyric.start_sp .. "sp")
        tex.sprint(-2, lyric.text)
        tex.sprint("\\hss}")
      end
    end

    tex.sprint("\\hss}")

    if sys_idx < #systems then
      tex.sprint("\\vskip\\systemvskip")
    end
  end
end
