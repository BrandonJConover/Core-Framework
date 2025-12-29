# OpenRSC Server (C#) - Requirements Documentation

## Overview

This document outlines the requirements and dependencies needed to build and run the OpenRSC C# game server.

## System Requirements

### Runtime Requirements
- **.NET 8.0 SDK** (version 8.0.100 or later)
- **Operating System**: Windows 10/11, Linux (Ubuntu 20.04+, Debian 11+), or macOS 12+
- **Memory**: Minimum 2GB RAM (4GB recommended for production)
- **Disk Space**: 100MB for application, additional space for database

### Development Requirements
- .NET 8.0 SDK
- IDE: Visual Studio 2022, JetBrains Rider, or VS Code with C# Dev Kit
- Git for version control

## NuGet Dependencies

### Core Server (OpenRSC.Server)

| Package | Version | Purpose |
|---------|---------|---------|
| Microsoft.Extensions.DependencyInjection | 8.0.0 | Dependency injection container |
| Microsoft.Extensions.DependencyInjection.Abstractions | 8.0.0 | DI abstractions |
| Microsoft.Extensions.Hosting | 8.0.0 | Generic host for services |
| Microsoft.Extensions.Configuration | 8.0.0 | Configuration system |
| Microsoft.Extensions.Configuration.Json | 8.0.0 | JSON configuration provider |
| Microsoft.Extensions.Options | 8.0.0 | Options pattern support |
| Microsoft.Extensions.Logging | 8.0.0 | Logging abstractions |
| Microsoft.Extensions.Logging.Abstractions | 8.0.0 | Logging interface types |
| Serilog | 3.1.1 | Structured logging |
| Serilog.Extensions.Hosting | 8.0.0 | Serilog integration with hosting |
| Serilog.Sinks.Console | 5.0.1 | Console log output |
| Serilog.Sinks.File | 5.0.0 | File log output |
| Dapper | 2.1.28 | Micro-ORM for database access |
| MySqlConnector | 2.3.3 | MySQL database driver |
| Microsoft.Data.Sqlite | 8.0.0 | SQLite database driver |
| System.IO.Pipelines | 8.0.0 | High-performance I/O |

### Test Project (OpenRSC.Server.Tests)

| Package | Version | Purpose |
|---------|---------|---------|
| Microsoft.NET.Test.Sdk | 17.9.0 | Test SDK |
| xunit | 2.7.0 | Unit testing framework |
| xunit.runner.visualstudio | 2.5.7 | Test runner integration |
| coverlet.collector | 6.0.1 | Code coverage collection |
| FluentAssertions | 6.12.0 | Fluent assertion library |
| Moq | 4.20.70 | Mocking framework |

## Database Requirements

The server supports two database backends:

### MySQL (Production Recommended)
- MySQL 8.0 or later
- MariaDB 10.5 or later

### SQLite (Development/Testing)
- SQLite 3.x (bundled with Microsoft.Data.Sqlite)

## Building the Project

```bash
# Clone the repository
git clone <repository-url>
cd Core-Framework/server-csharp

# Restore dependencies
dotnet restore

# Build the solution
dotnet build

# Run tests
dotnet test

# Run the server
dotnet run --project OpenRSC.Server
```

## Configuration

Create an `appsettings.json` file in the OpenRSC.Server directory:

```json
{
  "Server": {
    "Port": 43594,
    "MaxPlayers": 2000,
    "TickRate": 640
  },
  "Database": {
    "Provider": "MySql",
    "ConnectionString": "Server=localhost;Database=openrsc;User=root;Password=password;"
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
        "Microsoft": "Warning"
      }
    }
  }
}
```

## Feature List

### Implemented Systems
- **Actions**: Walk-to actions with retry mechanism
- **Combat**: Melee, ranged, magic combat with styles
- **Skills**: Mining, Smithing, Fishing, Cooking, Woodcutting, Firemaking, Crafting, Herblore, Runecraft, Agility, Thieving, Fletching, Ranged
- **Prayer**: Prayer activation, drain, and effects
- **Fatigue**: RSC-specific fatigue system
- **Inventory**: 30-slot inventory with equipment slots
- **Bank**: Full banking system with presets
- **Trading**: Player-to-player trading
- **Dueling**: PvP dueling with rules and stakes
- **Clans**: Clan management system
- **Parties**: Group party system
- **Achievements**: Achievement tracking and rewards
- **Quests**: Quest progress tracking
- **Wilderness**: PvP zone management and skulling
- **Drop Tables**: Weighted loot system
- **Minigames**: Fishing Trawler minigame
- **Plugins**: Dynamic plugin loading system

### Network Layer
- TCP socket server with async I/O
- Packet-based protocol matching RSC client
- High-performance buffer pooling

### Database Layer
- Repository pattern for data access
- Support for MySQL and SQLite
- Async database operations

## Architecture

The server follows modern .NET patterns:
- **Dependency Injection**: All services registered via DI container
- **Options Pattern**: Type-safe configuration
- **Repository Pattern**: Data access abstraction
- **Event System**: Decoupled event handling
- **Action System**: Queueable player actions with retry support

## License

See the main repository LICENSE file for licensing information.
