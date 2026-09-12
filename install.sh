#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# Termux KDE Plasma Installation Script
# GPU accelerated via virgl/ANGLE
# ============================================================
#
# Supports TWO installation modes:
#   1) Termux Native - KDE runs directly in Termux
#   2) Chroot - KDE runs inside a real Linux chroot (needs root)
#
# Requirements:
#   - Termux from F-Droid (not Play Store)
#   - Termux:X11 app from GitHub releases
#   - Android 8+
#
# Usage:
#   chmod +x install.sh
#   ./install.sh            # interactive mode selection
#   ./install.sh --native   # force Termux native install
#   ./install.sh --chroot   # force chroot install
#   ./install.sh --force    # restart from scratch
#   ./install.sh --status   # show progress
#
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

STATE_FILE="$HOME/.install-kde-state"
MODE_FILE="$HOME/.install-kde-mode"
CHROOT_DIR="$HOME/chroot-ubuntu"
CHROOT_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.2-base-arm64.tar.gz"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ============================================================
# Mode selection
# ============================================================

select_mode() {
    if [ -f "$MODE_FILE" ]; then
        INSTALL_MODE=$(cat "$MODE_FILE")
        info "Previous installation mode: $INSTALL_MODE"
        return
    fi

    echo ""
    echo -e "${BOLD}=========================================="
    echo -e "  Termux KDE Plasma Installer"
    echo -e "==========================================${NC}"
    echo ""
    echo -e "${CYAN}Select installation mode:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Termux Native"
    echo -e "     KDE runs directly in Termux (no root needed)"
    echo -e "     Lighter, faster, uses Termux packages"
    echo ""
    echo -e "  ${GREEN}2)${NC} Chroot (requires root)"
    echo -e "     KDE runs inside a real Ubuntu chroot"
    echo -e "     Full Ubuntu environment, closer to desktop Linux"
    echo ""

    # Check for root
    su -c "id" &>/dev/null
    if [ $? -ne 0 ]; then
        warn "Root access not available. Chroot mode requires root."
        echo ""
    fi

    read -rp "Select [1-2] (default: 1): " MODE_CHOICE
    case "${MODE_CHOICE:-1}" in
        1) INSTALL_MODE="native" ;;
        2)
            su -c "id" &>/dev/null
            if [ $? -ne 0 ]; then
                error "Root access required for chroot mode."
                error "Please root your device or choose native mode."
                exit 1
            fi
            INSTALL_MODE="chroot"
            ;;
        *) INSTALL_MODE="native" ;;
    esac

    echo "$INSTALL_MODE" > "$MODE_FILE"
    info "Installation mode set to: $INSTALL_MODE"
}

# ============================================================
# Common helpers
# ============================================================

total_steps_native=14
total_steps_chroot=10

get_total_steps() {
    if [ "$INSTALL_MODE" = "chroot" ]; then
        echo $total_steps_chroot
    else
        echo $total_steps_native
    fi
}

step_done() {
    local mode_prefix="${INSTALL_MODE}_"
    grep -q "^${mode_prefix}step_$1=done$" "$STATE_FILE" 2>/dev/null
}

mark_done() {
    local mode_prefix="${INSTALL_MODE}_"
    mkdir -p "$(dirname "$STATE_FILE")"
    if [ -f "$STATE_FILE" ]; then
        sed -i "/^${mode_prefix}step_$1=/d" "$STATE_FILE"
    fi
    echo "${mode_prefix}step_$1=done" >> "$STATE_FILE"
}

run_step() {
    local step=$1
    local desc=$2
    local force="${3:-}"
    local total=$(get_total_steps)
    local func="${INSTALL_MODE}_step_${step}"

    if [ "$force" != "force" ] && step_done "$step"; then
        info "Step $step/$total: $desc (already done, skipping)"
        return 0
    fi

    info "Step $step/$total: $desc"
    if $func; then
        mark_done "$step"
        return 0
    else
        error "Step $step/$total failed: $desc"
        error "Run ./install.sh to retry from this step."
        return 1
    fi
}

# ---- Handle flags ----
FORCE_MODE=""
case "${1:-}" in
    --force)
        warn "Resetting install state. Starting fresh..."
        rm -f "$STATE_FILE"
        rm -f "$MODE_FILE"
        ;;
    --status)
        if [ ! -f "$STATE_FILE" ]; then
            info "No installation progress found. Run ./install.sh to start."
        else
            info "Installation mode: $(cat "$MODE_FILE" 2>/dev/null || echo 'not set')"
            info "Completed steps:"
            local total=$(get_total_steps)
            for i in $(seq 1 $total); do
                if step_done "$i"; then
                    echo -e "  ${GREEN}[x]${NC} Step $i"
                else
                    echo -e "  ${YELLOW}[ ]${NC} Step $i"
                fi
            done
        fi
        exit 0
        ;;
    --native)
        FORCE_MODE="native"
        echo "$FORCE_MODE" > "$MODE_FILE"
        info "Forced mode: native"
        ;;
    --chroot)
        FORCE_MODE="chroot"
        su -c "id" &>/dev/null
        if [ $? -ne 0 ]; then
            error "Root access required for chroot mode."
            exit 1
        fi
        echo "$FORCE_MODE" > "$MODE_FILE"
        info "Forced mode: chroot"
        ;;
    --help|-h)
        echo "Usage: ./install.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (none)     Interactive mode selection"
        echo "  --native   Force Termux native installation"
        echo "  --chroot   Force chroot installation (needs root)"
        echo "  --force    Reset and restart from scratch"
        echo "  --status   Show installation progress"
        echo "  --help     Show this help"
        exit 0
        ;;
esac

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
    touch "$STATE_FILE"
fi

# ============================================================
# GPU detection
# ============================================================

detect_gpu() {
    if [ -d /sys/class/kgsl/kgsl-3d0 ] 2>/dev/null; then
        echo "adreno"
        return
    fi
    local vulkan_hw
    vulkan_hw=$(getprop ro.hardware.vulkan 2>/dev/null | tr '[:upper:]' '[:lower:]')
    case "$vulkan_hw" in
        mali)    echo "mali" ;;
        xclipse) echo "xclipse" ;;
        *)       echo "unknown" ;;
    esac
}

