# 3D MVC-to-SBS Converter

Converts 3D MVC (Multi-View Coding) Blu-ray MKV files to Side-by-Side (SBS) format, compatible with Plex VR players and 3D TVs.

Uses [FRIMDecode64](https://www.videohelp.com/software/FRIM) v1.29 via Wine to decode the MVC bitstream, then encodes to H.264 SBS with ffmpeg.

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
```

> **Important:** Build and run on x86_64 Linux only. This image will **not** build or run on Apple Silicon Macs via Docker Desktop — Wine cannot operate under QEMU's x86 emulation due to ARM/x86 page size incompatibilities (16K vs 4K). macOS users should use Option A instead.

## Pipeline

1. Detect video framerate and resolution via `ffprobe`
2. Extract H.264/MVC bitstream via `mkvextract`
3. Decode MVC to raw SBS via `FRIMDecode64 -sw`, pipe to `ffmpeg` (libx264, CRF 18)
4. Mux SBS video with original audio and subtitles via `mkvmerge` (subtitle default flag set to off)
5. Remux via `ffmpeg` to fix container metadata for Plex compatibility

## Input

MKV files ripped from 3D Blu-ray discs with [MakeMKV](https://www.makemkv.com/). The MKV must contain an H.264/MVC video track.

## Intermediate Files

The converter creates intermediate files next to the output to allow resuming if a step fails:
- `*_bitstream.h264` — raw MVC bitstream (~same size as input)
- `*_sbs_video.mkv` — SBS video before audio mux

These can be deleted after a successful conversion.
