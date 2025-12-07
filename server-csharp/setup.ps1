# OpenRSC Server (C#) - Setup Script for Windows
# This script installs the required dependencies and sets up the project

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "OpenRSC Server (C#) Setup Script" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

function Write-Status {
    param([string]$Message)
    Write-Host "[OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $Message
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $Message
}

# Check for .NET SDK
function Test-DotNetSdk {
    Write-Host "Checking for .NET SDK..."
    try {
        $version = dotnet --version
        $majorVersion = [int]($version.Split('.')[0])
        if ($majorVersion -ge 8) {
            Write-Status ".NET SDK $version is installed"
            return $true
        } else {
            Write-Warning ".NET SDK $version found, but version 8.0+ is required"
            return $false
        }
    } catch {
        Write-Warning ".NET SDK is not installed"
        return $false
    }
}

# Install .NET SDK using winget
function Install-DotNetSdk {
    Write-Host ""
    Write-Host "Installing .NET SDK 8.0..."

    # Check if winget is available
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Using winget to install .NET SDK..."
        winget install Microsoft.DotNet.SDK.8 --accept-source-agreements --accept-package-agreements
    } else {
        # Try using chocolatey
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "Using Chocolatey to install .NET SDK..."
            choco install dotnet-8.0-sdk -y
        } else {
            Write-Error "Neither winget nor Chocolatey is available."
            Write-Host ""
            Write-Host "Please install .NET SDK 8.0 manually from:" -ForegroundColor Yellow
            Write-Host "https://dotnet.microsoft.com/download/dotnet/8.0" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Or install winget/Chocolatey and run this script again."
            exit 1
        }
    }

    # Refresh environment
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    Write-Status ".NET SDK installation initiated. You may need to restart your terminal."
}

# Restore NuGet packages
function Restore-Packages {
    Write-Host ""
    Write-Host "Restoring NuGet packages..."
    dotnet restore
    Write-Status "NuGet packages restored"
}

# Build the project
function Build-Project {
    Write-Host ""
    Write-Host "Building the project..."
    dotnet build --configuration Release
    Write-Status "Project built successfully"
}

# Run tests
function Test-Project {
    Write-Host ""
    Write-Host "Running tests..."
    $result = dotnet test --no-build --configuration Release
    if ($LASTEXITCODE -eq 0) {
        Write-Status "All tests passed"
    } else {
        Write-Warning "Some tests failed. Check the output above for details."
    }
}

# Create default configuration
function New-Configuration {
    $configFile = "OpenRSC.Server\appsettings.json"
    if (-not (Test-Path $configFile)) {
        Write-Host ""
        Write-Host "Creating default configuration..."
        $config = @"
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
"@
        $config | Out-File -FilePath $configFile -Encoding UTF8
        Write-Status "Default configuration created"
    } else {
        Write-Status "Configuration file already exists"
    }
}

# Main setup flow
function Main {
    # Check/Install .NET SDK
    if (-not (Test-DotNetSdk)) {
        $response = Read-Host "Do you want to install .NET SDK 8.0? (y/n)"
        if ($response -eq 'y' -or $response -eq 'Y') {
            Install-DotNetSdk

            # Re-check after installation
            if (-not (Test-DotNetSdk)) {
                Write-Warning "Please restart your terminal and run this script again after .NET SDK installation completes."
                exit 0
            }
        } else {
            Write-Error ".NET SDK 8.0 is required to build the project"
            exit 1
        }
    }

    # Restore packages
    Restore-Packages

    # Build project
    Build-Project

    # Run tests
    $response = Read-Host "Do you want to run tests? (y/n)"
    if ($response -eq 'y' -or $response -eq 'Y') {
        Test-Project
    }

    # Create config
    New-Configuration

    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host "Setup Complete!" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "To start the server, run:"
    Write-Host "  dotnet run --project OpenRSC.Server" -ForegroundColor White
    Write-Host ""
    Write-Host "For production deployment:"
    Write-Host "  dotnet publish -c Release -o .\publish" -ForegroundColor White
    Write-Host "  cd publish; .\OpenRSC.Server.exe" -ForegroundColor White
    Write-Host ""
}

# Run main function
Main