gpu_label() {
    case "$1" in
        adreno)  echo "Adreno (Snapdragon)" ;;
        mali)    echo "Mali (MediaTek)" ;;
        xclipse) echo "Xclipse (Samsung Exynos)" ;;
        *)       echo "Unknown GPU" ;;
    esac
}

# ============================================================
# Interactive setup (username + HW mode)
# ============================================================

SETUP_CONF="$HOME/.local/share/plasma-setup.conf"

load_setup_conf() {
    if [ -f "$SETUP_CONF" ]; then
        PROOT_USER=$(grep "^PROOT_USER=" "$SETUP_CONF" 2>/dev/null | cut -d= -f2)
        HW_MODE=$(grep "^HW_MODE=" "$SETUP_CONF" 2>/dev/null | cut -d= -f2)
    fi
}

save_setup_conf() {
    mkdir -p "$(dirname "$SETUP_CONF")"
    echo "PROOT_USER=$PROOT_USER" > "$SETUP_CONF"
    echo "HW_MODE=$HW_MODE" >> "$SETUP_CONF"
}

interactive_setup() {
    load_setup_conf

    if [ -z "$PROOT_USER" ]; then
        echo ""
        info "=== Interactive Setup ==="
        echo ""
        read -rp "Enter username for the system [kemji]: " INPUT_USER
        PROOT_USER="${INPUT_USER:-kemji}"
        save_setup_conf
    fi

    if [ -z "$HW_MODE" ]; then
        local GPU=$(detect_gpu)
        local LABEL=$(gpu_label "$GPU")
        echo ""
        info "GPU detected: $LABEL"
        echo ""
        echo "Hardware Acceleration Options:"
        echo ""
        case "$GPU" in
            adreno)
                echo "  1) Software        - safe, no GPU"
                echo "  2) ANGLE OpenGL    - good compatibility"
                echo "  3) Turnip Vulkan   - native Adreno Vulkan"
                echo "  4) Turnip + Zink   - best performance (Adreno)"
                echo ""
                read -rp "Select [1-4] (default: 3): " INPUT_HW
                case "${INPUT_HW:-3}" in
                    1) HW_MODE="software" ;;
                    2) HW_MODE="angle-gl" ;;
                    3) HW_MODE="turnip" ;;
                    4) HW_MODE="turnip-zink" ;;
                    *) HW_MODE="turnip" ;;
                esac
                ;;
            mali|*)
                echo "  1) Software        - safe, no GPU"
                echo "  2) ANGLE OpenGL    - recommended for Mali"
                echo "  3) ANGLE Vulkan    - experimental"
                echo ""
                read -rp "Select [1-3] (default: 2): " INPUT_HW
                case "${INPUT_HW:-2}" in
                    1) HW_MODE="software" ;;
                    2) HW_MODE="angle-gl" ;;
                    3) HW_MODE="angle-vulkan" ;;
                    *) HW_MODE="angle-gl" ;;
                esac
                ;;
        esac
        save_setup_conf
    fi
}

# Run interactive setup before steps (only on fresh install)
if [ ! -f "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
    select_mode
    interactive_setup
else
    select_mode
    load_setup_conf
fi

# ============================================================
# NATIVE MODE - Step functions (original Termux native)
# ============================================================

native_step_1() {
    pkg update -y && pkg upgrade -y
}

native_step_2() {
    pkg install -y root-repo x11-repo glibc-repo
}

native_step_3() {
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
        breeze-gtk \
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
}

native_step_4() {
    DEBIAN_FRONTEND=noninteractive pkg install -y virglrenderer-android
}

native_step_5() {
    DEBIAN_FRONTEND=noninteractive pkg install -y \
        picom \
        dbus \
        mesa-demos \
        termux-x11-nightly
}

native_step_6() {
    DEBIAN_FRONTEND=noninteractive pkg install -y pulseaudio
}

native_step_7() {
    mkdir -p ~/bin
    HW_CONF="$HOME/.local/share/plasma-hw.conf"

    cat > ~/bin/plasma << 'PLASMA_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash

HW_CONF="$HOME/.local/share/plasma-hw.conf"
HW_MODE=$(grep "^HW_MODE=" "$HW_CONF" 2>/dev/null | cut -d= -f2 || echo "angle-gl")
UPOWER_ENABLED=$(grep "^UPOWER_ENABLED=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
if [ -z "$UPOWER_ENABLED" ]; then UPOWER_ENABLED="true"; fi

_detect_gpu_anland() {
    if [ -d /sys/class/kgsl/kgsl-3d0 ] 2>/dev/null; then
        echo "adreno"
        return
    fi
    local vh
    vh=$(getprop ro.hardware.vulkan 2>/dev/null | tr '[:upper:]' '[:lower:]')
    case "$vh" in
        mali)    echo "mali" ;;
        xclipse) echo "xclipse" ;;
        *)       echo "unknown" ;;
    esac
}

case "$HW_MODE" in
    software)
        HW_ENV="LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe MESA_GL_VERSION_OVERRIDE=4.3"
        HW_SERVER="virgl_test_server_android"
        HW_QT_BACKEND="software"
        ;;
    angle-gl)
        HW_ENV="GALLIUM_DRIVER=virpipe MESA_GL_VERSION_OVERRIDE=4.3 MESA_GLES_VERSION_OVERRIDE=3.0 MESA_NO_ERROR=1 LIBGL_DRI3_DISABLE=1"
        HW_SERVER="virgl_test_server_android --angle-gl"
        HW_QT_BACKEND="vulkan"
        ;;
    angle-vulkan)
        HW_ENV="GALLIUM_DRIVER=virpipe MESA_GL_VERSION_OVERRIDE=4.1COMPAT MESA_GLES_VERSION_OVERRIDE=3.2 MESA_GLSL_VERSION_OVERRIDE=410 MESA_NO_ERROR=1 LIBGL_DRI3_DISABLE=1 EPOXY_USE_ANGLE=1 LD_LIBRARY_PATH=$PREFIX/opt/angle-android/vulkan"
        HW_SERVER="virgl_test_server_android --angle-vulkan"
        HW_QT_BACKEND="vulkan"
        ;;
    turnip)
        HW_ENV="MESA_VK_WSI_PRESENT_MODE=fifo"
        HW_SERVER=""
        HW_QT_BACKEND="vulkan"
        ;;
    turnip-zink)
        HW_ENV="MESA_GL_VERSION_OVERRIDE=4.3 ZINK_DESCRIPTORS=lazy MESA_VK_WSI_PRESENT_MODE=fifo"
        HW_SERVER=""
        HW_QT_BACKEND="vulkan"
        ;;
    *)
        HW_ENV="GALLIUM_DRIVER=virpipe MESA_GL_VERSION_OVERRIDE=4.3 MESA_GLES_VERSION_OVERRIDE=3.0 MESA_NO_ERROR=1 LIBGL_DRI3_DISABLE=1"
        HW_SERVER="virgl_test_server_android --angle-gl"
        HW_QT_BACKEND="vulkan"
        ;;
