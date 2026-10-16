#!/bin/zsh
# Starts a web app (portal on 3010 or admin panel on 3011) against the LOCAL emulators only. Usage: start-web.sh ~/Downloads/baymax-portal 3010   or   start-web.sh ~/Downloads/baymax-admin 3011
export NEXT_PUBLIC_API_URL=http://localhost:4010
export NEXT_PUBLIC_USE_EMULATOR=true
export NEXT_PUBLIC_FIREBASE_API_KEY=fake-key
export NEXT_PUBLIC_FIREBASE_APP_ID=fake-app
export NEXT_PUBLIC_FIREBASE_PROJECT_ID=demo-baymax
export NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=demo-baymax.firebaseapp.com
export NEXT_PUBLIC_ADMIN_URL=http://localhost:3011
cd "$1" && rm -rf .next && exec ./node_modules/.bin/next dev -p "$2"
