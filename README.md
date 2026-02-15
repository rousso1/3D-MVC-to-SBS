# 3D MVC-to-SBS Converter

Converts 3D MVC (Multi-View Coding) Blu-ray MKV files to Side-by-Side (SBS) format, compatible with Plex VR players and 3D TVs.

Uses [FRIMDecode64](https://www.videohelp.com/software/FRIM) v1.29 via Wine to decode the MVC bitstream, then encodes to H.264 SBS with ffmpeg.

## Pipeline

1. Detect video framerate and resolution via `ffprobe`
2. Extract H.264/MVC bitstream via `mkvextract`
3. Decode MVC to raw SBS via `FRIMDecode64 -sw`, pipe to `ffmpeg` (libx264, CRF 18)
4. Mux SBS video with original audio/subtitles via `mkvmerge`
5. Remux via `ffmpeg` to fix container metadata for Plex compatibility

## Option A: macOS (Intel or Apple Silicon)

```bash
# Install dependencies (idempotent)
bash setup-mac.sh

# Convert a movie
./convert.sh input/movie.mkv output/movie_sbs.mkv
```

The setup script installs: Rosetta 2 (Apple Silicon only), Wine CrossOver (gcenx tap), mkvtoolnix, ffmpeg, and FRIMDecode64.

## Option B: Docker (x86_64 Linux)

```bash
# Build the image
docker build -t mvc-to-sbs .

# Convert a movie
docker run --rm \
  -v ./input:/input \
  -v ./output:/output \
  mvc-to-sbs /input/movie.mkv /output/movie_sbs.mkv
```

> **Note:** The Docker image is `linux/amd64` only. Docker + Wine does not work on Apple Silicon Macs due to ARM/x86 page size incompatibilities.

## Input

MKV files ripped from 3D Blu-ray discs with [MakeMKV](https://www.makemkv.com/). The MKV must contain an H.264/MVC video track.

## Intermediate Files

The converter creates intermediate files next to the output to allow resuming if a step fails:
- `*_bitstream.h264` — raw MVC bitstream (~same size as input)
- `*_sbs_video.mkv` — SBS video before audio mux

These can be deleted after a successful conversion.
