#!/usr/bin/env bash
# =============================================================================
#  shell-ninja/i3-dotfiles  ->  Void Linux (runit, xbps, Xorg, emptty) port
#
#  Usage:   ./install-void.sh [--yes] [--no-pkgs]
#     --yes       answer "yes"/default to every question
#     --no-pkgs   skip xbps/fonts/services, only (re)deploy the dotfiles
#
#  What it does
#    1. installs the xbps equivalents of the upstream pacman/apt package lists
#    2. installs fonts (Nerd Fonts from upstream releases) and greenclip
#    3. sets up PipeWire for runit/i3 (no systemd user units)
#    4. deploys the dotfiles with systemd/pacman/apt bits replaced
#    5. optionally enables NetworkManager as a runit service
#
#  Safe to re-run. Existing configs are backed up, never deleted.
# =============================================================================
set -uo pipefail

REPO_URL="https://github.com/shell-ninja/i3-dotfiles"
THEMES_URL="https://github.com/shell-ninja/themes_icons"
WALLS_URL="https://github.com/shell-ninja/Wallpapers"

HERE="$(cd "$(dirname "$0")" && pwd)"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/i3-void-port"
SRC="$CACHE/i3-dotfiles"
OVERLAY="$CACHE/overlay"
CFG="$HOME/.config"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$CFG/i3_Backups_${USER}/$STAMP"

ASSUME_YES=0
DO_PKGS=1
for a in "$@"; do
    case "$a" in
        --yes|-y) ASSUME_YES=1 ;;
        --no-pkgs) DO_PKGS=0 ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        *) echo "unknown option: $a"; exit 1 ;;
    esac
done

# ---------- output helpers ---------------------------------------------------
c_red=$'\e[1;31m'; c_grn=$'\e[1;32m'; c_yel=$'\e[1;33m'; c_cyn=$'\e[1;36m'; c_end=$'\e[0m'
act()  { printf '%s=>%s %s\n' "$c_grn" "$c_end" "$*"; }
note() { printf '%s::%s %s\n' "$c_cyn" "$c_end" "$*"; }
warn() { printf '%s!!%s %s\n' "$c_yel" "$c_end" "$*"; }
err()  { printf '%s><%s %s\n' "$c_red" "$c_end" "$*" >&2; }
skip() { printf '%s[ skip ]%s %s\n' "$c_yel" "$c_end" "$*"; }

ask() {   # ask "question" [default y|n]  -> returns 0 for yes
    local q="$1" def="${2:-y}" ans
    if [[ $ASSUME_YES -eq 1 ]]; then [[ $def == y ]]; return; fi
    local hint="[Y/n]"; [[ $def == n ]] && hint="[y/N]"
    read -r -p "?? $q $hint " ans
    ans="${ans:-$def}"
    [[ "$ans" =~ ^[Yy]$ ]]
}

FAILED=()

# ---------- preflight --------------------------------------------------------
preflight() {
    if [[ $EUID -eq 0 ]]; then err "Run this as your normal user, not root (it uses sudo/doas where needed)."; exit 1; fi

    # shellcheck disable=SC1091
    . /etc/os-release 2>/dev/null || true
    if [[ "${ID:-}" != "void" ]]; then
        warn "This doesn't look like Void Linux (ID=${ID:-unknown})."
        ask "Continue anyway?" n || exit 1
    fi

    for t in git curl tar; do
        command -v "$t" >/dev/null || { err "'$t' is required. Install it: xbps-install $t"; exit 1; }
    done

    if command -v sudo >/dev/null; then SUDO=sudo
    elif command -v doas >/dev/null; then SUDO=doas
    else err "Neither sudo nor doas found. Install one and add yourself to it."; exit 1; fi

    if [[ ! -d /var/service/dbus && ! -L /var/service/dbus ]]; then
        warn "The 'dbus' runit service is not enabled (/var/service/dbus). i3 apps need it:"
        warn "   sudo ln -s /etc/sv/dbus /var/service/"
    fi
    if [[ ! -d /var/service/elogind && ! -L /var/service/elogind ]]; then
        warn "The 'elogind' runit service is not enabled (/var/service/elogind). Poweroff/reboot and XDG_RUNTIME_DIR need it:"
        warn "   sudo ln -s /etc/sv/elogind /var/service/"
    fi
}

