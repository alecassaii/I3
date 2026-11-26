#!/usr/bin/env bash
# =============================================================================
#  install.sh
#  Installs and configures i3 + emptty on Void Linux.
#  This script simply automates the guide in the README.
# =============================================================================

set -Eeuo pipefail

# ----------------------------- Defaults --------------------------------------
TTY_NUM=7
LOCALE_LANG="it_IT.UTF-8"
TERMINAL_PKG="kitty"
USE_MINIMAL=false
AUTOLOGIN=false
TARGET_USER="$(id -un)"
ASSUME_YES=false
DRY_RUN=false
START_SERVICE=true

BASE_PKGS=(xinit i3 i3status dmenu emptty dbus elogind)
OTHER_DMS=(lightdm sddm gdm lxdm slim)
MIN_FREE_MB=500

# ----------------------------- Look & feel -----------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m'; C_CYAN=$'\e[36m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

WIDTH=64
SUMMARY=()      # "STATUS|description"
STEP_NO=0
TOTAL_STEPS=7

line() { printf '%s%*s%s\n' "$C_DIM" "$WIDTH" '' "$C_RESET" | tr ' ' '─'; }

banner() {
    echo
    printf '%s╔' "$C_CYAN"; printf '═%.0s' $(seq 1 $((WIDTH-2))); printf '╗%s\n' "$C_RESET"
    printf '%s║%s%s%-*s%s%s║%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" $((WIDTH-2)) \
        "  i3 + emptty installer for Void Linux" "$C_RESET" "$C_CYAN" "$C_RESET"
    printf '%s╚' "$C_CYAN"; printf '═%.0s' $(seq 1 $((WIDTH-2))); printf '╝%s\n' "$C_RESET"
}

step()  { STEP_NO=$((STEP_NO+1)); echo; line; printf '%s%s[%d/%d]%s %s%s%s\n' "$C_BOLD" "$C_BLUE" "$STEP_NO" "$TOTAL_STEPS" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"; line; }
info()  { printf '  %s•%s %s\n' "$C_CYAN" "$C_RESET" "$1"; }
ok()    { printf '  %s✔%s %s\n' "$C_GREEN" "$C_RESET" "$1"; SUMMARY+=("OK|$1"); }
warn()  { printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; SUMMARY+=("WARN|$1"); }
fail()  { printf '  %s✘%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; SUMMARY+=("FAIL|$1"); }
die()   { fail "$1"; echo; printf '%sAborted.%s\n' "$C_RED" "$C_RESET" >&2; exit 1; }

confirm() {
    $ASSUME_YES && return 0
    local reply
    read -r -p "  ${C_YELLOW}?${C_RESET} $1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Run a command (or just print it in dry-run mode)
run() {
    if $DRY_RUN; then
        printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
    else
        "$@"
    fi
}

on_error() {
    local code=$? line_no=$1
    echo >&2
    printf '%s✘ Unexpected error at line %s (exit code %s).%s\n' "$C_RED" "$line_no" "$code" "$C_RESET" >&2
    exit "$code"
}
trap 'on_error $LINENO' ERR

# ----------------------------- Usage -----------------------------------------
usage() {
    cat <<EOF
Usage: ${0##*/} [options]

Options:
  -a, --autologin        Enable autologin for the target user
  -u, --user NAME        User for autologin (default: current user: $TARGET_USER)
  -l, --lang LOCALE      Locale for emptty (default: $LOCALE_LANG)
  -t, --tty N            TTY number for emptty (default: $TTY_NUM)
  -T, --terminal PKG     Terminal emulator package (default: $TERMINAL_PKG)
  -m, --minimal          Use xorg-minimal instead of the xorg meta-package
  -n, --no-start         Enable emptty but do not start it right now
  -y, --yes              Do not ask for confirmation
  -d, --dry-run          Show what would be done without changing anything
  -h, --help             Show this help

Example:
  ./${0##*/} --autologin --lang en_US.UTF-8 --terminal alacritty
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a|--autologin) AUTOLOGIN=true ;;
        -u|--user)      TARGET_USER="${2:?missing value for $1}"; shift ;;
        -l|--lang)      LOCALE_LANG="${2:?missing value for $1}"; shift ;;
        -t|--tty)       TTY_NUM="${2:?missing value for $1}"; shift ;;
        -T|--terminal)  TERMINAL_PKG="${2:?missing value for $1}"; shift ;;
        -m|--minimal)   USE_MINIMAL=true ;;
        -n|--no-start)  START_SERVICE=false ;;
        -y|--yes)       ASSUME_YES=true ;;
        -d|--dry-run)   DRY_RUN=true ;;
        -h|--help)      usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

