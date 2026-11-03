#!/usr/bin/env bash

# Generate Flutter's official Android and iOS host projects around the
# hand-written Dart skeleton. Run this script once after Flutter is installed.
#
# IMPORTANT: Commit or back up your current work before running generators.
# Flutter normally preserves custom lib/ files when recreating a project, but a
# clean Git state makes any unexpected generated change easy to inspect.

set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo 'Flutter is not available in PATH.' >&2
  echo 'Install Flutter from https://docs.flutter.dev/get-started/install' >&2
  exit 1
fi

# The repository itself is the Flutter project. Do not generate another nested
# `morpheus/` directory. `com.example` is acceptable for practice only; choose a
# permanent reverse-domain identifier before publishing to an app store.
flutter create \
  --platforms=android,ios \
  --org=com.example \
  --project-name=morpheus \
  .

flutter pub get
dart run build_runner build
dart format lib test
flutter analyze
flutter test

echo 'Platform folders generated and checks completed.'