# ---------- overlay files (the Void-specific replacements) -------------------
write_overlay() {
    rm -rf "$OVERLAY"
    mkdir -p "$OVERLAY/i3/configs" "$OVERLAY/i3/scripts"

    # ---- main i3 config: upstream had "included" (typo) and duplicated autostarts
    cat > "$OVERLAY/i3/config" <<'EOF'
# i3 main config (Void Linux port)
# Needs i3 >= 4.20 for the "include" directive (Void ships a newer one).
set $mod Mod4
set $alt Mod1

include ~/.config/i3/configs/keybinds.conf
include ~/.config/i3/configs/rules.conf
include ~/.config/i3/configs/workdpaces.conf
include ~/.config/i3/configs/colors.conf
include ~/.config/i3/configs/settings.conf
include ~/.config/i3/configs/startup.conf
EOF

    # ---- startup: everything launched from i3 (no systemd user units on Void)
    cat > "$OVERLAY/i3/configs/startup.conf" <<'EOF'
# Autostart (Void Linux port: runit has no user services, so i3 launches everything)

# audio: PipeWire (pulse + alsa layers come from its config / alsa-pipewire)
exec_always --no-startup-id ~/.config/i3/scripts/audio.sh

# wallpaper, bar, colours
exec --no-startup-id feh --bg-scale ~/.config/i3/.cache/current.png
exec_always --no-startup-id ~/.config/polybar/launch.sh
exec --no-startup-id ~/.config/i3/scripts/Colors.sh

# helpers
exec --no-startup-id ~/.config/i3/scripts/polkit.sh
exec_always --no-startup-id sh -c 'pgrep -x dunst >/dev/null || dunst'
exec --no-startup-id greenclip daemon
exec --no-startup-id dex --autostart --environment i3
exec --no-startup-id xss-lock --transfer-sleep-lock -- i3lock --nofork
exec --no-startup-id nm-applet

# exec_always --no-startup-id picom
EOF

    # ---- audio launcher
    cat > "$OVERLAY/i3/scripts/audio.sh" <<'EOF'
#!/bin/sh
# Start PipeWire once per session. WirePlumber and the PulseAudio layer
# (pipewire-pulse) are started by pipewire itself through its config
# (see /etc/pipewire/pipewire.conf.d/20-pipewire-pulse.conf).
pgrep -x pipewire >/dev/null 2>&1 && exit 0
setsid pipewire >/dev/null 2>&1 &
EOF

    # ---- update checker used by the polybar "update" module
    cat > "$OVERLAY/i3/scripts/systemupdate.sh" <<'EOF'
#!/bin/bash
# Void Linux (xbps) version. Used by polybar's "update" module.

upd_script="$HOME/.config/i3/scripts/pkgupdate.sh"

check_update() {
    # -M: fetch repo data into memory (works without root), -u: list updates, -n: dry run
    xbps-install -Mun 2>/dev/null | wc -l
}

package_update() {
    kitty --title update sh -c "${upd_script}"
}

case $1 in
    --check)  check_update ;;
    --update) package_update ;;
    *) echo "Invalid option" ;;
esac
EOF

    cat > "$OVERLAY/i3/scripts/pkgupdate.sh" <<'EOF'
#!/bin/bash
# Void Linux (xbps) system update.

if command -v sudo >/dev/null; then su_cmd=sudo; else su_cmd=doas; fi

printf '\n== Void Linux system update ==\n\n'

