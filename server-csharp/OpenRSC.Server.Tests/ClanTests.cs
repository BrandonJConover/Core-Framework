using FluentAssertions;
using OpenRSC.Server.Clan;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using Xunit;

namespace OpenRSC.Server.Tests;

public class ClanTests
{
    private Player CreatePlayer(string name) => new(name, new Point(0, 0));

    [Fact]
    public void ClanManager_CreateClan_Succeeds()
    {
        var manager = new ClanManager();
        var leader = CreatePlayer("Leader");

        var result = manager.CreateClan(leader, "Test Clan", "TC");

        result.Success.Should().BeTrue();
        var clan = manager.GetPlayerClan(leader);
        clan.Should().NotBeNull();
        clan!.Name.Should().Be("Test Clan");
        clan.Tag.Should().Be("TC");
    }

    [Fact]
    public void ClanManager_CreateClan_AlreadyInClan_Fails()
    {
        var manager = new ClanManager();
        var leader = CreatePlayer("Leader");
        manager.CreateClan(leader, "Clan 1", "C1");

        var result = manager.CreateClan(leader, "Clan 2", "C2");

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("already in a clan");
    }

    [Fact]
    public void Clan_LeaderHasCorrectRank()
    {
        var manager = new ClanManager();
        var leader = CreatePlayer("Leader");
        manager.CreateClan(leader, "Test Clan", "TC");

        var clan = manager.GetPlayerClan(leader)!;
        var member = clan.GetMember(leader);

        member.Should().NotBeNull();
        member!.Rank.Should().Be(ClanRank.Leader);
    }

    [Fact]
    public void ClanManager_InvitePlayer_Succeeds()
    {
        var manager = new ClanManager();
        var leader = CreatePlayer("Leader");
        var newMember = CreatePlayer("NewMember");
        manager.CreateClan(leader, "Test Clan", "TC");

        var result = manager.InvitePlayer(leader, newMember);

        result.Success.Should().BeTrue();
    }

    [Fact]
    public void ClanManager_AcceptInvite_JoinsClan()
    {
        var manager = new ClanManager();
        var leader = CreatePlayer("Leader");
        var newMember = CreatePlayer("NewMember");
        manager.CreateClan(leader, "Test Clan", "TC");
        manager.InvitePlayer(leader, newMember);

        var result = manager.AcceptInvite(newMember);

        result.Success.Should().BeTrue();
        var clan = manager.GetPlayerClan(newMember);
        clan.Should().NotBeNull();
        clan!.Name.Should().Be("Test Clan");
    }

    [Fact]
    public void ClanManager_LeaveClan_RemovesMember()
    {
        var manager = new ClanManager();
        var leader = CreatePlayer("Leader");
        var member = CreatePlayer("Member");
        manager.CreateClan(leader, "Test Clan", "TC");
        manager.InvitePlayer(leader, member);
        manager.AcceptInvite(member);

        var result = manager.LeaveClan(member);

        result.Success.Should().BeTrue();
        manager.GetPlayerClan(member).Should().BeNull();
    }

    [Fact]
    public void ClanManager_LeaderCannotLeave()
    {
        var manager = new ClanManager();
        var leader = CreatePlayer("Leader");
        manager.CreateClan(leader, "Test Clan", "TC");

        var result = manager.LeaveClan(leader);

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("transfer leadership");
    }

    [Fact]
    public void Clan_HasPermission_ChecksRank()
    {
        var manager = new ClanManager();
        var leader = CreatePlayer("Leader");
        var member = CreatePlayer("Member");
        manager.CreateClan(leader, "Test Clan", "TC");
        manager.InvitePlayer(leader, member);
        manager.AcceptInvite(member);

        var clan = manager.GetPlayerClan(leader)!;

        clan.HasPermission(leader, ClanPermission.DisbandClan).Should().BeTrue();
        clan.HasPermission(member, ClanPermission.DisbandClan).Should().BeFalse();
    }
}
