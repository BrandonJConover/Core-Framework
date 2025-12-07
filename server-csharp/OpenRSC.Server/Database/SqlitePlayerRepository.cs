using System.Data;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Options;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Database;

/// <summary>
/// SQLite configuration options.
/// </summary>
public sealed class SqliteOptions
{
    public string ConnectionString { get; set; } = "Data Source=openrsc.db";
    public bool CreateIfMissing { get; set; } = true;
}

/// <summary>
/// SQLite implementation of player repository.
/// </summary>
public sealed class SqlitePlayerRepository : IPlayerRepository, IAsyncDisposable
{
    private readonly SqliteOptions _options;
    private SqliteConnection? _connection;

    public SqlitePlayerRepository(IOptions<SqliteOptions> options)
    {
        _options = options.Value;
    }

    /// <summary>
    /// Initializes the database connection and schema.
    /// </summary>
    public async Task InitializeAsync()
    {
        _connection = new SqliteConnection(_options.ConnectionString);
        await _connection.OpenAsync();

        if (_options.CreateIfMissing)
        {
            await CreateSchemaAsync();
        }
    }

    private async Task CreateSchemaAsync()
    {
        var sql = """
            CREATE TABLE IF NOT EXISTS players (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL UNIQUE COLLATE NOCASE,
                username_hash INTEGER NOT NULL,
                password_hash TEXT NOT NULL,
                creation_date TEXT NOT NULL,
                last_login TEXT,
                last_ip TEXT,
                x INTEGER NOT NULL DEFAULT 122,
                y INTEGER NOT NULL DEFAULT 647,
                combat_style INTEGER NOT NULL DEFAULT 0,
                iron_man INTEGER NOT NULL DEFAULT 0,
                iron_man_restriction INTEGER NOT NULL DEFAULT 0,
                group_id INTEGER NOT NULL DEFAULT 1,
                banned INTEGER NOT NULL DEFAULT 0,
                muted INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS player_skills (
                player_id INTEGER NOT NULL,
                skill_id INTEGER NOT NULL,
                current_level INTEGER NOT NULL,
                experience INTEGER NOT NULL,
                PRIMARY KEY (player_id, skill_id),
                FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS player_inventory (
                player_id INTEGER NOT NULL,
                slot INTEGER NOT NULL,
                item_id INTEGER NOT NULL,
                amount INTEGER NOT NULL DEFAULT 1,
                PRIMARY KEY (player_id, slot),
                FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS player_bank (
                player_id INTEGER NOT NULL,
                slot INTEGER NOT NULL,
                item_id INTEGER NOT NULL,
                amount INTEGER NOT NULL DEFAULT 1,
                PRIMARY KEY (player_id, slot),
                FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS player_equipment (
                player_id INTEGER NOT NULL,
                slot INTEGER NOT NULL,
                item_id INTEGER NOT NULL,
                PRIMARY KEY (player_id, slot),
                FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS player_friends (
                player_id INTEGER NOT NULL,
                friend_hash INTEGER NOT NULL,
                PRIMARY KEY (player_id, friend_hash),
                FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS player_ignores (
                player_id INTEGER NOT NULL,
                ignore_hash INTEGER NOT NULL,
                PRIMARY KEY (player_id, ignore_hash),
                FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS player_quests (
                player_id INTEGER NOT NULL,
                quest_id INTEGER NOT NULL,
                stage INTEGER NOT NULL DEFAULT 0,
                completed INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (player_id, quest_id),
                FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_players_username ON players(username);
            CREATE INDEX IF NOT EXISTS idx_players_username_hash ON players(username_hash);
            """;

        await using var command = new SqliteCommand(sql, _connection);
        await command.ExecuteNonQueryAsync();
    }

    public async Task<Player?> GetByUsernameAsync(string username)
    {
        EnsureConnected();

        var sql = "SELECT * FROM players WHERE username = @username";
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@username", username);

        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            return null;

        return await LoadPlayerFromReaderAsync(reader);
    }

    public async Task<Player?> GetByIdAsync(long id)
    {
        EnsureConnected();

        var sql = "SELECT * FROM players WHERE id = @id";
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@id", id);

        await using var reader = await command.ExecuteReaderAsync();
        if (!await reader.ReadAsync())
            return null;

        return await LoadPlayerFromReaderAsync(reader);
    }