esac

QT_BACKEND=$(grep "^QT_BACKEND=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
if [ -z "$QT_BACKEND" ]; then
    QT_BACKEND="$HW_QT_BACKEND"
fi

case "$QT_BACKEND" in
    opengl) ;;
    vulkan) ;;
    software)
        export QT_QUICK_BACKEND=software
        ;;
esac

if [ -f "$HOME/.local/lib/termux-user.so" ] && grep -q "^TERMUX_USER=" "$HW_CONF" 2>/dev/null; then
    export LD_PRELOAD="$HOME/.local/lib/termux-user.so${LD_PRELOAD:+:$LD_PRELOAD}"
    TERMUX_USER_VAL=$(grep "^TERMUX_USER=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
    if [ -n "$TERMUX_USER_VAL" ]; then
        export USER="$TERMUX_USER_VAL"
        export LOGNAME="$TERMUX_USER_VAL"
    fi
fi

export $HW_ENV
export vblank_mode=0
export GTK_CSD=0
export XDG_RUNTIME_DIR=${TMPDIR}
export DISPLAY=:0
export PULSE_SERVER=127.0.0.1

stop_plasma() {
    echo "Shutting down KDE Plasma..."
    timeout 3 plasma-shutdown 2>/dev/null
    sleep 1
    killall -9 startplasma-x11 plasmashell plasma_session kwin_x11 kded6 \
        ksmserver kglobalaccel powerdevil kaccess kscreen xembedsniproxy \
        kactivitymanagerd kwalletd6 baloorunner gmenudbusmenuproxy \
        polkit-agent-helper-1 krunner ksplash kcminit 2>/dev/null
    killall -9 picom 2>/dev/null
    killall -9 virgl_test_server_android 2>/dev/null
    killall -9 upowerd 2>/dev/null
    local x11_pid
    x11_pid=$(ps -eo pid,args 2>/dev/null | grep "[t]ermux-x11 com.termux" | awk '{print $1}')
    if [ -n "$x11_pid" ]; then
        kill -9 $x11_pid 2>/dev/null
    fi
    pulseaudio --kill 2>/dev/null
    sleep 1
    echo "Done."
}

if [ "$1" = "stop" ]; then
    stop_plasma
    exit 0
fi

if [ "$1" = "change" ]; then
    exec ~/bin/plasma-change
fi

stop_plasma
sleep 1

unset PULSE_SERVER
pulseaudio --kill 2>/dev/null
sleep 1
pulseaudio --start --exit-idle-time=-1

sleep 1
PULSE_SOCK=$(ls /data/data/com.termux/files/usr/tmp/pulse*/native 2>/dev/null | head -1)
if [ -n "$PULSE_SOCK" ]; then
    export PULSE_SERVER="unix:$PULSE_SOCK"
else
    export PULSE_SERVER=127.0.0.1
fi

if [ -n "$HW_SERVER" ]; then
    setsid $HW_SERVER </dev/null >/dev/null 2>&1 &
    sleep 1
fi

am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity &>/dev/null
sleep 3

setsid termux-x11 :0 </dev/null >/dev/null 2>&1 &
sleep 5

TRIES=0
while [ ! -e "${TMPDIR}/.X11-unix/X0" ] && [ $TRIES -lt 20 ]; do
    sleep 1
    TRIES=$((TRIES + 1))
done

if [ ! -e "${TMPDIR}/.X11-unix/X0" ]; then
    echo "ERROR: X11 display not ready. Is Termux:X11 app installed?"
    exit 1
fi

echo "X11 display ready."

KDEG="$HOME/.config/kdeglobals"
mkdir -p "$(dirname "$KDEG")"
if grep -q "SceneGraphBackend" "$KDEG" 2>/dev/null; then
    sed -i "s/SceneGraphBackend=.*/SceneGraphBackend=$QT_BACKEND/" "$KDEG"
else
    printf "\n[QtQuickRendererSettings]\nSceneGraphBackend=%s\n" "$QT_BACKEND" >> "$KDEG"
fi

KWINRC="$HOME/.config/kwinrc"
if [ -f "$KWINRC" ]; then
    if grep -q "org.kde.kdecoration2" "$KWINRC" 2>/dev/null; then
        sed -i 's/^Theme=.*/Theme=breeze/' "$KWINRC"
    else
        printf "\n[org.kde.kdecoration2]\nTheme=breeze\n" >> "$KWINRC"
    fi
    if grep -q "^\[Compositing\]" "$KWINRC" 2>/dev/null; then
        sed -i '/^\[Compositing\]/,/^\[/{s/^OpenGLIsSafe=.*/OpenGLIsSafe=true/}' "$KWINRC"
    fi
    sed -i '/^Backend=wayland$/d' "$KWINRC" 2>/dev/null
fi

chmod +x ~/bin/.plasma-daemon
setsid ~/bin/.plasma-daemon </dev/null >/dev/null 2>&1 &

sleep 5

if [ "$UPOWER_ENABLED" = "false" ]; then
    killall -9 upowerd 2>/dev/null
    killall -9 org_kde_powerdevil 2>/dev/null
fi

echo "KDE Plasma started (mode: $HW_MODE, backend: $QT_BACKEND). Check Termux:X11 app."
PLASMA_SCRIPT
    chmod +x ~/bin/plasma

    cat > ~/bin/.plasma-daemon << 'DAEMON_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash

HW_CONF="$HOME/.local/share/plasma-hw.conf"
HW_MODE=$(grep "^HW_MODE=" "$HW_CONF" 2>/dev/null | cut -d= -f2 || echo "angle-gl")

case "$HW_MODE" in
    software)
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        export MESA_GL_VERSION_OVERRIDE=4.3
        ;;
    angle-gl)
        export GALLIUM_DRIVER=virpipe
        export MESA_GL_VERSION_OVERRIDE=4.3
        export MESA_GLES_VERSION_OVERRIDE=3.0
        export MESA_NO_ERROR=1
        export LIBGL_DRI3_DISABLE=1
        ;;
    angle-vulkan)
        export GALLIUM_DRIVER=virpipe
        export MESA_GL_VERSION_OVERRIDE=4.1COMPAT
        export MESA_GLES_VERSION_OVERRIDE=3.2
        export MESA_GLSL_VERSION_OVERRIDE=410
        export MESA_NO_ERROR=1
        export LIBGL_DRI3_DISABLE=1
        export EPOXY_USE_ANGLE=1
        export LD_LIBRARY_PATH=$PREFIX/opt/angle-android/vulkan
        ;;
    turnip)
        export MESA_VK_WSI_PRESENT_MODE=fifo
        ;;
    turnip-zink)
        export MESA_GL_VERSION_OVERRIDE=4.3
        export ZINK_DESCRIPTORS=lazy
        export MESA_VK_WSI_PRESENT_MODE=fifo
        ;;
    *)
        export GALLIUM_DRIVER=virpipe
        export MESA_GL_VERSION_OVERRIDE=4.3
        export MESA_GLES_VERSION_OVERRIDE=3.0
        export MESA_NO_ERROR=1
        export LIBGL_DRI3_DISABLE=1
        ;;
