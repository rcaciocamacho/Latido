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
  y **color de banda térmica** del perfil compartido (`hwprofile`): reposo, normal,
  carga alta, aviso y crítico — no umbrales clavados en el QML
- 🌀 **Ventilador** con rpm, tres estados (`en marcha` / `parado` / `¡sin respuesta!`)
  y aviso de anomalía (temperatura alta sin rpm) con su motivo en el tooltip
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
│  • Perfil térmico: hwprofile (k10temp/Tctl + thinkpad/fan1)│
│  • CPU %: delta de /proc/stat                              │
│  • RAM: /proc/meminfo (usada / total)                      │
│  • Frecuencia: scaling_cur_freq                             │
│  • Muestreo 1 Hz · historial 360 s (360 muestras)          │
│  • Config JSON en ~/.config/latido/config.json             │
└─────────────────────────────────────────────────────────────┘
```

El **estado térmico no se calcula en el QML**: lo publica el backend en el bloque
`termico` (suavizado de 6 muestras, histéresis 3,5 °C, persistencia de bajada y
anomalía de ventilador) y el widget solo lo pinta. Es el mismo bloque que publica
Termika, así que los dos widgets enseñan la misma banda con el mismo equipo.

---

## 📋 Requisitos

| Paquete | Motivo |
|---------|--------|
| **KDE Plasma 6** (KF 6.x, Qt 6) | Entorno del plasmoid |
| **python3** (solo stdlib) | Backend — no hay nada que instalar |
| **hwprofile** (`~/.local/lib/hwprofile`) | Perfil térmico compartido con Termika. **Opcional**: sin él el backend arranca y el widget funciona con los campos de siempre (`termico.disponible: false`) |
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
| GET | `/api/status` | `temp_c`, `fan_rpm` (null = sin lectura), `cpu_pct`, `mem_pct`, `mem_used_gb`, `mem_total_gb`, `freq_mhz`, `cores`, `cpu_name`, `temp_warn_c`, `temp_crit_c`, `history`, `mem_history`, `temp_history` y el bloque `termico` |
| GET | `/api/config` | Configuración actual (`interval_s`, `unit`, umbrales, `perfil_umbrales_version`) |
| POST | `/api/config` | Guardar config `{interval_s: 1-10, unit: "C"\|"F", temp_warn_c, temp_crit_c}` |

Bloque `termico` (contrato `OVDD-perfil-termico.md` §3.4): `disponible`, `perfil`
(`id`, `origen`, `umbrales`, `histeresis_c`, `ventana_muestras`, `persistencia_s`,
`polling_interval_ms`), `sensor` (`temp`, `fan`, `ignorados`, `temp_disponible`,
`fan_disponible`), `temp_suave_c`, `estado`, `estado_anterior`, `desde_s`,
`restante_s` y `ventilador` (`rpm`, `aviso`, `aviso_motivo`, `aviso_desde_s`).
Si `hwprofile` no está instalado, el servicio arranca igual y publica
`termico: {disponible: false, motivo: …}` (el widget degrada sin romperse).

`temp_warn_c`/`temp_crit_c` siguen siendo **override** de `warning_min`/
`critical_min` del perfil; el resto del perfil es de solo lectura. `interval_s`
es la cadencia del widget: el muestreo interno es siempre 1 s.

---

## 🛠️ Solución de problemas

| Problema | Causa | Solución |
|----------|-------|----------|
| El icono muestra "—" | Backend caído | `systemctl --user status latido.service` · `journalctl --user -u latido -f` |
| La temperatura sale en gris y sin chip de estado | `hwprofile` no instalado (`termico.disponible: false`) | Instala el perfil compartido: `cd hwprofile && ./install.sh` y reinicia `latido.service` |
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
