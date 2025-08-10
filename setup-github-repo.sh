#!/bin/bash

# Setup GitHub repository for My Custom Polygon-MCP

echo "Setting up GitHub repository for My Custom Polygon-MCP..."

# 1. Initialize git repository
echo "Initializing git repository..."
git init

# 2. Add all files
echo "Adding files to git..."
git add .

# 3. Create initial commit
echo "Creating initial commit..."
git commit -m "Initial commit: Polygon.io MCP server

- MCP server with FastMCP for Polygon.io financial data APIs
- Support for 53+ API endpoints
- STDIO, SSE, and HTTP transport support
- Complete project structure with examples"

# 4. Create GitHub repository
echo "Creating GitHub repository..."
gh repo create "My-Custom-Polygon-MCP" --public --description "Polygon.io MCP server for financial market data" --source=.

# 5. Push to GitHub
echo "Pushing to GitHub..."
git push -u origin main

echo "Done! Your repository is now available on GitHub."