#!/bin/bash
# Completely wipes all NeverMiss app data to simulate a fresh install.

SERVICE="codes.maker.NeverMiss"
KEYCHAIN=~/Library/Keychains/login.keychain-db

echo "Killing NeverMiss processes..."
pkill -f "$SERVICE" 2>/dev/null
pkill -f "NeverMiss.app" 2>/dev/null
sleep 0.5

echo "Clearing Keychain tokens..."
while security delete-generic-password -s "$SERVICE" "$KEYCHAIN" 2>/dev/null; do :; done

echo "Killing preferences cache..."
killall cfprefsd 2>/dev/null
sleep 0.5

echo "Deleting UserDefaults..."
rm -f ~/Library/Preferences/$SERVICE.plist
rm -f ~/Library/Containers/$SERVICE/Data/Library/Preferences/$SERVICE.plist

echo "Deleting SwiftData database..."
rm -rf ~/Library/Containers/$SERVICE/Data/Library/Application\ Support/default.store*

echo "Deleting saved window state..."
rm -rf ~/Library/Containers/$SERVICE/Data/tmp/$SERVICE.savedState

echo "Done. App is now in fresh install state. Run from Xcode (Cmd+R)."
