using OpenRSC.Server.Entities;
using OpenRSC.Server.Services;

namespace OpenRSC.Server.Social;

/// <summary>
/// Manages a player's friends and ignore lists.
/// </summary>
public sealed class SocialManager
{
    private readonly Player _player;
    private readonly HashSet<long> _friends = new();
    private readonly HashSet<long> _ignores = new();
    private readonly WorldService _worldService;

    private const int MaxFriends = 200;
    private const int MaxIgnores = 100;

    /// <summary>
    /// Friends list.
    /// </summary>
    public IReadOnlySet<long> Friends => _friends;

    /// <summary>
    /// Ignore list.
    /// </summary>
    public IReadOnlySet<long> Ignores => _ignores;

    /// <summary>
    /// Event raised when a friend comes online.
    /// </summary>
    public event Action<long, bool>? FriendStatusChanged;

    public SocialManager(Player player, WorldService worldService)
    {
        _player = player;
        _worldService = worldService;
    }

    /// <summary>
    /// Adds a friend by username hash.
    /// </summary>
    public SocialResult AddFriend(long usernameHash)
    {
        if (_friends.Count >= MaxFriends)
            return SocialResult.Fail("Your friends list is full.");

        if (_friends.Contains(usernameHash))
            return SocialResult.Fail("That player is already on your friends list.");

        if (usernameHash == _player.UsernameHash)
            return SocialResult.Fail("You can't add yourself as a friend.");

        _friends.Add(usernameHash);

        // Check if friend is online and notify
        var friend = _worldService.GetPlayerByHash(usernameHash);
        if (friend is not null && CanSeeOnlineStatus(friend))
        {
            FriendStatusChanged?.Invoke(usernameHash, true);
        }

        return SocialResult.Success;
    }

    /// <summary>
    /// Removes a friend.
    /// </summary>
    public SocialResult RemoveFriend(long usernameHash)
    {
        if (!_friends.Remove(usernameHash))
            return SocialResult.Fail("That player is not on your friends list.");

        return SocialResult.Success;
    }

    /// <summary>
    /// Adds a player to the ignore list.
    /// </summary>
    public SocialResult AddIgnore(long usernameHash)
    {
        if (_ignores.Count >= MaxIgnores)
            return SocialResult.Fail("Your ignore list is full.");

        if (_ignores.Contains(usernameHash))
            return SocialResult.Fail("That player is already on your ignore list.");

        if (usernameHash == _player.UsernameHash)
            return SocialResult.Fail("You can't ignore yourself.");

        _ignores.Add(usernameHash);

        return SocialResult.Success;
    }

    /// <summary>
    /// Removes a player from the ignore list.
    /// </summary>
    public SocialResult RemoveIgnore(long usernameHash)
    {
        if (!_ignores.Remove(usernameHash))
            return SocialResult.Fail("That player is not on your ignore list.");

        return SocialResult.Success;
    }

    /// <summary>
    /// Checks if a player is on the friends list.
    /// </summary>
    public bool IsFriend(long usernameHash) => _friends.Contains(usernameHash);

    /// <summary>
    /// Checks if a player is on the ignore list.
    /// </summary>
    public bool IsIgnored(long usernameHash) => _ignores.Contains(usernameHash);

    /// <summary>
    /// Checks if we can see another player's online status.
    /// </summary>
    private bool CanSeeOnlineStatus(Player other)
    {
        return other.PrivacySettings.OnlineStatus switch
        {
            OnlineStatusSetting.Everyone => true,
            OnlineStatusSetting.Friends => other.Social.IsFriend(_player.UsernameHash),
            OnlineStatusSetting.Nobody => false,
            _ => true
        };
    }

    /// <summary>
    /// Called when the player logs in.
    /// </summary>
    public void OnLogin()
    {
        // Notify friends that we're online
        foreach (var friendHash in _friends)
        {
            var friend = _worldService.GetPlayerByHash(friendHash);
            if (friend is not null && friend.Social.IsFriend(_player.UsernameHash))
            {
                if (CanSeeOnlineStatus(_player))
                {
                    friend.Social.FriendStatusChanged?.Invoke(_player.UsernameHash, true);
                }
            }
        }
    }

