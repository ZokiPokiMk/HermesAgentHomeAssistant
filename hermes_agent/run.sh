#!/command/with-contenv bash
set -euo pipefail

OPTIONS_PATH="${OPTIONS_PATH:-/data/options.json}"
ADDON_CONFIG_DIR="${ADDON_CONFIG_DIR:-/config}"
export HERMES_HOME="${HERMES_HOME:-/config/.hermes}"
PYTHON_BIN="${PYTHON_BIN:-/opt/hermes/.venv/bin/python}"
HERMES_BIN="${HERMES_BIN:-/opt/hermes/bin/hermes}"

mkdir -p "$HERMES_HOME" "$HERMES_HOME/workspace" "$ADDON_CONFIG_DIR"
mkdir -p /run/nginx 2>/dev/null || true

if [ ! -f "$OPTIONS_PATH" ]; then
  echo "Missing Home Assistant options file: $OPTIONS_PATH" >&2
  exit 1
fi

"$PYTHON_BIN" <<'PY'
import json
import os
import pathlib
import stat
import sys

import yaml

options_path = pathlib.Path(os.environ.get("OPTIONS_PATH", "/data/options.json"))
home = pathlib.Path(os.environ.get("HERMES_HOME", "/data/hermes"))
home.mkdir(parents=True, exist_ok=True)
(home / "workspace").mkdir(parents=True, exist_ok=True)

with options_path.open("r", encoding="utf-8") as handle:
    options = json.load(handle)


def text(name, default=""):
    value = options.get(name, default)
    if value is None:
        return default
    return str(value).strip()


def text_list(name):
    value = options.get(name, [])
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return [part.strip() for part in str(value).split(",") if part.strip()]


def boolean(name, default=False):
    value = options.get(name, default)
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "on"}


def integer(name, default):
    try:
        return int(options.get(name, default))
    except (TypeError, ValueError):
        return default


def validated_port(name, default):
    port = integer(name, default)
    if port < 1024 or port > 65535:
        return default
    return port


use_supervisor_api = boolean("use_supervisor_api", True)
configured_hass_url = text("hass_url", "http://homeassistant:8123")
hass_url = "http://127.0.0.1:28123" if use_supervisor_api else configured_hass_url
hass_token = text("hass_token")

if use_supervisor_api and not hass_token:
    hass_token = os.environ.get("SUPERVISOR_TOKEN", "").strip()

if not hass_token:
    print(
        "Hermes Agent needs a Home Assistant token. Enable use_supervisor_api "
        "or set hass_token to a Long-Lived Access Token.",
        file=sys.stderr,
    )
    sys.exit(1)

proxy_marker = home / ".addon_use_supervisor_proxy"
if use_supervisor_api:
    proxy_marker.write_text("1\n", encoding="utf-8")
else:
    proxy_marker.unlink(missing_ok=True)

env_values = {
    "HERMES_HOME": str(home),
    "HASS_URL": hass_url.rstrip("/"),
    "HASS_TOKEN": hass_token,
    "TERMINAL_CWD": str(home / "workspace"),
    "TERMINAL_TIMEOUT": str(integer("terminal_timeout", 180)),
    "HERMES_HA_NOTIFICATION_MODE": text("ha_notification_mode", "errors_only"),
    "WEB_TOOLS_DEBUG": "false",
    "VISION_TOOLS_DEBUG": "false",
    "MOA_TOOLS_DEBUG": "false",
    "IMAGE_TOOLS_DEBUG": "false",
}

timezone = text("timezone", "Asia/Seoul")
if timezone:
    env_values["TZ"] = timezone

http_proxy = text("http_proxy")
if http_proxy:
    env_values["HTTP_PROXY"] = http_proxy
    env_values["HTTPS_PROXY"] = http_proxy
    env_values["http_proxy"] = http_proxy
    env_values["https_proxy"] = http_proxy
    env_values["NO_PROXY"] = "localhost,127.0.0.1,::1,homeassistant,supervisor,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12,.local"
    env_values["no_proxy"] = env_values["NO_PROXY"]

if boolean("force_ipv4_dns", True):
    env_values["NODE_OPTIONS"] = "--dns-result-order=ipv4first"

env_path = home / ".env"
existing_env_lines = []
if env_path.exists():
    existing_env_lines = env_path.read_text(encoding="utf-8").splitlines()

