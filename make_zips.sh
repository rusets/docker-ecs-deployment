#!/bin/bash
set -e

# Упаковка wake Lambda
cd wake
zip -r ../infra/wake.zip lambda_function.py > /dev/null
cd ..

# Упаковка autosleep Lambda
cd autosleep
zip -r ../infra/sleep.zip auto_sleep.py > /dev/null
cd ..

echo "✅ Zips created: infra/wake.zip and infra/sleep.zip"
