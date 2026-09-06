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

total_steps=14

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
                echo "  4) Anland Wayland  - native Wayland (needs AnlandTermux APK)"
                echo ""
                read -rp "Select [1-4] (default: 2): " INPUT_HW
                case "${INPUT_HW:-2}" in
                    1) HW_MODE="software" ;;
                    2) HW_MODE="angle-gl" ;;
                    3) HW_MODE="angle-vulkan" ;;
                    4) HW_MODE="anland" ;;
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
UPOWER_ENABLED=$(grep "^UPOWER_ENABLED=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
if [ -z "$UPOWER_ENABLED" ]; then UPOWER_ENABLED="true"; fi

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
    anland)
        HW_ENV="ANLAND=1 ANLAND_SOCKET=\$TMPDIR/anland/display_daemon.sock MESA_LOADER_DRIVER_OVERRIDE=kgsl TURNIP_KMD=kgsl GALLIUM_DRIVER=freedreno FD_FORCE_KGSL=1 XWAYLAND_FORCE_KGSL_SURFACELESS=1 EGL_PLATFORM=surfaceless"
        HW_SERVER=""
        HW_QT_BACKEND="vulkan"
        HW_DISPLAY="anland"
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

# LD_PRELOAD for username override
if [ -f "\$HOME/.local/lib/termux-user.so" ] && grep -q "^TERMUX_USER=" "\$HW_CONF" 2>/dev/null; then
    export LD_PRELOAD="\$HOME/.local/lib/termux-user.so\${LD_PRELOAD:+:\$LD_PRELOAD}"
    TERMUX_USER_VAL=\$(grep "^TERMUX_USER=" "\$HW_CONF" 2>/dev/null | cut -d= -f2)
    if [ -n "\$TERMUX_USER_VAL" ]; then
        export USER="\$TERMUX_USER_VAL"
        export LOGNAME="\$TERMUX_USER_VAL"
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
    killall -9 anland 2>/dev/null
    killall -9 anland-compatible 2>/dev/null
    killall -9 kwin_wayland 2>/dev/null
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
pulseaudio --start --exit-idle-time=-1

# Detect actual PulseAudio Unix socket (TCP often fails on Termux)
sleep 1
PULSE_SOCK=\$(ls /data/data/com.termux/files/usr/tmp/pulse-*/native 2>/dev/null | head -1)
if [ -n "\$PULSE_SOCK" ]; then
    export PULSE_SERVER="unix:\$PULSE_SOCK"
else
    export PULSE_SERVER=127.0.0.1
fi

if [ -n "\$HW_SERVER" ]; then
    setsid \$HW_SERVER </dev/null >/dev/null 2>&1 &
    sleep 1
fi

# Anland Wayland mode - different startup path
if [ "\$HW_DISPLAY" = "anland" ]; then
    # Create XDG_RUNTIME_DIR with proper permissions
    mkdir -p "\$TMPDIR/run"
    chown -R \$(id -un):\$(id -gn) "\$TMPDIR/run"
    chmod -R 700 "\$TMPDIR/run"
    mkdir -p "\$TMPDIR/.X11-unix"
    chmod 1777 "\$TMPDIR/.X11-unix"
    mkdir -p "\$TMPDIR/anland"

    # Start Anland daemon
    killall anland >/dev/null 2>&1
    setsid anland </dev/null >/dev/null 2>&1 &
    sleep 2

    # Launch AnlandTermux app
    am start --user 0 -n com.lfdevs.anlandtermux/.MainActivity &>/dev/null
    sleep 3

    TRIES=0
    while [ ! -e "\$TMPDIR/anland/display_daemon.sock" ] && [ \$TRIES -lt 20 ]; do
        sleep 1
        TRIES=\$((TRIES + 1))
    done

    if [ ! -e "\$TMPDIR/anland/display_daemon.sock" ]; then
        echo "ERROR: Anland display not ready. Is AnlandTermux app installed?"
        exit 1
    fi

    echo "Anland display ready."

    # Set SceneGraphBackend only on first run
    KDEG="\$HOME/.config/kdeglobals"
    if [ ! -f "\$KDEG" ] || ! grep -q "SceneGraphBackend" "\$KDEG" 2>/dev/null; then
        mkdir -p "\$(dirname "\$KDEG")"
        printf "\\n[QtQuickRendererSettings]\\nSceneGraphBackend=%s\\n" "\$QT_BACKEND" >> "\$KDEG"
    fi

    chmod +x ~/bin/.plasma-daemon
    setsid ~/bin/.plasma-daemon </dev/null >/dev/null 2>&1 &

    sleep 5

    # Disable UPower if user chose to
    if [ "$UPOWER_ENABLED" = "false" ]; then
        killall -9 upowerd 2>/dev/null
        killall -9 org_kde_powerdevil 2>/dev/null
    fi

    echo "KDE Plasma started (mode: anland, backend: \$QT_BACKEND). Check AnlandTermux app."
    exit 0
