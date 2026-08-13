# 💓 Latido — Plasmoid de KDE Plasma 6

> El pulso de tu equipo en el panel: temperatura del procesador, uso de CPU y
> memoria RAM siempre a la vista, con iconos, barras de progreso y gráficas en vivo.

![Plasma 6](https://img.shields.io/badge/Plasma-6-blue)
![KDE Frameworks](https://img.shields.io/badge/KF-6.28-blue)
![Python](https://img.shields.io/badge/Python-3-stdlib-3776AB)
![Licencia](https://img.shields.io/badge/Licencia-GPL--2.0-green)

---

## ✨ Características

- 🌡️ **Temperatura CPU** en el icono del panel y en el panel expandido, con icono
  que cambia según el estado (❄ frío / 🌡 normal / 🔥 caliente) y color del valor
  (cian → ámbar → rojo según la temperatura)
- ⚡ **Uso de CPU** con porcentaje, barra de progreso y **gráfica en vivo**
  (historial de ~3-6 minutos)
- 🧠 **Memoria RAM** con porcentaje, barra, gráfica en vivo y uso concreto
  (usada / total en GB)
- 📊 **Frecuencia actual** del procesador y número de hilos
- 📏 **Icono compacto** con las 3 métricas siempre visibles en el panel;
  un clic expande el detalle
- ⚙️ **Configurable**: intervalo de refresco (1-5 s) y unidad de temperatura (°C/°F)
  desde Clic derecho → *Configurar Latido*
- 🌑 **Tema oscuro** integrado (paleta fija estilo HUD, coherente en cualquier color scheme)
- 🔌 **Backend robusto**: si el servicio no está corriendo, el icono lo indica
  sin romper el panel
- 🐍 **Solo stdlib**: backend Python sin dependencias externas (lee `/proc` y `/sys`)

---

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│  PLASMOID  rccamacho.latido                                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Icono panel: 🌡 88° · cpu 12% · mem 38%               │  │
│  │ Popup: tarjetas temp/CPU/RAM + barras + sparklines   │  │
│  └──────────────────────────┬────────────────────────────┘  │
└─────────────────────────────┼───────────────────────────────┘
                              │  HTTP 127.0.0.1:8136 (XMLHttpRequest)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  BACKEND  latido_backend.py  (Python 3 · stdlib · systemd)  │
│  • Temperatura: /sys/class/hwmon (k10temp/coretemp/… )     │
│  • CPU %: delta de /proc/stat                              │
│  • RAM: /proc/meminfo (usada / total)                      │
│  • Frecuencia: scaling_cur_freq                             │
│  • Historial 180 muestras para las gráficas                │
│  • Config JSON en ~/.config/latido/config.json             │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 Requisitos

| Paquete | Motivo |
|---------|--------|
| **KDE Plasma 6** (KF 6.x, Qt 6) | Entorno del plasmoid |
| **python3** (solo stdlib) | Backend — no hay nada que instalar |
| Sensores del chip (k10temp/coretemp/thinkpad) | Temperatura — presentes en cualquier portátil/sobremesa moderno |

---

## 🚀 Instalación

### 1. Backend

```bash
cp backend/latido_backend.py ~/.local/bin/
chmod +x ~/.local/bin/latido_backend.py
```

### 2. Servicio systemd (usuario)

```bash
cp service/latido.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now latido.service
```

> 💡 La unidad usa `%h` (el home del usuario), así que funciona para cualquier
> usuario sin tocar el `ExecStart`.

### 3. Plasmoid

```bash
kpackagetool6 -t Plasma/Applet -i plasmoid/rccamacho.latido/
systemctl --user restart plasma-plasmashell.service
```

### 4. Añadir al panel

1. Clic derecho en el panel → **Añadir widgets** → busca **Latido**
2. Arrástralo al panel: verás `[🌡 88° | cpu 12% | mem 38%]` en vivo
3. Clic en el icono → panel expandido con temperatura, CPU y memoria

### 5. Verificar la API

```bash
curl http://127.0.0.1:8136/api/status
```

---

## 🔄 Actualización

```bash
# 1. Copiar el nuevo backend y reiniciar el servicio
cp backend/latido_backend.py ~/.local/bin/
systemctl --user restart latido.service

# 2. Reinstalar el plasmoid (desde el repo, nunca desde ~/.local/share)
kpackagetool6 -t Plasma/Applet -r rccamacho.latido   # desinstala
kpackagetool6 -t Plasma/Applet -i plasmoid/rccamacho.latido/
rm -rf ~/.cache/plasmashell/qmlcache/                 # caché QML
systemctl --user restart plasma-plasmashell.service
```

---

## 🔌 API del backend

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/status` | `temp_c`, `cpu_pct`, `mem_pct`, `mem_used_gb`, `mem_total_gb`, `freq_mhz`, `cores`, `cpu_name`, `history`, `mem_history` |
| GET | `/api/config` | Configuración actual (`interval_s`, `unit`) |
| POST | `/api/config` | Guardar config `{interval_s: 1-10, unit: "C"\|"F"}` |

---

## 🛠️ Solución de problemas

| Problema | Causa | Solución |
|----------|-------|----------|
| El icono muestra "—" | Backend caído | `systemctl --user status latido.service` · `journalctl --user -u latido -f` |
| La temperatura sale a 0° | Sin sensor compatible | Comprueba con `sensors` que el chip se detecta (k10temp/coretemp/thinkpad) |
| El panel expandido no ajusta su alto | Tamaño de popup recordado | Eliminar `popupHeight`/`popupWidth` de la sección del applet en `~/.config/plasma-org.kde.plasma.desktop-appletsrc` |
| Los cambios del QML no se aplican | Caché QML de plasmashell | `rm -rf ~/.cache/plasmashell/qmlcache/` + reiniciar plasmashell |
| El widget no aparece en la lista | Lista cacheada | `systemctl --user restart plasma-plasmashell.service` |

---

## 📁 Estructura del repositorio

```
latido-plasmoid/
├── backend/
│   └── latido_backend.py            ← Backend Python (HTTP + muestreador)
├── service/
│   └── latido.service               ← Unidad systemd de usuario
└── plasmoid/
    └── rccamacho.latido/            ← El widget (metadata.json + QML)
        └── contents/
            ├── config/              ← ConfigPage nativa (Configurar)
            └── ui/                  ← main.qml + SparkLine.qml + config/
```

## 📄 Licencia

GPL-2.0+ — hecho para el escritorio KDE, con cariño. 💙
