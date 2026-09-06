#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# Termux KDE Plasma Native Installation Script
# GPU accelerated via virgl/ANGLE
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
#   ./install.sh            # resume from last completed step
#   ./install.sh --force    # restart from scratch
#   ./install.sh --status   # show progress
#
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STATE_FILE="$HOME/.install-kde-state"

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

total_steps=13

step_done() {
    grep -q "^step_$1=done$" "$STATE_FILE" 2>/dev/null
}

mark_done() {
    mkdir -p "$(dirname "$STATE_FILE")"
    if [ -f "$STATE_FILE" ]; then
        sed -i "/^step_$1=/d" "$STATE_FILE"
    fi
    echo "step_$1=done" >> "$STATE_FILE"
}

run_step() {
    local step=$1
    local desc=$2
    local func="step_${step}"

    if step_done "$step"; then
        info "Step $step/$total_steps: $desc (already done, skipping)"
        return 0
    fi

    info "Step $step/$total_steps: $desc"
    if $func; then
        mark_done "$step"
        return 0
    else
        error "Step $step/$total_steps failed: $desc"
        error "Run ./install.sh to retry from this step."
        return 1
    fi
}

# ---- Handle flags ----
case "${1:-}" in
    --force)
        warn "Resetting install state. Starting fresh..."
        rm -f "$STATE_FILE"
        ;;
    --status)
        if [ ! -f "$STATE_FILE" ]; then
            info "No installation progress found. Run ./install.sh to start."
        else
            info "Completed steps:"
            for i in $(seq 1 $total_steps); do
                if step_done "$i"; then
                    echo -e "  ${GREEN}[x]${NC} Step $i"
                else
                    echo -e "  ${YELLOW}[ ]${NC} Step $i"
                fi
            done
        fi
        exit 0
        ;;
    --help|-h)
        echo "Usage: ./install.sh [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  (none)     Resume from last completed step"
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

    # Only prompt if not already configured
    if [ -z "$PROOT_USER" ]; then
        echo ""
        info "=== Interactive Setup ==="
        echo ""
        read -rp "Enter username for proot Ubuntu [kemji]: " INPUT_USER
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
    interactive_setup
else
    load_setup_conf
fi

# ============================================================
# Step functions
# ============================================================

step_1() {
    pkg update -y && pkg upgrade -y
}

step_2() {
    pkg install -y root-repo x11-repo glibc-repo
}

step_3() {
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

step_4() {
    DEBIAN_FRONTEND=noninteractive pkg install -y virglrenderer-android
}

step_5() {
    DEBIAN_FRONTEND=noninteractive pkg install -y \
        picom \
        dbus \
        mesa-demos \
        termux-x11-nightly
}

step_6() {
    DEBIAN_FRONTEND=noninteractive pkg install -y pulseaudio
}

step_7() {
    mkdir -p ~/bin

    # --- ~/bin/plasma ---
    cat > ~/bin/plasma << 'PLASMA_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash

# plasma - Start/Stop KDE Plasma with GPU acceleration on Termux X11
# Usage: plasma [start|stop|change]

HW_CONF="$HOME/.local/share/plasma-hw.conf"
HW_MODE=$(grep "^HW_MODE=" "$HW_CONF" 2>/dev/null | cut -d= -f2 || echo "angle-gl")

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

# Read QT_BACKEND from config (fallback to HW mode default)
QT_BACKEND=$(grep "^QT_BACKEND=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
if [ -z "$QT_BACKEND" ]; then
    QT_BACKEND="$HW_QT_BACKEND"
fi

# Apply QT_BACKEND-specific environment overrides
case "$QT_BACKEND" in
    opengl)
        export EPOXY_USE_ANGLE=1
        export LD_LIBRARY_PATH="${PREFIX}/opt/angle-android/gl${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        ;;
    vulkan)
        if [ -z "$EPOXY_USE_ANGLE" ]; then
            export EPOXY_USE_ANGLE=1
            export LD_LIBRARY_PATH="${PREFIX}/opt/angle-android/vulkan${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        fi
        ;;
    software)
        export QT_QUICK_BACKEND=software
        ;;
esac

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

pulseaudio --kill 2>/dev/null
sleep 1
pulseaudio --start \
  --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
  --exit-idle-time=-1

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

# Set SceneGraphBackend only on first run — never override user's choice
KDEG="$HOME/.config/kdeglobals"
if [ ! -f "$KDEG" ] || ! grep -q "SceneGraphBackend" "$KDEG" 2>/dev/null; then
    mkdir -p "$(dirname "$KDEG")"
    printf "\n[QtQuickRendererSettings]\nSceneGraphBackend=%s\n" "$QT_BACKEND" >> "$KDEG"
fi

chmod +x ~/bin/.plasma-daemon
setsid ~/bin/.plasma-daemon </dev/null >/dev/null 2>&1 &

sleep 5
echo "KDE Plasma started (mode: $HW_MODE, backend: $QT_BACKEND). Check Termux:X11 app."
PLASMA_SCRIPT
    chmod +x ~/bin/plasma

    # --- ~/bin/.plasma-daemon ---
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