esac

QT_BACKEND=$(grep "^QT_BACKEND=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
case "$QT_BACKEND" in
    software)
        export QT_QUICK_BACKEND=software
        ;;
esac

if [ -f "$HOME/.local/lib/termux-user.so" ] && grep -q "^TERMUX_USER=" "$HW_CONF" 2>/dev/null; then
    export LD_PRELOAD="$HOME/.local/lib/termux-user.so${LD_PRELOAD:+:$LD_PRELOAD}"
    TERMUX_USER_VAL=$(grep "^TERMUX_USER=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
    if [ -n "$TERMUX_USER_VAL" ]; then
        export USER="$TERMUX_USER_VAL"
        export LOGNAME="$TERMUX_USER_VAL"
    fi
fi

export DISPLAY=:0
export vblank_mode=0
export GTK_CSD=0
export XDG_RUNTIME_DIR=${TMPDIR}

PULSE_SOCK=$(ls /data/data/com.termux/files/usr/tmp/pulse*/native 2>/dev/null | head -1)
if [ -n "$PULSE_SOCK" ]; then
    export PULSE_SERVER="unix:$PULSE_SOCK"
else
    export PULSE_SERVER=127.0.0.1
fi

exec dbus-run-session startplasma-x11
DAEMON_SCRIPT
    chmod +x ~/bin/.plasma-daemon

    cat > ~/bin/plasma-change << 'CHANGE_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash

HW_CONF="$HOME/.local/share/plasma-hw.conf"

detect_gpu() {
    if [ -d /sys/class/kgsl/kgsl-3d0 ] 2>/dev/null; then
        echo "adreno"
        return
    fi
    local vulkan_hw
    vulkan_hw=$(getprop ro.hardware.vulkan 2>/dev/null | tr '[:upper:]' '[:lower:]')
    case "$vulkan_hw" in
        mali)    echo "mali" ;;
        xclipse) echo "xclipse" ;;
        *)       echo "unknown" ;;
    esac
}

gpu_label() {
    case "$1" in
        adreno)  echo "Adreno (Snapdragon)" ;;
        mali)    echo "Mali (MediaTek)" ;;
        xclipse) echo "Xclipse (Samsung Exynos)" ;;
        *)       echo "Unknown GPU" ;;
    esac
}

CURRENT_MODE="angle-gl"
CURRENT_BACKEND="vulkan"
CURRENT_USER="kemji"
if [ -f "$HW_CONF" ]; then
    CURRENT_MODE=$(grep "^HW_MODE=" "$HW_CONF" 2>/dev/null | cut -d= -f2 || echo "angle-gl")
    CURRENT_BACKEND=$(grep "^QT_BACKEND=" "$HW_CONF" 2>/dev/null | cut -d= -f2 || echo "vulkan")
    CURRENT_USER=$(grep "^PROOT_USER=" "$HW_CONF" 2>/dev/null | cut -d= -f2 || echo "kemji")
fi

GPU=$(detect_gpu)
LABEL=$(gpu_label "$GPU")

echo ""
echo "=========================================="
echo "   Plasma Settings"
echo "   GPU: $LABEL"
echo "=========================================="
echo ""
echo "  1) Hardware Acceleration  [$CURRENT_MODE]"
echo "  2) Qt Rendering Backend   [$CURRENT_BACKEND]"
echo "  3) Proot Username         [$CURRENT_USER]"
echo ""
read -rp "Select [1-3] (q=cancel): " SECTION
echo ""

