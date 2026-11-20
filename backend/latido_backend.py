#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Latido backend — CPU temperature, CPU usage and RAM for the Latido plasmoid.

Fuentes: perfil térmico compartido ``hwprofile`` (contrato
``docs/contracts/OVDD-perfil-termico.md`` de hwprofile), ``/proc/stat`` y
``/proc/meminfo``. Expone una API JSON en 127.0.0.1:8136. Solo stdlib; el
paquete ``hwprofile`` es opcional (si falta, se degrada sin romper nada).

Endpoints:
    GET  /api/status   -> métricas + historial + bloque «termico»
    GET  /api/config   -> configuración actual
    POST /api/config   -> {interval_s: 1-10, unit: "C"|"F", temp_warn_c, temp_crit_c}

Variables de entorno (solo banco de pruebas / auditoría; no hacen falta en uso
normal, todo tiene su valor por defecto):
    LATIDO_PORT    puerto de escucha (8136)
    LATIDO_CONFIG  ruta de config.json (~/.config/latido/config.json)
    LATIDO_HWMON   raíz de hwmon (/sys/class/hwmon)
"""
import json
import os
import socketserver
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

# ---------------------------------------------------------------------------
# Perfil térmico compartido (contrato §3.1). Import TOLERANTE: si el paquete no
# está instalado el servicio arranca igual, deja el motivo en el journal y
# publica «termico»: {disponible: false, motivo: …}; el QML sigue funcionando
# con los campos de siempre (§5.11). Nunca un servicio en bucle de reinicio.
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.expanduser("~/.local/lib"))
try:
    from hwprofile import PerfilInvalido, Sensores, Termico, cargar_perfil
    HWDISPONIBLE = True
    HWERROR = ""
except Exception as _exc:                   # ImportError o instalación corrupta
    Sensores = Termico = cargar_perfil = None
    HWDISPONIBLE = False
    HWERROR = f"{type(_exc).__name__}: {_exc}"

    class PerfilInvalido(ValueError):
        """Marcador de tipo: con hwprofile instalado es la excepción real."""

PORT = int(os.environ.get("LATIDO_PORT", "8136"))
# Ventana del sparkline en SEGUNDOS (contrato §3.5): 360 s = 360 muestras a 1 Hz.
HISTORY_LEN = 360
# Tick del sampler a 1 s fijo (contrato §3.5); `interval_s` del config deja de
# gobernar el muestreo y queda solo como cadencia del QML.
TICK_S = 1.0
CONFIG_PATH = Path(
    os.environ.get("LATIDO_CONFIG")
    or (Path.home() / ".config" / "latido" / "config.json")
).expanduser()
HWMON_RAIZ = os.environ.get("LATIDO_HWMON", "/sys/class/hwmon")

DEFAULT_CONFIG = {
    "interval_s": 2,                    # cadencia del QML (ya NO del muestreo)
    "unit": "C",
    "temp_warn_c": 60,                  # override de warning_min (§4.3)
    "temp_crit_c": 80,                  # override de critical_min (§4.3)
    "auto_show": True,                  # mostrar la mascota flotante
}

SYS_CPU = Path("/sys/devices/system/cpu")


def _log(mensaje):
    """Log a stderr (el unit lo manda al journal, el QML nunca lo ve)."""
    print(f"[latido] {mensaje}", file=sys.stderr, flush=True)


def _hist_pct(valor):
    """Muestra de historial de porcentaje: entera (360 s × 3 series ≤ 6 KB)."""
    return int(round(valor))


def _hist_temp(valor):
    """Muestra de historial de temperatura: 0,1 °C (es la serie del sparkline)."""
    return round(valor, 1)


class Sampler:
    def __init__(self):
        self.lock = threading.RLock()
        self.config = dict(DEFAULT_CONFIG)
        self._load_config()
        self.state = {
            "temp_c": None, "cpu_pct": 0.0,
            "mem_pct": 0.0, "mem_used_gb": 0.0, "mem_total_gb": 0.0,
            "freq_mhz": 0, "fan_rpm": None,
            "cpu_hist": [], "mem_hist": [], "temp_hist": [],
        }
        self._prev_stat = None
        self.cpu_name, self.cores = self._read_cpu_info()

        # ---- perfil térmico compartido (§3.1, §3.4) ----
        self.perfil = None              # perfil vigente (con override aplicado)
        self.perfil_base = None         # perfil tal cual, sin override
        self.termico = None             # máquina de estados (None si no hay lib)
        self.sensores = None            # resolver de sensores (None si no hay lib)
        self.motivo_sin_perfil = ""     # por qué no hay bloque «termico»
        self._cargar_perfil()           # deja perfil_base/sensores o el motivo
        self._migrar_umbrales()         # §4.3: 85/95 -> 87/94 + sello de versión
        self.aplicar_umbrales()         # override temp_warn_c/crit_c + Termico

        # Sensores de respaldo: SOLO modo degradado (sin hwprofile instalado).
        self.temp_path = self._buscar_temp_degradado() if self.sensores is None else None
        self.fan_path = self._buscar_fan_degradado() if self.sensores is None else None

    # ---------------- config ----------------
    def _load_config(self):
        try:
            if CONFIG_PATH.exists():
                self.config.update(json.loads(CONFIG_PATH.read_text()))
        except Exception as exc:
            _log(f"config.json ilegible ({exc}); se usan los valores por defecto")

    def _save_config(self):
        try:
            CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
            CONFIG_PATH.write_text(json.dumps(self.config, indent=2))
        except Exception as exc:
            _log(f"no se pudo guardar config.json: {exc}")

    # ---------------- perfil térmico ----------------
    def _cargar_perfil(self):
        """Carga el perfil compartido y su resolver de sensores (§3.1, §3.2)."""
        if not HWDISPONIBLE:
            self.motivo_sin_perfil = f"hwprofile no instalado ({HWERROR})"
            _log(f"perfil térmico no disponible: {self.motivo_sin_perfil}")
            return
        try:
            self.perfil_base = cargar_perfil()
            self.sensores = Sensores(HWMON_RAIZ, self.perfil_base.ignored_sensors)
        except Exception as exc:
            self.perfil_base = None
            self.sensores = None
            self.motivo_sin_perfil = f"perfil térmico no cargado: {exc}"
            _log(self.motivo_sin_perfil)

    def _migrar_umbrales(self):
        """Migración obligatoria §4.3: adopta 87/94 la primera vez y sella.

        Sin el sello ``perfil_umbrales_version`` el ``config.json`` de este
        equipo seguiría con 85/95 (contradicen el perfil) y el perfil no se
        aplicaría nunca. Los dos valores siguen siendo override legítimo
        después (§3.4): solo se escriben una vez.
        """
        if self.perfil_base is None or "perfil_umbrales_version" in self.config:
            return
        umbrales = self.perfil_base.umbrales()
        self.config["temp_warn_c"] = int(round(float(umbrales["warning_min"])))
        self.config["temp_crit_c"] = int(round(float(umbrales["critical_min"])))
        self.config["perfil_umbrales_version"] = 1
        self._save_config()
        _log(
            "migración de umbrales: temp_warn_c=%s temp_crit_c=%s "
            "perfil_umbrales_version=1"
            % (self.config["temp_warn_c"], self.config["temp_crit_c"])
        )

    def aplicar_umbrales(self):
        """Aplica el override de umbrales y (re)construye la máquina térmica.

        ``temp_warn_c``/``temp_crit_c`` sobrescriben ``warning_min``/
        ``critical_min`` del perfil (§3.4, §4.3); el resto es de solo lectura.
        Si el override deja los umbrales no monótonos, ``PerfilInvalido`` lo
        rechaza: se conserva el perfil del fichero y se deja constancia.

        Se toma el lock porque la llamada llega desde el hilo HTTP mientras el
        sampler puede estar dentro de ``termico.actualizar()``.
        """
        with self.lock:
            self._aplicar_umbrales_sin_lock()

    def _aplicar_umbrales_sin_lock(self):
        if self.perfil_base is None:
            return
        perfil = self.perfil_base
        try:
            perfil = self.perfil_base.con_umbrales(
                self.config.get("temp_warn_c"), self.config.get("temp_crit_c")
            )
        except PerfilInvalido as exc:
            _log(f"override de umbrales rechazado ({exc}); manda el perfil")

        if self.termico is not None and perfil.thresholds_celsius == self.perfil.thresholds_celsius:
            return                      # nada cambió: la máquina sigue como está

        # Al cambiar los umbrales la máquina se reconstruye; se reinyecta la cola
        # de muestras (la ventana de suavizado son los últimos segundos) para no
        # perder el suavizado ni el estado por un cambio de configuración.
        maquina = Termico(perfil)
        ahora = time.monotonic()
        recientes = list(self.state["temp_hist"])[-perfil.ventana_muestras:]
        for posicion, muestra in enumerate(recientes):
            maquina.actualizar(muestra, None, ahora - (len(recientes) - posicion))
        self.termico = maquina
        self.perfil = perfil

    def tick_s(self):
        """Periodo del sampler: el ``polling_interval_ms`` del perfil (1 s)."""
        if self.perfil is not None:
            return max(0.2, float(self.perfil.polling_interval_ms) / 1000.0)
        return TICK_S

    # ---------------- descubrimiento ----------------
    def _read_cpu_info(self):
        name, cores = "", 0
        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("model name"):
                        if not name:
                            name = line.split(":", 1)[1].strip()
                        cores += 1
        except Exception:
            pass
        return (name or "CPU"), (cores or 1)

    def _buscar_temp_degradado(self):
        """Modo degradado: primer temp*_input del chip preferido (sin hwprofile)."""
        encontrados = []
        try:
            for d in Path(HWMON_RAIZ).glob("hwmon*"):
                try:
                    nombre = (d / "name").read_text().strip()
                except Exception:
                    continue
                if nombre in ("k10temp", "coretemp", "thinkpad", "acpitz", "acpi"):
                    for t in sorted(d.glob("temp*_input")):
                        encontrados.append((nombre, t))
        except Exception:
            pass
        if not encontrados:
            return None
        preferencia = {"k10temp": 0, "coretemp": 0, "thinkpad": 1, "acpitz": 2, "acpi": 3}
        encontrados.sort(key=lambda c: (preferencia.get(c[0], 9), c[1].name))
        return encontrados[0][1]

    def _buscar_fan_degradado(self):
        """Modo degradado: primer fan1_input del chip ``thinkpad``.

        NO hay fallback a ningún otro chip: en este equipo hay un sensor que
        devuelve 0 rpm con el ventilador girando (contrato §3.2), así que usarlo
        produciría una anomalía falsa permanente. Sin lectura -> ``null``.
        """
        try:
            for d in Path(HWMON_RAIZ).glob("hwmon*"):
                try:
                    if (d / "name").read_text().strip() == "thinkpad":
                        f = d / "fan1_input"
                        if f.exists():
                            return f
                except Exception:
                    continue
        except Exception:
            pass
        return None

    # ---------------- lectores ----------------
    def _leer_temperatura(self):
        """Tctl del perfil; ``None`` sin lectura (nunca un valor inventado)."""
        if self.sensores is not None and self.perfil is not None:
            return self.sensores.temperatura(self.perfil.primary_sensor)
        return self._read_temp()

    def _leer_rpm(self):
        """RPM del perfil; ``None`` sin lectura (nunca 0 por defecto)."""
        if self.sensores is not None and self.perfil is not None:
            return self.sensores.ventilador(self.perfil.fan_sensor)
        return self._read_fan_rpm()

    def _read_temp(self):
        if self.temp_path is None:
            return None
        try:
            return int(self.temp_path.read_text().strip()) / 1000.0
        except Exception:
            return None

    def _read_fan_rpm(self):
        if self.fan_path is None:
            return None
        try:
            return int(self.fan_path.read_text().strip())
        except Exception:
            return None

    def _read_cpu_stat(self):
        try:
            with open("/proc/stat") as f:
                parts = f.readline().split()
            nums = [int(x) for x in parts[1:9]]
            return sum(nums), nums[3] + nums[4]          # (total, idle+iowait)
        except Exception:
            return None

    def _read_freq(self):
        try:
            cur = SYS_CPU / "cpu0" / "cpufreq" / "scaling_cur_freq"
            return int(cur.read_text().strip()) // 1000   # kHz -> MHz
        except Exception:
            pass
        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("cpu MHz"):
                        return int(float(line.split(":")[1].strip()))
        except Exception:
            pass
        return 0

    def _read_mem(self):
        tot = avail = None
        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        tot = int(line.split()[1])
                    elif line.startswith("MemAvailable:"):
                        avail = int(line.split()[1])
                    if tot is not None and avail is not None:
                        break
        except Exception:
            pass
        if tot and avail is not None:
            used = tot - avail
            return used / 1024 / 1024, tot / 1024 / 1024, used / tot * 100.0
        return 0.0, 0.0, 0.0

    # ---------------- muestreo ----------------
    def sample(self):
        stat = self._read_cpu_stat()
        cpu_pct = self.state["cpu_pct"]
        if stat and self._prev_stat:
            pt, pi = self._prev_stat
            dt = stat[0] - pt
            di = stat[1] - pi
            if dt > 0:
                cpu_pct = max(0.0, min(100.0, (dt - di) / dt * 100.0))
        if stat:
            self._prev_stat = stat

        temp = self._leer_temperatura()
        fan_rpm = self._leer_rpm()
        used_gb, tot_gb, mem_pct = self._read_mem()
        freq = self._read_freq()

        with self.lock:
            st = self.state
            st["temp_c"] = temp
            st["fan_rpm"] = fan_rpm
            st["cpu_pct"] = cpu_pct
            st["mem_pct"] = mem_pct
            st["mem_used_gb"] = used_gb
            st["mem_total_gb"] = tot_gb
            st["freq_mhz"] = freq
            st["cpu_hist"].append(_hist_pct(cpu_pct))
            st["mem_hist"].append(_hist_pct(mem_pct))
            if temp is not None:
                st["temp_hist"].append(_hist_temp(temp))
            for key in ("cpu_hist", "mem_hist", "temp_hist"):
                if len(st[key]) > HISTORY_LEN:
                    st[key] = st[key][-HISTORY_LEN:]
            # una muestra -> una entrada en la máquina de estados (1 Hz)
            if self.termico is not None:
                self.termico.actualizar(temp, fan_rpm, time.monotonic())

    def _bloque_termico(self):
        """Bloque «termico» del contrato §3.4 (o su versión degradada)."""
        if self.termico is None:
            motivo = self.motivo_sin_perfil or "perfil térmico no disponible"
            return {"disponible": False, "motivo": motivo}
        # snapshot() no añade muestra: entre dos ticks el bloque sigue vivo
        # (desde_s y restante_s se recalculan con el reloj actual)
        return {"disponible": True, **self.termico.snapshot(time.monotonic())}

    def snapshot(self):
        with self.lock:
            c = self.config
            return {
                "temp_c": self.state["temp_c"],
                "fan_rpm": self.state["fan_rpm"],
                "cpu_pct": round(self.state["cpu_pct"], 1),
                "mem_pct": round(self.state["mem_pct"], 1),
                "mem_used_gb": round(self.state["mem_used_gb"], 1),
                "mem_total_gb": round(self.state["mem_total_gb"], 1),
                "freq_mhz": self.state["freq_mhz"],
                "cores": self.cores,
                "cpu_name": self.cpu_name,
                # umbrales de temperatura (override del perfil, §4.3)
                "temp_warn_c": c["temp_warn_c"],
                "temp_crit_c": c["temp_crit_c"],
                "history": list(self.state["cpu_hist"]),
                "mem_history": list(self.state["mem_hist"]),
                "temp_history": list(self.state["temp_hist"]),
                # estado térmico (suavizado, histéresis, persistencia, anomalía)
                "termico": self._bloque_termico(),
            }


class Handler(BaseHTTPRequestHandler):
    sampler = None

    def _send(self, obj, code=200):
        # Separadores compactos: con 360 s de historial × 3 series el payload se
        # queda por debajo del límite de 6 KB del contrato (AC-2).
        body = json.dumps(obj, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/api/status"):
            self._send(self.sampler.snapshot())
        elif self.path.startswith("/api/config"):
            self._send(self.sampler.config)
        else:
            self._send({"ok": True, "service": "latido", "port": PORT})

    def do_POST(self):
        if self.path.startswith("/api/config"):
            try:
                length = int(self.headers.get("Content-Length", 0))
                data = json.loads(self.rfile.read(length) or b"{}")
            except Exception:
                self._send({"ok": False, "error": "bad json"}, 400)
                return
            cfg = self.sampler.config
            if isinstance(data.get("interval_s"), int):
                # cadencia del QML (§3.5): ya no gobierna el muestreo
                cfg["interval_s"] = max(1, min(10, data["interval_s"]))
            if data.get("unit") in ("C", "F"):
                cfg["unit"] = data["unit"]
            if data.get("temp_warn_c") is not None:
                cfg["temp_warn_c"] = int(max(25, min(115, float(data["temp_warn_c"]))))
            if data.get("temp_crit_c") is not None:
                cfg["temp_crit_c"] = int(max(40, min(125, float(data["temp_crit_c"]))))
            if cfg["temp_crit_c"] <= cfg["temp_warn_c"]:
                cfg["temp_crit_c"] = cfg["temp_warn_c"] + 5
            if isinstance(data.get("auto_show"), bool):
                cfg["auto_show"] = data["auto_show"]
            # unos umbrales elegidos por el usuario ya son «post-migración»: se
            # sellan para que el arranque siguiente no los devuelva a 87/94
            cfg["perfil_umbrales_version"] = 1
            self.sampler._save_config()
            self.sampler.aplicar_umbrales()
            self._send({"ok": True, "config": cfg})
        else:
            self._send({"ok": False, "error": "not found"}, 404)

    def log_message(self, fmt, *args):
        pass


class ThreadedHTTPServer(socketserver.ThreadingMixIn, HTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    sampler = Sampler()
    Handler.sampler = sampler

    def loop():
        while True:
            sampler.sample()
            threading.Event().wait(sampler.tick_s())

    threading.Thread(target=loop, daemon=True).start()

    server = ThreadedHTTPServer(("127.0.0.1", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