# xbps updates itself first and then asks to be re-run, so run it twice.
$su_cmd xbps-install -Syu
$su_cmd xbps-install -Syu

sleep 1
printf '\n\n<> Please press ENTER to close '
read -r
EOF
}

# ---------- 1. packages ------------------------------------------------------
installed_pkg() { xbps-query "$1" >/dev/null 2>&1; }
in_repo()       { xbps-query -R "$1" >/dev/null 2>&1; }

# install_one name [alt-name ...]  -> installs the first candidate that exists
install_one() {
    local c
    for c in "$@"; do
        if installed_pkg "$c"; then skip "$c already installed"; return 0; fi
    done
    for c in "$@"; do
        if in_repo "$c"; then
            act "Installing $c"
            if $SUDO xbps-install -y "$c" >/dev/null 2>&1; then return 0; fi
            FAILED+=("$c (install error)"); return 1
        fi
    done
    FAILED+=("$1 (not found in repos; tried: $*)")
    return 1
}

install_packages() {
    note "Syncing xbps repositories"
    $SUDO xbps-install -Sy xbps >/dev/null 2>&1 || true
    if ask "Run a full system update first? (recommended on Void; partial upgrades are unsupported)" y; then
        $SUDO xbps-install -Syu || true
        $SUDO xbps-install -Syu || true   # second pass in case xbps itself was updated
    else
        $SUDO xbps-install -S >/dev/null 2>&1 || true
    fi

    note "Core desktop packages"
    local core=(
        i3 i3lock xss-lock dex dunst libnotify feh kitty rofi polybar
        jq maim xclip xdotool xrandr xinput libinput
        curl wget git unzip fontconfig parallel
        btop fastfetch ffmpeg ImageMagick neovim
        polkit-gnome lxappearance brightnessctl
        network-manager-applet NetworkManager ntfs-3g nvtop crudini firefox
        python3-Pillow
    )
    for p in "${core[@]}"; do install_one "$p"; done

    note "Theming (Qt/GTK)"
    for p in qt5ct qt6ct Kvantum Kvantum-qt5 qt5-svg qt6-svg dconf; do install_one "$p"; done
    install_one nwg-look   # optional; skipped with a note if it's not in the repo

    note "pywal (colour theming)"
    if ! install_one python3-pywal pywal; then
        warn "pywal isn't in the repo. Trying pipx/pip as a fallback."
        install_one python3-pip >/dev/null 2>&1 || true
        pip3 install --user --break-system-packages pywal >/dev/null 2>&1 \
            || pip3 install --user pywal >/dev/null 2>&1 \
            || FAILED+=("pywal (pip fallback failed too)")
        warn "If pywal came from pip, make sure ~/.local/bin is in PATH for your i3 session."
    fi

    note "Audio: PipeWire + PulseAudio compatibility + ALSA bridge"
    for p in pipewire wireplumber alsa-pipewire alsa-utils pulseaudio-utils pamixer pavucontrol; do
        install_one "$p"
    done

    if ask "Install the KDE apps the config expects (dolphin, ark, gwenview, okular)? They pull many deps." y; then
        for p in dolphin ark gwenview okular; do install_one "$p"; done
        KDE_APPS=1
    else
        KDE_APPS=0
    fi

    setup_pipewire
}

setup_pipewire() {
    note "Wiring PipeWire for a non-systemd session"
    # PulseAudio layer: pamixer / pavucontrol / polybar volume need it
    if [[ -f /usr/share/examples/pipewire/20-pipewire-pulse.conf ]]; then
        $SUDO mkdir -p /etc/pipewire/pipewire.conf.d
        $SUDO ln -sf /usr/share/examples/pipewire/20-pipewire-pulse.conf /etc/pipewire/pipewire.conf.d/20-pipewire-pulse.conf
    else
        warn "20-pipewire-pulse.conf example not found; pipewire-pulse must be started manually."
    fi
    # ALSA layer: polybar's internal/alsa module and ALSA-only apps
    if [[ -d /usr/share/alsa/alsa.conf.d ]]; then
        $SUDO mkdir -p /etc/alsa/conf.d
        for f in 50-pipewire.conf 99-pipewire-default.conf; do
            [[ -f /usr/share/alsa/alsa.conf.d/$f ]] && $SUDO ln -sf "/usr/share/alsa/alsa.conf.d/$f" "/etc/alsa/conf.d/$f"
        done
    fi
}