fi

# X11 mode (existing logic)
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

# Disable UPower if user chose to (kills the noisy Termux:API spam)
if [ "$UPOWER_ENABLED" = "false" ]; then
    killall -9 upowerd 2>/dev/null
    killall -9 org_kde_powerdevil 2>/dev/null
fi

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
    anland)
        export ANLAND=1
        export ANLAND_SOCKET=\$TMPDIR/anland/display_daemon.sock
        export MESA_LOADER_DRIVER_OVERRIDE=kgsl
        export TURNIP_KMD=kgsl
        export GALLIUM_DRIVER=freedreno
        export FD_FORCE_KGSL=1
        export XWAYLAND_FORCE_KGSL_SURFACELESS=1
        export EGL_PLATFORM=surfaceless
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
QT_BACKEND=\$(grep "^QT_BACKEND=" "\$HW_CONF" 2>/dev/null | cut -d= -f2)
case "\$QT_BACKEND" in
    opengl)
        export EPOXY_USE_ANGLE=1
        export LD_LIBRARY_PATH="\${PREFIX}/opt/angle-android/gl\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
        ;;
    vulkan)
        if [ -z "\$EPOXY_USE_ANGLE" ]; then
            export EPOXY_USE_ANGLE=1
            export LD_LIBRARY_PATH="\${PREFIX}/opt/angle-android/vulkan\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
        fi
        ;;
    software)
        export QT_QUICK_BACKEND=software
        ;;
esac

# LD_PRELOAD for username override
if [ -f "\$HOME/.local/lib/termux-user.so" ] && grep -q "^TERMUX_USER=" "\$HW_CONF" 2>/dev/null; then
    export LD_PRELOAD="\$HOME/.local/lib/termux-user.so\${LD_PRELOAD:+:\$LD_PRELOAD}"
    TERMUX_USER_VAL=\$(grep "^TERMUX_USER=" "\$HW_CONF" 2>/dev/null | cut -d= -f2)
    if [ -n "\$TERMUX_USER_VAL" ]; then
        export USER="\$TERMUX_USER_VAL"
        export LOGNAME="\$TERMUX_USER_VAL"
    fi
fi

export DISPLAY=:0
export vblank_mode=0
export GTK_CSD=0
export XDG_RUNTIME_DIR=\${TMPDIR}

# Detect actual PulseAudio Unix socket
PULSE_SOCK=\$(ls /data/data/com.termux/files/usr/tmp/pulse-*/native 2>/dev/null | head -1)
if [ -n "\$PULSE_SOCK" ]; then
    export PULSE_SERVER="unix:\$PULSE_SOCK"
else
    export PULSE_SERVER=127.0.0.1
fi

# Use Wayland session for Anland, X11 for everything else
if [ "\$HW_MODE" = "anland" ]; then
    exec dbus-run-session startplasma-wayland
else
    exec dbus-run-session startplasma-x11
fi
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

upower_label() {
    case "$1" in
        true)  echo "enabled" ;;
        false) echo "disabled" ;;
        *)     echo "enabled" ;;
    esac
}

