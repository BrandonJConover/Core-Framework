# OpenRSC Replit Notes

This repository can be launched in Replit with the included workflow files.
The Replit path is intended as a lightweight development/demo environment for
the legacy Java OpenRSC server.

## Runtime

- Java: GraalVM CE from Replit's Java module
- Build tool: Apache Ant
- Python: status dashboard on port `5000`
- Database: SQLite preservation database at `server/inc/sqlite/preservation.db`

## Workflow

The "Start application" workflow runs:

```bash
bash start.sh
```

That script:

1. Starts `status_server.py` on port `5000`.
2. Creates `server/local.conf` from `server/default.conf` when missing.
3. Builds `server/core.jar` and `server/plugins.jar` when missing.
4. Starts the OpenRSC server with `ant runserver -DconfFile=local`.

## Ports

- `43594`: RSC game TCP protocol
- `43494`: WebSocket bridge for web clients
- `5000`: Replit status dashboard

## Notes

- This setup intentionally keeps SQLite as the default. The experimental
  PostgreSQL work on the Replit branch should be reviewed and ported
  separately before changing shared defaults.
- `server-java-modern/` requires a newer Java runtime than the legacy server.
