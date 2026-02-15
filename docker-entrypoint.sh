#!/bin/bash
set -euo pipefail

# MVC to SBS conversion script (Docker)
# Usage: docker run --rm -v ./input:/input -v ./output:/output mvc-to-sbs /input/movie.mkv /output/movie_sbs.mkv

if [ $# -lt 2 ]; then
  echo "Usage: docker run --rm -v ./input:/input -v ./output:/output mvc-to-sbs /input/movie.mkv /output/movie_sbs.mkv"
  exit 1
fi

INPUT_PATH="$1"
OUTPUT_PATH="$2"

FRIM_EXE="/opt/frim/x64/FRIMDecode64.exe"

OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
BASENAME=$(basename "$OUTPUT_PATH" .mkv)
BITSTREAM_PATH="${OUTPUT_DIR}/${BASENAME}_bitstream.h264"
SBS_VIDEO_PATH="${OUTPUT_DIR}/${BASENAME}_sbs_video.mkv"

echo "=== MVC to SBS Converter (Docker) ==="
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
echo "  SBS Resolution: $DOUBLE_RESOLUTION"
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
  wine64 "$FRIM_EXE" -sw -i:mvc "$BITSTREAM_PATH" -o - -sbs | \
    ffmpeg -y -f rawvideo -s:v "$DOUBLE_RESOLUTION" -r "$FRAMERATE" -i - \
    -c:v libx264 -preset medium -crf 18 "$SBS_VIDEO_PATH"
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
ffmpeg -y -i "$MUXED_PATH" -c copy -map 0 "$OUTPUT_PATH"
rm -f "$MUXED_PATH"

echo ""
echo "=== Done! ==="
echo "  Output: $OUTPUT_PATH"
echo "  Size: $(du -h "$OUTPUT_PATH" | cut -f1)"
echo ""
echo "Intermediate files can be deleted:"
echo "  rm '$BITSTREAM_PATH' '$SBS_VIDEO_PATH'"
