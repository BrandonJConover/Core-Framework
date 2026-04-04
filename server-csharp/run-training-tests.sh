#!/bin/bash
# Run ML Training and Bot Tests
# This script runs the game completion training to verify bots can beat the game

set -e

echo "====================================="
echo "OpenRSC Bot Training & Testing Suite"
echo "====================================="
echo

# Build first
echo "[1/4] Building solution..."
dotnet build --configuration Release --verbosity minimal

# Run unit tests
echo
echo "[2/4] Running unit tests..."
dotnet test --filter "Category!=E2E" --verbosity minimal --no-build

# Run simulation tests
echo
echo "[3/4] Running simulation tests..."
dotnet test --filter "FullyQualifiedName~SimulationTests" --verbosity normal --no-build

# Run game completion tests
echo
echo "[4/4] Running game completion training tests..."
dotnet test --filter "FullyQualifiedName~GameCompletionTests" --verbosity normal --no-build

echo
echo "====================================="
echo "All tests completed successfully!"
echo "====================================="
