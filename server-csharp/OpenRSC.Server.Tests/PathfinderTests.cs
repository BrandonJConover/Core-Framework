using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using OpenRSC.Server.Models;
using OpenRSC.Server.World;
using Xunit;

namespace OpenRSC.Server.Tests;

public class PathfinderTests
{
    private readonly WorldMap _worldMap;
    private readonly Pathfinder _pathfinder;

    public PathfinderTests()
    {
        _worldMap = new WorldMap(NullLogger<WorldMap>.Instance);
        _pathfinder = new Pathfinder(_worldMap);
    }

    [Fact]
    public void FindPath_SameStartAndEnd_ReturnsSinglePoint()
    {
        var start = new Point(10, 10);
        var path = _pathfinder.FindPath(start, start);

        path.Should().HaveCount(1);
        path[0].Should().Be(start);
    }

    [Fact]
    public void FindPath_AdjacentPoints_ReturnsDirectPath()
    {
        var start = new Point(10, 10);
        var end = new Point(11, 10);
        var path = _pathfinder.FindPath(start, end);

        path.Should().HaveCount(2);
        path[0].Should().Be(start);
        path[1].Should().Be(end);
    }

    [Fact]
    public void FindPath_DiagonalPoints_ReturnsPath()
    {
        var start = new Point(10, 10);
        var end = new Point(11, 11);
        var path = _pathfinder.FindPath(start, end);

        path.Should().HaveCount(2);
        path[0].Should().Be(start);
        path[1].Should().Be(end);
    }

    [Fact]
    public void FindPath_LongerDistance_ReturnsOptimalPath()
    {
        var start = new Point(10, 10);
        var end = new Point(15, 15);
        var path = _pathfinder.FindPath(start, end);

        // Diagonal path should be 6 steps (including start)
        path.Should().HaveCount(6);
        path[0].Should().Be(start);
        path[^1].Should().Be(end);
    }

    [Fact]
    public void FindPathToRange_AlreadyInRange_ReturnsCurrentPosition()
    {
        var start = new Point(10, 10);
        var target = new Point(11, 10);
        var path = _pathfinder.FindPathToRange(start, target, 1);

        path.Should().HaveCount(1);
        path[0].Should().Be(start);
    }

    [Fact]
    public void FindPathToRange_OutOfRange_ReturnsPathToRange()
    {
        var start = new Point(10, 10);
        var target = new Point(20, 10);
        var path = _pathfinder.FindPathToRange(start, target, 1);

        path.Should().NotBeEmpty();
        var finalPos = path[^1];
        finalPos.WithinRange(target, 1).Should().BeTrue();
    }

    [Fact]
    public void Path_GetNextStep_AdvancesThroughPath()
    {
        var points = new List<Point>
        {
            new(0, 0),
            new(1, 0),
            new(2, 0)
        };
        var path = new Path(points);

        path.IsComplete.Should().BeFalse();
        path.GetNextStep().Should().Be(new Point(0, 0));
        path.GetNextStep().Should().Be(new Point(1, 0));
        path.GetNextStep().Should().Be(new Point(2, 0));
        path.IsComplete.Should().BeTrue();
        path.GetNextStep().Should().BeNull();
    }

    [Fact]
    public void Path_RemainingSteps_ReturnsCorrectCount()
    {
        var points = new List<Point>
        {
            new(0, 0),
            new(1, 0),
            new(2, 0)
        };
        var path = new Path(points);

        path.RemainingSteps.Should().Be(3);
        path.GetNextStep();
        path.RemainingSteps.Should().Be(2);
    }

    [Fact]
    public void Path_Skip_SkipsSteps()
    {
        var points = new List<Point>
        {
            new(0, 0),
            new(1, 0),
            new(2, 0),
            new(3, 0)
        };
        var path = new Path(points);

        path.Skip(2);
        path.GetNextStep().Should().Be(new Point(2, 0));
    }
}
