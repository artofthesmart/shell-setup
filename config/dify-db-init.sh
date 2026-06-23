#!/bin/bash
set -e

# Create the dify_plugin database needed by dify-plugin-daemon.
# This script runs only on first postgres initialization (empty data dir).
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE dify_plugin;
EOSQL