# ---------- 2. fonts + greenclip --------------------------------------------
install_fonts() {
    note "System fonts"
    install_one font-awesome6 font-awesome5 font-awesome
    install_one noto-fonts-ttf
    install_one noto-fonts-emoji
    install_one font-cascadia-code cascadia-code

    note "Nerd Fonts (JetBrainsMono + Meslo) from upstream releases"
    local fdir="$HOME/.local/share/fonts/NerdFonts"
    mkdir -p "$fdir"
    local tmp; tmp="$(mktemp -d)"
    for f in JetBrainsMono Meslo; do
        if ls "$fdir"/"${f}"* >/dev/null 2>&1; then skip "$f Nerd Font already present"; continue; fi
        act "Downloading $f Nerd Font"
        if curl -fL --retry 3 -o "$tmp/$f.zip" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$f.zip" \
           && unzip -oq "$tmp/$f.zip" -d "$fdir" ; then :
        else
            FAILED+=("$f Nerd Font (download failed)")
        fi
    done
    rm -rf "$tmp"
    fc-cache -f >/dev/null 2>&1 || true
}

install_greenclip() {
    note "greenclip (clipboard history; not in Void repos)"
    if command -v greenclip >/dev/null; then skip "greenclip already installed"
    else
        local tmp; tmp="$(mktemp)"
        if curl -fL --retry 3 -o "$tmp" "https://github.com/erebe/greenclip/releases/latest/download/greenclip"; then
            $SUDO install -m 0755 "$tmp" /usr/local/bin/greenclip
        else
            FAILED+=("greenclip (download failed; the clipboard keybinds won't work)")
        fi
        rm -f "$tmp"
    fi

    # same config upstream writes, minus the systemd unit (i3 starts the daemon)
    cat > "$CFG/greenclip.toml" <<'EOF'
[greenclip]
  history_file = "~/.cache/greenclip.history"
  max_history_length = 50
  max_selection_size_bytes = 0
  trim_space_from_selection = true
  use_primary_selection_as_input = false
  blacklisted_applications = []
  enable_image_support = true
  image_cache_directory = "/tmp/greenclip"
  static_history = [
  ]
EOF
}

# ---------- 3. services / groups --------------------------------------------
setup_services() {
    note "Services and groups"
    if ask "Enable NetworkManager as a runit service? (conflicts with dhcpcd/wpa_supplicant; say no if you already have networking)" n; then
        if [[ -e /var/service/dhcpcd || -e /var/service/wpa_supplicant ]]; then
            warn "dhcpcd/wpa_supplicant is enabled. Disable it first, or NetworkManager will fight it:"
            warn "   sudo rm /var/service/dhcpcd /var/service/wpa_supplicant"
        fi
        $SUDO ln -sf /etc/sv/NetworkManager /var/service/
        $SUDO usermod -aG network "$USER" 2>/dev/null || true
        act "NetworkManager enabled (starts within a few seconds)."
    fi
    # brightnessctl's udev rule uses the 'video' group
    if ! id -nG "$USER" | grep -qw video; then
        $SUDO usermod -aG video "$USER" && act "Added $USER to 'video' (needed for brightnessctl). Re-login to apply."
    fi
}

