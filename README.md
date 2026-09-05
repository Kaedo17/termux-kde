# Termux KDE Plasma

Native KDE Plasma 6 desktop on Android via Termux + Termux:X11 with GPU acceleration.

## Requirements

- Android 8+
- [Termux](https://f-droid.org/en/packages/com.termux/) (F-Droid, NOT Play Store)
- [Termux:X11](https://github.com/termux/termux-x11/releases) app

## Install

```bash
chmod +x install.sh
./install.sh
```

## Usage

| Command | Description |
|---------|-------------|
| `plasma` | Start KDE Plasma desktop |
| `proot-code` | Launch VS Code from Ubuntu proot |
| `proot` | Login to Ubuntu proot as kemji |

## What's Included

- **KDE Plasma 6** (native, not proot)
- **virgl GPU acceleration** for Mali GPUs
- **Picom compositor** for window shadows
- **PulseAudio** for sound
- **proot-distro Ubuntu** for running Linux apps
- **VS Code** (via proot)
- **Konsole, Dolphin, Kate, Ark, Elisa, Gwenview, KCalc, Spectacle**

## Architecture

```
┌─────────────────────────────────────┐
│         Termux:X11 App              │
│         (Display Server)            │
├─────────────────────────────────────┤
│     KDE Plasma 6 (Native Termux)   │
│     startplasma-x11                 │
│     virgl (GPU accel)               │
│     picom (compositor)              │
├─────────────────────────────────────┤
│     proot-distro Ubuntu            │
│     User: kemji (sudo enabled)     │
│     VS Code, apps                  │
└─────────────────────────────────────┘
```

## Files Created

| File | Purpose |
|------|---------|
| `~/bin/plasma` | Start KDE desktop |
| `~/bin/proot-code` | Launch VS Code from proot |
| `~/.config/picom.conf` | Compositor config |
| `~/.local/share/applications/vscode-proot.desktop` | KDE launcher entry |
| `~/.bashrc` | PATH + proot alias |

## Samsung Tab S11

This setup is optimized for Samsung Tab S11 with Mali GPU. GPU acceleration is provided via virglrenderer (GALLIUM_DRIVER=virpipe).