    private async Task<Player> LoadPlayerFromReaderAsync(SqliteDataReader reader)
    {
        var id = reader.GetInt64(reader.GetOrdinal("id"));
        var username = reader.GetString(reader.GetOrdinal("username"));
        var x = reader.GetInt32(reader.GetOrdinal("x"));
        var y = reader.GetInt32(reader.GetOrdinal("y"));

        var player = new Player(username, new Point(x, y));

        // Load skills
        await LoadSkillsAsync(id, player);

        // Load inventory
        await LoadInventoryAsync(id, player);

        // Load bank
        await LoadBankAsync(id, player);

        // Load equipment
        await LoadEquipmentAsync(id, player);

        // Load friends/ignores
        await LoadSocialAsync(id, player);

        // Load quests
        await LoadQuestsAsync(id, player);

        return player;
    }

    private async Task LoadSkillsAsync(long playerId, Player player)
    {
        var sql = "SELECT skill_id, current_level, experience FROM player_skills WHERE player_id = @playerId";
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@playerId", playerId);

        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var skillId = reader.GetInt32(0);
            var experience = reader.GetInt32(2);

            if (Enum.IsDefined(typeof(Skills.Skill), skillId))
            {
                var skill = (Skills.Skill)skillId;
                // Would set experience directly
                player.Skills.AddExperience(skill, experience);
            }
        }
    }

    private async Task LoadInventoryAsync(long playerId, Player player)
    {
        var sql = "SELECT slot, item_id, amount FROM player_inventory WHERE player_id = @playerId ORDER BY slot";
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@playerId", playerId);

        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var itemId = reader.GetInt32(1);
            var amount = reader.GetInt32(2);
            // Would load into inventory
        }
    }

    private async Task LoadBankAsync(long playerId, Player player)
    {
        var sql = "SELECT slot, item_id, amount FROM player_bank WHERE player_id = @playerId ORDER BY slot";
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@playerId", playerId);

        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var itemId = reader.GetInt32(1);
            var amount = reader.GetInt32(2);
            // Would load into bank
        }
    }

    private async Task LoadEquipmentAsync(long playerId, Player player)
    {
        var sql = "SELECT slot, item_id FROM player_equipment WHERE player_id = @playerId";
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@playerId", playerId);

        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var slot = reader.GetInt32(0);
            var itemId = reader.GetInt32(1);
            // Would load into equipment
        }
    }

    private async Task LoadSocialAsync(long playerId, Player player)
    {
        // Load friends
        var friendsSql = "SELECT friend_hash FROM player_friends WHERE player_id = @playerId";
        await using var friendsCommand = new SqliteCommand(friendsSql, _connection);
        friendsCommand.Parameters.AddWithValue("@playerId", playerId);

        await using var friendsReader = await friendsCommand.ExecuteReaderAsync();
        while (await friendsReader.ReadAsync())
        {
            var friendHash = friendsReader.GetInt64(0);
            player.Friends.AddFriend(friendHash);
        }

        // Load ignores
        var ignoresSql = "SELECT ignore_hash FROM player_ignores WHERE player_id = @playerId";
        await using var ignoresCommand = new SqliteCommand(ignoresSql, _connection);
        ignoresCommand.Parameters.AddWithValue("@playerId", playerId);

        await using var ignoresReader = await ignoresCommand.ExecuteReaderAsync();
        while (await ignoresReader.ReadAsync())
        {
            var ignoreHash = ignoresReader.GetInt64(0);
            player.Friends.AddIgnore(ignoreHash);
        }
    }

    private async Task LoadQuestsAsync(long playerId, Player player)
    {
        var sql = "SELECT quest_id, stage, completed FROM player_quests WHERE player_id = @playerId";
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@playerId", playerId);

        await using var reader = await command.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var questId = reader.GetInt32(0);
            var stage = reader.GetInt32(1);
            var completed = reader.GetBoolean(2);
            // Would load into quest tracker
        }
    }

    public async Task<bool> SaveAsync(Player player)
    {
        EnsureConnected();

        await using var transaction = await _connection!.BeginTransactionAsync();

        try
        {
            // Get or create player record
            var playerId = await GetOrCreatePlayerIdAsync(player);

            // Update main player data
            await UpdatePlayerDataAsync(playerId, player);

            // Save skills
            await SaveSkillsAsync(playerId, player);

            // Save inventory
            await SaveInventoryAsync(playerId, player);

            // Save bank
            await SaveBankAsync(playerId, player);

            // Save equipment
            await SaveEquipmentAsync(playerId, player);

            // Save social
            await SaveSocialAsync(playerId, player);

            // Save quests
            await SaveQuestsAsync(playerId, player);

            await transaction.CommitAsync();
            return true;
        }
        catch
        {
            await transaction.RollbackAsync();
            throw;
        }
    }

    private async Task<long> GetOrCreatePlayerIdAsync(Player player)
    {
        var selectSql = "SELECT id FROM players WHERE username = @username";
        await using var selectCommand = new SqliteCommand(selectSql, _connection);
        selectCommand.Parameters.AddWithValue("@username", player.Username);

        var result = await selectCommand.ExecuteScalarAsync();
        if (result is not null)
            return (long)result;

        // Create new player
        var insertSql = """
            INSERT INTO players (username, username_hash, password_hash, creation_date, x, y)
            VALUES (@username, @hash, '', datetime('now'), @x, @y);
            SELECT last_insert_rowid();
            """;
        await using var insertCommand = new SqliteCommand(insertSql, _connection);
        insertCommand.Parameters.AddWithValue("@username", player.Username);
        insertCommand.Parameters.AddWithValue("@hash", player.UsernameHash);
        insertCommand.Parameters.AddWithValue("@x", player.Location.X);
        insertCommand.Parameters.AddWithValue("@y", player.Location.Y);

        return (long)(await insertCommand.ExecuteScalarAsync())!;
    }

    private async Task UpdatePlayerDataAsync(long playerId, Player player)
    {
        var sql = """
            UPDATE players SET
                x = @x,
                y = @y,
                last_login = datetime('now')
            WHERE id = @id
            """;
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@id", playerId);
        command.Parameters.AddWithValue("@x", player.Location.X);
        command.Parameters.AddWithValue("@y", player.Location.Y);
        await command.ExecuteNonQueryAsync();
    }

    private async Task SaveSkillsAsync(long playerId, Player player)
    {
        // Delete existing skills
        var deleteSql = "DELETE FROM player_skills WHERE player_id = @playerId";
        await using var deleteCommand = new SqliteCommand(deleteSql, _connection);
        deleteCommand.Parameters.AddWithValue("@playerId", playerId);
        await deleteCommand.ExecuteNonQueryAsync();

        // Insert current skills
        var insertSql = "INSERT INTO player_skills (player_id, skill_id, current_level, experience) VALUES (@playerId, @skillId, @level, @exp)";
        foreach (var skill in Enum.GetValues<Skills.Skill>())
        {
            await using var insertCommand = new SqliteCommand(insertSql, _connection);
            insertCommand.Parameters.AddWithValue("@playerId", playerId);
            insertCommand.Parameters.AddWithValue("@skillId", (int)skill);
            insertCommand.Parameters.AddWithValue("@level", player.Skills.GetCurrentLevel(skill));
            insertCommand.Parameters.AddWithValue("@exp", player.Skills.GetExperience(skill));
            await insertCommand.ExecuteNonQueryAsync();
        }
    }

    private async Task SaveInventoryAsync(long playerId, Player player)
    {
        var deleteSql = "DELETE FROM player_inventory WHERE player_id = @playerId";
        await using var deleteCommand = new SqliteCommand(deleteSql, _connection);
        deleteCommand.Parameters.AddWithValue("@playerId", playerId);
        await deleteCommand.ExecuteNonQueryAsync();

        var slot = 0;
        var insertSql = "INSERT INTO player_inventory (player_id, slot, item_id, amount) VALUES (@playerId, @slot, @itemId, @amount)";
        foreach (var item in player.Inventory.GetItems())
        {
            await using var insertCommand = new SqliteCommand(insertSql, _connection);
            insertCommand.Parameters.AddWithValue("@playerId", playerId);
            insertCommand.Parameters.AddWithValue("@slot", slot++);
            insertCommand.Parameters.AddWithValue("@itemId", item.CatalogId);
            insertCommand.Parameters.AddWithValue("@amount", item.Amount);
            await insertCommand.ExecuteNonQueryAsync();
        }
    }

    private async Task SaveBankAsync(long playerId, Player player)
    {
        var deleteSql = "DELETE FROM player_bank WHERE player_id = @playerId";
        await using var deleteCommand = new SqliteCommand(deleteSql, _connection);
        deleteCommand.Parameters.AddWithValue("@playerId", playerId);
        await deleteCommand.ExecuteNonQueryAsync();

        var slot = 0;
        var insertSql = "INSERT INTO player_bank (player_id, slot, item_id, amount) VALUES (@playerId, @slot, @itemId, @amount)";
        foreach (var item in player.Bank.GetItems())
        {
            await using var insertCommand = new SqliteCommand(insertSql, _connection);
            insertCommand.Parameters.AddWithValue("@playerId", playerId);
            insertCommand.Parameters.AddWithValue("@slot", slot++);
            insertCommand.Parameters.AddWithValue("@itemId", item.CatalogId);
            insertCommand.Parameters.AddWithValue("@amount", item.Amount);
            await insertCommand.ExecuteNonQueryAsync();
        }
    }

    private async Task SaveEquipmentAsync(long playerId, Player player)
    {
        var deleteSql = "DELETE FROM player_equipment WHERE player_id = @playerId";
        await using var deleteCommand = new SqliteCommand(deleteSql, _connection);
        deleteCommand.Parameters.AddWithValue("@playerId", playerId);
        await deleteCommand.ExecuteNonQueryAsync();

        var insertSql = "INSERT INTO player_equipment (player_id, slot, item_id) VALUES (@playerId, @slot, @itemId)";
        foreach (var (slot, item) in player.Equipment.GetEquipped())
        {
            await using var insertCommand = new SqliteCommand(insertSql, _connection);
            insertCommand.Parameters.AddWithValue("@playerId", playerId);
            insertCommand.Parameters.AddWithValue("@slot", (int)slot);
            insertCommand.Parameters.AddWithValue("@itemId", item.CatalogId);
            await insertCommand.ExecuteNonQueryAsync();
        }
    }

    private async Task SaveSocialAsync(long playerId, Player player)
    {
        // Delete and re-insert friends
        var deleteFriendsSql = "DELETE FROM player_friends WHERE player_id = @playerId";
        await using var deleteFriendsCommand = new SqliteCommand(deleteFriendsSql, _connection);
        deleteFriendsCommand.Parameters.AddWithValue("@playerId", playerId);
        await deleteFriendsCommand.ExecuteNonQueryAsync();

        var insertFriendSql = "INSERT INTO player_friends (player_id, friend_hash) VALUES (@playerId, @friendHash)";
        foreach (var friendHash in player.Friends.GetFriends())
        {
            await using var insertCommand = new SqliteCommand(insertFriendSql, _connection);
            insertCommand.Parameters.AddWithValue("@playerId", playerId);
            insertCommand.Parameters.AddWithValue("@friendHash", friendHash);
            await insertCommand.ExecuteNonQueryAsync();
        }

        // Delete and re-insert ignores
        var deleteIgnoresSql = "DELETE FROM player_ignores WHERE player_id = @playerId";
        await using var deleteIgnoresCommand = new SqliteCommand(deleteIgnoresSql, _connection);
        deleteIgnoresCommand.Parameters.AddWithValue("@playerId", playerId);
        await deleteIgnoresCommand.ExecuteNonQueryAsync();

        var insertIgnoreSql = "INSERT INTO player_ignores (player_id, ignore_hash) VALUES (@playerId, @ignoreHash)";
        foreach (var ignoreHash in player.Friends.GetIgnores())
        {
            await using var insertCommand = new SqliteCommand(insertIgnoreSql, _connection);
            insertCommand.Parameters.AddWithValue("@playerId", playerId);
            insertCommand.Parameters.AddWithValue("@ignoreHash", ignoreHash);
            await insertCommand.ExecuteNonQueryAsync();
        }
    }

    private async Task SaveQuestsAsync(long playerId, Player player)
    {
        var deleteSql = "DELETE FROM player_quests WHERE player_id = @playerId";
        await using var deleteCommand = new SqliteCommand(deleteSql, _connection);
        deleteCommand.Parameters.AddWithValue("@playerId", playerId);
        await deleteCommand.ExecuteNonQueryAsync();

        var insertSql = "INSERT INTO player_quests (player_id, quest_id, stage, completed) VALUES (@playerId, @questId, @stage, @completed)";
        foreach (var (questId, progress) in player.Quests.GetAllProgress())
        {
            await using var insertCommand = new SqliteCommand(insertSql, _connection);
            insertCommand.Parameters.AddWithValue("@playerId", playerId);
            insertCommand.Parameters.AddWithValue("@questId", questId);
            insertCommand.Parameters.AddWithValue("@stage", progress.CurrentStage);
            insertCommand.Parameters.AddWithValue("@completed", progress.IsComplete);
            await insertCommand.ExecuteNonQueryAsync();
        }
    }

    public async Task<bool> ExistsAsync(string username)
    {
        EnsureConnected();

        var sql = "SELECT COUNT(*) FROM players WHERE username = @username";
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@username", username);

        var count = (long)(await command.ExecuteScalarAsync())!;
        return count > 0;
    }

    public async Task<bool> DeleteAsync(long id)
    {
        EnsureConnected();

        var sql = "DELETE FROM players WHERE id = @id";
        await using var command = new SqliteCommand(sql, _connection);
        command.Parameters.AddWithValue("@id", id);

        var rowsAffected = await command.ExecuteNonQueryAsync();
        return rowsAffected > 0;
    }

    private void EnsureConnected()
    {
        if (_connection is null || _connection.State != ConnectionState.Open)
        {
            throw new InvalidOperationException("Database connection is not open. Call InitializeAsync first.");
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_connection is not null)
        {
            await _connection.DisposeAsync();
            _connection = null;
        }
    }
}
