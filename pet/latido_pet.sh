#!/usr/bin/env bash
# Lanzador de la mascota flotante del Latido (Pulguito).
# Inyecta el entorno gráfico de la sesión (leído de plasmashell) y arranca qml6.
set -u
STAGE_DIR="$HOME/.local/share/latido/pet"

# Extraer entorno gráfico del proceso plasmashell de la sesión activa
PM="$(pgrep -x plasmashell | head -1)"
if [ -n "$PM" ]; then
    export $(tr '\0' '\n' < "/proc/$PM/environ" 2>/dev/null \
        | grep -E '^(DISPLAY|WAYLAND_DISPLAY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|XAUTHORITY|KDE_FULL_SESSION|XDG_CURRENT_DESKTOP|DESKTOP_SESSION|XDG_SESSION_TYPE)=' | xargs)
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export KDE_FULL_SESSION="${KDE_FULL_SESSION:-true}"
# Forzamos X11/XWayland (DISPLAY=:0): a diferencia de Wayland, el cliente SÍ
# puede posicionar la ventana con x/y absolutas -> esquina superior derecha.
export QT_QPA_PLATFORM=xcb
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

exec /usr/bin/qml6 "$STAGE_DIR/PetStage.qml"