managed_keys = set(env_values)
env_lines = []
for line in existing_env_lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        env_lines.append(line)
        continue
    key = stripped.split("=", 1)[0].strip()
    if key not in managed_keys:
        env_lines.append(line)

if env_lines and env_lines[-1].strip():
    env_lines.append("")

env_lines.extend([
    "# Managed by the Home Assistant Hermes Agent add-on.",
    "# Hermes provider/model credentials are intentionally preserved above.",
])
for key, value in env_values.items():
    safe_value = str(value).replace("\n", "")
    env_lines.append(f"{key}={safe_value}")

env_path.write_text("\n".join(env_lines) + "\n", encoding="utf-8")
env_path.chmod(stat.S_IRUSR | stat.S_IWUSR)

watch_domains = text_list("watch_domains")
legacy_noisy_domains = ["climate", "binary_sensor", "alarm_control_panel", "light"]
if watch_domains == legacy_noisy_domains:
    watch_domains = ["climate", "alarm_control_panel", "light"]

config_path = home / "config.yaml"
if config_path.exists():
    with config_path.open(encoding="utf-8") as handle:
        config = yaml.safe_load(handle) or {}
else:
    config = {}

config["terminal"] = {
    **(config.get("terminal") if isinstance(config.get("terminal"), dict) else {}),
    "backend": "local",
    "cwd": str(home / "workspace"),
    "timeout": integer("terminal_timeout", 180),
    "lifetime_seconds": 300,
}

platform_toolsets = config.get("platform_toolsets")
if isinstance(platform_toolsets, dict):
    homeassistant_toolsets = platform_toolsets.get("homeassistant")
    if isinstance(homeassistant_toolsets, list) and "homeassistant" not in homeassistant_toolsets:
        platform_toolsets["homeassistant"] = ["homeassistant", *homeassistant_toolsets]
    config["platform_toolsets"] = platform_toolsets

platforms = config.get("platforms")
if not isinstance(platforms, dict):
    platforms = {}
homeassistant_platform = platforms.get("homeassistant")
if not isinstance(homeassistant_platform, dict):
    homeassistant_platform = {}
homeassistant_extra = homeassistant_platform.get("extra")
if not isinstance(homeassistant_extra, dict):
    homeassistant_extra = {}
homeassistant_extra.update({
    "url": hass_url.rstrip("/"),
    "watch_domains": watch_domains,
    "watch_entities": text_list("watch_entities"),
    "ignore_entities": text_list("ignore_entities"),
    "watch_all": boolean("watch_all", False),
    "cooldown_seconds": integer("cooldown_seconds", 30),
})
homeassistant_platform["enabled"] = True
homeassistant_platform["extra"] = homeassistant_extra
platforms["homeassistant"] = homeassistant_platform
config["platforms"] = platforms

config_path.write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
config_path.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP)

runtime = {
    "timezone": timezone,
    "enable_terminal": boolean("enable_terminal", True),
    "terminal_port": validated_port("terminal_port", 7681),
    "enable_dashboard": boolean("enable_dashboard", True),
    "nginx_log_level": text("nginx_log_level", "minimal"),
}
(home / ".addon_runtime.json").write_text(json.dumps(runtime, indent=2) + "\n", encoding="utf-8")

print("Generated Hermes configuration for Home Assistant.")
PY

if [ "${HERMES_ADDON_CONFIG_ONLY:-false}" = "true" ]; then
  exit 0
fi

set -a
# shellcheck disable=SC1091
. "$HERMES_HOME/.env"
set +a

if [ -f "$HERMES_HOME/.addon_use_supervisor_proxy" ]; then
  "$PYTHON_BIN" <<'PY' &
import asyncio
import json
import os

import aiohttp
from aiohttp import web

SUPERVISOR_TOKEN = os.environ.get("SUPERVISOR_TOKEN", "").strip()
NOTIFICATION_MODE = os.environ.get("HERMES_HA_NOTIFICATION_MODE", "errors_only").strip().lower()
REST_BASE = "http://supervisor/core/api"
WS_URL = "ws://supervisor/core/websocket"
ERROR_NOTIFICATION_TERMS = (
    "error",
    "failed",
    "failure",
    "exception",
    "traceback",
    "critical",
    "unavailable",
    "unable",
    "cannot",
    "can't",
    "timeout",
    "timed out",
    "denied",
    "crash",
    "오류",
    "실패",
    "예외",
    "에러",
    "타임아웃",
)


