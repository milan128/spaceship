#!/bin/bash
set -e

echo "=== Installing Flutter SDK for Vercel ==="
if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

export PATH="$PATH:$(pwd)/flutter/bin"
flutter config --no-analytics
flutter --version

echo "=== Building Flutter Web Release ==="
flutter pub get
flutter build web --release

echo "=== Build Complete: output in build/web ==="
