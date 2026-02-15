#!/bin/bash
set -euo pipefail

# MVC to SBS conversion script (native macOS with Wine)
# Usage: ./convert.sh input.mkv output.mkv
# Intermediate files are saved next to the output so the script can resume if a step fails.

if [ $# -lt 2 ]; then
  echo "Usage: $0 input.mkv output.mkv"
  exit 1
fi

INPUT_PATH="$1"
OUTPUT_PATH="$2"

TOOLS_DIR="$(cd "$(dirname "$0")/tools" && pwd)"
FRIM_EXE="$TOOLS_DIR/FRIMDecode64/x64/FRIMDecode64.exe"
WINEPREFIX="$TOOLS_DIR/wineprefix"

export WINEDEBUG=-all
export WINEPREFIX

OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
BASENAME=$(basename "$OUTPUT_PATH" .mkv)
BITSTREAM_PATH="${OUTPUT_DIR}/${BASENAME}_bitstream.h264"
SBS_VIDEO_PATH="${OUTPUT_DIR}/${BASENAME}_sbs_video.mkv"

echo "=== MVC to SBS Converter ==="
echo "Input:  $INPUT_PATH"
echo "Output: $OUTPUT_PATH"
echo ""

# Step 1: Extract framerate and resolution
echo "[1/5] Detecting video properties..."
FRAMERATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$INPUT_PATH")
RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$INPUT_PATH")
RESOLUTION=$(echo "$RESOLUTION" | tr -d '[:space:]')
WIDTH=$(echo "$RESOLUTION" | cut -dx -f1)
HEIGHT=$(echo "$RESOLUTION" | cut -dx -f2)
DOUBLE_WIDTH=$((WIDTH * 2))
DOUBLE_RESOLUTION="${DOUBLE_WIDTH}x${HEIGHT}"

echo "  Framerate: $FRAMERATE"
echo "  Resolution: ${WIDTH}x${HEIGHT}"
echo "  SBS raw resolution: $DOUBLE_RESOLUTION"

# Auto-detect black bars via cropdetect on the source
echo "  Detecting black bars..."
CROP_FILTER=""
CROP_LINE=$(ffmpeg -ss 300 -i "$INPUT_PATH" -vframes 10 -vf cropdetect=24:16:0 -f null - 2>&1 | grep -o 'crop=[0-9:]*' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}') || true
if [ -n "$CROP_LINE" ]; then
  CROP_H=$(echo "$CROP_LINE" | cut -d= -f2 | cut -d: -f2)
  CROP_Y=$(echo "$CROP_LINE" | cut -d= -f2 | cut -d: -f4)
  if [ "$CROP_H" -lt "$HEIGHT" ]; then
    CROP_FILTER="crop=${DOUBLE_WIDTH}:${CROP_H}:0:${CROP_Y}"
    echo "  Detected: $CROP_LINE -> SBS crop: $CROP_FILTER"
    echo "  Output SBS resolution: ${DOUBLE_WIDTH}x${CROP_H}"
  else
    echo "  No significant black bars detected."
  fi
else
  echo "  Could not detect crop, skipping."
fi
echo ""

# Step 2: Extract H.264/MVC bitstream from MKV
if [ -f "$BITSTREAM_PATH" ]; then
  echo "[2/5] Bitstream already extracted, skipping..."
  echo "  Size: $(du -h "$BITSTREAM_PATH" | cut -f1)"
else
  echo "[2/5] Extracting H.264/MVC bitstream from MKV..."
  mkvextract tracks "$INPUT_PATH" 0:"$BITSTREAM_PATH"
  echo "  Extracted: $(du -h "$BITSTREAM_PATH" | cut -f1)"
fi
echo ""

# Step 3: Decode MVC to raw SBS using FRIMDecode via Wine, encode with ffmpeg
if [ -f "$SBS_VIDEO_PATH" ]; then
  echo "[3/5] SBS video already encoded, skipping..."
  echo "  Size: $(du -h "$SBS_VIDEO_PATH" | cut -f1)"
else
  echo "[3/5] Decoding MVC to SBS using FRIMDecode (this will take a while)..."
  VFILTER=()
  if [ -n "$CROP_FILTER" ]; then
    VFILTER=(-vf "$CROP_FILTER")
  fi
  wine64 "$FRIM_EXE" -sw -i:mvc "$BITSTREAM_PATH" -o - -sbs | \
    ffmpeg -y -f rawvideo -s:v "$DOUBLE_RESOLUTION" -r "$FRAMERATE" -i - \
    "${VFILTER[@]}" -c:v libx264 -preset medium -crf 18 "$SBS_VIDEO_PATH"
  echo "  SBS video encoded: $(du -h "$SBS_VIDEO_PATH" | cut -f1)"
fi
echo ""

# Step 4: Mux SBS video with original audio and subtitles using mkvmerge
echo "[4/5] Muxing SBS video with original audio and subtitles..."
MUXED_PATH="${OUTPUT_DIR}/${BASENAME}_muxed.mkv"
mkvmerge -o "$MUXED_PATH" \
  "$SBS_VIDEO_PATH" \
  --no-video "$INPUT_PATH"

# Step 5: Remux with ffmpeg to write proper container metadata (duration, bitrate)
# mkvmerge leaves these as N/A which causes Plex playback errors
echo "[5/5] Fixing container metadata for Plex compatibility..."
ffmpeg -y -i "$MUXED_PATH" -c copy -map 0 -disposition:s 0 "$OUTPUT_PATH"
rm -f "$MUXED_PATH"

echo ""
echo "=== Done! ==="
echo "  Output: $OUTPUT_PATH"
echo "  Size: $(du -h "$OUTPUT_PATH" | cut -f1)"
echo ""
echo "Intermediate files can be deleted:"
echo "  rm '$BITSTREAM_PATH' '$SBS_VIDEO_PATH'"
