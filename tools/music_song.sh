#!/usr/bin/env bash
# Turns a song (any audio or video file ffmpeg can read) into a Polox music file, the way the songs in
# assets/music were made (1.27.8): audio only, trailing silence below -50 dB trimmed (keeping 0.1 s),
# levelled to -18 LUFS with plain gain (no limiter: check the true peak it prints stays under 0 dBTP),
# 10 ms fade in and 30 ms fade out so the loop seam never clicks, Ogg Vorbis q3, 44.1 kHz stereo, no
# metadata.
#   tools/music_song.sh <input file> assets/music/<id>.ogg
# Then: add [id, title, where it's from, seconds] to SONGS in scripts/world/music_player.gd, import it
# (tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --import), set loop=true in its
# .ogg.import and import again.
set -e
in="$1"
out="$2"
if [ -z "$in" ] || [ -z "$out" ]; then
  echo "usage: tools/music_song.sh <input file> assets/music/<id>.ogg" >&2
  exit 2
fi
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$in")
il=$(ffmpeg -hide_banner -nostats -i "$in" -vn -af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 | grep '"input_i"' | grep -o '[-0-9.]*' | head -1)
# The last stretch of silence that runs to the end of the file (silencedetect reports its end as the duration).
end=$(ffmpeg -hide_banner -nostats -i "$in" -vn -af silencedetect=noise=-50dB:d=0.25 -f null - 2>&1 | awk -v d="$dur" '
  /silence_start:/ { for (i = 1; i <= NF; i++) if ($i == "silence_start:") s = $(i + 1) }
  /silence_end:/   { for (i = 1; i <= NF; i++) if ($i == "silence_end:") e = $(i + 1); if (d - e < 0.05) tail = s }
  END { if (tail != "") printf "%.3f", tail + 0.1; else printf "%.3f", d }')
gain=$(awk -v i="$il" 'BEGIN { printf "%.2f", -18 - i }')
fo=$(awk -v e="$end" 'BEGIN { printf "%.3f", e - 0.03 }')
ffmpeg -hide_banner -loglevel error -y -i "$in" -vn -map 0:a:0 \
  -af "atrim=0:$end,asetpts=PTS-STARTPTS,volume=${gain}dB,afade=t=in:d=0.01,afade=t=out:st=$fo:d=0.03" \
  -c:a libvorbis -q:a 3 -ar 44100 -ac 2 -map_metadata -1 "$out"
check=$(ffmpeg -hide_banner -nostats -i "$out" -af loudnorm=print_format=json -f null - 2>&1 | grep -E '"input_(i|tp)"' | grep -o '[-0-9.]*' | tr '\n' ' ')
printf "%s: %.1f of %.1f s, gain %s dB -> loudness / true peak: %s\n" "$out" "$end" "$dur" "$gain" "$check"