    /// <summary>
    /// Called when the player logs out.
    /// </summary>
    public void OnLogout()
    {
        // Notify friends that we're offline
        foreach (var friendHash in _friends)
        {
            var friend = _worldService.GetPlayerByHash(friendHash);
            if (friend is not null && friend.Social.IsFriend(_player.UsernameHash))
            {
                friend.Social.FriendStatusChanged?.Invoke(_player.UsernameHash, false);
            }
        }
    }

    /// <summary>
    /// Gets the online status of all friends.
    /// </summary>
    public IEnumerable<(long UsernameHash, bool IsOnline, int World)> GetFriendsStatus()
    {
        foreach (var friendHash in _friends)
        {
            var friend = _worldService.GetPlayerByHash(friendHash);
            var isOnline = friend is not null && CanSeeOnlineStatus(friend);
            var world = isOnline ? _worldService.WorldId : 0;
            yield return (friendHash, isOnline, world);
        }
    }

    /// <summary>
    /// Loads friends and ignores from data.
    /// </summary>
    public void Load(IEnumerable<long> friends, IEnumerable<long> ignores)
    {
        _friends.Clear();
        foreach (var f in friends.Take(MaxFriends))
            _friends.Add(f);

        _ignores.Clear();
        foreach (var i in ignores.Take(MaxIgnores))
            _ignores.Add(i);
    }
}

/// <summary>
/// Player privacy settings.
/// </summary>
public sealed class PrivacySettings
{
    /// <summary>
    /// Who can see online status.
    /// </summary>
    public OnlineStatusSetting OnlineStatus { get; set; } = OnlineStatusSetting.Everyone;

    /// <summary>
    /// Who can send private messages.
    /// </summary>
    public PrivateMessageSetting PrivateMessages { get; set; } = PrivateMessageSetting.Everyone;

    /// <summary>
    /// Who can send trade requests.
    /// </summary>
    public TradeRequestSetting TradeRequests { get; set; } = TradeRequestSetting.Everyone;

    /// <summary>
    /// Who can send duel requests.
    /// </summary>
    public DuelRequestSetting DuelRequests { get; set; } = DuelRequestSetting.Everyone;
}

public enum OnlineStatusSetting { Everyone, Friends, Nobody }
public enum PrivateMessageSetting { Everyone, Friends, Nobody }
public enum TradeRequestSetting { Everyone, Friends, Nobody }
public enum DuelRequestSetting { Everyone, Friends, Nobody }

/// <summary>
/// Result of a social operation.
/// </summary>
public readonly record struct SocialResult(bool Success, string? Message = null)
{
    public static SocialResult Fail(string message) => new(false, message);
    public static readonly SocialResult Success = new(true);
}

/// <summary>
/// Manages private messaging.
/// </summary>
public sealed class PrivateMessageManager
{
    private readonly WorldService _worldService;
    private int _messageCounter;

    public PrivateMessageManager(WorldService worldService)
    {
        _worldService = worldService;
    }

    /// <summary>
    /// Sends a private message between players.
    /// </summary>
    public MessageResult SendMessage(Player sender, long recipientHash, string message)
    {
        if (string.IsNullOrWhiteSpace(message))
            return MessageResult.Fail("Message cannot be empty.");

        if (message.Length > 80)
            message = message[..80];

        var recipient = _worldService.GetPlayerByHash(recipientHash);
        if (recipient is null)
            return MessageResult.Fail("That player is not online.");

        // Check privacy settings
        var canMessage = recipient.PrivacySettings.PrivateMessages switch
        {
            PrivateMessageSetting.Everyone => true,
            PrivateMessageSetting.Friends => recipient.Social.IsFriend(sender.UsernameHash),
            PrivateMessageSetting.Nobody => false,
            _ => true
        };

        if (!canMessage)
            return MessageResult.Fail("That player is not accepting private messages.");

        // Check ignore list
        if (recipient.Social.IsIgnored(sender.UsernameHash))
            return MessageResult.Fail("That player is not accepting private messages.");

        // Generate message ID
        var messageId = Interlocked.Increment(ref _messageCounter);

        // Deliver message
        recipient.ReceivePrivateMessage(sender.UsernameHash, messageId, message);

        return MessageResult.Ok(messageId);
    }
}

/// <summary>
/// Result of sending a message.
/// </summary>
public readonly record struct MessageResult(bool Success, int MessageId = 0, string? Error = null)
{
    public static MessageResult Fail(string error) => new(false, Error: error);
    public static MessageResult Ok(int messageId) => new(true, messageId);
}
