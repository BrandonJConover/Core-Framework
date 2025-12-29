using FluentAssertions;
using OpenRSC.Server.Duel;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using Xunit;

namespace OpenRSC.Server.Tests;

public class DuelTests
{
    private Player CreatePlayer(string name) => new(name, new Point(0, 0));

    [Fact]
    public void DuelSession_Create_SetsConfiguring()
    {
        var p1 = CreatePlayer("Player1");
        var p2 = CreatePlayer("Player2");

        var session = new DuelSession(p1, p2);

        session.State.Should().Be(DuelState.Configuring);
        session.Player1.Should().Be(p1);
        session.Player2.Should().Be(p2);
    }

    [Fact]
    public void DuelSession_ToggleRule_TogglesCorrectly()
    {
        var p1 = CreatePlayer("Player1");
        var p2 = CreatePlayer("Player2");
        var session = new DuelSession(p1, p2);

        session.ToggleRule(p1, DuelRules.NoMagic);
        session.HasRule(DuelRules.NoMagic).Should().BeTrue();

        session.ToggleRule(p1, DuelRules.NoMagic);
        session.HasRule(DuelRules.NoMagic).Should().BeFalse();
    }

    [Fact]
    public void DuelSession_Accept_RequiresBothPlayers()
    {
        var p1 = CreatePlayer("Player1");
        var p2 = CreatePlayer("Player2");
        var session = new DuelSession(p1, p2);

        session.Accept(p1);
        session.State.Should().Be(DuelState.Configuring);
        session.Player1Accepted.Should().BeTrue();
        session.Player2Accepted.Should().BeFalse();

        session.Accept(p2);
        session.State.Should().Be(DuelState.FirstConfirm);
    }

    [Fact]
    public void DuelSession_GetOpponent_ReturnsCorrectPlayer()
    {
        var p1 = CreatePlayer("Player1");
        var p2 = CreatePlayer("Player2");
        var session = new DuelSession(p1, p2);

        session.GetOpponent(p1).Should().Be(p2);
        session.GetOpponent(p2).Should().Be(p1);
    }

    [Fact]
    public void DuelSession_IsParticipant_ReturnsCorrectly()
    {
        var p1 = CreatePlayer("Player1");
        var p2 = CreatePlayer("Player2");
        var p3 = CreatePlayer("Player3");
        var session = new DuelSession(p1, p2);

        session.IsParticipant(p1).Should().BeTrue();
        session.IsParticipant(p2).Should().BeTrue();
        session.IsParticipant(p3).Should().BeFalse();
    }

    [Fact]
    public void DuelManager_RequestDuel_SendsRequest()
    {
        var manager = new DuelManager();
        var p1 = CreatePlayer("Player1");
        var p2 = CreatePlayer("Player2");

        var result = manager.RequestDuel(p1, p2);

        result.Success.Should().BeTrue();
    }

    [Fact]
    public void DuelManager_RequestDuel_SelfDuel_Fails()
    {
        var manager = new DuelManager();
        var p1 = CreatePlayer("Player1");

        var result = manager.RequestDuel(p1, p1);

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("yourself");
    }

    [Fact]
    public void DuelManager_MutualRequest_StartsDuel()
    {
        var manager = new DuelManager();
        var p1 = CreatePlayer("Player1");
        var p2 = CreatePlayer("Player2");

        // P1 requests P2
        manager.RequestDuel(p1, p2);

        // P2 requests P1 (should start duel)
        var result = manager.RequestDuel(p2, p1);

        result.Success.Should().BeTrue();
        manager.GetActiveDuel(p1).Should().NotBeNull();
        manager.GetActiveDuel(p2).Should().NotBeNull();
    }
}