case "$SECTION" in
    1)
        echo "--- Hardware Acceleration ---"
        echo ""
        case "$GPU" in
            adreno)
                echo "  1) Software        - safe, no GPU"
                echo "  2) ANGLE OpenGL    - good compatibility"
                echo "  3) Turnip Vulkan   - native Adreno Vulkan"
                echo "  4) Turnip + Zink   - best performance (Adreno)"
                echo ""
                read -rp "Select [1-4] (q=cancel): " CHOICE
                case "$CHOICE" in
                    1) NEW_MODE="software" ;;
                    2) NEW_MODE="angle-gl" ;;
                    3) NEW_MODE="turnip" ;;
                    4) NEW_MODE="turnip-zink" ;;
                    q|Q) echo "Cancelled."; exit 0 ;;
                    *) echo "Invalid choice."; exit 1 ;;
                esac
                ;;
            mali|*)
                echo "  1) Software        - safe, no GPU"
                echo "  2) ANGLE OpenGL    - recommended for Mali"
                echo "  3) ANGLE Vulkan    - experimental"
                echo ""
                read -rp "Select [1-3] (q=cancel): " CHOICE
                case "$CHOICE" in
                    1) NEW_MODE="software" ;;
                    2) NEW_MODE="angle-gl" ;;
                    3) NEW_MODE="angle-vulkan" ;;
                    q|Q) echo "Cancelled."; exit 0 ;;
                    *) echo "Invalid choice."; exit 1 ;;
                esac
                ;;
        esac
        mkdir -p "$(dirname "$HW_CONF")"
        sed -i "s/^HW_MODE=.*/HW_MODE=$NEW_MODE/" "$HW_CONF" 2>/dev/null || echo "HW_MODE=$NEW_MODE" >> "$HW_CONF"
        echo ""
        echo "Hardware acceleration changed to: $NEW_MODE"
        ;;
    2)
        echo "--- Qt Rendering Backend ---"
        echo ""
        echo "  1) vulkan   - GPU accelerated (recommended)"
        echo "  2) opengl   - OpenGL rendering"
        echo "  3) software - CPU only (safe fallback)"
        echo ""
        read -rp "Select [1-3] (q=cancel): " CHOICE
        case "$CHOICE" in
            1) NEW_BACKEND="vulkan" ;;
            2) NEW_BACKEND="opengl" ;;
            3) NEW_BACKEND="software" ;;
            q|Q) echo "Cancelled."; exit 0 ;;
            *) echo "Invalid choice."; exit 1 ;;
        esac
        mkdir -p "$(dirname "$HW_CONF")"
        sed -i "s/^QT_BACKEND=.*/QT_BACKEND=$NEW_BACKEND/" "$HW_CONF" 2>/dev/null || echo "QT_BACKEND=$NEW_BACKEND" >> "$HW_CONF"
        KDEG="$HOME/.config/kdeglobals"
        if [ -f "$KDEG" ] && grep -q "SceneGraphBackend" "$KDEG" 2>/dev/null; then
            sed -i "s/SceneGraphBackend=.*/SceneGraphBackend=$NEW_BACKEND/" "$KDEG"
        fi
        echo ""
        echo "Qt backend changed to: $NEW_BACKEND"
        ;;
    3)
        echo "--- Proot Username ---"
        echo ""
        echo "Current username: $CURRENT_USER"
        read -rp "Enter new username (Enter to keep current): " NEW_USER
        if [ -n "$NEW_USER" ] && [ "$NEW_USER" != "$CURRENT_USER" ]; then
            mkdir -p "$(dirname "$HW_CONF")"
            sed -i "s/^PROOT_USER=.*/PROOT_USER=$NEW_USER/" "$HW_CONF" 2>/dev/null || echo "PROOT_USER=$NEW_USER" >> "$HW_CONF"
            echo ""
            echo "Username changed to: $NEW_USER"
        else
            echo "Username unchanged."
        fi
        ;;
    q|Q)
        echo "Cancelled."
        exit 0
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

echo ""
read -rp "Restart plasma now? [Y/n]: " RESTART
if [[ ! "$RESTART" =~ ^[nN] ]]; then
    echo "Restarting plasma..."
    ~/bin/plasma stop
    sleep 2
    ~/bin/plasma
else
    echo "Done. Run 'plasma' to apply changes."
fi
CHANGE_SCRIPT
    chmod +x ~/bin/plasma-change

    mkdir -p "$(dirname "$HW_CONF")"
    if [ ! -f "$HW_CONF" ]; then
        echo "HW_MODE=${HW_MODE:-angle-gl}" > "$HW_CONF"
        echo "GPU_FAMILY=$(detect_gpu)" >> "$HW_CONF"
        echo "PROOT_USER=${PROOT_USER:-kemji}" >> "$HW_CONF"
        echo "QT_BACKEND=vulkan" >> "$HW_CONF"
    fi
}

native_step_8() {
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
}

native_step_9() {
    pkg install -y proot-distro
    if [ ! -d /data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu ]; then
        proot-distro install ubuntu
    fi
    local USER="${PROOT_USER:-kemji}"
    proot-distro login ubuntu -- bash -c "
if ! id $USER &>/dev/null; then
    useradd -m -s /bin/bash $USER
    mkdir -p /etc/sudoers.d
    echo '$USER ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER
    chmod 440 /etc/sudoers.d/$USER
    echo 'User $USER created'
else
    echo 'User $USER already exists'
fi
"
}

native_step_10() {
    mkdir -p ~/bin
    local USER="${PROOT_USER:-kemji}"
    cat > ~/bin/proot-code << PROOT_CODE
#!/data/data/com.termux/files/usr/bin/bash

proot-distro login ubuntu -u $USER \\
  --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix \\
  -- env DISPLAY=:0 \\
  /usr/share/code/code \\
  --no-sandbox \\
  --user-data-dir=/home/$USER/.vscode-data \\
  "\$@"
PROOT_CODE
    chmod +x ~/bin/proot-code
}

native_step_11() {
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
}

native_step_12() {
    local USER="${PROOT_USER:-kemji}"
    if ! grep -q 'termux-kde' ~/.bashrc 2>/dev/null; then
        cat >> ~/.bashrc << BASHRC_ADDON

# ---- Termux KDE ----
export PATH="\$HOME/bin:\$HOME/.shortcuts:\$PATH"
alias proot='proot-distro login ubuntu -u $USER --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix'
BASHRC_ADDON
    fi
}

