gregosheet = gregosheet or {}

function gregosheet.main(melody_str, lyrics_str, tone_str)
  local melody = gregosheet.parse_melody(melody_str)
  local lyrics = gregosheet.parse_lyrics(lyrics_str)
  local systems = gregosheet.spacing_compute(melody, lyrics, tone_str)
  gregosheet.render(systems)
end
