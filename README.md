# Hermes Agent Home Assistant Add-on

Home Assistant add-on repository for running [Hermes Agent](https://github.com/NousResearch/hermes-agent) as a supervised Home Assistant app on Home Assistant OS (HAOS) and other Home Assistant Supervisor installations.

The add-on wraps the official `nousresearch/hermes-agent` container and configures Hermes' built-in Home Assistant gateway. It can listen to selected Home Assistant state changes, let Hermes react to them, and forward only error notifications to Home Assistant by default.

The add-on stores Hermes state in `addon_configs/XXXXXXXX_hermes_agent/.hermes` and exposes a small Home Assistant Ingress page with dashboard and terminal access.

The same nginx-backed web UI is also exposed on host port `9119` for trusted network access, while the Hermes dashboard is exposed separately on host port `9118`.

## Install

1. In Home Assistant, open **Settings > Add-ons > Add-on Store**.
2. Open the three-dot menu, choose **Repositories**, and add:

   `https://github.com/ZokiPokiMk/HermesAgentHomeAssistant`

3. Install **Hermes Agent**.
4. Start the add-on, open the terminal or dashboard, then configure Hermes with `hermes setup` / `hermes model`.

## Notes

- By default the add-on uses Home Assistant's Supervisor API token, so you do not need to create a Long-Lived Access Token.
- Model, provider, API key, and persona settings belong to Hermes itself under `addon_configs/XXXXXXXX_hermes_agent/.hermes`; the add-on does not overwrite them on restart.
- The add-on stores Hermes data under `addon_configs/XXXXXXXX_hermes_agent/.hermes`, which is preserved by Home Assistant backups.
- The image is large because it uses the official Hermes Agent image with browser automation and messaging dependencies included.

## References

- Home Assistant add-on structure and Ingress/terminal ideas were adapted from [techartdev/OpenClawHomeAssistant](https://github.com/techartdev/OpenClawHomeAssistant).