native_step_13() {
    DEBIAN_FRONTEND=noninteractive pkg install -y \
        firefox \
        code-oss
    mkdir -p ~/.local/share/applications
    cat > ~/.local/share/applications/firefox.desktop << 'FIREFOX_DESKTOP'
[Desktop Entry]
Name=Firefox
Comment=Mozilla Firefox web browser
Exec=firefox
Icon=firefox
Type=Application
Categories=Network;WebBrowser;
Terminal=false
StartupNotify=true
FIREFOX_DESKTOP
    cat > ~/.local/share/applications/code-oss.desktop << 'CODE_DESKTOP'
[Desktop Entry]
Name=Code OSS
Comment=Visual Studio Code - OSS
Exec=code-oss
Icon=com.visualstudio.code.oss
Type=Application
Categories=Development;IDE;
Terminal=false
StartupNotify=true
CODE_DESKTOP
    mkdir -p /data/data/com.termux/files/usr/share/icons/hicolor/48x48/apps
    cp /data/data/com.termux/files/usr/share/pixmaps/com.visualstudio.code.oss.png \
       /data/data/com.termux/files/usr/share/icons/hicolor/48x48/apps/ 2>/dev/null
    gtk-update-icon-cache -f /data/data/com.termux/files/usr/share/icons/hicolor/ 2>/dev/null
}

native_step_14() {
    mkdir -p ~/.local/lib
    cat > ~/.local/lib/termux-user.c << 'TERMUX_USER_C'
#define _GNU_SOURCE
#include <pwd.h>
#include <dlfcn.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>

#undef getpwuid
#undef getpwuid_r

static struct passwd orig_pwd;
static char username[256];
static char home_dir[512];
static char shell_path[64];
static int initialized = 0;

static void init() {
    if (initialized) return;
    initialized = 1;

    const char *home = getenv("HOME");
    if (!home) return;
    char path[512];
    snprintf(path, sizeof(path), "%s/.local/share/plasma-hw.conf", home);

    FILE *f = fopen(path, "r");
    if (!f) return;

    char line[512];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "TERMUX_USER=", 12) == 0) {
            char *val = line + 12;
            val[strcspn(val, "\r\n")] = 0;
            if (strlen(val) > 0) {
                strncpy(username, val, sizeof(username) - 1);
            }
            break;
        }
    }
    fclose(f);

    if (username[0]) {
        snprintf(home_dir, sizeof(home_dir), "/data/data/com.termux/files/home");
        strncpy(shell_path, "/data/data/com.termux/files/usr/bin/bash", sizeof(shell_path) - 1);
    }
}

struct passwd *getpwuid(uid_t uid) {
    init();

    typedef struct passwd *(*getpwuid_fn)(uid_t);
    getpwuid_fn orig = (getpwuid_fn)dlsym(RTLD_NEXT, "getpwuid");
    struct passwd *pw = orig(uid);

    if (pw && username[0]) {
        orig_pwd = *pw;
        orig_pwd.pw_name = username;
        orig_pwd.pw_dir = home_dir;
        orig_pwd.pw_shell = shell_path;
        return &orig_pwd;
    }
    return pw;
}

int getpwuid_r(uid_t uid, struct passwd *pwd, char *buf, size_t buflen, struct passwd **result) {
    init();

    typedef int (*getpwuid_r_fn)(uid_t, struct passwd *, char *, size_t, struct passwd **);
    getpwuid_r_fn orig = (getpwuid_r_fn)dlsym(RTLD_NEXT, "getpwuid_r");
    int ret = orig(uid, pwd, buf, buflen, result);

    if (ret == 0 && *result && username[0]) {
        (*result)->pw_name = username;
        (*result)->pw_dir = home_dir;
        (*result)->pw_shell = shell_path;
    }
    return ret;
}
TERMUX_USER_C
    DEBIAN_FRONTEND=noninteractive pkg install -y clang
    clang -shared -fPIC -o ~/.local/lib/termux-user.so \
        ~/.local/lib/termux-user.c -ldl
}

# ============================================================
# CHROOT MODE - Step functions
# ============================================================

chroot_step_1() {
    pkg update -y && pkg upgrade -y
    pkg install -y wget tar proot
}

chroot_step_2() {
    if [ -d "$CHROOT_DIR" ]; then
        info "Chroot directory already exists at $CHROOT_DIR"
        read -rp "Re-download rootfs? This will erase the existing one. [y/N]: " REDOWNLOAD
        if [[ "$REDOWNLOAD" =~ ^[yY] ]]; then
            rm -rf "$CHROOT_DIR"
        else
            info "Keeping existing rootfs."
            return 0
        fi
    fi

    info "Downloading Ubuntu 24.04 arm64 rootfs..."
    local TARFILE="$HOME/ubuntu-base-24.04.2-base-arm64.tar.gz"
    if [ ! -f "$TARFILE" ]; then
        wget -q --show-progress -O "$TARFILE" "$CHROOT_URL" || {
            error "Failed to download rootfs. Check your internet connection."
            return 1
        }
    fi

    info "Extracting rootfs to $CHROOT_DIR..."
    mkdir -p "$CHROOT_DIR"
    su -c "tar -xzf $TARFILE -C $CHROOT_DIR" || {
        error "Failed to extract rootfs. Do you have root access?"
        return 1
    }

    info "Rootfs extracted successfully."
    rm -f "$TARFILE"
}

chroot_step_3() {
    info "Configuring chroot environment..."

    # Mount necessary filesystems
    su -c "mount -t proc proc $CHROOT_DIR/proc" 2>/dev/null
    su -c "mount -t sysfs sysfs $CHROOT_DIR/sys" 2>/dev/null
    su -c "mount --bind /dev $CHROOT_DIR/dev" 2>/dev/null
    su -c "mount --bind /dev/pts $CHROOT_DIR/dev/pts" 2>/dev/null
    su -c "mount --bind /dev/shm $CHROOT_DIR/dev/shm" 2>/dev/null
    su -c "mount --bind /data/data/com.termux/files/usr/tmp $CHROOT_DIR/tmp" 2>/dev/null

    # Set up DNS
    su -c "cp /etc/resolv.conf $CHROOT_DIR/etc/resolv.conf" 2>/dev/null || true

    # Set hostname
    su -c "echo 'localhost' > $CHROOT_DIR/etc/hostname" 2>/dev/null || true

    # Set up hosts file
    if [ ! -f "$CHROOT_DIR/etc/hosts" ] || ! grep -q "localhost" "$CHROOT_DIR/etc/hosts" 2>/dev/null; then
        su -c "cat > $CHROOT_DIR/etc/hosts << 'HOSTS'
127.0.0.1       localhost
::1             localhost
HOSTS"
    fi

    info "Chroot filesystems mounted."
}

