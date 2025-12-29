using Dapper;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MySqlConnector;
using OpenRSC.Server.Configuration;

namespace OpenRSC.Server.Database;

/// <summary>
/// MySQL implementation of player repository using Dapper.
/// </summary>
public sealed class MySqlPlayerRepository : IPlayerRepository
{
    private readonly ILogger<MySqlPlayerRepository> _logger;
    private readonly DatabaseSettings _settings;
    private readonly string _tablePrefix;

    public MySqlPlayerRepository(
        ILogger<MySqlPlayerRepository> logger,
        IOptions<DatabaseSettings> settings)
    {
        _logger = logger;
        _settings = settings.Value;
        _tablePrefix = _settings.TablePrefix;
    }

    private async Task<MySqlConnection> CreateConnectionAsync()
    {
        var connection = new MySqlConnection(_settings.ConnectionString);
        await connection.OpenAsync();
        return connection;
    }

    public async Task<PlayerData?> LoadPlayerAsync(string username)
    {
        await using var connection = await CreateConnectionAsync();

        var sql = $@"
            SELECT
                p.id AS Id,
                p.username AS Username,
                p.x AS X,
                p.y AS Y,
                p.combat AS CombatLevel,
                p.skill_total AS TotalLevel,
                p.creation_date AS CreatedAt,
                p.login_date AS LastLogin,
                p.quest_points AS QuestPoints,
                e.cur_attack, e.cur_defense, e.cur_strength, e.cur_hits,
                e.cur_ranged, e.cur_prayer, e.cur_magic, e.cur_cooking,
                e.cur_woodcut, e.cur_fletching, e.cur_fishing, e.cur_firemaking,
                e.cur_crafting, e.cur_smithing, e.cur_mining, e.cur_herblaw,
                e.cur_agility, e.cur_thieving,
                e.exp_attack, e.exp_defense, e.exp_strength, e.exp_hits,
                e.exp_ranged, e.exp_prayer, e.exp_magic, e.exp_cooking,
                e.exp_woodcut, e.exp_fletching, e.exp_fishing, e.exp_firemaking,
                e.exp_crafting, e.exp_smithing, e.exp_mining, e.exp_herblaw,
                e.exp_agility, e.exp_thieving
            FROM {_tablePrefix}players p
            LEFT JOIN {_tablePrefix}experience e ON p.id = e.playerID
            WHERE LOWER(p.username) = @Username";

        var result = await connection.QueryFirstOrDefaultAsync<dynamic>(sql, new { Username = username.ToLowerInvariant() });

        if (result == null)
            return null;

        var player = new PlayerData
        {
            Id = (int)result.Id,
            Username = (string)result.Username,
            X = (int)result.X,
            Y = (int)result.Y,
            CombatLevel = (int)result.CombatLevel,
            TotalLevel = (int)result.TotalLevel,
            QuestPoints = (int)result.QuestPoints,
            CreatedAt = (DateTime)result.CreatedAt,
            LastLogin = (DateTime)result.LastLogin
        };

        // Parse stats (simplified - full implementation would handle all 18 skills)
        player.CurrentStats = new[]
        {
            (int)(result.cur_attack ?? 1),
            (int)(result.cur_defense ?? 1),
            (int)(result.cur_strength ?? 1),
            (int)(result.cur_hits ?? 10),
            (int)(result.cur_ranged ?? 1),
            (int)(result.cur_prayer ?? 1),
            (int)(result.cur_magic ?? 1),
            (int)(result.cur_cooking ?? 1),
            (int)(result.cur_woodcut ?? 1),
            (int)(result.cur_fletching ?? 1),
            (int)(result.cur_fishing ?? 1),
            (int)(result.cur_firemaking ?? 1),
            (int)(result.cur_crafting ?? 1),
            (int)(result.cur_smithing ?? 1),
            (int)(result.cur_mining ?? 1),
            (int)(result.cur_herblaw ?? 1),
            (int)(result.cur_agility ?? 1),
            (int)(result.cur_thieving ?? 1)
        };

        player.Experience = new[]
        {
            (int)(result.exp_attack ?? 0),
            (int)(result.exp_defense ?? 0),
            (int)(result.exp_strength ?? 0),
            (int)(result.exp_hits ?? 1154),
            (int)(result.exp_ranged ?? 0),
            (int)(result.exp_prayer ?? 0),
            (int)(result.exp_magic ?? 0),
            (int)(result.exp_cooking ?? 0),
            (int)(result.exp_woodcut ?? 0),
            (int)(result.exp_fletching ?? 0),
            (int)(result.exp_fishing ?? 0),
            (int)(result.exp_firemaking ?? 0),
            (int)(result.exp_crafting ?? 0),
            (int)(result.exp_smithing ?? 0),
            (int)(result.exp_mining ?? 0),
            (int)(result.exp_herblaw ?? 0),
            (int)(result.exp_agility ?? 0),
            (int)(result.exp_thieving ?? 0)
        };

        player.MaxStats = player.CurrentStats.ToArray();
        player.Hitpoints = player.CurrentStats[3];
        player.MaxHitpoints = player.MaxStats[3];

        return player;
    }

