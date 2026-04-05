#!/usr/bin/env bash
# Git smudge filter — runs on `git checkout` / `git pull`
# Replaces REDACTED placeholders with real secrets from secrets.env
# so your local copy always has working keys.
#
# NOTE: The clean filter is pattern-based (catches any key by prefix).
# The smudge filter restores ONLY the keys listed in secrets.env.
# For keys not in secrets.env, the REDACTED placeholder stays — you fill them in manually.

SECRETS_FILE="$(git rev-parse --show-toplevel)/secrets.env"

if [[ ! -f "$SECRETS_FILE" ]]; then
  cat
  exit 0
fi

set -a
source "$SECRETS_FILE"
set +a

# Build a sed expression for each populated secret
SED_ARGS=()

[[ -n "$PERPLEXITY_API_KEY" && "$PERPLEXITY_API_KEY" != "PASTE_YOUR"* ]] && \
  SED_ARGS+=(-e "s/REDACTED_PERPLEXITY_KEY/$PERPLEXITY_API_KEY/g")

[[ -n "$XAI_API_KEY" && "$XAI_API_KEY" != "PASTE_YOUR"* ]] && \
  SED_ARGS+=(-e "s/REDACTED_XAI_KEY/$XAI_API_KEY/g")

[[ -n "$OPENROUTER_API_KEY" && "$OPENROUTER_API_KEY" != "PASTE_YOUR"* ]] && \
  SED_ARGS+=(-e "s/REDACTED_OPENROUTER_KEY/$OPENROUTER_API_KEY/g")

[[ -n "$OPENAI_API_KEY" && "$OPENAI_API_KEY" != "PASTE_YOUR"* ]] && \
  SED_ARGS+=(-e "s/REDACTED_OPENAI_KEY/$OPENAI_API_KEY/g")

[[ -n "$DISCORD_SYNTRA_TOKEN" && "$DISCORD_SYNTRA_TOKEN" != "PASTE_YOUR"* ]] && \
  SED_ARGS+=(-e "s/REDACTED_DISCORD_TOKEN/$DISCORD_SYNTRA_TOKEN/g")

[[ -n "$GATEWAY_TOKEN" && "$GATEWAY_TOKEN" != "PASTE_YOUR"* ]] && \
  SED_ARGS+=(-e "s/REDACTED_TOKEN/$GATEWAY_TOKEN/g")

[[ -n "$ELEVENLABS_API_KEY" && "$ELEVENLABS_API_KEY" != "PASTE_YOUR"* ]] && \
  SED_ARGS+=(-e "s/REDACTED_SK_KEY/$ELEVENLABS_API_KEY/g")

[[ -n "$GOOGLE_API_KEY" && "$GOOGLE_API_KEY" != "PASTE_YOUR"* ]] && \
  SED_ARGS+=(-e "s/REDACTED_GOOGLE_KEY/$GOOGLE_API_KEY/g")

if [[ ${#SED_ARGS[@]} -gt 0 ]]; then
  sed "${SED_ARGS[@]}"
else
  cat
fi
