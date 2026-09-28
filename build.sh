#!/bin/bash
set -euo pipefail

# ADBConsoleKit — libadb.a + XcodeGen на GitHub Actions (Mac не нужен).
# Прошлая сборка падала за ~3 мин на git submodule --recursive с android.googlesource.com.

ROOT="$(cd "$(dirname "$0")" && pwd)"
ADB_ROOT="$ROOT/Dependencies/adb-mobile"
cd "$ROOT"

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_NO_ENV_HINTS=1
export CMAKE_POLICY_VERSION_MINIMUM=3.5
export GIT_TERMINAL_PROMPT=0
export GIT_HTTP_LOW_SPEED_LIMIT=1000
export GIT_HTTP_LOW_SPEED_TIME=60

git config --global http.version HTTP/1.1
git config --global http.postBuffer 524288000
git config --global advice.detachedHead false
git config --global url."https://github.com/google/boringssl.git".insteadOf "https://boringssl.googlesource.com/boringssl.git"

log() { echo "::group::$*"; echo "===== $* ====="; }
endlog() { echo "::endgroup::"; }

die() {
  echo "::error::$*"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "### Error"
      echo '```'
      echo "$*"
      echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

retry() {
  local attempts="$1"; shift
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    echo "WARN: failed attempt $n/$attempts: $*"
    sleep $((n * 8))
    n=$((n + 1))
  done
}

# Annotated tags (v1.5.6, v28.3) на shallow clone дают "is not a commit".
# Peel к коммиту через ^{commit}.
clone_tag() {
  local url="$1" dest="$2" tag="$3"
  echo "clone $url tag $tag -> $dest"
  rm -rf "$dest"
  mkdir -p "$dest"
  git init "$dest" >/dev/null
  git -C "$dest" remote add origin "$url"
  if git -C "$dest" fetch --depth 1 origin "refs/tags/${tag}^{commit}"; then
    git -C "$dest" checkout --force FETCH_HEAD || return 1
  elif git -C "$dest" fetch --depth 1 origin "refs/tags/${tag}"; then
    git -C "$dest" checkout --force FETCH_HEAD || return 1
  else
    rm -rf "$dest"
    git clone --depth 1 --branch "$tag" "$url" "$dest" || return 1
  fi
}

github_mirror_for() {
  case "$1" in
    *platform/system/core*) echo "https://github.com/LineageOS/android_system_core.git" ;;
    *platform/system/extras*) echo "https://github.com/LineageOS/android_system_extras.git" ;;
    *platform/external/selinux*) echo "https://github.com/LineageOS/android_external_selinux.git" ;;
    *platform/external/f2fs-tools*) echo "https://github.com/LineageOS/android_external_f2fs-tools.git" ;;
    *platform/external/e2fsprogs*) echo "https://github.com/LineageOS/android_external_e2fsprogs.git" ;;
    *platform/system/tools/mkbootimg*) echo "https://github.com/LineageOS/android_system_tools_mkbootimg.git" ;;
    *platform/external/avb*) echo "https://github.com/LineageOS/android_external_avb.git" ;;
    *platform/system/libbase*) echo "https://github.com/LineageOS/android_system_libbase.git" ;;
    *platform/system/libziparchive*) echo "https://github.com/LineageOS/android_system_libziparchive.git" ;;
    *platform/packages/modules/adb*) echo "https://github.com/LineageOS/android_packages_modules_adb.git" ;;
    *platform/system/logging*) echo "https://github.com/LineageOS/android_system_logging.git" ;;
    *platform/external/fmtlib*) echo "https://github.com/LineageOS/android_external_fmtlib.git" ;;
    *platform/system/libufdt*) echo "https://github.com/LineageOS/android_system_libufdt.git" ;;
    *platform/external/libusb*) echo "https://github.com/LineageOS/android_external_libusb.git" ;;
    *platform/system/fs/fs_mgr*) echo "https://github.com/LineageOS/android_system_fs_fs_mgr.git" ;;
    *boringssl*) echo "https://github.com/google/boringssl.git" ;;
    *) echo "" ;;
  esac
}

