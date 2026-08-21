#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Latido backend — CPU temperature, CPU usage and RAM for the Latido plasmoid.

Fuentes: /sys/class/hwmon (k10temp/coretemp/thinkpad), /proc/stat, /proc/meminfo.
Expone una API JSON en 127.0.0.1:8136. Solo stdlib.

Endpoints:
    GET  /api/status   -> métricas + historial
    GET  /api/config   -> configuración actual
    POST /api/config   -> {interval_s: 1-10, unit: "C"|"F", temp_warn_c, temp_crit_c}
"""
import json
import socketserver
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

PORT = 8136
HISTORY_LEN = 180                       # muestras (a interval_s s -> 3-6 min)
CONFIG_PATH = Path.home() / ".config" / "latido" / "config.json"
DEFAULT_CONFIG = {
    "interval_s": 2,
    "unit": "C",
    "temp_warn_c": 60,                  # por debajo -> color normal; desde aquí -> ámbar
    "temp_crit_c": 80,                  # desde aquí -> rojo (umbral crítico)
}

SYS_HWMON = Path("/sys/class/hwmon")
SYS_CPU = Path("/sys/devices/system/cpu")

class Sampler:
    def __init__(self):
        self.lock = threading.Lock()
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
        self.temp_path = self._find_temp_sensor()
        self.fan_path = self._find_fan_sensor()

    # ---------------- config ----------------
    def _load_config(self):
        try:
            if CONFIG_PATH.exists():
                self.config.update(json.loads(CONFIG_PATH.read_text()))
        except Exception:
            pass

    def _save_config(self):
        try:
            CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
            CONFIG_PATH.write_text(json.dumps(self.config, indent=2))
        except Exception:
            pass

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

    def _find_temp_sensor(self):
        """Primer temp*_input del chip preferido: k10temp/coretemp, thinkpad, acpitz."""
        found = []
        try:
            for d in SYS_HWMON.glob("hwmon*"):
                try:
                    name = (d / "name").read_text().strip()
                except Exception:
                    continue
                if name in ("k10temp", "coretemp", "thinkpad", "acpitz", "acpi"):
                    for t in sorted(d.glob("temp*_input")):
                        found.append((name, t))
        except Exception:
            pass
        if not found:
            return None
        pref = {"k10temp": 0, "coretemp": 0, "thinkpad": 1, "acpitz": 2, "acpi": 3}
        found.sort(key=lambda c: (pref.get(c[0], 9), c[1].name))
        return found[0][1]

    def _find_fan_sensor(self):
        """Primer fan1_input del chip thinkpad/acpi_fan (RPM del ventilador)."""
        for name in ("thinkpad", "acpi_fan"):
            try:
                for d in SYS_HWMON.glob("hwmon*"):
                    if (d / "name").read_text().strip() == name:
                        f = d / "fan1_input"
                        if f.exists():
                            return f
            except Exception:
                continue
        return None

    # ---------------- lectores ----------------
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

        temp = self._read_temp()
        fan_rpm = self._read_fan_rpm()
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
            st["cpu_hist"].append(round(cpu_pct, 1))
            st["mem_hist"].append(round(mem_pct, 1))
            if temp is not None:
                st["temp_hist"].append(round(temp, 1))
            for key in ("cpu_hist", "mem_hist", "temp_hist"):
                if len(st[key]) > HISTORY_LEN:
                    st[key] = st[key][-HISTORY_LEN:]

    def snapshot(self):
        with self.lock:
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
                "history": list(self.state["cpu_hist"]),
                "mem_history": list(self.state["mem_hist"]),
                "temp_history": list(self.state["temp_hist"]),
            }

class Handler(BaseHTTPRequestHandler):
    sampler = None

    def _send(self, obj, code=200):
        body = json.dumps(obj).encode()
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
                cfg["interval_s"] = max(1, min(10, data["interval_s"]))
            if data.get("unit") in ("C", "F"):
                cfg["unit"] = data["unit"]
            if data.get("temp_warn_c") is not None:
                cfg["temp_warn_c"] = int(max(25, min(115, float(data["temp_warn_c"]))))
            if data.get("temp_crit_c") is not None:
                cfg["temp_crit_c"] = int(max(40, min(125, float(data["temp_crit_c"]))))
            if cfg["temp_crit_c"] <= cfg["temp_warn_c"]:
                cfg["temp_crit_c"] = cfg["temp_warn_c"] + 5
            self.sampler._save_config()
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
            threading.Event().wait(sampler.config["interval_s"])

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
