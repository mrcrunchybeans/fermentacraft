#!/bin/bash

# Build the web app
flutter build web

# 1. SSH into the server and delete all old files
ssh u956007161@145.223.125.244 -p 65002 "rm -rf ~/domains/fermentacraft.com/public_html/*"

# 2. Copy the new files
scp -P 65002 -r ./build/web/* u956007161@145.223.125.244:~/domains/fermentacraft.com/public_html/