# Клонирует один submodule path из текущего git-репозитория.
fetch_one_submodule() {
  local path="$1"
  echo "→ submodule $path"
  local n=1
  while [ "$n" -le 4 ]; do
    if git submodule update --init --depth 1 --force -- "$path"; then
      return 0
    fi
    echo "WARN: shallow $path failed (try $n)"
    if git submodule update --init --force -- "$path"; then
      return 0
    fi
    n=$((n + 1))
    sleep $((n * 5))
  done

  local url=""
  url="$(git config --file .gitmodules --get-regexp "submodule\..*\.path" | awk -v p="$path" '$2==p {print $1}' | sed 's/\.path$/.url/' | head -1)"
  local giturl=""
  if [ -n "$url" ]; then
    giturl="$(git config --file .gitmodules --get "$url" || true)"
  fi
  local mirror
  mirror="$(github_mirror_for "$giturl")"
  if [ -z "$mirror" ]; then
    mirror="$(github_mirror_for "$path")"
  fi
  if [ -n "$mirror" ]; then
    echo "WARN: googlesource failed for $path — trying $mirror"
    rm -rf "$path"
    if retry 3 git clone --depth 1 "$mirror" "$path"; then
      return 0
    fi
  fi
  return 1
}

fetch_direct_submodules() {
  local repo="$1"
  (
    cd "$repo"
    git submodule sync || true
    local paths
    paths="$(git config --file .gitmodules --get-regexp 'submodule\..*\.path' | awk '{print $2}' || true)"
    if [ -z "$paths" ]; then
      echo "no submodules in $repo"
      return 0
    fi
    local p
    for p in $paths; do
      fetch_one_submodule "$p" || die "Не удалось клонировать submodule: $repo/$p"
    done
  )
}

echo "Host: $(uname -a)"
echo "Xcode: $(xcodebuild -version 2>/dev/null | tr '\n' ' ' || true)"
echo "CMake: $(cmake --version 2>/dev/null | head -1 || echo missing)"
echo "Go: $(go version 2>/dev/null || echo missing)"
df -h . || true

# ---------------------------------------------------------------- 1. Исходники adb-mobile
log "Clone adb-mobile"
mkdir -p Dependencies

NEED_LIBADB_BUILD=1
if [ -s "$ADB_ROOT/output/libadb.a" ] && \
   { [ -f "$ADB_ROOT/output/include/adb_public.h" ] || [ -f "$ADB_ROOT/output/include/adb_puiblic.h" ]; }; then
  echo "libadb.a already present — skip clone/build"
  NEED_LIBADB_BUILD=0
fi

if [ "$NEED_LIBADB_BUILD" = "1" ]; then
  if [ ! -d "$ADB_ROOT/.git" ]; then
    rm -rf "$ADB_ROOT"
    retry 4 git clone --depth 1 https://github.com/wsvn53/adb-mobile.git "$ADB_ROOT"
  fi
  cd "$ADB_ROOT"
  git fetch --depth 1 origin || true
  git log -1 --format='adb-mobile commit: %H'

  git submodule sync || true
  fetch_one_submodule ios-cmake || die "ios-cmake submodule failed"
  fetch_one_submodule android-tools || die "android-tools submodule failed"

  mkdir -p external
  if [ ! -f external/lz4/lib/lz4.h ]; then
    retry 4 clone_tag https://github.com/lz4/lz4.git external/lz4 v1.9.4
  fi
  if [ ! -f external/zstd/lib/zstd.h ]; then
    retry 4 clone_tag https://github.com/facebook/zstd.git external/zstd v1.5.6
  fi
  if [ ! -f external/brotli/c/include/brotli/decode.h ]; then
    retry 4 clone_tag https://github.com/google/brotli.git external/brotli v1.1.0
  fi
  if [ ! -d external/protobuf/.git ]; then
    retry 4 clone_tag https://github.com/protocolbuffers/protobuf.git external/protobuf v28.3
  fi
  if [ ! -f external/protobuf/third_party/abseil-cpp/CMakeLists.txt ]; then
    mkdir -p external/protobuf/third_party
    retry 4 clone_tag https://github.com/abseil/abseil-cpp.git \
      external/protobuf/third_party/abseil-cpp 20240722.0
  fi
  [ -f external/lz4/lib/lz4.h ] || die "lz4 checkout empty"
  [ -f external/zstd/lib/zstd.h ] || die "zstd checkout empty"
  [ -f external/brotli/c/include/brotli/decode.h ] || die "brotli checkout empty"
  [ -f external/protobuf/CMakeLists.txt ] || [ -d external/protobuf/src ] || die "protobuf checkout empty"
  [ -f external/protobuf/third_party/abseil-cpp/CMakeLists.txt ] || die "abseil checkout empty"

  # Не даём upstream-скриптам снова ходить на googlesource / качать все third_party protobuf.
  python3 - <<'PY'
