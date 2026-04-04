using System.Data;
using Dapper;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Npgsql;
using OpenRSC.Server.Configuration;

namespace OpenRSC.Server.Database;

/// <summary>
/// PostgreSQL implementation of player repository.
/// Optimized for game server workloads with connection pooling and batch operations.
/// </summary>
public sealed class PostgresPlayerRepository : IPlayerRepository, IAsyncDisposable
{
    private readonly ILogger<PostgresPlayerRepository> _logger;
    private readonly DatabaseSettings _settings;
    private readonly NpgsqlDataSource _dataSource;
    private readonly string _tablePrefix;

    public PostgresPlayerRepository(
        ILogger<PostgresPlayerRepository> logger,
        IOptions<DatabaseSettings> settings)
    {
        _logger = logger;
        _settings = settings.Value;
        _tablePrefix = _settings.TablePrefix;

        // Create connection pool
        var builder = new NpgsqlDataSourceBuilder(_settings.ConnectionString)
        {
            Name = "OpenRSC",
        };

        // Configure connection pool
        builder.ConnectionStringBuilder.MinPoolSize = _settings.MinPoolSize;
        builder.ConnectionStringBuilder.MaxPoolSize = _settings.MaxPoolSize;
        builder.ConnectionStringBuilder.CommandTimeout = _settings.CommandTimeoutSeconds;

        // Enable logging if configured
        if (_settings.EnableQueryLogging)
        {
            builder.EnableParameterLogging();
        }

        _dataSource = builder.Build();

        _logger.LogInformation("PostgreSQL repository initialized with pool size {Min}-{Max}",
            _settings.MinPoolSize, _settings.MaxPoolSize);
    }

    #region Player CRUD

    /// <inheritdoc />
    public async Task<PlayerData?> LoadPlayerAsync(string username)
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        var player = await conn.QuerySingleOrDefaultAsync<PlayerData>(
            $"""
            SELECT
                id AS "Id",
                username AS "Username",
                password_hash AS "PasswordHash",
                email AS "Email",
                x AS "X",
                y AS "Y",
                combat_level AS "CombatLevel",
                total_level AS "TotalLevel",
                quest_points AS "QuestPoints",
                bank_pins AS "BankPins",
                created_at AS "CreatedAt",
                last_login AS "LastLogin",
                last_ip AS "LastIp",
                is_banned AS "IsBanned",
                is_muted AS "IsMuted",
                group_id AS "GroupId"
            FROM {_tablePrefix}players
            WHERE LOWER(username) = LOWER(@Username)
            """,
            new { Username = username });

        if (player is not null)
        {
            // Load skills
            player.Skills = await LoadPlayerSkillsAsync(conn, player.Id);

            // Load inventory
            player.Inventory = await LoadPlayerInventoryAsync(conn, player.Id);

            // Load bank
            player.Bank = await LoadPlayerBankAsync(conn, player.Id);

            // Load equipment
            player.Equipment = await LoadPlayerEquipmentAsync(conn, player.Id);

            // Load quests
            player.Quests = await LoadPlayerQuestsAsync(conn, player.Id);
        }

