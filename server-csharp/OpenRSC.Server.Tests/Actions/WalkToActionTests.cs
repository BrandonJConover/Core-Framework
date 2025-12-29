using FluentAssertions;
using Microsoft.Extensions.Options;
using Moq;
using OpenRSC.Server.Actions;
using OpenRSC.Server.Configuration;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Tests.Actions;

/// <summary>
/// Tests for the WalkToAction retry mechanism.
/// </summary>
public class WalkToActionTests
{
    private readonly Mock<IOptions<ServerSettings>> _serverSettingsMock;
    private readonly Mock<IOptions<ActionRetrySettings>> _actionRetrySettingsMock;

    public WalkToActionTests()
    {
        _serverSettingsMock = new Mock<IOptions<ServerSettings>>();
        _serverSettingsMock.Setup(x => x.Value).Returns(new ServerSettings());

        _actionRetrySettingsMock = new Mock<IOptions<ActionRetrySettings>>();
        _actionRetrySettingsMock.Setup(x => x.Value).Returns(new ActionRetrySettings
        {
            Enabled = true,
            MaxRetries = 10
        });
    }

    private Player CreateTestPlayer(string username = "TestPlayer")
    {
        return new Player(
            username,
            new Point(100, 100),
            _serverSettingsMock.Object,
            _actionRetrySettingsMock.Object);
    }

    [Fact]
    public void OnAttemptFailed_ShouldIncrementRetryCount()
    {
        // Arrange
        var player = CreateTestPlayer();
        var action = new TestWalkToAction(player, new Point(105, 105), shouldExecute: false);

        // Act
        action.OnAttemptFailed(1);
        action.OnAttemptFailed(2);
        action.OnAttemptFailed(3);

        // Assert
        action.RetryAttempts.Should().Be(3);
    }

    [Fact]
    public void OnAttemptFailed_ShouldReturnFalse_WhenMaxRetriesExceeded()
    {
        // Arrange
        var player = CreateTestPlayer();
        var action = new TestWalkToAction(player, new Point(105, 105), shouldExecute: false);
        action.MaxRetries = 3;

        // Act
        var result1 = action.OnAttemptFailed(1);
        var result2 = action.OnAttemptFailed(2);
        var result3 = action.OnAttemptFailed(3);

        // Assert
        result1.Should().BeTrue();
        result2.Should().BeTrue();
        result3.Should().BeFalse();
    }

    [Fact]
    public void OnAttemptFailed_ShouldReturnFalse_WhenRetryDisabled()
    {
        // Arrange
        var player = CreateTestPlayer();
        var action = new TestWalkToAction(player, new Point(105, 105), shouldExecute: false);
        action.RetryEnabled = false;

        // Act
        var result = action.OnAttemptFailed(1);

        // Assert
        result.Should().BeFalse();
        action.RetryAttempts.Should().Be(0);
    }

    [Fact]
    public void HasExceededRetryLimit_ShouldReturnTrue_WhenLimitReached()
    {
        // Arrange
        var player = CreateTestPlayer();
        var action = new TestWalkToAction(player, new Point(105, 105), shouldExecute: false);
        action.MaxRetries = 2;

        // Simulate failed attempts
        action.OnAttemptFailed(1);
        action.OnAttemptFailed(2);

        // Assert
        action.HasExceededRetryLimit.Should().BeTrue();
    }

    [Fact]
    public void ShouldExecute_ShouldReturnFalse_WhenAlreadyExecuted()
    {
        // Arrange
        var player = CreateTestPlayer();
        var action = new TestWalkToAction(player, new Point(100, 100), shouldExecute: true);

        // Execute the action
        action.Execute();

        // Assert
        action.ShouldExecute().Should().BeFalse();
        action.IsExecuted.Should().BeTrue();
    }

    [Fact]
    public void Execute_ShouldCallExecuteInternal()
    {
        // Arrange
        var player = CreateTestPlayer();
        var action = new TestWalkToAction(player, new Point(100, 100), shouldExecute: true);

        // Act
        action.Execute();

        // Assert
        action.ExecuteInternalCalled.Should().BeTrue();
    }

    [Fact]
    public void ResetRetryAttempts_ShouldClearCounter()
    {
        // Arrange
        var player = CreateTestPlayer();
        var action = new TestWalkToAction(player, new Point(105, 105), shouldExecute: false);

        action.OnAttemptFailed(1);
        action.OnAttemptFailed(2);
        action.RetryAttempts.Should().Be(2);

        // Act
        action.ResetRetryAttempts();

        // Assert
        action.RetryAttempts.Should().Be(0);
    }

    /// <summary>
    /// Test implementation of WalkToAction for unit testing.
    /// </summary>
    private class TestWalkToAction : WalkToAction
    {
        private readonly bool _shouldExecute;
        public bool ExecuteInternalCalled { get; private set; }

        public TestWalkToAction(Player player, Point location, bool shouldExecute)
            : base(player, location)
        {
            _shouldExecute = shouldExecute;
        }

        protected override void ExecuteInternal()
        {
            ExecuteInternalCalled = true;
        }

        protected override bool ShouldExecuteInternal()
        {
            return _shouldExecute;
        }
    }
}
