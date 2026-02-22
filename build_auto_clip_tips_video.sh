#!/usr/bin/env bash
set -euo pipefail
# Ensure decimal values use dot for ffmpeg/awk expressions.
export LC_NUMERIC=C

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'USAGE'
Usage:
  ./build_auto_clip_tips_video.sh [--text "...."] [--text-file path]

Options:
  --text        Empfehlungstext direkt uebergeben
  --text-file   Datei mit Empfehlungstext (default: assets/videos/auto-clip-tips-script.txt)
  --voice       macOS Stimme fuer say (default: Anna)
  --ai          Text zuerst ueber KI-Agenten umschreiben (Wally/Trixi/Herbie)
  --morph-steps Anzahl Zwischenbilder pro Bildpaar (default: 4)
  --min-duration Mindestlaenge des Videos in Sekunden (default: 26)
  --frame-sec   Zielzeit je Bildframe in Sekunden (default: 0.16, kleiner = schneller)
  --no-webm     nur MP4 erzeugen
  -h, --help    Hilfe anzeigen

Output:
  assets/videos/auto-clip-tips-main.mp4
  assets/videos/auto-clip-tips-main.webm (optional)
USAGE
}

die() {
  echo "[!] $*" >&2
  exit 1
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "Missing command: $c"
}

escape_ffconcat_path() {
  printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

TEXT_FILE="assets/videos/auto-clip-tips-script.txt"
INPUT_TEXT=""
TTS_VOICE="${TTS_VOICE:-Anna}"
GENERATE_WEBM=1
TIPS_AI_ENABLED="${TIPS_AI_ENABLED:-0}"
TIPS_AI_PROVIDER="${TIPS_AI_PROVIDER:-ollama}"
TIPS_AI_MODEL="${TIPS_AI_MODEL:-qwen2.5:7b}"
TIPS_AI_DEBUG="${TIPS_AI_DEBUG:-0}"
TIPS_MORPH_STEPS="${TIPS_MORPH_STEPS:-4}"
TIPS_MIN_DURATION="${TIPS_MIN_DURATION:-26}"
TIPS_FRAME_SEC="${TIPS_FRAME_SEC:-0.16}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --text)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --text"
      INPUT_TEXT="$1"
      ;;
    --text-file)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --text-file"
      TEXT_FILE="$1"
      ;;
    --voice)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --voice"
      TTS_VOICE="$1"
      ;;
    --ai)
      TIPS_AI_ENABLED=1
      ;;
    --morph-steps)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --morph-steps"
      TIPS_MORPH_STEPS="$1"
      ;;
    --min-duration)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --min-duration"
      TIPS_MIN_DURATION="$1"
      ;;
    --frame-sec)
      shift
      [[ $# -gt 0 ]] || die "Missing value for --frame-sec"
      TIPS_FRAME_SEC="$1"
      ;;
    --no-webm)
      GENERATE_WEBM=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
  shift
done

require_cmd ffmpeg
require_cmd ffprobe
require_cmd python3

run_agent_rewrite() {
  local source_text="$1"
  local prompt=""
  local output=""
  local debug_file="$TMP_DIR/agent.debug.txt"

  case "$TIPS_AI_PROVIDER" in
    ollama)
      command -v ollama >/dev/null 2>&1 || return 1
      ollama list >/dev/null 2>&1 || return 1
      ollama show "$TIPS_AI_MODEL" >/dev/null 2>&1 || return 1
      prompt="$(cat <<EOF
Du bist Wally, ein klarer, direkter Sprecher fuer Auto-Clip Tips.
Arbeite intern mit drei Rollen und gib NUR den finalen Sprechertext aus:
1) Wally: 3 klare Schritte
2) Trixi: schnellster pragmatischer Weg
3) Herbie: Sinn-Check, was fehlt

Regeln:
- Deutsch
- Maximal 85 Woerter
- Kurz, konkret, freundlich
- Keine Emojis, keine Hashtags
- Keine Meta-Erklaerung
- Keine Rollen in der Ausgabe