def supervisor_headers(content_type="application/json"):
    headers = {"Authorization": f"Bearer {SUPERVISOR_TOKEN}"}
    if content_type:
        headers["Content-Type"] = content_type
    return headers


def should_forward_notification(path, body):
    if path.strip("/") != "services/persistent_notification/create":
        return True
    if NOTIFICATION_MODE == "all":
        return True
    if NOTIFICATION_MODE == "off":
        return False
    try:
        payload = json.loads(body.decode("utf-8") if body else "{}")
    except (json.JSONDecodeError, UnicodeDecodeError):
        return True
    text = " ".join(
        str(payload.get(key, ""))
        for key in ("title", "message", "notification_id")
    ).lower()
    return any(term in text for term in ERROR_NOTIFICATION_TERMS)


async def websocket_proxy(request):
    downstream = web.WebSocketResponse(heartbeat=30)
    await downstream.prepare(request)

    async with aiohttp.ClientSession(headers=supervisor_headers()) as session:
        async with session.ws_connect(WS_URL, heartbeat=30) as upstream:
            async def to_upstream():
                async for message in downstream:
                    if message.type == aiohttp.WSMsgType.TEXT:
                        await upstream.send_str(message.data)
                    elif message.type == aiohttp.WSMsgType.BINARY:
                        await upstream.send_bytes(message.data)
                    elif message.type == aiohttp.WSMsgType.ERROR:
                        break
                await upstream.close()

            async def to_downstream():
                async for message in upstream:
                    if message.type == aiohttp.WSMsgType.TEXT:
                        await downstream.send_str(message.data)
                    elif message.type == aiohttp.WSMsgType.BINARY:
                        await downstream.send_bytes(message.data)
                    elif message.type == aiohttp.WSMsgType.ERROR:
                        break
                await downstream.close()

            await asyncio.gather(to_upstream(), to_downstream(), return_exceptions=True)

    return downstream


async def rest_proxy(request):
    path = request.match_info.get("path", "")
    target_url = f"{REST_BASE}/{path}" if path else REST_BASE
    body = await request.read()
    content_type = request.headers.get("Content-Type", "application/json")

    if not should_forward_notification(path, body):
        print("Suppressed non-error Home Assistant persistent notification from Hermes.", flush=True)
        return web.json_response([])

    async with aiohttp.ClientSession() as session:
        async with session.request(
            request.method,
            target_url,
            params=request.query,
            headers=supervisor_headers(content_type),
            data=body if body else None,
        ) as response:
            response_body = await response.read()
            headers = {}
            if response.content_type:
                headers["Content-Type"] = response.headers.get("Content-Type", response.content_type)
            return web.Response(body=response_body, status=response.status, headers=headers)


app = web.Application()
app.router.add_get("/api/websocket", websocket_proxy)
app.router.add_route("*", "/api/{path:.*}", rest_proxy)

web.run_app(app, host="127.0.0.1", port=28123, print=None)
PY
  sleep 1
fi

read_runtime() {
  jq -r "$1" "$HERMES_HOME/.addon_runtime.json"
}

ENABLE_TERMINAL="$(read_runtime '.enable_terminal')"
TERMINAL_PORT="$(read_runtime '.terminal_port')"
ENABLE_DASHBOARD="$(read_runtime '.enable_dashboard')"
DASHBOARD_PORT="9118"
DASHBOARD_PROXY_PORT="49118"
NGINX_LOG_LEVEL="$(read_runtime '.nginx_log_level')"

GW_PID=""
DASHBOARD_PID=""
TTYD_PID=""
NGINX_PID=""
SHUTTING_DOWN=false
HERMES_TERMINAL_HOME="$HERMES_HOME/home"
HERMES_TERMINAL_BASHRC="$HERMES_TERMINAL_HOME/.bashrc"
HERMES_TERMINAL_LAUNCHER="$HERMES_HOME/terminal-shell"

mkdir -p "$HERMES_TERMINAL_HOME" "$HERMES_HOME/workspace"

cat > "$HERMES_TERMINAL_BASHRC" <<EOF
export HERMES_HOME="$HERMES_HOME"
export HOME="$HERMES_TERMINAL_HOME"
export USER=hermes
export LOGNAME=hermes
export PATH="/opt/hermes/.venv/bin:$HERMES_HOME/.local/bin:\$PATH"
cd "$HERMES_HOME/workspace" 2>/dev/null || true
export PS1='hermes@\h:\w\$ '
EOF

