#!/usr/bin/env bash
# Installs what the Flutter app needs to build Android APKs, in ~/development, without sudo:
# Flutter SDK, Temurin JDK 17 and the Android command-line SDK. Every download is checked against its checksum.
# Safe to run again: finished steps are skipped. Afterwards: source ~/.bashrc && flutter doctor
set -euo pipefail

DEV="$HOME/development"
FLUTTER_URL=https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.50.0-stable.tar.xz
FLUTTER_SHA256=6ea2d806fd57269ae783e6788e2a81fc26eaad782f1e0d0ff38623bb765ff9f5
JDK_URL=https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.21%2B9/OpenJDK17U-jdk_x64_linux_hotspot_17.0.21_9.tar.gz
JDK_SHA256=8b9b611d917e3dfd8419d3566b5949226f69b052fed7e109c1368add1dfe8711
TOOLS_URL=https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip
TOOLS_SHA1=e025545c62a8e64c7559119566a569fb1dec5f60
ANDROID_PACKAGES=("platform-tools" "platforms;android-36" "build-tools;36.0.0")

mkdir -p "$DEV" && cd "$DEV"

fetch() {  # url, file, algorithm, checksum
  [ -f "$2" ] || curl -fL --retry 3 -o "$2" "$1"
  echo "$4  $2" | "$3sum" -c -
}

if [ ! -x flutter/bin/flutter ]; then
  fetch "$FLUTTER_URL" flutter.tar.xz sha256 "$FLUTTER_SHA256"
  tar -xf flutter.tar.xz && rm flutter.tar.xz
fi

if [ ! -x jdk-17/bin/java ]; then
  fetch "$JDK_URL" jdk.tar.gz sha256 "$JDK_SHA256"
  mkdir -p jdk-17 && tar -xzf jdk.tar.gz -C jdk-17 --strip-components=1 && rm jdk.tar.gz
fi

SDK="$DEV/android-sdk"
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  fetch "$TOOLS_URL" cmdline-tools.zip sha1 "$TOOLS_SHA1"
  mkdir -p "$SDK/cmdline-tools" && unzip -q cmdline-tools.zip -d "$SDK/cmdline-tools"
  mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest" && rm cmdline-tools.zip
fi

export JAVA_HOME="$DEV/jdk-17" ANDROID_HOME="$SDK"
export PATH="$DEV/flutter/bin:$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"
(yes | sdkmanager --licenses >/dev/null) || true   # newer tools need no licence step; yes then exits on a closed pipe
sdkmanager "${ANDROID_PACKAGES[@]}"

if ! grep -q "northgate mobile toolchain" "$HOME/.bashrc"; then
  cat >> "$HOME/.bashrc" <<EOF
# northgate mobile toolchain (scripts/setup-mobile.sh)
export JAVA_HOME="$DEV/jdk-17" ANDROID_HOME="$SDK"
export PATH="$DEV/flutter/bin:\$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:\$PATH"
EOF
fi

flutter config --no-analytics --android-sdk "$SDK" >/dev/null
dart --disable-analytics >/dev/null 2>&1 || true
flutter doctor
