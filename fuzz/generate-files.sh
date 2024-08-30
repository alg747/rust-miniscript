#!/usr/bin/env bash

set -e

REPO_DIR=$(git rev-parse --show-toplevel)

# can't find the file because of the ENV var
# shellcheck source=/dev/null
source "$REPO_DIR/fuzz/fuzz-util.sh"

# 1. Generate fuzz/Cargo.toml
cat > "$REPO_DIR/fuzz/Cargo.toml" <<EOF
[package]
name = "descriptor-fuzz"
edition = "2021"
rust-version = "1.63.0"
version = "0.0.1"
authors = ["Generated by fuzz/generate-files.sh"]
publish = false

[package.metadata]
cargo-fuzz = true

[dependencies]
honggfuzz = { version = "0.5.56", default-features = false }
miniscript = { path = "..", features = [ "compiler" ] }
old_miniscript = { package = "miniscript", git = "https://github.com/apoelstra/rust-miniscript/", rev = "1259375d7b7c91053e09d1cbe3db983612fe301c" }

regex = "1.0"
EOF

for targetFile in $(listTargetFiles); do
    targetName=$(targetFileToName "$targetFile")
    cat >> "$REPO_DIR/fuzz/Cargo.toml" <<EOF

[[bin]]
name = "$targetName"
path = "$targetFile"
EOF
done

# 2. Generate .github/workflows/fuzz.yml
cat > "$REPO_DIR/.github/workflows/cron-daily-fuzz.yml" <<EOF
# Automatically generated by fuzz/generate-files.sh
name: Fuzz
on:
  schedule:
    # 6am every day UTC, this correlates to:
    # - 11pm PDT
    # - 7am CET
    # - 5pm AEDT
    - cron: '00 06 * * *'

jobs:
  fuzz:
    if: \${{ !github.event.act }}
    runs-on: ubuntu-20.04
    strategy:
      fail-fast: false
      matrix:
        # We only get 20 jobs at a time, we probably don't want to go
        # over that limit with fuzzing because of the hour run time.
        fuzz_target: [
$(for name in $(listTargetNames); do echo "$name,"; done)
        ]
    steps:
      - name: Install test dependencies
        run: sudo apt-get update -y && sudo apt-get install -y binutils-dev libunwind8-dev libcurl4-openssl-dev libelf-dev libdw-dev cmake gcc libiberty-dev
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        id: cache-fuzz
        with:
          path: |
            ~/.cargo/bin
            fuzz/target
            target
          key: cache-\${{ matrix.target }}-\${{ hashFiles('**/Cargo.toml','**/Cargo.lock') }}
      - uses: dtolnay/rust-toolchain@stable
        with:
          toolchain: '1.65.0'
      - name: fuzz
        run: cd fuzz && ./fuzz.sh "\${{ matrix.fuzz_target }}"
      - run: echo "\${{ matrix.fuzz_target }}" >executed_\${{ matrix.fuzz_target }}
      - uses: actions/upload-artifact@v4
        with:
          name: executed_\${{ matrix.fuzz_target }}
          path: executed_\${{ matrix.fuzz_target }}

  verify-execution:
    if: \${{ !github.event.act }}
    needs: fuzz
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/download-artifact@v4
      - name: Display structure of downloaded files
        run: ls -R
      - run: find executed_* -type f -exec cat {} + | sort > executed
      - run: source ./fuzz/fuzz-util.sh && listTargetNames | sort | diff - executed
EOF