chroot_step_4() {
    info "Creating chroot user: ${PROOT_USER:-kemji}"
    local USER="${PROOT_USER:-kemji}"

    su -c "chroot $CHROOT_DIR /bin/bash -c \"
if ! id $USER &>/dev/null; then
    useradd -m -s /bin/bash $USER
    echo '$USER ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$USER
    chmod 440 /etc/sudoers.d/$USER
    echo 'User $USER created'
else
    echo 'User $USER already exists'
fi
\""
}

chroot_step_5() {
    info "Installing KDE Plasma in chroot (this may take a while)..."

    su -c "chroot $CHROOT_DIR /bin/bash -c \"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    ubuntu-desktop \
    kde-standard \
    dbus-x11 \
    x11-xserver-utils \
    mesa-utils \
    pulseaudio \
    sudo \
    wget \
    curl \
    net-tools \
    iputils-ping \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    gnupg
\""
}

chroot_step_6() {
    info "Installing GPU acceleration in chroot..."

    su -c "chroot $CHROOT_DIR /bin/bash -c \"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends \
    mesa-utils \
    libgl1-mesa-dri \
    libgl1-mesa-glx \
    libgles2-mesa \
    libegl1-mesa \
    vulkan-tools || true
\""
}

chroot_step_7() {
    info "Creating chroot launcher scripts..."
    mkdir -p ~/bin

    local USER="${PROOT_USER:-kemji}"

    cat > ~/bin/plasma-chroot << PLASMA_CHROOT_SCRIPT
#!/data/data/com.termux/files/usr/bin/bash

# plasma-chroot - Start KDE Plasma from Ubuntu chroot
# Usage: plasma-chroot [start|stop]

CHROOT_DIR="$CHROOT_DIR"
CHROOT_USER="$USER"
HW_CONF="$HOME/.local/share/plasma-hw.conf"
HW_MODE=\$(grep "^HW_MODE=" "\$HW_CONF" 2>/dev/null | cut -d= -f2 || echo "angle-gl")

case "\$1" in
    stop)
        echo "Shutting down chroot KDE Plasma..."
        su -c "chroot \$CHROOT_DIR /bin/bash -c 'export DISPLAY=:0; killall -9 startplasma-x11 plasmashell kwin_x11 kded6 2>/dev/null'"
        su -c "killall -9 virgl_test_server_android 2>/dev/null"
        su -c "killall -9 termux-x11 2>/dev/null"
        pulseaudio --kill 2>/dev/null
        echo "Done."
        exit 0
        ;;
esac

# Stop any existing session
\$0 stop 2>/dev/null
sleep 1

# Unset PULSE_SERVER before starting PulseAudio
unset PULSE_SERVER
pulseaudio --kill 2>/dev/null
sleep 1
pulseaudio --start --exit-idle-time=-1

sleep 1
PULSE_SOCK=\$(ls /data/data/com.termux/files/usr/tmp/pulse*/native 2>/dev/null | head -1)
if [ -n "\$PULSE_SOCK" ]; then
    export PULSE_SERVER="unix:\$PULSE_SOCK"
else
    export PULSE_SERVER=127.0.0.1
fi

# Start virgl renderer if needed (native Termux side)
case "\$HW_MODE" in
    software|angle-gl|angle-vulkan)
        setsid virgl_test_server_android --angle-gl </dev/null >/dev/null 2>&1 &
        sleep 1
        ;;
esac

# Start Termux:X11
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity &>/dev/null
sleep 3
setsid termux-x11 :0 </dev/null >/dev/null 2>&1 &
sleep 5

TRIES=0
while [ ! -e "\${TMPDIR}/.X11-unix/X0" ] && [ \$TRIES -lt 20 ]; do
    sleep 1
    TRIES=\$((TRIES + 1))
done

if [ ! -e "\${TMPDIR}/.X11-unix/X0" ]; then
    echo "ERROR: X11 display not ready. Is Termux:X11 app installed?"
    exit 1
fi

echo "X11 display ready."

# Mount chroot filesystems
su -c "mount -t proc proc \$CHROOT_DIR/proc" 2>/dev/null
su -c "mount -t sysfs sysfs \$CHROOT_DIR/sys" 2>/dev/null
su -c "mount --bind /dev \$CHROOT_DIR/dev" 2>/dev/null
su -c "mount --bind /dev/pts \$CHROOT_DIR/dev/pts" 2>/dev/null
su -c "mount --bind /data/data/com.termux/files/usr/tmp \$CHROOT_DIR/tmp" 2>/dev/null

# Copy resolv.conf
su -c "cp /etc/resolv.conf \$CHROOT_DIR/etc/resolv.conf" 2>/dev/null || true

# Start KDE in chroot
info() { echo -e "\033[0;32m[INFO]\033[0m \$*"; }
info "Starting KDE Plasma in chroot..."

su -c "chroot \$CHROOT_DIR /bin/bash -c \"
export HOME=/home/$CHROOT_USER
export USER=$CHROOT_USER
export LOGNAME=$CHROOT_USER
export DISPLAY=:0
export XDG_RUNTIME_DIR=/tmp
export PULSE_SERVER=unix:\$XDG_RUNTIME_DIR/pulse/native
export QT_SELECT=qt5

