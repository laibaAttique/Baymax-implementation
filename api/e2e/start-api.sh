#!/bin/zsh
# Starts the API on port 4010 against the LOCAL emulators only (never the real project). Usage: start-api.sh
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIREBASE_DATABASE_EMULATOR_HOST=127.0.0.1:9000
export GCLOUD_PROJECT=demo-baymax
export FIREBASE_DATABASE_URL=https://demo-baymax-default-rtdb.firebaseio.com
export PORTAL_ORIGIN=http://localhost:3010,http://localhost:3011
export PORT=4010
cd "${0:A:h}/.." && exec node src/index.js
