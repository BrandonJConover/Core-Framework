using FluentAssertions;
using OpenRSC.Server.Models;
using OpenRSC.Server.Movement;
using Xunit;

namespace OpenRSC.Server.Tests;

public class WalkingQueueTests
{
    [Fact]
    public void AddStep_AddsToQueue()
    {
        var queue = new WalkingQueue();
        queue.AddStep(new Point(1, 1));

        queue.HasSteps.Should().BeTrue();
        queue.Count.Should().Be(1);
    }

    [Fact]
    public void GetNextStep_ReturnsAndRemovesStep()
    {
        var queue = new WalkingQueue();
        var point = new Point(1, 1);
        queue.AddStep(point);

        var result = queue.GetNextStep();

        result.Should().Be(point);
        queue.HasSteps.Should().BeFalse();
    }

    [Fact]
    public void PeekNextStep_ReturnsWithoutRemoving()
    {
        var queue = new WalkingQueue();
        var point = new Point(1, 1);
        queue.AddStep(point);

        var result = queue.PeekNextStep();

        result.Should().Be(point);
        queue.HasSteps.Should().BeTrue();
    }

    [Fact]
    public void Reset_ClearsQueue()
    {
        var queue = new WalkingQueue();
        queue.AddStep(new Point(1, 1));
        queue.AddStep(new Point(2, 2));

        queue.Reset();

        queue.HasSteps.Should().BeFalse();
        queue.Count.Should().Be(0);
    }

    [Fact]
    public void ProcessTick_Walking_MovesOneStep()
    {
        var queue = new WalkingQueue();
        queue.IsRunning = false;
        queue.AddStep(new Point(1, 0));
        queue.AddStep(new Point(2, 0));

        var current = new Point(0, 0);
        var result = queue.ProcessTick(current, (_, _) => true);

        result.HasMovement.Should().BeTrue();
        result.DidRun.Should().BeFalse();
        result.Positions.Should().HaveCount(1);
        result.FinalPosition.Should().Be(new Point(1, 0));
    }

    [Fact]
    public void ProcessTick_Running_MovesTwoSteps()
    {
        var queue = new WalkingQueue();
        queue.IsRunning = true;
        queue.AddStep(new Point(1, 0));
        queue.AddStep(new Point(2, 0));

        var current = new Point(0, 0);
        var result = queue.ProcessTick(current, (_, _) => true);

        result.HasMovement.Should().BeTrue();
        result.DidRun.Should().BeTrue();
        result.Positions.Should().HaveCount(2);
        result.FinalPosition.Should().Be(new Point(2, 0));
    }

    [Fact]
    public void ProcessTick_BlockedPath_ClearsQueueAndStops()
    {
        var queue = new WalkingQueue();
        queue.AddStep(new Point(1, 0));
        queue.AddStep(new Point(2, 0));

        var current = new Point(0, 0);
        var result = queue.ProcessTick(current, (_, _) => false);

        result.HasMovement.Should().BeFalse();
        queue.HasSteps.Should().BeFalse();
    }

    [Fact]
    public void Destination_ReturnsLastPoint()
    {
        var queue = new WalkingQueue();
        queue.AddStep(new Point(1, 0));
        queue.AddStep(new Point(2, 0));
        queue.AddStep(new Point(3, 0));

        queue.Destination.Should().Be(new Point(3, 0));
    }

    [Fact]
    public void AddStep_RespectsMaxSize()
    {
        var queue = new WalkingQueue(maxSize: 3);
        queue.AddStep(new Point(1, 0));
        queue.AddStep(new Point(2, 0));
        queue.AddStep(new Point(3, 0));
        queue.AddStep(new Point(4, 0)); // Should be ignored

        queue.Count.Should().Be(3);
        queue.Destination.Should().Be(new Point(3, 0));
    }
}