[[ "$TTY_NUM" =~ ^[0-9]+$ ]] || { echo "Invalid TTY number: $TTY_NUM" >&2; exit 2; }

if $USE_MINIMAL; then XORG_PKG="xorg-minimal"; else XORG_PKG="xorg"; fi
PKGS=("$XORG_PKG" "${BASE_PKGS[@]}" "$TERMINAL_PKG")

# ----------------------------- Helpers ---------------------------------------
pkg_installed() { xbps-query "$1" >/dev/null 2>&1; }

wait_for_service() {   # wait_for_service <name> [timeout_s]
    local svc="$1" timeout="${2:-15}" i out
    for ((i=0; i<timeout; i++)); do
        out="$(sudo sv status "$svc" 2>&1 || true)"
        [[ "$out" == run:* ]] && return 0
        sleep 1
    done
    return 1
}

enable_service() {     # enable_service <name>
    local svc="$1"
    if [[ -e "/var/service/$svc" ]]; then
        info "Service '$svc' is already enabled."
    else
        [[ -d "/etc/sv/$svc" ]] || die "Service definition /etc/sv/$svc not found (is the package installed?)."
        run sudo ln -sv "/etc/sv/$svc" /var/service/
    fi
}

# ============================================================================
banner
$DRY_RUN && printf '\n  %s*** DRY-RUN MODE: no changes will be made ***%s\n' "$C_YELLOW" "$C_RESET"

# ----------------------------- 1. Pre-flight checks --------------------------
step "Pre-flight checks"

[[ -n "${BASH_VERSION:-}" ]] && ok "Running under Bash ${BASH_VERSION%%(*}" || die "This script requires Bash."

if [[ $EUID -eq 0 ]]; then
    die "Do not run as root. Run as your normal user: the script uses sudo when needed."
fi
ok "Running as regular user: $(id -un)"

# Void Linux?
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" == "void" ]]; then
        ok "Distribution: Void Linux"
    else
        die "This script is for Void Linux (detected: ${PRETTY_NAME:-unknown})."
    fi
else
    die "Cannot read /etc/os-release: unable to detect the distribution."
fi

# Required tools
for tool in xbps-install xbps-query sudo ln tee sv grep; do
    if command -v "$tool" >/dev/null 2>&1; then
        :
    else
        die "Required command not found: $tool"
    fi
done
ok "Required tools present (xbps, sudo, sv, tee, ...)"

# sudo access
if $DRY_RUN; then
    info "Skipping sudo authentication (dry-run)."
else
    info "Requesting sudo privileges..."
    sudo -v || die "Unable to obtain sudo privileges (is $(id -un) in /etc/sudoers?)."
    # keep sudo alive for the duration of the script
    ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    trap 'kill "${SUDO_KEEPALIVE_PID:-0}" 2>/dev/null || true' EXIT
    ok "sudo privileges obtained"
fi

# runit
if [[ -d /var/service ]]; then
    ok "runit service directory found (/var/service)"
else
    die "/var/service not found: is runit your init system?"
fi

# Disk space
free_mb=$(df -Pm / | awk 'NR==2 {print $4}')
if (( free_mb >= MIN_FREE_MB )); then
    ok "Free disk space: ${free_mb} MB"
else
    warn "Low disk space on / (${free_mb} MB, ${MIN_FREE_MB} MB recommended)"
fi

