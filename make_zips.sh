#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

############################################################
# This script packages the Python code for two AWS Lambdas:
# 1. wake.zip     → Lambda that wakes the ECS service
# 2. sleep.zip    → Lambda that auto-scales ECS service down
#
# Both zip archives are placed in the "infra" folder,
# so Terraform can pick them up during deployment.
############################################################

# --- Package "wake" Lambda function ---
cd wake
# Create zip archive with lambda_function.py
# -r = recursive (handles dependencies if later added)
# Output is redirected to /dev/null to suppress verbose logs
zip -r ../infra/wake.zip lambda_function.py > /dev/null
cd ..

# --- Package "autosleep" Lambda function ---
cd autosleep
# Create zip archive with auto_sleep.py
zip -r ../infra/sleep.zip auto_sleep.py > /dev/null
cd ..

# Final confirmation message
echo "✅ Zips created: infra/wake.zip and infra/sleep.zip"