#!/bin/bash
set -e

############################################
# Package Lambda functions for deployment
# Purpose: create wake.zip and sleep.zip in infra/
############################################

cd wake
zip -r ../infra/wake.zip lambda_function.py > /dev/null
cd ..

cd autosleep
zip -r ../infra/sleep.zip auto_sleep.py > /dev/null
cd ..

echo "✅ Zips created: infra/wake.zip and infra/sleep.zip"