Quelle:
$source_text
EOF
)"
      output="$(ollama run "$TIPS_AI_MODEL" "$prompt" 2>/dev/null || true)"
      ;;
    none)
      output="$source_text"
      ;;
    *)
      return 1
      ;;
  esac

  output="$(printf '%s' "$output" | tr '\r' '\n' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -n "$output" ]] || return 1

  if [[ "$TIPS_AI_DEBUG" = "1" ]]; then
    {
      echo "provider=$TIPS_AI_PROVIDER"
      echo "model=$TIPS_AI_MODEL"
      echo
      echo "[SOURCE]"
      echo "$source_text"
      echo "[/SOURCE]"
      echo
      echo "[OUTPUT]"
      echo "$output"
      echo "[/OUTPUT]"
    } > "$debug_file"
  fi

  printf '%s\n' "$output"
  return 0
}

if [[ -z "$INPUT_TEXT" ]]; then
  if [[ -f "$TEXT_FILE" ]]; then
    INPUT_TEXT="$(cat "$TEXT_FILE")"
  else
    mkdir -p "$(dirname "$TEXT_FILE")"
    cat > "$TEXT_FILE" <<'TXT'
Auto-Clip Tipp: Fuehre jede Aenderung kurz und klar aus.
Zeige immer den konkreten Nutzen fuer den Workflow.
Belege jede Empfehlung mit 3 main-Links aus dem Repo.
TXT
    INPUT_TEXT="$(cat "$TEXT_FILE")"
  fi
fi

