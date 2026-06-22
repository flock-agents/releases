#!/bin/sh
set -eu

REPO="flock-agents/releases"
BINARY_NAME="flockagents"
INSTALL_DIR_SYSTEM="/usr/local/bin"
INSTALL_DIR_USER="${HOME}/.local/bin"

main() {
    check_deps
    detect_platform
    fetch_latest_version
    download_binary
    verify_checksum
    install_binary
    print_success
}

check_deps() {
    if ! command -v curl >/dev/null 2>&1; then
        if command -v wget >/dev/null 2>&1; then
            HAS_WGET=1
        else
            error "curl or wget is required but neither is installed"
        fi
    fi
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
        error "sha256sum or shasum is required for checksum verification"
    fi
}

detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"

    case "${OS}" in
        Linux)  OS="linux" ;;
        Darwin) OS="darwin" ;;
        *)      error "unsupported operating system: ${OS}" ;;
    esac

    case "${ARCH}" in
        x86_64|amd64)  ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)             error "unsupported architecture: ${ARCH}" ;;
    esac

    log "Detected platform: ${OS}/${ARCH}"
}

fetch_latest_version() {
    log "Fetching latest version..."
    LATEST_URL="https://api.github.com/repos/${REPO}/releases/latest"
    RESPONSE="$(http_get "${LATEST_URL}")"

    VERSION="$(printf '%s' "${RESPONSE}" | tr ',' '\n' | grep '"tag_name"' | head -1 | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"//;s/".*//')"
    if [ -z "${VERSION}" ]; then
        error "could not determine latest version from GitHub releases"
    fi

    # Strip leading "cli-" prefix if present (tags are cli-vX.Y.Z)
    VERSION_TAG="${VERSION}"
    VERSION_NUM="$(printf '%s' "${VERSION}" | sed 's/^cli-//')"

    log "Latest version: ${VERSION_NUM}"
}

download_binary() {
    BINARY_FILENAME="${BINARY_NAME}-cli-${OS}-${ARCH}"
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION_TAG}/${BINARY_FILENAME}"
    CHECKSUMS_URL="https://github.com/${REPO}/releases/download/${VERSION_TAG}/checksums.txt"

    TMPDIR="$(mktemp -d)"
    trap 'rm -rf "${TMPDIR}"' EXIT

    log "Downloading ${BINARY_FILENAME}..."
    http_download "${DOWNLOAD_URL}" "${TMPDIR}/${BINARY_FILENAME}"

    log "Downloading checksums..."
    http_download "${CHECKSUMS_URL}" "${TMPDIR}/checksums.txt"
}

verify_checksum() {
    log "Verifying checksum..."

    EXPECTED="$(grep -F "${BINARY_FILENAME}" "${TMPDIR}/checksums.txt" | awk '{print $1}')"
    if [ -z "${EXPECTED}" ]; then
        error "checksum not found for ${BINARY_FILENAME} in checksums.txt"
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        ACTUAL="$(sha256sum "${TMPDIR}/${BINARY_FILENAME}" | awk '{print $1}')"
    else
        ACTUAL="$(shasum -a 256 "${TMPDIR}/${BINARY_FILENAME}" | awk '{print $1}')"
    fi

    if [ "${EXPECTED}" != "${ACTUAL}" ]; then
        error "checksum mismatch: expected ${EXPECTED}, got ${ACTUAL}"
    fi

    log "Checksum verified"
}

install_binary() {
    if [ -w "${INSTALL_DIR_SYSTEM}" ]; then
        TARGET_DIR="${INSTALL_DIR_SYSTEM}"
    else
        TARGET_DIR="${INSTALL_DIR_USER}"
        mkdir -p "${TARGET_DIR}"
    fi

    mv "${TMPDIR}/${BINARY_FILENAME}" "${TARGET_DIR}/${BINARY_NAME}"
    chmod +x "${TARGET_DIR}/${BINARY_NAME}"

    log "Installed to ${TARGET_DIR}/${BINARY_NAME}"

    check_path "${TARGET_DIR}"
}

check_path() {
    TARGET="$1"
    case ":${PATH}:" in
        *":${TARGET}:"*) return ;;
    esac

    SHELL_NAME="$(basename "${SHELL:-/bin/sh}")"
    case "${SHELL_NAME}" in
        zsh)  PROFILE_FILE="${HOME}/.zshrc" ;;
        bash) PROFILE_FILE="${HOME}/.bashrc" ;;
        fish) PROFILE_FILE="${HOME}/.config/fish/config.fish" ;;
        *)    PROFILE_FILE="${HOME}/.profile" ;;
    esac

    warn "${TARGET} is not in your PATH. Add it with:"
    if [ "${SHELL_NAME}" = "fish" ]; then
        printf '  fish_add_path "%s"\n' "${TARGET}"
    else
        printf '  echo '\''export PATH="$PATH:%s"'\'' >> %s\n' "${TARGET}" "${PROFILE_FILE}"
    fi
    printf '\n'
}

print_success() {
    printf '\n'
    log "${BINARY_NAME} installed (${VERSION_NUM}). Run 'flockagents install' to set up Flock."
}

http_get() {
    URL="$1"
    if [ -z "${HAS_WGET:-}" ]; then
        curl -fsSL --tlsv1.2 "${URL}"
    else
        wget -qO- "${URL}"
    fi
}

http_download() {
    URL="$1"
    DEST="$2"
    if [ -z "${HAS_WGET:-}" ]; then
        curl -fsSL --tlsv1.2 -o "${DEST}" "${URL}"
    else
        wget -qO "${DEST}" "${URL}"
    fi
}

log() {
    printf '[flockagents] %s\n' "$1"
}

warn() {
    printf '[flockagents] WARNING: %s\n' "$1" >&2
}

error() {
    printf '[flockagents] ERROR: %s\n' "$1" >&2
    exit 1
}

main
