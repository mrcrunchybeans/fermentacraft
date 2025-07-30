#!/bin/bash

# Build the web app
flutter build web

# Deploy via scp
scp -P 65002 -r .\build\web\* u956007161@145.223.125.244:~/domains/fermentacraft.com/public_html/
