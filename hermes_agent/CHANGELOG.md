# Changelog

## 0.1.2

- Exposes the Hermes dashboard on host port `9118`, separate from the nginx-backed web UI on host port `9119`.
- Initial Home Assistant add-on wrapper for the official Hermes Agent container.
- Generates Hermes `.env`, `config.yaml`, and `SOUL.md` from add-on options.
- Enables Home Assistant event monitoring through Supervisor API by default.