# Network
if command -v curl >/dev/null 2>&1; then
    net_cmd=(curl -fsI --max-time 8 https://repo-default.voidlinux.org)
else
    net_cmd=(ping -c1 -W3 repo-default.voidlinux.org)
fi
if "${net_cmd[@]}" >/dev/null 2>&1; then
    ok "Void repository reachable"
else
    warn "Cannot reach repo-default.voidlinux.org (package installation may fail)"
fi

# Locale
lang_base="${LOCALE_LANG%.*}"
if locale -a 2>/dev/null | grep -qiE "^${lang_base}\.utf-?8$"; then
    ok "Locale available: $LOCALE_LANG"
else
    warn "Locale $LOCALE_LANG is not generated. Enable it in /etc/default/libc-locales and run: sudo xbps-reconfigure -f glibc-locales"
fi

# Autologin user
if $AUTOLOGIN; then
    if id "$TARGET_USER" >/dev/null 2>&1; then
        ok "Autologin user exists: $TARGET_USER"
    else
        die "Autologin user '$TARGET_USER' does not exist."
    fi
fi

# TTY conflicts
if [[ -e "/var/service/agetty-tty${TTY_NUM}" ]]; then
    warn "agetty is running on tty${TTY_NUM}: it may conflict with emptty. Choose another TTY with --tty or disable agetty-tty${TTY_NUM}."
else
    ok "tty${TTY_NUM} is free from agetty"
fi

# Planned configuration
echo
info "Planned configuration:"
printf '      %-14s %s\n' "Xorg package:"  "$XORG_PKG"
printf '      %-14s %s\n' "Terminal:"      "$TERMINAL_PKG"
printf '      %-14s %s\n' "Locale:"        "$LOCALE_LANG"
printf '      %-14s %s\n' "emptty TTY:"    "tty${TTY_NUM}"
printf '      %-14s %s\n' "Autologin:"     "$($AUTOLOGIN && echo "yes ($TARGET_USER)" || echo no)"
echo
confirm "Proceed with installation?" || die "Cancelled by user."

# ----------------------------- 2. Packages -----------------------------------
step "Installing base packages"

info "Updating xbps and synchronizing repositories..."
run sudo xbps-install -Sy xbps
run sudo xbps-install -Syu

missing=()
for p in "${PKGS[@]}"; do
    pkg_installed "$p" || missing+=("$p")
done

if ((${#missing[@]})); then
    info "Installing: ${missing[*]}"
    run sudo xbps-install -y "${missing[@]}"
else
    info "All packages are already installed."
fi

$USE_MINIMAL && warn "xorg-minimal selected: remember to install the video drivers for your GPU manually."

if ! $DRY_RUN; then
    for p in "${PKGS[@]}"; do
        if pkg_installed "$p"; then
            printf '      %s✔%s %s\n' "$C_GREEN" "$C_RESET" "$p"
        else
            fail "Package not installed: $p"
            die "Package installation failed."
        fi
    done
    ok "All packages installed (${#PKGS[@]})"
    if [[ -f /usr/share/xsessions/i3.desktop ]]; then
        ok "Session file found: /usr/share/xsessions/i3.desktop"
    else
        warn "/usr/share/xsessions/i3.desktop not found: i3 may not appear in the session list"
    fi
fi

# ----------------------------- 3. Core services ------------------------------
step "Enabling system services (runit)"

enable_service dbus
enable_service elogind

if ! $DRY_RUN; then
    for svc in dbus elogind; do
        if wait_for_service "$svc" 15; then
            ok "Service running: $svc"
        else
            fail "Service not running: $svc ($(sudo sv status "$svc" 2>&1 || true))"
            die "Cannot continue without $svc."
        fi
    done
fi

# ----------------------------- 4. emptty config ------------------------------
step "Configuring emptty"

EMPTTY_CONF=/etc/emptty/conf

if $AUTOLOGIN; then
    conf_user="$TARGET_USER"
    conf_auto="true"
    conf_session="i3"
else
    conf_user=""
    conf_auto="false"
    conf_session=""
fi

build_conf() {
    cat <<EOF
TTY_NUMBER=${TTY_NUM}
SWITCH_TTY=true
PRINT_ISSUE=true
DEFAULT_USER=${conf_user}
AUTOLOGIN=${conf_auto}
AUTOLOGIN_SESSION=${conf_session}
LANG=${LOCALE_LANG}
DBUS_LAUNCH=true
ALWAYS_DONT_SWITCH=false
EOF
}

if $DRY_RUN; then
    info "Would write ${EMPTTY_CONF} with:"
    build_conf | sed 's/^/      /'
else
    sudo mkdir -p /etc/emptty
    if [[ -f "$EMPTTY_CONF" ]]; then
        backup="${EMPTTY_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
        sudo cp -a "$EMPTTY_CONF" "$backup"
        ok "Existing configuration backed up to $backup"
    fi
    build_conf | sudo tee "$EMPTTY_CONF" >/dev/null
    ok "Configuration written to $EMPTTY_CONF"
fi

if $AUTOLOGIN; then
    if ! getent group nopasswdlogin >/dev/null; then
        info "Group 'nopasswdlogin' does not exist: creating it."
        run sudo groupadd nopasswdlogin
    fi
    run sudo usermod -aG nopasswdlogin "$TARGET_USER"
    $DRY_RUN || ok "User '$TARGET_USER' added to group nopasswdlogin (autologin enabled)"
fi

if ! $DRY_RUN; then
    info "Current contents of $EMPTTY_CONF:"
    sed 's/^/      /' "$EMPTTY_CONF"
    for key in "TTY_NUMBER=${TTY_NUM}" "DBUS_LAUNCH=true" "LANG=${LOCALE_LANG}" "AUTOLOGIN=${conf_auto}"; do
        grep -qx "$key" "$EMPTTY_CONF" || die "Configuration check failed: missing '$key'"
    done
    ok "Configuration verified"
fi

# ----------------------------- 5. Other display managers ---------------------
step "Checking for other display managers"

found_dm=()
for dm in "${OTHER_DMS[@]}"; do
    [[ -e "/var/service/$dm" ]] && found_dm+=("$dm")
done

if ((${#found_dm[@]})); then
    warn "Active display manager(s) detected: ${found_dm[*]}"
    for dm in "${found_dm[@]}"; do
        if confirm "Disable '$dm' (remove /var/service/$dm)?"; then
            run sudo rm -v "/var/service/$dm"
            $DRY_RUN || ok "Disabled display manager: $dm"
        else
            warn "'$dm' left enabled: it may conflict with emptty"
        fi
    done
else
    ok "No conflicting display managers found"
fi

# ----------------------------- 6. Start emptty -------------------------------
step "Enabling the emptty service"

if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    warn "You seem to be inside a graphical session: starting emptty will switch you to tty${TTY_NUM}."
fi

if $START_SERVICE; then
    if [[ -e /var/service/emptty ]]; then
        info "Service 'emptty' is already enabled."
    else
        if confirm "Enable emptty now? It starts immediately and switches to tty${TTY_NUM}."; then
            enable_service emptty
        else
            warn "emptty not enabled. Enable later with: sudo ln -sv /etc/sv/emptty /var/service/"
        fi
    fi
else
    info "Skipping start (--no-start). Enable later with: sudo ln -sv /etc/sv/emptty /var/service/"
fi

if ! $DRY_RUN && [[ -e /var/service/emptty ]]; then
    if wait_for_service emptty 15; then
        ok "Service running: emptty"
    else
        fail "emptty is not running ($(sudo sv status emptty 2>&1 || true))"
    fi
fi

# ----------------------------- 7. Summary ------------------------------------
step "Summary"

n_ok=0; n_warn=0; n_fail=0
for entry in "${SUMMARY[@]}"; do
    status="${entry%%|*}"; msg="${entry#*|}"
    case "$status" in
        OK)   n_ok=$((n_ok+1));     printf '  %s✔%s %s\n' "$C_GREEN"  "$C_RESET" "$msg" ;;
        WARN) n_warn=$((n_warn+1)); printf '  %s⚠%s %s\n' "$C_YELLOW" "$C_RESET" "$msg" ;;
        FAIL) n_fail=$((n_fail+1)); printf '  %s✘%s %s\n' "$C_RED"    "$C_RESET" "$msg" ;;
    esac
done

echo
line
printf '  %s%d OK%s   %s%d warnings%s   %s%d errors%s\n' \
    "$C_GREEN" "$n_ok" "$C_RESET" "$C_YELLOW" "$n_warn" "$C_RESET" "$C_RED" "$n_fail" "$C_RESET"
line

if $DRY_RUN; then
    echo; info "Dry-run finished: nothing was changed."
    exit 0
fi

echo
printf '%sNext steps%s\n' "$C_BOLD" "$C_RESET"
info "Log in on tty${TTY_NUM} (Ctrl+Alt+F${TTY_NUM}) and select the 'i3' session."
info "On first launch, i3-config-wizard creates ~/.config/i3/config and lets you pick \$mod (Super or Alt)."
info "Press \$mod+Enter to open the terminal ($TERMINAL_PKG) and \$mod+d for dmenu."
$AUTOLOGIN && info "Autologin is enabled: you will go straight into i3 at the next boot."
echo

(( n_fail == 0 )) || exit 1