# ---------- 4. dotfiles ------------------------------------------------------
fetch_sources() {
    mkdir -p "$CACHE"
    if [[ -d "$SRC/.git" ]]; then
        act "Updating cached dotfiles repo"
        git -C "$SRC" pull --ff-only -q || warn "git pull failed; using the cached copy."
    else
        act "Cloning $REPO_URL"
        git clone --depth=1 "$REPO_URL" "$SRC" || { err "Could not clone the dotfiles repo."; exit 1; }
    fi
}

install_themes() {
    note "GTK themes + icons (shell-ninja/themes_icons)"
    local t="$CACHE/themes_icons"
    if [[ -d "$t/.git" ]]; then git -C "$t" pull --ff-only -q || true
    else git clone --depth=1 "$THEMES_URL" "$t" -q || { FAILED+=("themes_icons (clone failed)"); return; }; fi
    mkdir -p "$HOME/.icons" "$HOME/.themes"
    # same extraction the upstream extract.sh does, without its pacman/zypper calls
    local f top
    for f in "$t"/icons/*.tar.gz; do
        [[ -e $f ]] || continue
        top="$(tar -tf "$f" | head -1 | sed -e 's@^\./@@' -e 's@/.*@@')"
        if [[ $top == icons ]]; then tar xzf "$f" -C "$HOME/.icons/" --strip-components=1; else tar xzf "$f" -C "$HOME/.icons/"; fi
    done
    for f in "$t"/themes/*.tar.gz; do
        [[ -e $f ]] || continue
        top="$(tar -tf "$f" | head -1 | sed -e 's@^\./@@' -e 's@/.*@@')"
        if [[ $top == themes ]]; then tar xzf "$f" -C "$HOME/.themes/" --strip-components=1; else tar xzf "$f" -C "$HOME/.themes/"; fi
    done
    if command -v gsettings >/dev/null; then
        gsettings set org.gnome.desktop.interface gtk-theme 'TokyoNight' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface icon-theme 'TokyoNight' 2>/dev/null || true
        gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice' 2>/dev/null || true
    fi
}

deploy_dotfiles() {
    note "Deploying dotfiles (backup: $BACKUP)"
    mkdir -p "$BACKUP" "$CFG"

    local items=(dunst fastfetch gtk-3.0 gtk-4.0 i3 kitty Kvantum menus nvim polybar qt5ct qt6ct rofi
                 dolphinrc kwalletmanagerrc kwalletrc)
    local it
    for it in "${items[@]}"; do
        if [[ -e "$CFG/$it" ]]; then
            act "Backing up existing $it"
            mv "$CFG/$it" "$BACKUP/"
        fi
    done

    # copy everything except the Arch-only picom file
    for it in "$SRC"/config/*; do
        [[ "$(basename "$it")" == picom.conf.arch ]] && continue
        cp -r "$it" "$CFG/"
    done

    # --- Void overlay on top of the upstream files
    cp "$OVERLAY/i3/config" "$CFG/i3/config"
    cp "$OVERLAY/i3/configs/startup.conf" "$CFG/i3/configs/startup.conf"
    cp "$OVERLAY/i3/scripts/"*.sh "$CFG/i3/scripts/"

    # keybinds.conf includes rules.conf, and the main config includes it too -> duplicate "mode resize"
    sed -i '\|^include ~/.config/i3/configs/rules.conf|d' "$CFG/i3/configs/keybinds.conf"

    # powermenu: systemctl -> elogind's loginctl; fix the lock image name (upstream wrote blur.png, creates blured.png)
    local pm="$CFG/i3/scripts/powermenu.sh"
    sed -i -e 's/systemctl poweroff/loginctl poweroff/' \
           -e 's/systemctl reboot/loginctl reboot/' \
           -e 's#\.cache/blur\.png#.cache/blured.png#' "$pm"

    chmod +x "$CFG"/i3/scripts/*.sh "$CFG/polybar/launch.sh"

    # wallpaper + blurred lock image (Wallpaper.sh uses `magick`, ImageMagick 7 provides it)
    mkdir -p "$CFG/i3/.cache"
    local wall="$CFG/i3/Wallpapers/cyberpunk-soldier-sci-fi.jpg"
    if [[ -f $wall ]]; then
        ln -sf "$wall" "$CFG/i3/.cache/current.png"
        command -v magick >/dev/null && magick "$wall" -blur 0x15 "$CFG/i3/.cache/blured.png" || true
    fi

    # dolphin/konsole state that upstream ships (only if the KDE apps were chosen)
    if [[ ${KDE_APPS:-1} -eq 1 ]]; then
        mkdir -p "$HOME/.local/state" "$HOME/.local/share"
        [[ -f $HOME/.local/state/dolphinstaterc ]] && mv "$HOME/.local/state/dolphinstaterc" "$BACKUP/"
        cp "$SRC/local/state/dolphinstaterc" "$HOME/.local/state/"
        [[ -d $HOME/.local/share/konsole ]] && mv "$HOME/.local/share/konsole" "$BACKUP/"
        cp -r "$SRC/local/share/konsole" "$HOME/.local/share/"
    fi

    # Qt platform theme: set where a session reads it. Verify with `echo $QT_QPA_PLATFORMTHEME` inside i3.
    for f in "$HOME/.profile" "$HOME/.xprofile"; do
        grep -qs 'QT_QPA_PLATFORMTHEME' "$f" || printf '\nexport QT_QPA_PLATFORMTHEME=qt6ct\n' >> "$f"
    done
}

set_refresh_rate() {
    command -v xrandr >/dev/null || return 0
    [[ -n "${DISPLAY:-}" ]] || { skip "No X display; skipping monitor setup (run it later from inside i3)."; return 0; }
    ask "Set a fixed refresh rate for your monitor at i3 startup?" n || return 0
    local out mode rate
    out="$(xrandr -q | awk '/ connected/{print $1; exit}')"
    mode="$(xrandr --current | awk '/\*/{print $1; exit}')"
    read -r -p "?? Refresh rate in Hz for $out ($mode) [60/75/144]: " rate
    [[ "$rate" =~ ^[0-9]+$ ]] || { warn "Not a number; skipping."; return 0; }
    printf '\nexec --no-startup-id xrandr --output %s --mode %s --rate %s\n' "$out" "$mode" "$rate" >> "$CFG/i3/configs/startup.conf"
    act "Added xrandr line to startup.conf"
}