    public async Task SavePlayerAsync(PlayerData player)
    {
        await using var connection = await CreateConnectionAsync();
        await using var transaction = await connection.BeginTransactionAsync();

        try
        {
            // Update player position and basic info
            var updatePlayerSql = $@"
                UPDATE {_tablePrefix}players
                SET x = @X, y = @Y, combat = @CombatLevel,
                    skill_total = @TotalLevel, quest_points = @QuestPoints
                WHERE id = @Id";

            await connection.ExecuteAsync(updatePlayerSql, player, transaction);

            // Update experience
            var updateExpSql = $@"
                UPDATE {_tablePrefix}experience
                SET cur_attack = @Attack, cur_defense = @Defense, cur_strength = @Strength,
                    cur_hits = @Hits, cur_ranged = @Ranged, cur_prayer = @Prayer,
                    cur_magic = @Magic, cur_cooking = @Cooking, cur_woodcut = @Woodcutting,
                    cur_fletching = @Fletching, cur_fishing = @Fishing, cur_firemaking = @Firemaking,
                    cur_crafting = @Crafting, cur_smithing = @Smithing, cur_mining = @Mining,
                    cur_herblaw = @Herblaw, cur_agility = @Agility, cur_thieving = @Thieving,
                    exp_attack = @ExpAttack, exp_defense = @ExpDefense, exp_strength = @ExpStrength,
                    exp_hits = @ExpHits, exp_ranged = @ExpRanged, exp_prayer = @ExpPrayer,
                    exp_magic = @ExpMagic, exp_cooking = @ExpCooking, exp_woodcut = @ExpWoodcutting,
                    exp_fletching = @ExpFletching, exp_fishing = @ExpFishing, exp_firemaking = @ExpFiremaking,
                    exp_crafting = @ExpCrafting, exp_smithing = @ExpSmithing, exp_mining = @ExpMining,
                    exp_herblaw = @ExpHerblaw, exp_agility = @ExpAgility, exp_thieving = @ExpThieving
                WHERE playerID = @Id";

            await connection.ExecuteAsync(updateExpSql, new
            {
                player.Id,
                Attack = player.CurrentStats[0],
                Defense = player.CurrentStats[1],
                Strength = player.CurrentStats[2],
                Hits = player.CurrentStats[3],
                Ranged = player.CurrentStats[4],
                Prayer = player.CurrentStats[5],
                Magic = player.CurrentStats[6],
                Cooking = player.CurrentStats[7],
                Woodcutting = player.CurrentStats[8],
                Fletching = player.CurrentStats[9],
                Fishing = player.CurrentStats[10],
                Firemaking = player.CurrentStats[11],
                Crafting = player.CurrentStats[12],
                Smithing = player.CurrentStats[13],
                Mining = player.CurrentStats[14],
                Herblaw = player.CurrentStats[15],
                Agility = player.CurrentStats[16],
                Thieving = player.CurrentStats[17],
                ExpAttack = player.Experience[0],
                ExpDefense = player.Experience[1],
                ExpStrength = player.Experience[2],
                ExpHits = player.Experience[3],
                ExpRanged = player.Experience[4],
                ExpPrayer = player.Experience[5],
                ExpMagic = player.Experience[6],
                ExpCooking = player.Experience[7],
                ExpWoodcutting = player.Experience[8],
                ExpFletching = player.Experience[9],
                ExpFishing = player.Experience[10],
                ExpFiremaking = player.Experience[11],
                ExpCrafting = player.Experience[12],
                ExpSmithing = player.Experience[13],
                ExpMining = player.Experience[14],
                ExpHerblaw = player.Experience[15],
                ExpAgility = player.Experience[16],
                ExpThieving = player.Experience[17]
            }, transaction);

            await transaction.CommitAsync();
            _logger.LogDebug("Saved player {Username}", player.Username);
        }
        catch (Exception ex)
        {
            await transaction.RollbackAsync();
            _logger.LogError(ex, "Error saving player {Username}", player.Username);
            throw;
        }
    }

