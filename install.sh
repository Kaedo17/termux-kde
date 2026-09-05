#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# Termux KDE Plasma Native Installation Script
# Samsung Tab S11 - GPU accelerated via virgl
# ============================================================
#
# This script installs KDE Plasma 6 natively in Termux
# (NOT inside proot-distro) with Termux:X11 display.
#
# Requirements:
#   - Termux from F-Droid (not Play Store)
#   - Termux:X11 app from GitHub releases
#   - Android 8+
#
# Usage:
#   chmod +x install.sh
#   ./install.sh
#
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ---- Step 1: Update Termux ----
info "Updating Termux packages..."
pkg update -y && pkg upgrade -y

# ---- Step 2: Install all repositories ----
info "Installing all package repositories..."
pkg install -y root-repo x11-repo glibc-repo

# ---- Step 3: Install KDE Plasma and dependencies ----
info "Installing KDE Plasma desktop..."
DEBIAN_FRONTEND=noninteractive pkg install -y \
    plasma-desktop \
    plasma-workspace \
    kwin-x11 \
    kde-cli-tools \
    konsole \
    dolphin \
    kate \
    ark \
    elisa \
    gwenview \
    kcalc \
    spectacle \
    systemsettings \
    breeze \
    oxygen \
    kmenuedit \
    kscreen \
    powerdevil \
    plasma-pa \
    milou \
    aurorae \
    kinfocenter \
    kwalletmanager \
    kio-extras \
    plasma-integration

# ---- Step 4: Install GPU acceleration (virgl) ----
info "Installing GPU acceleration (virglrenderer)..."
DEBIAN_FRONTEND=noninteractive pkg install -y virglrenderer-android

# ---- Step 5: Install compositor and extras ----
info "Installing picom compositor and extras..."
DEBIAN_FRONTEND=noninteractive pkg install -y \
    picom \
    dbus-x11 \
    x11-apps \
    mesa-utils

# ---- Step 6: Install PulseAudio ----
info "Installing PulseAudio..."
DEBIAN_FRONTEND=noninteractive pkg install -y pulseaudio

# ---- Step 7: Create plasma launch script ----
info "Creating plasma launch script..."
mkdir -p ~/bin

cat > ~/bin/plasma << 'PLASMA_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash

# Kill any existing X11 or virgl processes
kill -9 $(pgrep -f "termux.x11") 2>/dev/null
kill -9 $(pgrep -f "Xwayland") 2>/dev/null
kill -9 $(pgrep -f "virgl_test_server_android") 2>/dev/null
kill -9 $(pgrep -f "startplasma") 2>/dev/null
kill -9 $(pgrep -f "picom") 2>/dev/null
sleep 1

# Start PulseAudio
pulseaudio --kill 2>/dev/null
sleep 1
pulseaudio --start \
  --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
  --exit-idle-time=-1

# GPU acceleration env vars (Mali GPU)
export GALLIUM_DRIVER=virpipe
export MESA_GL_VERSION_OVERRIDE=4.3
export MESA_GLES_VERSION_OVERRIDE=3.0
export MESA_NO_ERROR=1
export vblank_mode=0

# Start virgl server
virgl_test_server_android &>/dev/null &
sleep 1

# Start Termux X11
export XDG_RUNTIME_DIR=${TMPDIR}
termux-x11 :0 &>/dev/null &
sleep 3

# Open Termux X11 app
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity &>/dev/null
sleep 1

# Start Plasma
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1

dbus-run-session startplasma-x11 &>/dev/null &
sleep 2

# Picom compositor for shadows
picom --config ~/.config/picom.conf &>/dev/null &

exit 0
PLASMA_SCRIPT
chmod +x ~/bin/plasma

# ---- Step 8: Create picom config ----
info "Creating picom config..."
mkdir -p ~/.config

cat > ~/.config/picom.conf << 'PICOM_CONFIG'
backend = "xrender"
dbus = true
detect-client-opacity = true
detect-rounded-corners = true
detect-transient = true
shadow = true
shadow-radius = 20
shadow-offset-x = -20
shadow-offset-y = -20
shadow-opacity = 0.70
shadow-exclude = [
  "class_g = 'plasmashell'",
  "class_g = 'firefox-default'",
  "class_g = 'chromium'",
  "class_g = 'Gimp'",
  "_GTK_FRAME_EXTENTS@:c",
  "window_type = 'dock'",
  "window_type = 'desktop'",
  "window_type = 'notification'",
  "window_type = 'tooltip'",
  "window_type = 'popup_menu'",
  "window_type = 'drop_down_menu'"
]
inactive-opacity = 1.0
active-opacity = 1.0
frame-opacity = 1.0

corner-radius = 8
rounded-corners-exclude = [
  "class_g = 'plasmashell'",
  "window_type = 'dock'",
  "window_type = 'desktop'",
  "window_type = 'notification'",
  "window_type = 'tooltip'",
  "window_type = 'popup_menu'",
  "window_type = 'drop_down_menu'"
]

mark-wmwin-focused = true
mark-ovredir-focused = true
use-ewmh-active-win = true

blur-background = false

log-level = "info"
log-file = "/tmp/picom.log"
PICOM_CONFIG

# ---- Step 9: Setup proot-distro for Linux apps ----
info "Setting up proot-distro Ubuntu for Linux apps..."
pkg install -y proot-distro

if [ ! -d /data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu ]; then
    proot-distro install ubuntu
fi

# Create non-root user in proot
proot-distro login ubuntu -- bash -c "
if ! id kemji &>/dev/null; then
    useradd -m -s /bin/bash kemji
    echo 'kemji ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/kemji
    chmod 440 /etc/sudoers.d/kemji
    echo 'User kemji created'
else
    echo 'User kemji already exists'
fi
"

# ---- Step 10: Create proot wrapper script ----
info "Creating proot-code wrapper..."
cat > ~/bin/proot-code << 'PROOT_CODE'
#!/data/data/com.termux/files/usr/bin/bash

# proot-code: Launch VS Code from proot Ubuntu on Termux X11
proot-distro login ubuntu -u kemji \
  --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix \
  -- env DISPLAY=:0 \
  /usr/share/code/code \
  --no-sandbox \
  --user-data-dir=/home/kemji/.vscode-data \
  "$@"
PROOT_CODE
chmod +x ~/bin/proot-code

# ---- Step 11: Create .desktop file for VS Code ----
info "Creating VS Code desktop entry..."
mkdir -p ~/.local/share/applications

cat > ~/.local/share/applications/vscode-proot.desktop << 'DESKTOP_FILE'
[Desktop Entry]
Name=VS Code (Proot)
Comment=Visual Studio Code from Ubuntu proot
Exec=/data/data/com.termux/files/home/bin/proot-code
Icon=vscode
Type=Application
Categories=Development;IDE;
Terminal=false
StartupNotify=true
DESKTOP_FILE

# ---- Step 12: Update .bashrc ----
info "Updating .bashrc..."
if ! grep -q 'termux-kde' ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'BASHRC_ADDON'

# ---- Termux KDE ----
export PATH="$HOME/bin:$HOME/.shortcuts:$PATH"
alias proot='proot-distro login ubuntu -u kemji --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix'
BASHRC_ADDON
fi

# ---- Done ----
echo ""
info "=========================================="
info "Installation complete!"
info "=========================================="
echo ""
info "To start KDE Plasma:"
info "  plasma"
echo ""
info "To launch VS Code (proot):"
info "  proot-code"
echo ""
info "To login to proot Ubuntu as kemji:"
info "  proot"
echo ""
info "Check the Termux:X11 app on your phone for the desktop."
echo ""
