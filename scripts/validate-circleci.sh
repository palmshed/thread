#!/bin/bash

if command -v circleci &>/dev/null; then
  if ! circleci config validate .circleci/config.yml; then
    echo "::error::CircleCI config validation failed"
    exit 1
  fi
  exit 0
fi

if [[ -n "${CI:-}" ]]; then
  echo "::warning::CircleCI CLI not found in CI; install it before running this validation job."
  exit 1
else
  echo "::warning::CircleCI CLI not found. Install with: brew install circleci"
  echo "Skipping CircleCI config validation"
  exit 0
fi