from pathlib import Path

p = Path("porting/scripts/make-adb.sh")
t = p.read_text()
t = t.replace(
    '(cd "$SOURCE_ROOT/android-tools" && git submodule update --init --recursive --force)',
    'echo "skip nested submodule update (already fetched)"',
)
p.write_text(t)

p = Path("porting/scripts/make-protobuf.sh")
t = p.read_text()
t = t.replace(
    '(cd "$SOURCE_ROOT/external/protobuf" && git clean -f && git checkout "v$protoc_version" && git submodule update --init --recursive)',
    '(cd "$SOURCE_ROOT/external/protobuf" && git checkout "v$protoc_version" || true)',
)
p.write_text(t)
print("patched make-adb.sh and make-protobuf.sh")
PY
fi
endlog

# ---------------------------------------------------------------- 2. Инструменты
log "Install build tools"
for tool in cmake git unzip curl python3; do
  have "$tool" || die "Не найден инструмент: $tool (должен быть на macos runner)"
done

if ! have go; then
  echo "Go not on PATH — installing"
  export PATH="/opt/homebrew/bin:/usr/local/go/bin:$PATH"
  if ! have go; then
    brew install go || { brew update && brew install go; } || true
  fi
  hash -r || true
fi
have go || die "Go так и не появился (нужен для BoringSSL). Поставь actions/setup-go в workflow."
go version

if ! have pkg-config && ! have pkgconf; then
  brew install pkgconf || brew install pkg-config || true
fi
have pkg-config || have pkgconf || die "pkg-config не найден"

if ! have xcodegen; then
  echo "Installing xcodegen..."
  brew install xcodegen || { brew update && brew install xcodegen; } || true
fi
if ! have xcodegen; then
  XG_DIR="${RUNNER_TEMP:-/tmp}/xcodegen-bin"
  mkdir -p "$XG_DIR"
  XG_ZIP="${RUNNER_TEMP:-/tmp}/xcodegen.zip"
  curl -fsSL -o "$XG_ZIP" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/2.42.0/xcodegen.zip" || true
  if [ -s "$XG_ZIP" ]; then
    unzip -qo "$XG_ZIP" -d "$XG_DIR"
    if [ -x "$XG_DIR/xcodegen" ]; then
      export PATH="$XG_DIR:$PATH"
    elif [ -x "$XG_DIR/bin/xcodegen" ]; then
      export PATH="$XG_DIR/bin:$PATH"
    fi
  fi
fi
have xcodegen || die "xcodegen не установлен"
xcodegen --version || true
endlog