# Read QT_BACKEND from config (fallback to HW mode default)
QT_BACKEND=$(grep "^QT_BACKEND=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
case "$QT_BACKEND" in
    opengl)
        export EPOXY_USE_ANGLE=1
        export LD_LIBRARY_PATH="${PREFIX}/opt/angle-android/gl${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        ;;
    vulkan)
        if [ -z "$EPOXY_USE_ANGLE" ]; then
            export EPOXY_USE_ANGLE=1
            export LD_LIBRARY_PATH="${PREFIX}/opt/angle-android/vulkan${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        fi
        ;;
    software)
        export QT_QUICK_BACKEND=software
        ;;
esac

export DISPLAY=:0
export PULSE_SERVER=127.0.0.1
export vblank_mode=0
export GTK_CSD=0
export XDG_RUNTIME_DIR=${TMPDIR}

exec dbus-run-session startplasma-x11
DAEMON_SCRIPT
    chmod +x ~/bin/.plasma-daemon

    # --- ~/bin/plasma-change ---
    cat > ~/bin/plasma-change << 'CHANGE_SCRIPT'
#!/data/data/com.termux/files/usr/bin/bash

# plasma-change - Change HW acceleration mode, Qt backend, or proot username

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

# Read current config
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
echo "  4) Termux Username        [${USER:-u0_a337}]"
echo ""
read -rp "Select [1-4] (q=cancel): " SECTION
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
        # Also update kdeglobals immediately so user can see the change
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
            echo "NOTE: Run ./install.sh to create this user in Ubuntu."
        else
            echo "Username unchanged."
        fi
        ;;
    4)
        echo "--- Termux Username ---"
        echo ""
        echo "Changes the username shown in your terminal and KDE."
        echo "Current username: ${USER:-u0_a337}"
        echo ""
        read -rp "Enter new username (Enter to keep current): " NEW_NAME
        if [ -n "$NEW_NAME" ]; then
            if grep -q '^# ---- Termux User ----' ~/.bashrc 2>/dev/null; then
                sed -i '/^# ---- Termux User ----$/,/^export LOGNAME=.*$/d' ~/.bashrc
            fi
            cat >> ~/.bashrc << USER_ADDON

# ---- Termux User ----
export USER="$NEW_NAME"
export LOGNAME="$NEW_NAME"
export PS1="$NEW_NAME@\\h:\\w\\$ "
USER_ADDON
            echo ""
            echo "Username changed to: $NEW_NAME"
            echo "Open a new terminal or restart KDE to see the change."
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

    # --- Default HW config ---
    mkdir -p "$(dirname "$HW_CONF")"
    if [ ! -f "$HW_CONF" ]; then
        echo "HW_MODE=${HW_MODE:-angle-gl}" > "$HW_CONF"
        echo "GPU_FAMILY=$(detect_gpu)" >> "$HW_CONF"
        echo "PROOT_USER=${PROOT_USER:-kemji}" >> "$HW_CONF"
        echo "QT_BACKEND=vulkan" >> "$HW_CONF"
    fi
}

step_8() {
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

step_9() {
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

step_10() {
    mkdir -p ~/bin
    local USER="${PROOT_USER:-kemji}"
    cat > ~/bin/proot-code << PROOT_CODE
#!/data/data/com.termux/files/usr/bin/bash

# proot-code: Launch VS Code from proot Ubuntu on Termux X11
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

step_11() {
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

step_12() {
    local USER="${PROOT_USER:-kemji}"
    if ! grep -q 'termux-kde' ~/.bashrc 2>/dev/null; then
        cat >> ~/.bashrc << BASHRC_ADDON

# ---- Termux KDE ----
export PATH="\$HOME/bin:\$HOME/.shortcuts:\$PATH"
alias proot='proot-distro login ubuntu -u $USER --bind /data/data/com.termux/files/usr/tmp/.X11-unix:/tmp/.X11-unix'
BASHRC_ADDON
    fi
}

step_13() {
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
Icon=code-oss
Type=Application
Categories=Development;IDE;
Terminal=false
StartupNotify=true
CODE_DESKTOP
}

# ============================================================
# Execute all steps
# ============================================================

step_desc() {
    case $1 in
        1) echo "Update Termux packages" ;;
        2) echo "Install package repositories" ;;
        3) echo "Install KDE Plasma desktop" ;;
        4) echo "Install GPU acceleration (virglrenderer)" ;;
        5) echo "Install picom compositor and extras" ;;
        6) echo "Install PulseAudio" ;;
        7) echo "Create plasma launch script" ;;
        8) echo "Create picom config" ;;
        9) echo "Setup proot-distro Ubuntu" ;;
        10) echo "Create proot-code wrapper" ;;
        11) echo "Create VS Code desktop entry" ;;
        12) echo "Update .bashrc" ;;
        13) echo "Install Firefox and Code OSS" ;;
    esac
}

for i in $(seq 1 $total_steps); do
    run_step "$i" "$(step_desc $i)" || exit 1
done

# ---- Done ----
echo ""
info "=========================================="
info "Installation complete!"
info "=========================================="
echo ""
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
echo ""
info "Check the Termux:X11 app on your phone for the desktop."
echo ""
