# 3D MVC-to-SBS Converter

Converts 3D Blu-ray MKV files to Side-by-Side (SBS) format, compatible with Plex VR players and 3D TVs.

Supports two types of 3D input:
- **MVC (Multi-View Coding)** — standard 3D Blu-ray format. Uses [FRIMDecode64](https://www.videohelp.com/software/FRIM) v1.29 via Wine to decode the MVC bitstream, then encodes to H.264 SBS with ffmpeg.
- **Frame-sequential** — alternating left/right eye frames at double framerate (e.g. ~48fps). Converted directly with ffmpeg's `stereo3d` filter — no Wine or FRIMDecode needed.

## Which option should I use?

| Platform | Option |
|---|---|
| **macOS** (Intel or Apple Silicon) | [Option A: macOS](#option-a-macos-intel-or-apple-silicon) — native install via Homebrew |
| **Linux x86_64** (servers, NAS, desktops) | [Option B: Docker](#option-b-docker-x86_64-linux) — containerized, no host dependencies |
| **Windows** | No setup needed — run [FRIMDecode64](https://www.videohelp.com/software/FRIM) natively (no Wine required). Install [mkvtoolnix](https://mkvtoolnix.download/) and [ffmpeg](https://ffmpeg.org/download.html), then follow the same pipeline steps manually or adapt `convert.sh` for PowerShell/WSL. |
| **Apple Silicon + Docker** | **Will not work** — Wine cannot run under Docker's x86 emulation on ARM due to page size incompatibilities. Use Option A instead. |

## Option A: macOS (Intel or Apple Silicon)

Run everything natively using Wine CrossOver (which uses Rosetta 2 on Apple Silicon for x86 translation).

```bash
# Install dependencies (idempotent — safe to run multiple times)
bash setup-mac.sh

# Convert a movie
./convert.sh input/movie.mkv output/movie_sbs.mkv

# Crop black bars (for VR headsets)
./convert.sh -c input/movie.mkv output/movie_sbs.mkv
```

**What `setup-mac.sh` installs:**
- Rosetta 2 (Apple Silicon only)
- Wine CrossOver via Homebrew (`gcenx/wine` tap)
- mkvtoolnix, ffmpeg via Homebrew
- FRIMDecode64 v1.29

## Option B: Docker (x86_64 Linux)

For Linux servers, NAS devices, or any x86_64 machine. The Docker image includes Wine, FRIMDecode64, mkvtoolnix, and ffmpeg — no host dependencies needed.

```bash
# Build the image (once)
docker build -t mvc-to-sbs .

# Convert a movie
docker run --rm \
  -v ./input:/input \
  -v ./output:/output \
  mvc-to-sbs /input/movie.mkv /output/movie_sbs.mkv

# Crop black bars (for VR headsets)
docker run --rm \
  -v ./input:/input \
  -v ./output:/output \
  mvc-to-sbs -c /input/movie.mkv /output/movie_sbs.mkv
```

> **Important:** Build and run on x86_64 Linux only. This image will **not** build or run on Apple Silicon Macs via Docker Desktop — Wine cannot operate under QEMU's x86 emulation due to ARM/x86 page size incompatibilities (16K vs 4K). macOS users should use Option A instead.

## Features

- **Optional black bar cropping** (`-c` flag) — detects and removes letterbox bars from the source (e.g. 2.35:1 movies in a 1080p frame). Best for VR headsets where every pixel counts. Off by default for TV compatibility, as non-standard resolutions can cause stretching on some displays.
- **Subtitle handling** — subtitles are kept in the output but with the default flag set to off, so they won't auto-display.
- **Resumable** — intermediate files are saved next to the output, so the script can pick up where it left off if a step fails.
- **Plex-compatible** — a final remux pass ensures proper container metadata (duration, bitrate) that Plex requires.

## Pipeline

1. Detect video framerate and resolution via `ffprobe` (+ `cropdetect` if `-c` flag is used)
2. Extract H.264/MVC bitstream via `mkvextract`
3. Decode MVC to raw SBS via `FRIMDecode64 -sw`, encode with `ffmpeg` (libx264, CRF 18; optionally crop black bars with `-c`)
4. Mux SBS video with original audio and subtitles via `mkvmerge` (subtitle default flag set to off)
5. Remux via `ffmpeg` to fix container metadata for Plex compatibility

## Input

MKV files ripped from 3D Blu-ray discs with [MakeMKV](https://www.makemkv.com/). The MKV must contain either:
- An **H.264/MVC** video track (standard 3D Blu-ray) — use `convert.sh`
- A **frame-sequential** H.264 track (~48fps, alternating L/R frames) — use the manual ffmpeg method below

## Frame-Sequential 3D (manual conversion)

Some 3D MKV files are already re-encoded from MVC to frame-sequential format (alternating left/right eye frames at ~48fps). These don't need FRIMDecode or Wine — just ffmpeg.

**How to identify:** Run `ffprobe` on the file. Frame-sequential files show ~48fps framerate and may have `stereo3d: frame alternate` or `stereo_mode: block_lr` metadata.

> **Note:** ffmpeg 8.0 has a bug where re-encoding frame-sequential files with stereo3d side data fails (`Task finished with error code: -17`). The workaround is to extract the raw H.264 bitstream first (stripping the container metadata), then re-encode.

```bash
INPUT="input/movie.mkv"
OUTPUT="output/movie_sbs.mkv"

# Step 1: Extract raw H.264 bitstream (fast, stream copy)
ffmpeg -y -i "$INPUT" -c:v copy -an -sn -bsf:v h264_mp4toannexb raw.h264

# Step 2: Re-encode to SBS + mux audio/subs from original
ffmpeg -y -r 48000/1001 -i raw.h264 -i "$INPUT" \
  -filter_complex "[0:v]stereo3d=al:sbsl[v]" \
  -map "[v]" -map 1:a -map "1:s?" \
  -r 24000/1001 \
  -c:v libx264 -preset medium -crf 18 \
  -c:a copy -c:s copy \
  -disposition:s 0 \
  "$OUTPUT"

# Step 3: Clean up
rm raw.h264
```

The `stereo3d=al:sbsl` filter takes alternating-frame input (`al`) and produces full side-by-side output (`sbsl`) at 3840x1080. Adjust `-r` values if your source uses a different framerate (check with `ffprobe`).

## Intermediate Files (MVC conversion)

The MVC converter creates intermediate files next to the output to allow resuming if a step fails:
- `*_bitstream.h264` — raw MVC bitstream (~same size as input)
- `*_sbs_video.mkv` — SBS video before audio mux

These can be deleted after a successful conversion.
