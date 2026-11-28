# Rebuild the same LGPL Android flavor selected by media_kit. Keep the ABI
# argument after source preparation so all Android ABIs share those layers.
FROM debian:bookworm-slim@sha256:e67eeead736ff7bbe258ef088bff683635c561b1fcfefad0806c1df4ab49ce0e AS builder
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates sudo git gcc-multilib g++ make automake pkg-config libtool nasm \
      python3-jsonschema python3-jinja2 python3-pip cmake ninja-build wget unzip patch && \
    echo 'meson==1.7.2 --hash=sha256:82c6818dc81743c96de3a458f06175776ebfde4081195ea31ea6971838f25e38' > /tmp/meson.txt && \
    pip3 install --break-system-packages --no-deps --require-hashes -r /tmp/meson.txt
WORKDIR /kit
RUN git init && git fetch --depth 1 https://github.com/Predidit/libmpv-android-video-build.git \
      0443048272a511d7a990a2a3d5ca6bbaf55a869a && git checkout --detach FETCH_HEAD
WORKDIR /kit/buildscripts
# The native-only build needs the pinned NDK, not the Android app SDK or JDK.
RUN wget -q https://dl.google.com/android/repository/android-ndk-r30-linux.zip -O /tmp/ndk.zip && \
    echo '5107f898313790e449e87eee2183d9a20602dee9  /tmp/ndk.zip' | sha1sum -c - && \
    mkdir -p sdk/android-sdk-linux/ndk sdk/bin && unzip -q /tmp/ndk.zip -d /tmp && \
    mv /tmp/android-ndk-r30 sdk/android-sdk-linux/ndk/30.0.16248370 && rm /tmp/ndk.zip && \
    wget -q https://raw.githubusercontent.com/FFmpeg/gas-preprocessor/ac1836309c2e77023c228b7184485597286289d3/gas-preprocessor.pl -O sdk/bin/gas-preprocessor.pl && \
    chmod +x sdk/bin/gas-preprocessor.pl
RUN bash -e include/download-deps.sh && bash -e patch.sh && cp flavors/default.sh scripts/ffmpeg.sh
COPY opensles-performance.patch /tmp/
RUN git -C deps/mpv apply /tmp/opensles-performance.patch
ARG ABI
RUN case "$ABI" in arm64-v8a) arch=arm64 ;; armeabi-v7a) arch=armv7l ;; \
      x86|x86_64) arch="$ABI" ;; *) exit 1 ;; esac && \
    bash -e build.sh --arch "$arch" && mkdir /result && cp -L "prefix/$ABI/lib/libmpv.so" /result/

FROM scratch
COPY --from=builder /result/ /
