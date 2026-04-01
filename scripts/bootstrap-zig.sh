#!/usr/bin/env bash
set -euo pipefail

ZIG_VERSION="0.12.0"
INSTALL_ROOT="${ZIMACLAW_TOOLCHAIN_DIR:-$PWD/.toolchain/zig}"
VERSION_DIR="${INSTALL_ROOT}/${ZIG_VERSION}"
CURRENT_LINK="${INSTALL_ROOT}/current"

detect_archive_name() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "${os}:${arch}" in
    Linux:x86_64) echo "zig-linux-x86_64-${ZIG_VERSION}.tar.xz" ;;
    Linux:aarch64) echo "zig-linux-aarch64-${ZIG_VERSION}.tar.xz" ;;
    Darwin:x86_64) echo "zig-macos-x86_64-${ZIG_VERSION}.tar.xz" ;;
    Darwin:arm64) echo "zig-macos-aarch64-${ZIG_VERSION}.tar.xz" ;;
    *)
      echo "Unsupported platform: ${os}/${arch}" >&2
      exit 1
      ;;
  esac
}

install_zig() {
  local archive_name url tmp_dir extracted_dir
  archive_name="$(detect_archive_name)"
  url="https://ziglang.org/download/${ZIG_VERSION}/${archive_name}"
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir:-}"' EXIT

  echo "Downloading ${url}"
  curl -fL "${url}" -o "${tmp_dir}/${archive_name}"

  extracted_dir="$(tar -tf "${tmp_dir}/${archive_name}" | awk -F/ 'NR==1 {print $1}')"
  tar -xf "${tmp_dir}/${archive_name}" -C "${tmp_dir}"

  rm -rf "${VERSION_DIR}"
  mkdir -p "${INSTALL_ROOT}"
  mv "${tmp_dir}/${extracted_dir}" "${VERSION_DIR}"
  ln -sfn "${VERSION_DIR}" "${CURRENT_LINK}"
}

if [ ! -x "${VERSION_DIR}/zig" ]; then
  install_zig
else
  ln -sfn "${VERSION_DIR}" "${CURRENT_LINK}"
fi

echo
echo "Zig ${ZIG_VERSION} is ready at ${CURRENT_LINK}"
echo "Run this in your shell:"
echo "  export PATH=\"${CURRENT_LINK}:\$PATH\""
