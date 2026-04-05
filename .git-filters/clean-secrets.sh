#!/usr/bin/env bash
# Git clean filter — runs on `git add` / `git commit`
# Pattern-based: catches ALL API keys by their known prefixes/formats.
# No need to enumerate every key — if it looks like a secret, it gets redacted.

sed \
  -e 's/pplx-[A-Za-z0-9_-]\{20,\}/REDACTED_PERPLEXITY_KEY/g' \
  -e 's/xai-[A-Za-z0-9_-]\{20,\}/REDACTED_XAI_KEY/g' \
  -e 's/sk-or-v1-[A-Za-z0-9_-]\{20,\}/REDACTED_OPENROUTER_KEY/g' \
  -e 's/sk-proj-[A-Za-z0-9_-]\{20,\}/REDACTED_OPENAI_KEY/g' \
  -e 's/sk-[A-Za-z0-9_-]\{20,\}/REDACTED_SK_KEY/g' \
  -e 's/sk_[A-Za-z0-9]\{20,\}/REDACTED_SK_KEY/g' \
  -e 's/AIzaSy[A-Za-z0-9_-]\{20,\}/REDACTED_GOOGLE_KEY/g' \
  -e 's/MTQ[A-Za-z0-9._-]\{30,\}/REDACTED_DISCORD_TOKEN/g' \
  -e 's/"token": *"[A-Za-z0-9_-]\{40,\}"/"token": "REDACTED_TOKEN"/g'