more_wallpapers() {
    ask "Download extra wallpapers (shell-ninja/Wallpapers)?" n || return 0
    local w="$CACHE/Wallpapers"
    rm -rf "$w"
    if git clone --depth=1 "$WALLS_URL" "$w" -q; then
        rm -rf "$w/.git"
        cp -r "$w"/* "$CFG/i3/Wallpapers/" 2>/dev/null || true
        act "Wallpapers added."
    else
        FAILED+=("extra wallpapers (clone failed)")
    fi
}

# ---------- main -------------------------------------------------------------
main() {
    preflight
    write_overlay

    if [[ $DO_PKGS -eq 1 ]]; then
        install_packages
        install_fonts
    fi

    fetch_sources
    mkdir -p "$CFG"
    [[ $DO_PKGS -eq 1 ]] && install_greenclip
    [[ $DO_PKGS -eq 1 ]] && install_themes
    deploy_dotfiles
    [[ $DO_PKGS -eq 1 ]] && setup_services
    set_refresh_rate
    more_wallpapers

    echo
    note "Done."
    if ((${#FAILED[@]})); then
        warn "These items need attention:"
        printf '   - %s\n' "${FAILED[@]}"
    fi
    cat <<EOF

Next steps
  1. Log out and back in through emptty (needed for the new groups and env vars),
     or press Super+Shift+r to restart i3 in place.
  2. Check audio:     wpctl status      and      pamixer --get-volume
  3. Old configs are in: $BACKUP
  4. Keybinds cheat sheet: Super+Shift+h

EOF
}

main "$@"