# Read current config
CURRENT_MODE="angle-gl"
CURRENT_BACKEND="vulkan"
CURRENT_USER="kemji"
CURRENT_UPOWER=$(grep "^UPOWER_ENABLED=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
if [ -z "$CURRENT_UPOWER" ]; then CURRENT_UPOWER="true"; fi
CURRENT_TERMUX_USER=$(grep "^TERMUX_USER=" "$HW_CONF" 2>/dev/null | cut -d= -f2)
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
echo "  4) Termux Username        [${CURRENT_TERMUX_USER:-$(id -un)}]"
echo "  5) UPower Battery         [$(upower_label "$CURRENT_UPOWER")]"
echo ""
read -rp "Select [1-5] (q=cancel): " SECTION
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
                echo "  4) Anland Wayland  - native Wayland (needs AnlandTermux APK)"
                echo ""
                read -rp "Select [1-4] (q=cancel): " CHOICE
                case "$CHOICE" in
                    1) NEW_MODE="software" ;;
                    2) NEW_MODE="angle-gl" ;;
                    3) NEW_MODE="angle-vulkan" ;;
                    4) NEW_MODE="anland" ;;
                    q|Q) echo "Cancelled."; exit 0 ;;
                    *) echo "Invalid choice."; exit 1 ;;
                esac
                ;;
        esac
        mkdir -p "$(dirname "$HW_CONF")"
        sed -i "s/^HW_MODE=.*/HW_MODE=$NEW_MODE/" "$HW_CONF" 2>/dev/null || echo "HW_MODE=$NEW_MODE" >> "$HW_CONF"
        echo ""
        echo "Hardware acceleration changed to: $NEW_MODE"
        if [ "$NEW_MODE" = "anland" ]; then
            echo ""
            echo "=========================================="
            echo " Anland Wayland - Setup Required"
            echo "=========================================="
            echo ""
            echo "You need to install these packages first:"
            echo ""
            echo "  pkg install ~/anland_5.13.3_aarch64.deb"
            echo "  pkg install ~/xwayland_24.1.12-2_aarch64.deb"
            echo "  unzip kwin-anland_6.7.4_aarch64.deb"
            echo ""
            echo "Install the AnlandTermux APK from:"
            echo "  https://github.com/lfdevs/anland-termux/releases/latest"
            echo ""
            echo "Use 'AnlandTermux-5.13.3-compatible.apk' for F-Droid Termux"
            echo "Use 'AnlandTermux-5.13.3.apk' for GitHub Termux"
            echo ""
            echo "Then run 'plasma' to start the Wayland session."
            echo ""
        fi
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
        echo "Current username: ${CURRENT_TERMUX_USER:-$(id -un)}"
        echo ""
        read -rp "Enter new username (Enter to keep current): " NEW_NAME
        if [ -n "$NEW_NAME" ] && [ "$NEW_NAME" != "${CURRENT_TERMUX_USER:-$(id -un)}" ]; then
            mkdir -p "$(dirname "$HW_CONF")"
            if grep -q "^TERMUX_USER=" "$HW_CONF" 2>/dev/null; then
                sed -i "s/^TERMUX_USER=.*/TERMUX_USER=$NEW_NAME/" "$HW_CONF"
            else
                echo "TERMUX_USER=$NEW_NAME" >> "$HW_CONF"
            fi
            if grep -q '^# ---- Termux User ----' ~/.bashrc 2>/dev/null; then
                sed -i '/^# ---- Termux User ----$/,/^export PS1=.*$/d' ~/.bashrc
            fi
            cat >> ~/.bashrc << USER_ADDON

# ---- Termux User ----
export USER="$NEW_NAME"
export LOGNAME="$NEW_NAME"
export PS1="$NEW_NAME@\\h:\\w\\$ "
USER_ADDON
            echo ""
            echo "Username changed to: $NEW_NAME"
            echo "Restart plasma or open a new terminal to see the change."
        else
            echo "Username unchanged."
        fi
        ;;
    5)
        echo "--- UPower Battery Monitoring ---"
        echo ""
        echo "UPower polls battery status via Termux:API, which causes repeated"
        echo "errors on Android 14+ due to a known Termux:API bug:"
        echo "  - 'Connection refused' (ResultReturner)"
        echo "  - 'FLAG_ACTIVITY_NEW_TASK' (TermuxApiReceiver)"
        echo ""
        echo "These errors are harmless but noisy."
        echo ""
        echo "  1) Enable   - keep battery monitoring (default)"
        echo "  2) Disable  - stop UPower, no more errors"
        echo ""
        read -rp "Select [1-2] (q=cancel): " CHOICE
        case "$CHOICE" in
            1) NEW_UPOWER="true" ;;
            2) NEW_UPOWER="false" ;;
            q|Q) echo "Cancelled."; exit 0 ;;
            *) echo "Invalid choice."; exit 1 ;;
        esac
        mkdir -p "$(dirname "$HW_CONF")"
        if grep -q "^UPOWER_ENABLED=" "$HW_CONF" 2>/dev/null; then
            sed -i "s/^UPOWER_ENABLED=.*/UPOWER_ENABLED=$NEW_UPOWER/" "$HW_CONF"
        else
            echo "UPOWER_ENABLED=$NEW_UPOWER" >> "$HW_CONF"
        fi
        echo ""
        if [ "$NEW_UPOWER" = "false" ]; then
            echo "UPower disabled. Battery monitoring will be stopped on next plasma start."
        else
            echo "UPower enabled. Battery monitoring will remain active."
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
Icon=com.visualstudio.code.oss
Type=Application
Categories=Development;IDE;
Terminal=false
StartupNotify=true
CODE_DESKTOP
    # Copy code-oss icon to hicolor theme (package only installs to pixmaps)
    mkdir -p /data/data/com.termux/files/usr/share/icons/hicolor/48x48/apps
    cp /data/data/com.termux/files/usr/share/pixmaps/com.visualstudio.code.oss.png \
       /data/data/com.termux/files/usr/share/icons/hicolor/48x48/apps/ 2>/dev/null
    gtk-update-icon-cache -f /data/data/com.termux/files/usr/share/icons/hicolor/ 2>/dev/null
}

step_14() {
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
        14) echo "Compile username override library" ;;
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