INPUT_TEXT="$(printf '%s' "$INPUT_TEXT" | tr '\r' '\n' | sed 's/[[:space:]]*$//')"
[[ -n "${INPUT_TEXT//[[:space:]]/}" ]] || die "Empty input text."
[[ "$TIPS_MORPH_STEPS" =~ ^[0-9]+$ ]] || die "--morph-steps must be >= 0"
[[ "$TIPS_MIN_DURATION" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--min-duration must be numeric"
[[ "$TIPS_FRAME_SEC" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--frame-sec must be numeric"

OUT_DIR="assets/videos"
OUT_MP4="$OUT_DIR/auto-clip-tips-main.mp4"
OUT_WEBM="$OUT_DIR/auto-clip-tips-main.webm"
TMP_DIR=".tmp/tips-video"
mkdir -p "$OUT_DIR" "$TMP_DIR"

NARRATION_FILE="$OUT_DIR/auto-clip-tips-spoken.txt"
VOICE_AIFF="$TMP_DIR/voice.aiff"
VOICE_WAV="$TMP_DIR/voice.wav"
SLIDESHOW_LIST="$TMP_DIR/slideshow.txt"

WIDTH=1280
HEIGHT=720
FPS=30
VIDEO_PAD=0.6
FALLBACK_WORDS_PER_SEC=2.6
FALLBACK_MIN_SEC=8

spoken_core="$(printf '%s' "$INPUT_TEXT" | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g')"
if [[ "$TIPS_AI_ENABLED" = "1" ]]; then
  if agent_text="$(run_agent_rewrite "$spoken_core")"; then
    spoken_core="$agent_text"
    echo "[+] KI-Agent: aktiv ($TIPS_AI_PROVIDER:$TIPS_AI_MODEL)"
  else
    echo "[!] KI-Agent nicht verfuegbar, nutze Originaltext."
  fi
fi

narration_text="Wally hier. ${spoken_core} Danke fuers Testen von Auto-Clip."

printf '%s\n' "$narration_text" > "$NARRATION_FILE"

voice_duration=""
if command -v say >/dev/null 2>&1; then
  echo "[+] TTS: say -v $TTS_VOICE"
  if say -v "$TTS_VOICE" -f "$NARRATION_FILE" -o "$VOICE_AIFF" 2>/dev/null; then
    ffmpeg -y -loglevel error -i "$VOICE_AIFF" -ar 48000 -ac 2 "$VOICE_WAV"
    voice_duration="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$VOICE_WAV" || true)"
  fi
fi

if [[ -z "$voice_duration" ]]; then
  words="$(printf '%s' "$narration_text" | wc -w | tr -d ' ')"
  voice_duration="$(awk -v w="$words" -v min="$FALLBACK_MIN_SEC" -v rate="$FALLBACK_WORDS_PER_SEC" 'BEGIN{d=w/rate; if(d<min)d=min; printf "%.3f", d}')"
  ffmpeg -y -loglevel error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t "$voice_duration" "$VOICE_WAV"
fi

total_dur="$(awk -v d="$voice_duration" -v p="$VIDEO_PAD" -v min="$TIPS_MIN_DURATION" 'BEGIN{t=d+p; if(t<min)t=min; printf "%.3f", t}')"

WALLY_IMAGES=()
while IFS= read -r img; do
  WALLY_IMAGES+=("$img")
done < <(find "$ROOT_DIR/pipeline/assets" -maxdepth 1 -type f \( -iname 'wally-[0-9]*.jpg' -o -iname 'wally-[0-9]*.jpeg' -o -iname 'wally-[0-9]*.png' \) | sort)

(( ${#WALLY_IMAGES[@]} > 0 )) || die "No wally-<n> images found in pipeline/assets."
echo "[+] Wally-Frames: ${#WALLY_IMAGES[@]} Quelle(n)"

NORMALIZED_IMAGES=()
img_idx=0
for src_img in "${WALLY_IMAGES[@]}"; do
  norm_img="$TMP_DIR/norm_${img_idx}.png"
  ffmpeg -y -loglevel error -i "$src_img" \
    -vf "scale=$WIDTH:$HEIGHT:force_original_aspect_ratio=increase,crop=$WIDTH:$HEIGHT,format=rgba" \
    -frames:v 1 "$norm_img"
  [[ -s "$norm_img" ]] || die "Failed to normalize image: $src_img"
  NORMALIZED_IMAGES+=("$norm_img")
  img_idx=$((img_idx + 1))
done

MORPH_IMAGES=()
morph_steps_int=$((TIPS_MORPH_STEPS))
if (( ${#NORMALIZED_IMAGES[@]} > 1 && morph_steps_int > 0 )); then
  for ((i=0; i<${#NORMALIZED_IMAGES[@]}; i++)); do
    a="${NORMALIZED_IMAGES[$i]}"
    b="${NORMALIZED_IMAGES[$(( (i + 1) % ${#NORMALIZED_IMAGES[@]} ))]}"
    MORPH_IMAGES+=("$a")
    for ((step=1; step<=morph_steps_int; step++)); do
      alpha="$(awk -v s="$step" -v n="$((morph_steps_int + 1))" 'BEGIN{printf "%.6f", s/n}')"
      blend_out="$TMP_DIR/morph_${i}_$(printf '%03d' "$step").png"
      ffmpeg -y -loglevel error \
        -i "$a" -i "$b" \
        -filter_complex "[0:v][1:v]blend=all_expr='A*(1-${alpha})+B*${alpha}',format=rgba" \
        -frames:v 1 \
        "$blend_out"
      [[ -s "$blend_out" ]] || die "Failed to build morph frame between $(basename "$a") and $(basename "$b")"
      MORPH_IMAGES+=("$blend_out")
    done
  done
else
  MORPH_IMAGES=("${NORMALIZED_IMAGES[@]}")
fi
echo "[+] Morph-Frames: ${#MORPH_IMAGES[@]} (steps=$morph_steps_int)"

base_count="${#MORPH_IMAGES[@]}"
(( base_count > 0 )) || die "No frames for slideshow."

target_frame_sec="$TIPS_FRAME_SEC"
desired_count="$(awk -v d="$total_dur" -v s="$target_frame_sec" 'BEGIN{c=int((d/s)+0.999); if(c<1)c=1; if(c>900)c=900; print c}')"
repeat_count="$(awk -v dc="$desired_count" -v bc="$base_count" 'BEGIN{r=int((dc/bc)+0.999); if(r<1)r=1; print r}')"

PLAY_IMAGES=()
for ((loop=0; loop<repeat_count; loop++)); do
  for frame in "${MORPH_IMAGES[@]}"; do
    PLAY_IMAGES+=("$frame")
    if (( ${#PLAY_IMAGES[@]} >= desired_count )); then
      break 2
    fi
  done
done

slide_count="${#PLAY_IMAGES[@]}"
(( slide_count > 0 )) || die "No playback frames built."
per_slide="$(awk -v d="$total_dur" -v c="$slide_count" 'BEGIN{printf "%.6f", d/c}')"
echo "[+] Playback-Frames: $slide_count (target ${target_frame_sec}s/frame, duration ${total_dur}s)"

: > "$SLIDESHOW_LIST"
for ((i=0; i<slide_count; i++)); do
  img_ref="$(basename "${PLAY_IMAGES[$i]}")"
  img_esc="$(escape_ffconcat_path "$img_ref")"
  printf "file '%s'\n" "$img_esc" >> "$SLIDESHOW_LIST"
  printf "duration %s\n" "$per_slide" >> "$SLIDESHOW_LIST"
done
last_idx=$(( slide_count - 1 ))
last_ref="$(basename "${PLAY_IMAGES[$last_idx]}")"
last_esc="$(escape_ffconcat_path "$last_ref")"
printf "file '%s'\n" "$last_esc" >> "$SLIDESHOW_LIST"

LOGO_LEFT=""
for candidate in \
  "pipeline/assets/wally-1.jpg" \
  "pipeline/assets/wally-2.jpg" \
  "pipeline/assets/wally-1.png" \
  "pipeline/assets/wally.jpg"
do
  if [[ -f "$candidate" ]]; then
    LOGO_LEFT="$candidate"
    break
  fi
done

LOGO_RIGHT=""
for candidate in \
  "pipeline/assets/wally-2.jpg" \
  "pipeline/assets/wally-3.jpg" \
  "pipeline/assets/wally-2.png" \
  "pipeline/assets/wally.jpg"
do
  if [[ -f "$candidate" ]]; then
    LOGO_RIGHT="$candidate"
    break
  fi
done

if [[ -n "$LOGO_LEFT" ]] && [[ "$LOGO_LEFT" = "$LOGO_RIGHT" ]]; then
  LOGO_RIGHT=""
fi

ffmpeg_inputs=(-f concat -safe 0 -i "$SLIDESHOW_LIST" -i "$VOICE_WAV")
next_input_idx=2
left_idx=""
right_idx=""

if [[ -f "$LOGO_LEFT" ]]; then
  ffmpeg_inputs+=(-i "$LOGO_LEFT")
  left_idx="$next_input_idx"
  next_input_idx=$((next_input_idx + 1))
fi
if [[ -f "$LOGO_RIGHT" ]]; then
  ffmpeg_inputs+=(-i "$LOGO_RIGHT")
  right_idx="$next_input_idx"
  next_input_idx=$((next_input_idx + 1))
fi

FILTER_COMPLEX="[0:v]fps=$FPS,setsar=1[v0]"
current_label="v0"
next_label_idx=1

if [[ -n "$left_idx" ]]; then
  next_label="v$next_label_idx"
  FILTER_COMPLEX="$FILTER_COMPLEX;[$left_idx:v]format=rgba,scale=220:90:force_original_aspect_ratio=decrease,pad=220:90:(ow-iw)/2:(oh-ih)/2:color=0x00000000[l_logo]"
  FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label][l_logo]overlay=x=24:y=H-h-20:format=auto[$next_label]"
  current_label="$next_label"
  next_label_idx=$((next_label_idx + 1))
fi

if [[ -n "$right_idx" ]]; then
  next_label="v$next_label_idx"
  FILTER_COMPLEX="$FILTER_COMPLEX;[$right_idx:v]format=rgba,scale=96:96:force_original_aspect_ratio=decrease,pad=96:96:(ow-iw)/2:(oh-ih)/2:color=0x00000000[r_logo]"
  FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label][r_logo]overlay=x=W-w-24:y=H-h-20:format=auto[$next_label]"
  current_label="$next_label"
fi

FILTER_COMPLEX="$FILTER_COMPLEX;[$current_label]format=yuv420p[vout]"

echo "[+] Render: $OUT_MP4"
ffmpeg -y \
  "${ffmpeg_inputs[@]}" \
  -filter_complex "$FILTER_COMPLEX" \
  -map "[vout]" -map 1:a \
  -af "apad=pad_dur=$total_dur" \
  -t "$total_dur" \
  -c:v libx264 -crf 20 -preset medium \
  -pix_fmt yuv420p \
  -c:a aac -b:a 160k \
  -movflags +faststart \
  "$OUT_MP4"

if [[ "$GENERATE_WEBM" = "1" ]]; then
  echo "[+] Render: $OUT_WEBM"
  ffmpeg -y \
    "${ffmpeg_inputs[@]}" \
    -filter_complex "$FILTER_COMPLEX" \
    -map "[vout]" -map 1:a \
    -af "apad=pad_dur=$total_dur" \
    -t "$total_dur" \
    -c:v libvpx-vp9 -b:v 0 -crf 30 -cpu-used 6 \
    -c:a libopus -b:a 96k \
    "$OUT_WEBM"
fi

echo "[+] Fertig:"
echo "    MP4: $OUT_MP4"
if [[ "$GENERATE_WEBM" = "1" ]]; then
  echo "   WebM: $OUT_WEBM"
fi
echo "   Text: $NARRATION_FILE"
