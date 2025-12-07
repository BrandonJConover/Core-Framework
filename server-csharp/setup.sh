#!/bin/bash

# OpenRSC Server (C#) - Setup Script
# This script installs the required dependencies and sets up the project

set -e

echo "======================================"
echo "OpenRSC Server (C#) Setup Script"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print status
print_status() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command_exists apt-get; then
            echo "debian"
        elif command_exists dnf; then
            echo "fedora"
        elif command_exists yum; then
            echo "rhel"
        elif command_exists pacman; then
            echo "arch"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

OS=$(detect_os)
echo "Detected OS: $OS"
echo ""

# Check for .NET SDK
check_dotnet() {
    echo "Checking for .NET SDK..."
    if command_exists dotnet; then
        DOTNET_VERSION=$(dotnet --version)
        MAJOR_VERSION=$(echo "$DOTNET_VERSION" | cut -d. -f1)
        if [ "$MAJOR_VERSION" -ge 8 ]; then
            print_status ".NET SDK $DOTNET_VERSION is installed"
            return 0
        else
            print_warning ".NET SDK $DOTNET_VERSION found, but version 8.0+ is required"
            return 1
        fi
    else
        print_warning ".NET SDK is not installed"
        return 1
    fi
}

# Install .NET SDK
install_dotnet() {
    echo ""
    echo "Installing .NET SDK 8.0..."

    case "$OS" in
        debian)
            # Add Microsoft package repository
            wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
            sudo dpkg -i packages-microsoft-prod.deb
            rm packages-microsoft-prod.deb
            sudo apt-get update
            sudo apt-get install -y dotnet-sdk-8.0
            ;;
        fedora)
            sudo dnf install -y dotnet-sdk-8.0
            ;;
        rhel)
            sudo yum install -y dotnet-sdk-8.0
            ;;
        arch)
            sudo pacman -S dotnet-sdk
            ;;
        macos)
            if command_exists brew; then
                brew install --cask dotnet-sdk
            else
                print_error "Homebrew is not installed. Please install .NET SDK manually from https://dotnet.microsoft.com/download"
                exit 1
            fi
            ;;
        *)
            print_error "Automatic installation not supported for this OS."
            echo "Please install .NET SDK 8.0 manually from:"
            echo "https://dotnet.microsoft.com/download/dotnet/8.0"
            exit 1
            ;;
    esac

    print_status ".NET SDK installed successfully"
}

# Restore NuGet packages
restore_packages() {
    echo ""
    echo "Restoring NuGet packages..."
    dotnet restore
    print_status "NuGet packages restored"
}

# Build the project
build_project() {
    echo ""
    echo "Building the project..."
    dotnet build --configuration Release
    print_status "Project built successfully"
}

# Run tests
run_tests() {
    echo ""
    echo "Running tests..."
    if dotnet test --no-build --configuration Release; then
        print_status "All tests passed"
    else
        print_warning "Some tests failed. Check the output above for details."
    fi
}

# Create default configuration
create_config() {
    CONFIG_FILE="OpenRSC.Server/appsettings.json"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo ""
        echo "Creating default configuration..."
        cat > "$CONFIG_FILE" << 'EOF'
{
  "Server": {
    "Port": 43594,
    "MaxPlayers": 2000,
    "TickRate": 640,
    "ServerName": "OpenRSC Server"
  },
  "Database": {
    "Provider": "Sqlite",
    "ConnectionString": "Data Source=openrsc.db"
  },
  "ActionRetry": {
    "MaxRetries": 3,
    "RetryDelayTicks": 1,
    "EnableRetry": true
  },
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "System": "Warning"
      }
    },
    "WriteTo": [
      { "Name": "Console" },
      { "Name": "File", "Args": { "path": "logs/server-.log", "rollingInterval": "Day" } }
    ]
  }
}
EOF
        print_status "Default configuration created"
    else
        print_status "Configuration file already exists"
    fi
}

# Main setup flow
main() {
    # Check/Install .NET SDK
    if ! check_dotnet; then
        read -p "Do you want to install .NET SDK 8.0? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_dotnet
        else
            print_error ".NET SDK 8.0 is required to build the project"
            exit 1
        fi
    fi

    # Restore packages
    restore_packages

    # Build project
    build_project

    # Run tests
    read -p "Do you want to run tests? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_tests
    fi

    # Create config
    create_config

    echo ""
    echo "======================================"
    echo "Setup Complete!"
    echo "======================================"
    echo ""
    echo "To start the server, run:"
    echo "  dotnet run --project OpenRSC.Server"
    echo ""
    echo "For production deployment:"
    echo "  dotnet publish -c Release -o ./publish"
    echo "  cd publish && ./OpenRSC.Server"
    echo ""
}

# Run main function
main
