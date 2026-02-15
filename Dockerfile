# MVC-to-SBS Converter — x86_64 Linux (Docker)
# Converts 3D MVC Blu-ray MKVs to Side-by-Side format
# Platform: linux/amd64 only (Wine cannot run under ARM emulation)

FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    WINEDEBUG=-all \
    WINEPREFIX=/root/.wine64 \
    WINEARCH=win64

# Install Wine (WineHQ stable), mkvtoolnix, ffmpeg
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg unzip \
        ffmpeg mkvtoolnix \
        # Wine dependencies
        wine wine64 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Download and extract FRIMDecode64 v1.29
RUN mkdir -p /opt/frim && \
    curl -L 'https://www.videohelp.com/download/FRIM_x64_version_1.29.zip' \
        -H 'Referer: https://www.videohelp.com/software/FRIM/old-versions' \
        -o /tmp/frim.zip && \
    unzip -o /tmp/frim.zip -d /opt/frim && \
    rm /tmp/frim.zip

# Initialize Wine prefix (headless, software rendering only)
RUN wineboot -u && wineserver -w

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
