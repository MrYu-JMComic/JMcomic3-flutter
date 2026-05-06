#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rust_dir="${RUST_BACKEND_RUST_DIR:-$repo_root/rust-backend/rust}"
out_dir="${RUST_ANDROID_JNILIBS_SOURCE:-$repo_root/build/rust-android-jni}"
source_lib_name="${RUST_ANDROID_SOURCE_LIB_NAME:-librust_lib_jasmine.so}"
dest_lib_name="librust.so"
verify_only=0

if [ "${1:-}" = "--verify-only" ]; then
  verify_only=1
elif [ "${1:-}" != "" ]; then
  echo "Usage: $0 [--verify-only]" >&2
  exit 2
fi

default_abis="arm64-v8a armeabi-v7a"
abi_list="${RUST_ANDROID_ABIS:-$default_abis}"
abi_list="${abi_list//,/ }"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

elf_byte() {
  od -An -N1 -j "$2" -tu1 "$1" | tr -d '[:space:]'
}

elf_u16le() {
  od -An -N2 -j "$2" -tu2 "$1" | tr -d '[:space:]'
}

validate_elf_for_abi() {
  local abi="$1"
  local lib_path="$2"
  local magic elf_class machine expected_class expected_machine

  if [ ! -f "$lib_path" ]; then
    echo "Missing Android Rust JNI lib for $abi: $lib_path" >&2
    exit 1
  fi

  magic="$(od -An -N4 -tx1 "$lib_path" | tr -d '[:space:]')"
  if [ "$magic" != "7f454c46" ]; then
    echo "Not an ELF file for $abi: $lib_path" >&2
    exit 1
  fi

  elf_class="$(elf_byte "$lib_path" 4)"
  machine="$(elf_u16le "$lib_path" 18)"
  case "$abi" in
    arm64-v8a)
      expected_class=2
      expected_machine=183
      ;;
    armeabi-v7a)
      expected_class=1
      expected_machine=40
      ;;
    x86)
      expected_class=1
      expected_machine=3
      ;;
    x86_64)
      expected_class=2
      expected_machine=62
      ;;
    *)
      echo "No ELF validation metadata configured for ABI: $abi" >&2
      exit 1
      ;;
  esac

  if [ "$elf_class" != "$expected_class" ] || [ "$machine" != "$expected_machine" ]; then
    echo "ELF ABI mismatch for $abi: $lib_path (class=$elf_class machine=$machine, expected class=$expected_class machine=$expected_machine)" >&2
    exit 1
  fi
}

check_git_abi_change_set() {
  if [ "${RUST_ALLOW_PARTIAL_JNILIB_CHANGE:-false}" = "true" ]; then
    return
  fi
  if ! command -v git >/dev/null 2>&1; then
    return
  fi

  local changed=()
  local abi status_line path
  for abi in $abi_list; do
    path="android/app/src/main/jniLibs/$abi/$dest_lib_name"
    status_line="$(cd "$repo_root" && git status --porcelain --untracked-files=no -- "$path")"
    if [ -n "$status_line" ]; then
      changed+=("$abi")
    fi
  done

  if [ "${#changed[@]}" -ne 0 ]; then
    local total=0
    for _ in $abi_list; do
      total=$((total + 1))
    done
    if [ "${#changed[@]}" -ne "$total" ]; then
      echo "Partial Android Rust JNI update detected. Changed ABI(s): ${changed[*]}; expected all tracked ABI(s): $abi_list" >&2
      exit 1
    fi
  fi
}

if [ "$verify_only" -eq 0 ] && [ ! -d "$rust_dir" ]; then
  echo "Rust backend directory not found: $rust_dir" >&2
  echo "Set RUST_BACKEND_RUST_DIR to the private backend rust/ directory." >&2
  exit 1
fi

if [ "$verify_only" -eq 0 ] && [ -n "${ANDROID_NDK_HOME:-}" ] && [ ! -d "$ANDROID_NDK_HOME" ]; then
  echo "ANDROID_NDK_HOME does not exist: $ANDROID_NDK_HOME" >&2
  exit 1
fi

flutter_root="${FLUTTER_ROOT:-}"
if [ -z "$flutter_root" ] && command -v flutter >/dev/null 2>&1; then
  flutter_bin="$(command -v flutter)"
  flutter_root="$(cd "$(dirname "$flutter_bin")/.." && pwd)"
fi

if [ ! -f "$repo_root/android/local.properties" ] && [ -n "$flutter_root" ]; then
  {
    echo "flutter.sdk=$flutter_root"
    if [ -n "${ANDROID_HOME:-}" ]; then
      echo "sdk.dir=$ANDROID_HOME"
    fi
  } > "$repo_root/android/local.properties"
fi

if [ "$verify_only" -eq 0 ] && ! command -v cargo >/dev/null 2>&1; then
  echo "cargo is not available on PATH." >&2
  exit 1
fi

if [ "$verify_only" -eq 0 ] && ! cargo ndk --version >/dev/null 2>&1; then
  echo "cargo-ndk is not available. Install it with: cargo install cargo-ndk --locked" >&2
  exit 1
fi

if [ "$verify_only" -eq 0 ]; then
  mkdir -p "$out_dir"

  echo "Building Android Rust JNI libs"
  echo "  rust_dir: $rust_dir"
  echo "  out_dir : $out_dir"
  echo "  abis    : $abi_list"

  pushd "$rust_dir" >/dev/null
  for abi in $abi_list; do
    cargo ndk -t "$abi" -o "$out_dir" build --release
  done
  popd >/dev/null

  for abi in $abi_list; do
    source_path="$out_dir/$abi/$source_lib_name"
    if [ ! -f "$source_path" ]; then
      source_path="$out_dir/$abi/$dest_lib_name"
    fi
    validate_elf_for_abi "$abi" "$source_path"
  done

  for abi in $abi_list; do
    source_path="$out_dir/$abi/$source_lib_name"
    if [ ! -f "$source_path" ]; then
      source_path="$out_dir/$abi/$dest_lib_name"
    fi
    dest_dir="$repo_root/android/app/src/main/jniLibs/$abi"
    dest_path="$dest_dir/$dest_lib_name"
    mkdir -p "$dest_dir"
    cp "$source_path" "$dest_path"
    rm -f "$dest_dir/$source_lib_name"
    if [ "$(sha256_file "$source_path")" != "$(sha256_file "$dest_path")" ]; then
      echo "Hash mismatch after copying $abi: $source_path -> $dest_path" >&2
      exit 1
    fi
  done
fi

for abi in $abi_list; do
  validate_elf_for_abi "$abi" "$repo_root/android/app/src/main/jniLibs/$abi/$dest_lib_name"
done
check_git_abi_change_set
echo "Android Rust JNI libs verified for ABI set: $abi_list"