    public async Task<bool> PlayerExistsAsync(string username)
    {
        await using var connection = await CreateConnectionAsync();

        var sql = $"SELECT COUNT(*) FROM {_tablePrefix}players WHERE LOWER(username) = @Username";
        var count = await connection.ExecuteScalarAsync<int>(sql, new { Username = username.ToLowerInvariant() });

        return count > 0;
    }

    public async Task<bool> CreatePlayerAsync(PlayerData player, string passwordHash)
    {
        await using var connection = await CreateConnectionAsync();
        await using var transaction = await connection.BeginTransactionAsync();

        try
        {
            var insertPlayerSql = $@"
                INSERT INTO {_tablePrefix}players
                (username, pass, x, y, combat, skill_total, creation_date, login_date)
                VALUES (@Username, @PasswordHash, @X, @Y, @CombatLevel, @TotalLevel, NOW(), NOW());
                SELECT LAST_INSERT_ID();";

            var playerId = await connection.ExecuteScalarAsync<int>(insertPlayerSql, new
            {
                player.Username,
                PasswordHash = passwordHash,
                player.X,
                player.Y,
                player.CombatLevel,
                player.TotalLevel
            }, transaction);

            // Insert default experience
            var insertExpSql = $@"
                INSERT INTO {_tablePrefix}experience (playerID, cur_hits, exp_hits)
                VALUES (@PlayerId, 10, 1154)";

            await connection.ExecuteAsync(insertExpSql, new { PlayerId = playerId }, transaction);

            await transaction.CommitAsync();
            player.Id = playerId;

            _logger.LogInformation("Created new player {Username} with ID {Id}", player.Username, playerId);
            return true;
        }
        catch (Exception ex)
        {
            await transaction.RollbackAsync();
            _logger.LogError(ex, "Error creating player {Username}", player.Username);
            return false;
        }
    }

    public async Task UpdateLoginTimeAsync(string username)
    {
        await using var connection = await CreateConnectionAsync();

        var sql = $"UPDATE {_tablePrefix}players SET login_date = NOW() WHERE LOWER(username) = @Username";
        await connection.ExecuteAsync(sql, new { Username = username.ToLowerInvariant() });
    }

    public async Task<string?> GetPasswordHashAsync(string username)
    {
        await using var connection = await CreateConnectionAsync();

        var sql = $"SELECT pass FROM {_tablePrefix}players WHERE LOWER(username) = @Username";
        return await connection.ExecuteScalarAsync<string?>(sql, new { Username = username.ToLowerInvariant() });
    }
}