# Start dbus
eval \\\$(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS

# Start KDE
startplasma-x11 &
KDE_PID=\\\$!

# Wait for KDE to finish
wait \\\$KDE_PID
\""
PLASMA_CHROOT_SCRIPT
    chmod +x ~/bin/plasma-chroot

    cat > ~/bin/chroot-shell << 'CHROOT_SHELL_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# chroot-shell - Open a shell in the chroot

CHROOT_DIR="$HOME/chroot-ubuntu"
CHROOT_USER="${PROOT_USER:-kemji}"

# Mount filesystems if not already mounted
su -c "mount -t proc proc $CHROOT_DIR/proc" 2>/dev/null
su -c "mount -t sysfs sysfs $CHROOT_DIR/sys" 2>/dev/null
su -c "mount --bind /dev $CHROOT_DIR/dev" 2>/dev/null
su -c "mount --bind /dev/pts $CHROOT_DIR/dev/pts" 2>/dev/null
su -c "mount --bind /data/data/com.termux/files/usr/tmp $CHROOT_DIR/tmp" 2>/dev/null
su -c "cp /etc/resolv.conf $CHROOT_DIR/etc/resolv.conf" 2>/dev/null || true

echo "Entering chroot shell as $CHROOT_USER..."
su -c "chroot $CHROOT_DIR /bin/su - $CHROOT_USER"
CHROOT_SHELL_SCRIPT
    chmod +x ~/bin/chroot-shell

    cat > ~/bin/chroot-umount << 'UMOUNT_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash
# chroot-umount - Unmount chroot filesystems

CHROOT_DIR="$HOME/chroot-ubuntu"

echo "Unmounting chroot filesystems..."
su -c "umount $CHROOT_DIR/dev/pts" 2>/dev/null
su -c "umount $CHROOT_DIR/dev/shm" 2>/dev/null
su -c "umount $CHROOT_DIR/dev" 2>/dev/null
su -c "umount $CHROOT_DIR/sys" 2>/dev/null
su -c "umount $CHROOT_DIR/proc" 2>/dev/null
su -c "umount $CHROOT_DIR/tmp" 2>/dev/null
echo "Done."
UMOUNT_SCRIPT
    chmod +x ~/bin/chroot-umount
}

chroot_step_8() {
    local USER="${PROOT_USER:-kemji}"
    if ! grep -q 'chroot-kde' ~/.bashrc 2>/dev/null; then
        cat >> ~/.bashrc << BASHRC_ADDON

# ---- Chroot KDE ----
export PATH="\$HOME/bin:\$PATH"
alias plasma-chroot='~/bin/plasma-chroot'
alias chroot-shell='~/bin/chroot-shell'
alias chroot-umount='~/bin/chroot-umount'
BASHRC_ADDON
    fi
}

chroot_step_9() {
    mkdir -p ~/.local/share/applications
    cat > ~/.local/share/applications/plasma-chroot.desktop << 'DESKTOP_FILE'
[Desktop Entry]
Name=KDE Plasma (Chroot)
Comment=KDE Plasma desktop from Ubuntu chroot
Exec=/data/data/com.termux/files/home/bin/plasma-chroot
Icon=plasma
Type=Application
Categories=System;Desktop;
Terminal=false
StartupNotify=true
DESKTOP_FILE
}

chroot_step_10() {
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
mark-wmwin-focused = true
mark-ovredir-focused = true
use-ewmh-active-win = true
blur-background = false
log-level = "info"
PICOM_CONFIG

    mkdir -p "$(dirname "$HW_CONF")"
    if [ ! -f "$HW_CONF" ]; then
        echo "HW_MODE=${HW_MODE:-angle-gl}" > "$HW_CONF"
        echo "GPU_FAMILY=$(detect_gpu)" >> "$HW_CONF"
        echo "PROOT_USER=${PROOT_USER:-kemji}" >> "$HW_CONF"
        echo "QT_BACKEND=vulkan" >> "$HW_CONF"
    fi
}

# ============================================================
# Step dispatchers
# ============================================================

native_step_desc() {
    case $1 in
        1) echo "Update Termux packages" ;;
        2) echo "Install package repositories" ;;
        3) echo "Install KDE Plasma desktop" ;;
        4) echo "Install GPU acceleration (virglrenderer)" ;;
        5) echo "Install picom compositor and extras" ;;
        6) echo "Install PulseAudio" ;;
        7) echo "Create plasma launch scripts" ;;
        8) echo "Create picom config" ;;
        9) echo "Setup proot-distro Ubuntu" ;;
        10) echo "Create proot-code wrapper" ;;
        11) echo "Create VS Code desktop entry" ;;
        12) echo "Update .bashrc" ;;
        13) echo "Install Firefox and Code OSS" ;;
        14) echo "Compile username override library" ;;
    esac
}

chroot_step_desc() {
    case $1 in
        1) echo "Update packages and install tools" ;;
        2) echo "Download Ubuntu rootfs" ;;
        3) echo "Configure chroot mounts" ;;
        4) echo "Create chroot user" ;;
        5) echo "Install KDE Plasma in chroot" ;;
        6) echo "Install GPU libs in chroot" ;;
        7) echo "Create launcher scripts" ;;
        8) echo "Update .bashrc" ;;
        9) echo "Create desktop entry" ;;
        10) echo "Create picom config" ;;
    esac
}

# ============================================================
# Execute all steps
# ============================================================

if [ "$INSTALL_MODE" = "chroot" ]; then
    info "Mode: CHROOT (Ubuntu inside real chroot)"
    for i in $(seq 1 $total_steps_chroot); do
        desc=$(chroot_step_desc $i)
        case $i in
            7|10) run_step "$i" "$desc" force || exit 1 ;;
            *)    run_step "$i" "$desc" || exit 1 ;;
        esac
    done
else
    info "Mode: TERMUX NATIVE"
    for i in $(seq 1 $total_steps_native); do
        desc=$(native_step_desc $i)
        case $i in
            7|8) run_step "$i" "$desc" force || exit 1 ;;
            *)   run_step "$i" "$desc" || exit 1 ;;
        esac
    done
fi

# ---- Done ----
echo ""
info "=========================================="
info "Installation complete! (mode: $INSTALL_MODE)"
info "=========================================="
echo ""

if [ "$INSTALL_MODE" = "chroot" ]; then
    info "To start KDE Plasma (chroot):"
    info "  plasma-chroot"
    echo ""
    info "To open a chroot shell:"
    info "  chroot-shell"
    echo ""
    info "To unmount chroot filesystems:"
    info "  chroot-umount"
    echo ""
    info "To change HW acceleration:"
    info "  plasma change"
else
    info "To start KDE Plasma:"
    info "  plasma"
    echo ""
    info "To change HW acceleration:"
    info "  plasma change"
    echo ""
    info "To launch VS Code (proot):"
    info "  proot-code"
    echo ""
    info "To login to proot Ubuntu as ${PROOT_USER:-kemji}:"
    info "  proot"
fi
echo ""
info "Check the Termux:X11 app on your phone for the desktop."
echo ""