cat > "$HERMES_TERMINAL_LAUNCHER" <<EOF
#!/usr/bin/env bash
export HERMES_HOME="$HERMES_HOME"
export HOME="$HERMES_TERMINAL_HOME"
export USER=hermes
export LOGNAME=hermes
export PATH="/opt/hermes/.venv/bin:$HERMES_HOME/.local/bin:\$PATH"
exec bash --rcfile "$HERMES_TERMINAL_BASHRC" -i
EOF

chmod +x "$HERMES_TERMINAL_LAUNCHER"

if id hermes >/dev/null 2>&1; then
  chown -R hermes:hermes "$HERMES_HOME" 2>/dev/null || true
fi

start_terminal() {
  echo "Starting web terminal on 127.0.0.1:${TERMINAL_PORT} ..."
  ttyd -W -i 127.0.0.1 -p "$TERMINAL_PORT" -b /terminal "$HERMES_TERMINAL_LAUNCHER" &
  TTYD_PID=$!
}

shutdown() {
  SHUTTING_DOWN=true
  echo "Shutdown requested; stopping Hermes Agent services..."
  for pid in "$NGINX_PID" "$TTYD_PID" "$DASHBOARD_PID" "$GW_PID"; do
    if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
      kill -TERM "$pid" >/dev/null 2>&1 || true
    fi
  done
  wait || true
}

trap shutdown TERM INT

if [ "$ENABLE_DASHBOARD" = "true" ]; then
  echo "Starting Hermes dashboard on 0.0.0.0:${DASHBOARD_PORT} ..."
  "$HERMES_BIN" dashboard --host 0.0.0.0 --port "$DASHBOARD_PORT" --insecure --no-open --tui &
  DASHBOARD_PID=$!
else
  echo "Hermes dashboard disabled."
fi

if [ "$ENABLE_TERMINAL" = "true" ]; then
  start_terminal
else
  echo "Web terminal disabled."
fi

DISK_TOTAL="$(df -h "$HERMES_HOME" | awk 'NR==2{print $2}')"
DISK_USED="$(df -h "$HERMES_HOME" | awk 'NR==2{print $3}')"
DISK_AVAIL="$(df -h "$HERMES_HOME" | awk 'NR==2{print $4}')"
DISK_PCT="$(df -h "$HERMES_HOME" | awk 'NR==2{print $5}')"

TERMINAL_PORT="$TERMINAL_PORT" \
DASHBOARD_PORT="$DASHBOARD_PORT" \
DASHBOARD_PROXY_PORT="$DASHBOARD_PROXY_PORT" \
ENABLE_TERMINAL="$ENABLE_TERMINAL" \
ENABLE_DASHBOARD="$ENABLE_DASHBOARD" \
DISK_TOTAL="$DISK_TOTAL" \
DISK_USED="$DISK_USED" \
DISK_AVAIL="$DISK_AVAIL" \
DISK_PCT="$DISK_PCT" \
NGINX_LOG_LEVEL="$NGINX_LOG_LEVEL" \
python3 /render_nginx.py

echo "Starting Home Assistant Ingress proxy on :48099 ..."
nginx -g 'daemon off;' &
NGINX_PID=$!

echo "Starting Hermes Home Assistant gateway..."
"$HERMES_BIN" gateway run --replace &
GW_PID=$!

while [ "$SHUTTING_DOWN" = "false" ]; do
  if ! kill -0 "$GW_PID" >/dev/null 2>&1; then
    echo "WARN: Hermes gateway exited. Restarting in 3s..."
    sleep 3
    "$HERMES_BIN" gateway run --replace &
    GW_PID=$!
  fi
  if [ -n "$DASHBOARD_PID" ] && ! kill -0 "$DASHBOARD_PID" >/dev/null 2>&1; then
    echo "WARN: Hermes dashboard exited. Restarting in 3s..."
    sleep 3
    "$HERMES_BIN" dashboard --host 0.0.0.0 --port "$DASHBOARD_PORT" --insecure --no-open --tui &
    DASHBOARD_PID=$!
  fi
  if [ -n "$TTYD_PID" ] && ! kill -0 "$TTYD_PID" >/dev/null 2>&1; then
    echo "WARN: web terminal exited. Restarting in 3s..."
    sleep 3
    start_terminal
  fi
  if ! kill -0 "$NGINX_PID" >/dev/null 2>&1; then
    echo "ERROR: nginx exited; stopping add-on."
    exit 1
  fi
  sleep 5
done