        return player;
    }

    /// <inheritdoc />
    public async Task SavePlayerAsync(PlayerData player)
    {
        await using var conn = await _dataSource.OpenConnectionAsync();
        await using var transaction = await conn.BeginTransactionAsync();

        try
        {
            // Upsert player
            var id = await conn.ExecuteScalarAsync<long>(
                $"""
                INSERT INTO {_tablePrefix}players
                    (username, password_hash, email, x, y, combat_level, total_level,
                     quest_points, last_login, last_ip, group_id)
                VALUES
                    (@Username, @PasswordHash, @Email, @X, @Y, @CombatLevel, @TotalLevel,
                     @QuestPoints, @LastLogin, @LastIp, @GroupId)
                ON CONFLICT (LOWER(username)) DO UPDATE SET
                    password_hash = COALESCE(EXCLUDED.password_hash, {_tablePrefix}players.password_hash),
                    email = COALESCE(EXCLUDED.email, {_tablePrefix}players.email),
                    x = EXCLUDED.x,
                    y = EXCLUDED.y,
                    combat_level = EXCLUDED.combat_level,
                    total_level = EXCLUDED.total_level,
                    quest_points = EXCLUDED.quest_points,
                    last_login = EXCLUDED.last_login,
                    last_ip = EXCLUDED.last_ip,
                    group_id = EXCLUDED.group_id
                RETURNING id
                """,
                player,
                transaction);

            player.Id = id;

            // Save skills
            if (player.Skills?.Count > 0)
            {
                await SavePlayerSkillsAsync(conn, transaction, player.Id, player.Skills);
            }

            // Save inventory
            if (player.Inventory is not null)
            {
                await SavePlayerInventoryAsync(conn, transaction, player.Id, player.Inventory);
            }

            // Save bank
            if (player.Bank is not null)
            {
                await SavePlayerBankAsync(conn, transaction, player.Id, player.Bank);
            }

            // Save equipment
            if (player.Equipment is not null)
            {
                await SavePlayerEquipmentAsync(conn, transaction, player.Id, player.Equipment);
            }

            // Save quests
            if (player.Quests?.Count > 0)
            {
                await SavePlayerQuestsAsync(conn, transaction, player.Id, player.Quests);
            }

            await transaction.CommitAsync();

            _logger.LogDebug("Saved player {Username} (ID: {Id})", player.Username, player.Id);
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }

    /// <inheritdoc />
    public async Task<bool> DeletePlayerAsync(string username)
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        var deleted = await conn.ExecuteAsync(
            $"DELETE FROM {_tablePrefix}players WHERE LOWER(username) = LOWER(@Username)",
            new { Username = username });

        return deleted > 0;
    }

    /// <inheritdoc />
    public async Task<bool> PlayerExistsAsync(string username)
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        return await conn.ExecuteScalarAsync<bool>(
            $"SELECT EXISTS(SELECT 1 FROM {_tablePrefix}players WHERE LOWER(username) = LOWER(@Username))",
            new { Username = username });
    }

    #endregion

    #region Skills

    private async Task<Dictionary<int, SkillData>> LoadPlayerSkillsAsync(NpgsqlConnection conn, long playerId)
    {
        var skills = await conn.QueryAsync<SkillData>(
            $"""
            SELECT skill_id AS "SkillId", current_level AS "CurrentLevel",
                   max_level AS "MaxLevel", experience AS "Experience"
            FROM {_tablePrefix}player_skills
            WHERE player_id = @PlayerId
            """,
            new { PlayerId = playerId });

        return skills.ToDictionary(s => s.SkillId);
    }

    private async Task SavePlayerSkillsAsync(NpgsqlConnection conn, NpgsqlTransaction transaction,
        long playerId, Dictionary<int, SkillData> skills)
    {
        // Bulk upsert using COPY for performance
        await using var writer = await conn.BeginBinaryImportAsync(
            $"COPY {_tablePrefix}player_skills_temp (player_id, skill_id, current_level, max_level, experience) FROM STDIN (FORMAT BINARY)");

        foreach (var (skillId, skill) in skills)
        {
            await writer.StartRowAsync();
            await writer.WriteAsync(playerId, NpgsqlTypes.NpgsqlDbType.Bigint);
            await writer.WriteAsync(skillId, NpgsqlTypes.NpgsqlDbType.Integer);
            await writer.WriteAsync(skill.CurrentLevel, NpgsqlTypes.NpgsqlDbType.Integer);
            await writer.WriteAsync(skill.MaxLevel, NpgsqlTypes.NpgsqlDbType.Integer);
            await writer.WriteAsync(skill.Experience, NpgsqlTypes.NpgsqlDbType.Bigint);
        }

        await writer.CompleteAsync();

        // Merge temp table into main table
        await conn.ExecuteAsync(
            $"""
            INSERT INTO {_tablePrefix}player_skills (player_id, skill_id, current_level, max_level, experience)
            SELECT player_id, skill_id, current_level, max_level, experience
            FROM {_tablePrefix}player_skills_temp
            ON CONFLICT (player_id, skill_id) DO UPDATE SET
                current_level = EXCLUDED.current_level,
                max_level = EXCLUDED.max_level,
                experience = EXCLUDED.experience;
            TRUNCATE {_tablePrefix}player_skills_temp;
            """,
            transaction: transaction);
    }

    #endregion

    #region Inventory

    private async Task<List<ItemData>> LoadPlayerInventoryAsync(NpgsqlConnection conn, long playerId)
    {
        var items = await conn.QueryAsync<ItemData>(
            $"""
            SELECT slot AS "Slot", item_id AS "ItemId", amount AS "Amount",
                   durability AS "Durability"
            FROM {_tablePrefix}player_inventory
            WHERE player_id = @PlayerId
            ORDER BY slot
            """,
            new { PlayerId = playerId });

        return items.ToList();
    }

    private async Task SavePlayerInventoryAsync(NpgsqlConnection conn, NpgsqlTransaction transaction,
        long playerId, List<ItemData> inventory)
    {
        // Clear existing inventory
        await conn.ExecuteAsync(
            $"DELETE FROM {_tablePrefix}player_inventory WHERE player_id = @PlayerId",
            new { PlayerId = playerId },
            transaction);

        if (inventory.Count == 0) return;

        // Bulk insert
        await conn.ExecuteAsync(
            $"""
            INSERT INTO {_tablePrefix}player_inventory (player_id, slot, item_id, amount, durability)
            VALUES (@PlayerId, @Slot, @ItemId, @Amount, @Durability)
            """,
            inventory.Select(item => new
            {
                PlayerId = playerId,
                item.Slot,
                item.ItemId,
                item.Amount,
                item.Durability
            }),
            transaction);
    }

    #endregion

    #region Bank

    private async Task<List<ItemData>> LoadPlayerBankAsync(NpgsqlConnection conn, long playerId)
    {
        var items = await conn.QueryAsync<ItemData>(
            $"""
            SELECT slot AS "Slot", item_id AS "ItemId", amount AS "Amount"
            FROM {_tablePrefix}player_bank
            WHERE player_id = @PlayerId
            ORDER BY slot
            """,
            new { PlayerId = playerId });

        return items.ToList();
    }

    private async Task SavePlayerBankAsync(NpgsqlConnection conn, NpgsqlTransaction transaction,
        long playerId, List<ItemData> bank)
    {
        await conn.ExecuteAsync(
            $"DELETE FROM {_tablePrefix}player_bank WHERE player_id = @PlayerId",
            new { PlayerId = playerId },
            transaction);

        if (bank.Count == 0) return;

        await conn.ExecuteAsync(
            $"""
            INSERT INTO {_tablePrefix}player_bank (player_id, slot, item_id, amount)
            VALUES (@PlayerId, @Slot, @ItemId, @Amount)
            """,
            bank.Select(item => new
            {
                PlayerId = playerId,
                item.Slot,
                item.ItemId,
                item.Amount
            }),
            transaction);
    }

    #endregion

    #region Equipment

    private async Task<Dictionary<int, ItemData>> LoadPlayerEquipmentAsync(NpgsqlConnection conn, long playerId)
    {
        var items = await conn.QueryAsync<ItemData>(
            $"""
            SELECT slot AS "Slot", item_id AS "ItemId", amount AS "Amount",
                   durability AS "Durability"
            FROM {_tablePrefix}player_equipment
            WHERE player_id = @PlayerId
            """,
            new { PlayerId = playerId });

        return items.ToDictionary(i => i.Slot);
    }

    private async Task SavePlayerEquipmentAsync(NpgsqlConnection conn, NpgsqlTransaction transaction,
        long playerId, Dictionary<int, ItemData> equipment)
    {
        await conn.ExecuteAsync(
            $"DELETE FROM {_tablePrefix}player_equipment WHERE player_id = @PlayerId",
            new { PlayerId = playerId },
            transaction);

        if (equipment.Count == 0) return;

        await conn.ExecuteAsync(
            $"""
            INSERT INTO {_tablePrefix}player_equipment (player_id, slot, item_id, amount, durability)
            VALUES (@PlayerId, @Slot, @ItemId, @Amount, @Durability)
            """,
            equipment.Select(kvp => new
            {
                PlayerId = playerId,
                Slot = kvp.Key,
                kvp.Value.ItemId,
                kvp.Value.Amount,
                kvp.Value.Durability
            }),
            transaction);
    }

    #endregion

    #region Quests

    private async Task<Dictionary<int, int>> LoadPlayerQuestsAsync(NpgsqlConnection conn, long playerId)
    {
        var quests = await conn.QueryAsync<(int QuestId, int Stage)>(
            $"""
            SELECT quest_id AS "QuestId", stage AS "Stage"
            FROM {_tablePrefix}player_quests
            WHERE player_id = @PlayerId
            """,
            new { PlayerId = playerId });

        return quests.ToDictionary(q => q.QuestId, q => q.Stage);
    }

    private async Task SavePlayerQuestsAsync(NpgsqlConnection conn, NpgsqlTransaction transaction,
        long playerId, Dictionary<int, int> quests)
    {
        await conn.ExecuteAsync(
            $"DELETE FROM {_tablePrefix}player_quests WHERE player_id = @PlayerId",
            new { PlayerId = playerId },
            transaction);

        if (quests.Count == 0) return;

        await conn.ExecuteAsync(
            $"""
            INSERT INTO {_tablePrefix}player_quests (player_id, quest_id, stage)
            VALUES (@PlayerId, @QuestId, @Stage)
            """,
            quests.Select(kvp => new
            {
                PlayerId = playerId,
                QuestId = kvp.Key,
                Stage = kvp.Value
            }),
            transaction);
    }

    #endregion

    #region Leaderboards

    /// <summary>
    /// Gets the highscores for a skill.
    /// </summary>
    public async Task<List<HighscoreEntry>> GetHighscoresAsync(int skillId, int limit = 100, int offset = 0)
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        var entries = await conn.QueryAsync<HighscoreEntry>(
            $"""
            SELECT
                p.username AS "Username",
                s.current_level AS "Level",
                s.experience AS "Experience",
                RANK() OVER (ORDER BY s.experience DESC) AS "Rank"
            FROM {_tablePrefix}player_skills s
            JOIN {_tablePrefix}players p ON p.id = s.player_id
            WHERE s.skill_id = @SkillId AND NOT p.is_banned
            ORDER BY s.experience DESC
            LIMIT @Limit OFFSET @Offset
            """,
            new { SkillId = skillId, Limit = limit, Offset = offset });

        return entries.ToList();
    }

    /// <summary>
    /// Gets a player's rank for a skill.
    /// </summary>
    public async Task<long?> GetPlayerSkillRankAsync(string username, int skillId)
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        return await conn.ExecuteScalarAsync<long?>(
            $"""
            SELECT rank FROM (
                SELECT
                    p.username,
                    RANK() OVER (ORDER BY s.experience DESC) AS rank
                FROM {_tablePrefix}player_skills s
                JOIN {_tablePrefix}players p ON p.id = s.player_id
                WHERE s.skill_id = @SkillId AND NOT p.is_banned
            ) ranked
            WHERE LOWER(username) = LOWER(@Username)
            """,
            new { Username = username, SkillId = skillId });
    }

    #endregion

    #region Schema

    /// <summary>
    /// Creates the database schema if it doesn't exist.
    /// </summary>
    public async Task InitializeSchemaAsync()
    {
        await using var conn = await _dataSource.OpenConnectionAsync();

        await conn.ExecuteAsync(
            $"""
            -- Players table
            CREATE TABLE IF NOT EXISTS {_tablePrefix}players (
                id BIGSERIAL PRIMARY KEY,
                username VARCHAR(12) NOT NULL,
                password_hash VARCHAR(255),
                email VARCHAR(255),
                x INTEGER NOT NULL DEFAULT 120,
                y INTEGER NOT NULL DEFAULT 648,
                combat_level INTEGER NOT NULL DEFAULT 3,
                total_level INTEGER NOT NULL DEFAULT 27,
                quest_points INTEGER NOT NULL DEFAULT 0,
                bank_pins VARCHAR(4),
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                last_login TIMESTAMPTZ,
                last_ip VARCHAR(45),
                is_banned BOOLEAN NOT NULL DEFAULT FALSE,
                is_muted BOOLEAN NOT NULL DEFAULT FALSE,
                group_id INTEGER NOT NULL DEFAULT 0,
                UNIQUE (LOWER(username))
            );
            CREATE INDEX IF NOT EXISTS idx_players_username ON {_tablePrefix}players (LOWER(username));

            -- Skills table
            CREATE TABLE IF NOT EXISTS {_tablePrefix}player_skills (
                player_id BIGINT NOT NULL REFERENCES {_tablePrefix}players(id) ON DELETE CASCADE,
                skill_id INTEGER NOT NULL,
                current_level INTEGER NOT NULL DEFAULT 1,
                max_level INTEGER NOT NULL DEFAULT 1,
                experience BIGINT NOT NULL DEFAULT 0,
                PRIMARY KEY (player_id, skill_id)
            );
            CREATE INDEX IF NOT EXISTS idx_skills_experience ON {_tablePrefix}player_skills (skill_id, experience DESC);

            -- Temp table for bulk skill updates
            CREATE UNLOGGED TABLE IF NOT EXISTS {_tablePrefix}player_skills_temp (
                player_id BIGINT,
                skill_id INTEGER,
                current_level INTEGER,
                max_level INTEGER,
                experience BIGINT
            );

            -- Inventory table
            CREATE TABLE IF NOT EXISTS {_tablePrefix}player_inventory (
                player_id BIGINT NOT NULL REFERENCES {_tablePrefix}players(id) ON DELETE CASCADE,
                slot INTEGER NOT NULL,
                item_id INTEGER NOT NULL,
                amount INTEGER NOT NULL DEFAULT 1,
                durability INTEGER,
                PRIMARY KEY (player_id, slot)
            );

            -- Bank table
            CREATE TABLE IF NOT EXISTS {_tablePrefix}player_bank (
                player_id BIGINT NOT NULL REFERENCES {_tablePrefix}players(id) ON DELETE CASCADE,
                slot INTEGER NOT NULL,
                item_id INTEGER NOT NULL,
                amount INTEGER NOT NULL DEFAULT 1,
                PRIMARY KEY (player_id, slot)
            );

            -- Equipment table
            CREATE TABLE IF NOT EXISTS {_tablePrefix}player_equipment (
                player_id BIGINT NOT NULL REFERENCES {_tablePrefix}players(id) ON DELETE CASCADE,
                slot INTEGER NOT NULL,
                item_id INTEGER NOT NULL,
                amount INTEGER NOT NULL DEFAULT 1,
                durability INTEGER,
                PRIMARY KEY (player_id, slot)
            );

            -- Quests table
            CREATE TABLE IF NOT EXISTS {_tablePrefix}player_quests (
                player_id BIGINT NOT NULL REFERENCES {_tablePrefix}players(id) ON DELETE CASCADE,
                quest_id INTEGER NOT NULL,
                stage INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (player_id, quest_id)
            );

            -- Friends table
            CREATE TABLE IF NOT EXISTS {_tablePrefix}player_friends (
                player_id BIGINT NOT NULL REFERENCES {_tablePrefix}players(id) ON DELETE CASCADE,
                friend_username VARCHAR(12) NOT NULL,
                PRIMARY KEY (player_id, friend_username)
            );

            -- Ignores table
            CREATE TABLE IF NOT EXISTS {_tablePrefix}player_ignores (
                player_id BIGINT NOT NULL REFERENCES {_tablePrefix}players(id) ON DELETE CASCADE,
                ignored_username VARCHAR(12) NOT NULL,
                PRIMARY KEY (player_id, ignored_username)
            );
            """);

        _logger.LogInformation("Database schema initialized");
    }

    #endregion

    public async ValueTask DisposeAsync()
    {
        await _dataSource.DisposeAsync();
    }
}

/// <summary>
/// Highscore entry.
/// </summary>
public sealed class HighscoreEntry
{
    public required string Username { get; init; }
    public int Level { get; init; }
    public long Experience { get; init; }
    public long Rank { get; init; }
}
