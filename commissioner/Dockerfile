# Planet Wars commissioner: the game-agnostic default commissioner with the
# Planet Wars ruleset config baked in and selected.
FROM ghcr.io/metta-ai/commissioners-default@sha256:75d77cf97479317c88988104b553ce746718138608ea00fcc14398d95e8d9b8f

COPY commissioner/planet_wars.yaml /app/commissioners/ruleset_strategy_commissioner/configs/planet_wars.yaml
ENV RULESET_STRATEGY_CONFIG_NAME=planet_wars
