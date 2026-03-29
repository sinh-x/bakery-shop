#!/bin/sh
set -e

baker db migrate
exec baker serve --host "$BAKER_HOST" --port "$BAKER_PORT"
