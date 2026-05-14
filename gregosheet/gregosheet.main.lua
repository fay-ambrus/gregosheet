gregosheet = gregosheet or {}

function gregosheet.main(pieces, clef_mode)
  gregosheet.clef_mode = clef_mode or "all"

  -- Use tone from the last piece only
  local tone_str = ""
  local last_piece = pieces[#pieces]
  if last_piece and last_piece.tone and last_piece.tone ~= "" then
    tone_str = last_piece.tone
  end

  -- Concatenate melodies and lyrics, compute character offsets
  local melody_str = ""
  local lyrics_str = ""
  local piece_offsets = {}

  for i, piece in ipairs(pieces) do
    local mel = piece.melody
    if i > 1 then
      -- Strip leading < from subsequent pieces
      if mel:sub(1, 1) == "<" then
        mel = mel:sub(2)
      end
      lyrics_str = lyrics_str .. " " .. piece.lyrics
    else
      lyrics_str = piece.lyrics
    end

    -- Count codepoints in melody_str so far to get offset
    local offset = 0
    for _ in utf8.codes(melody_str) do
      offset = offset + 1
    end

    table.insert(piece_offsets, {
      melody_start_char = offset + 1,
      title = piece.title or "",
    })

    melody_str = melody_str .. mel
  end

  -- Parse
  local melody = gregosheet.parse_melody(melody_str)
  local lyrics = gregosheet.parse_lyrics(lyrics_str)

  -- Annotate tokens with piece boundaries (skip piece 1, it's always the start)
  local token_idx = 1
  for i = 2, #piece_offsets do
    local start_char = piece_offsets[i].melody_start_char
    while token_idx <= #melody and melody[token_idx].char_pos < start_char do
      token_idx = token_idx + 1
    end
    if token_idx <= #melody then
      melody[token_idx].piece_start = {
        title = piece_offsets[i].title,
      }
    end
  end

  -- Annotate first token with piece 1 title (if any)
  if #piece_offsets > 0 and piece_offsets[1].title ~= "" then
    melody[1].piece_start = {
      title = piece_offsets[1].title,
    }
  end

  local systems = gregosheet.spacing_compute(melody, lyrics, tone_str)
  gregosheet.render(systems)
end
