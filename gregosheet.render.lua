gregosheet = gregosheet or {}

function gregosheet.render(systems)
  for sys_idx, system in ipairs(systems) do
    gregosheet.debug_print("RENDER system " .. sys_idx .. ": " .. #system.events .. " events, " .. #system.syllables .. " syllables")
    for i, ev in ipairs(system.events) do
      gregosheet.debug_print("  ev[" .. i .. "] " .. ev.type .. " glyph=" .. (ev.glyph or ""))
    end
    for i, syl in ipairs(system.syllables) do
      gregosheet.debug_print("  syl[" .. i .. "] '" .. (syl.text or "") .. "' start_sp=" .. tostring(syl.start_sp))
    end
    -- Wrap system (title + music + lyrics) in a vbox to keep them together
    tex.sprint("\\vbox{")

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

    for _, event in ipairs(system.events) do
      if event.type == "piece_boundary" then
        tex.sprint(-2, event.glyph or "")
      elseif event.type ~= "comment" and event.glyph and event.glyph ~= "" then
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
        if syl.comment or syl.tone or syl.text == "*" or syl.text == "ANT." then
          tex.sprint("\\textcolor{red}{")
          tex.sprint(-2, syl.text)
          tex.sprint("}")
        else
          tex.sprint(-2, syl.text)
        end
        tex.sprint("\\hss}")
      end
    end

    tex.sprint("\\hss}")
    tex.sprint("}")  -- close vbox

    if sys_idx < #systems then
      tex.sprint("\\vskip\\systemvskip")
    end
  end
end