# ---------------------------------------------------------------- 3. protoc 28.3
log "Install protoc 28.3"
PB_DIR="$HOME/protoc-28.3"
PB_ZIP="${RUNNER_TEMP:-/tmp}/protoc-28.3.zip"
if [ "$(protoc --version 2>/dev/null | awk '{print $2}' || true)" != "28.3" ]; then
  brew unlink protobuf abseil >/dev/null 2>&1 || true
  retry 4 curl -fsSL -o "$PB_ZIP" \
    "https://github.com/protocolbuffers/protobuf/releases/download/v28.3/protoc-28.3-osx-universal_binary.zip"
  rm -rf "$PB_DIR"
  mkdir -p "$PB_DIR"
  unzip -qo "$PB_ZIP" -d "$PB_DIR"
  chmod +x "$PB_DIR/bin/protoc"
fi
export PATH="$PB_DIR/bin:$PATH"
if [ -n "${GITHUB_PATH:-}" ]; then echo "$PB_DIR/bin" >> "$GITHUB_PATH"; fi
hash -r
PROTOC_VERSION="$(protoc --version | awk '{print $2}')"
echo "protoc version: $PROTOC_VERSION"
[ "$PROTOC_VERSION" = "28.3" ] || die "adb-mobile требует protoc 28.3, найдено $PROTOC_VERSION"
endlog

# ---------------------------------------------------------------- 4. libadb.a (iphoneos/arm64)
if [ "$NEED_LIBADB_BUILD" = "1" ]; then
  log "Prefetch android-tools vendor (googlesource, с ретраями)"
  fetch_direct_submodules "$ADB_ROOT/android-tools"
  endlog

  log "Build libadb for iphoneos/arm64"
  cd "$ADB_ROOT"
  rm -rf output
  mkdir -p output

  for lib in lz4 zstd brotli protobuf adb; do
    [ -f "porting/scripts/make-${lib}.sh" ] || die "Нет porting/scripts/make-${lib}.sh"
  done

  for lib in lz4 zstd brotli protobuf; do
    echo "===== make $lib iphoneos/arm64 ====="
    TARGET="$lib/iphoneos/arm64" OUTPUT="$ADB_ROOT/output" bash "porting/scripts/make-${lib}.sh"
  done
  echo "===== make adb iphoneos/arm64 ====="
  TARGET="adb/iphoneos/arm64" OUTPUT="$ADB_ROOT/output" bash "porting/scripts/make-adb.sh"

  mkdir -p output/include
  cp -av porting/adb/include/*.h output/include/

  if [ -f output/include/adb_public.h ] && [ ! -f output/include/adb_puiblic.h ]; then
    cp output/include/adb_public.h output/include/adb_puiblic.h
  fi
  if [ -f output/include/adb_puiblic.h ] && [ ! -f output/include/adb_public.h ]; then
    cp output/include/adb_puiblic.h output/include/adb_public.h
  fi

  rm -f output/iphoneos/arm64/libadb-full.a output/libadb.a
  shopt -s nullglob
  A_FILES=(output/iphoneos/arm64/*.a)
  shopt -u nullglob
  [ ${#A_FILES[@]} -gt 0 ] || die "Нет .a после сборки adb-mobile"
  libtool -static -o output/iphoneos/arm64/libadb-full.a "${A_FILES[@]}"
  cp output/iphoneos/arm64/libadb-full.a output/libadb.a

  test -s output/libadb.a || die "libadb.a пустой"
  lipo -info output/libadb.a || true
  echo "ADB library ready: $ADB_ROOT/output/libadb.a"
  ls -lh output/libadb.a output/include || true
  endlog
fi

[ -s "$ADB_ROOT/output/libadb.a" ] || die "Нет $ADB_ROOT/output/libadb.a"
[ -f "$ADB_ROOT/output/include/adb_public.h" ] || [ -f "$ADB_ROOT/output/include/adb_puiblic.h" ] \
  || die "Нет public-заголовка adb в output/include"

# ---------------------------------------------------------------- 5. Xcode-проект
log "Generate Xcode project"
cd "$ROOT"
xcodegen generate --spec project.yml
[ -d "$ROOT/ADBConsoleKit.xcodeproj" ] || die "XcodeGen не создал ADBConsoleKit.xcodeproj"
echo "Project generated: $ROOT/ADBConsoleKit.xcodeproj"
endlog

echo "build.sh OK"
