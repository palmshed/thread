#!/bin/bash

# Docker Hub Setup Script for CircleCI
# This script helps configure Docker Hub credentials for the CI pipeline

set -e

echo "🐳 Docker Hub Setup for CircleCI"
echo "================================"

# Check if we're in the right directory
if [ ! -f ".circleci/config.yml" ]; then
    echo "❌ Error: Run this script from the project root directory"
    exit 1
fi

# Get Docker Hub username
read -p "Enter your Docker Hub username: " DOCKERHUB_USERNAME

if [ -z "$DOCKERHUB_USERNAME" ]; then
    echo "❌ Error: Docker Hub username is required"
    exit 1
fi

echo ""
echo "📝 Next steps to complete setup:"
echo ""
echo "1. Generate Docker Hub Access Token:"
echo "   - Go to https://hub.docker.com/settings/security"
echo "   - Click 'New Access Token'"
echo "   - Name: 'CircleCI-${CIRCLE_PROJECT_REPONAME:-thread}'"
echo "   - Permissions: Read, Write, Delete"
echo "   - Copy the generated token"
echo ""
echo "2. Add Environment Variables in CircleCI:"
echo "   - Go to your CircleCI project settings"
echo "   - Navigate to Environment Variables"
echo "   - Add: DOCKERHUB_USERNAME = $DOCKERHUB_USERNAME"
echo "   - Add: DOCKERHUB_PASSWORD = <your_access_token>"
echo ""
echo "3. Confirm the CircleCI project has access to this repository."
echo "   The config reads DOCKERHUB_USERNAME directly; no file rewrite is required."

echo ""
echo "🚀 Setup complete! Your Docker images will be pushed to:"
echo "   - $DOCKERHUB_USERNAME/thread-gpu:latest"
echo "   - $DOCKERHUB_USERNAME/thread-cpu:latest"
echo ""
echo "💡 Test the setup by pushing a commit to trigger the CI pipeline."
