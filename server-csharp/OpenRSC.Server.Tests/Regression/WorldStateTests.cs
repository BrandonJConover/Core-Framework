using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.World;
using Xunit;

namespace OpenRSC.Server.Tests.Regression;

/// <summary>
/// Regression tests for world state and map systems.
/// These tests ensure world mechanics remain consistent.
/// </summary>
public class WorldStateTests
{
    #region Point Operations

    [Fact]
    public void Point_DistanceTo_CalculatesCorrectly()
    {
        var p1 = new Point(0, 0);
        var p2 = new Point(3, 4);

        var distance = p1.DistanceTo(p2);

        distance.Should().Be(5); // 3-4-5 triangle
    }

    [Fact]
    public void Point_DistanceTo_SamePoint_IsZero()
    {
        var p = new Point(100, 100);

        p.DistanceTo(p).Should().Be(0);
    }

    [Fact]
    public void Point_WithinRange_ReturnsTrue_WhenInRange()
    {
        var p1 = new Point(0, 0);
        var p2 = new Point(3, 4);

        p1.WithinRange(p2, 5).Should().BeTrue();
    }

    [Fact]
    public void Point_WithinRange_ReturnsFalse_WhenOutOfRange()
    {
        var p1 = new Point(0, 0);
        var p2 = new Point(3, 4);

        p1.WithinRange(p2, 4).Should().BeFalse();
    }

    [Fact]
    public void Point_Equality_Works()
    {
        var p1 = new Point(10, 20);
        var p2 = new Point(10, 20);
        var p3 = new Point(10, 21);

        p1.Should().Be(p2);
        p1.Should().NotBe(p3);
    }

    #endregion

    #region Region Management

    [Fact]
    public void Region_ContainsCorrectTiles()
    {
        var region = new Region(0, 0);

        // Region 0,0 should contain tiles from (0,0) to (47,47)
        region.Contains(new Point(0, 0)).Should().BeTrue();
        region.Contains(new Point(47, 47)).Should().BeTrue();
        region.Contains(new Point(48, 0)).Should().BeFalse();
    }

    [Fact]
    public void Region_GetTile_ReturnsCorrectTile()
    {
        var region = new Region(0, 0);
        var tile = region.GetTile(new Point(10, 10));

        tile.Should().NotBeNull();
        tile!.Location.Should().Be(new Point(10, 10));
    }

    [Fact]
    public void Region_GetTile_OutOfBounds_ReturnsNull()
    {
        var region = new Region(0, 0);

        region.GetTile(new Point(100, 100)).Should().BeNull();
    }

    [Fact]
    public void Region_Players_TrackCorrectly()
    {
        var region = new Region(0, 0);
        var player = new Player("Test", new Point(10, 10));

        region.AddPlayer(player);

        region.Players.Should().Contain(player);
    }

    [Fact]
    public void Region_RemovePlayer_Works()
    {
        var region = new Region(0, 0);
        var player = new Player("Test", new Point(10, 10));
        region.AddPlayer(player);

        region.RemovePlayer(player);

        region.Players.Should().NotContain(player);
    }

    [Fact]
    public void Region_Npcs_TrackCorrectly()
    {
        var region = new Region(0, 0);
        var npc = new Npc(1, new Point(10, 10));

        region.AddNpc(npc);

        region.Npcs.Should().Contain(npc);
    }

    #endregion

    #region WorldMap

    [Fact]
    public void WorldMap_GetRegion_CreatesIfNotExists()
    {
        var worldMap = new WorldMap(NullLogger<WorldMap>.Instance);

        var region = worldMap.GetRegion(new Point(100, 100));

        region.Should().NotBeNull();
    }

    [Fact]
    public void WorldMap_GetRegion_ReturnsSameRegion()
    {
        var worldMap = new WorldMap(NullLogger<WorldMap>.Instance);

        var region1 = worldMap.GetRegion(new Point(10, 10));
        var region2 = worldMap.GetRegion(new Point(20, 20)); // Same region

        region1.Should().Be(region2);
    }

    [Fact]
    public void WorldMap_GetTile_ReturnsCorrectTile()
    {
        var worldMap = new WorldMap(NullLogger<WorldMap>.Instance);

        var tile = worldMap.GetTile(new Point(100, 100));

        tile.Should().NotBeNull();
        tile!.Location.Should().Be(new Point(100, 100));
    }

    [Fact]
    public void WorldMap_IsValidLocation_ChecksBounds()
    {
        WorldMap.IsValidLocation(new Point(0, 0)).Should().BeTrue();
        WorldMap.IsValidLocation(new Point(500, 500)).Should().BeTrue();
        WorldMap.IsValidLocation(new Point(-1, 0)).Should().BeFalse();
        WorldMap.IsValidLocation(new Point(0, -1)).Should().BeFalse();
    }

    #endregion

    #region Tile Properties

    [Fact]
    public void Tile_DefaultsToNotBlocked()
    {
        var tile = new Tile(new Point(0, 0));

        tile.IsBlocked.Should().BeFalse();
    }

    [Fact]
    public void Tile_AddBlock_BlocksMovement()
    {
        var tile = new Tile(new Point(0, 0));

        tile.AddBlock(TraversalFlags.FullBlock);

        tile.IsBlocked.Should().BeTrue();
    }

    [Fact]
    public void Tile_RemoveBlock_UnblocksMovement()
    {
        var tile = new Tile(new Point(0, 0));
        tile.AddBlock(TraversalFlags.FullBlock);

        tile.RemoveBlock(TraversalFlags.FullBlock);

        tile.IsBlocked.Should().BeFalse();
    }

    [Fact]
    public void Tile_CanTraverse_ChecksDirection()
    {
        var tile = new Tile(new Point(0, 0));

        tile.CanTraverse(Direction.North).Should().BeTrue();

        tile.AddBlock(TraversalFlags.BlockNorth);

        tile.CanTraverse(Direction.North).Should().BeFalse();
        tile.CanTraverse(Direction.South).Should().BeTrue();
    }

    #endregion

    #region Pathfinding

    [Fact]
    public void Pathfinder_SameLocation_ReturnsSinglePoint()
    {
        var worldMap = new WorldMap(NullLogger<WorldMap>.Instance);
        var pathfinder = new Pathfinder(worldMap);
        var point = new Point(100, 100);

        var path = pathfinder.FindPath(point, point);

        path.Should().HaveCount(1);
        path[0].Should().Be(point);
    }

    [Fact]
    public void Pathfinder_Adjacent_ReturnsDirectPath()
    {
        var worldMap = new WorldMap(NullLogger<WorldMap>.Instance);
        var pathfinder = new Pathfinder(worldMap);
        var start = new Point(100, 100);
        var end = new Point(101, 100);

        var path = pathfinder.FindPath(start, end);

        path.Should().HaveCount(2);
        path[0].Should().Be(start);
        path[1].Should().Be(end);
    }

    [Fact]
    public void Pathfinder_FindsOptimalPath()
    {
        var worldMap = new WorldMap(NullLogger<WorldMap>.Instance);
        var pathfinder = new Pathfinder(worldMap);
        var start = new Point(100, 100);
        var end = new Point(105, 105);

        var path = pathfinder.FindPath(start, end);

        // Diagonal path should be 6 steps (including start)
        path.Should().HaveCount(6);
        path[0].Should().Be(start);
        path[^1].Should().Be(end);
    }

    [Fact]
    public void Pathfinder_PathToRange_StopsInRange()
    {
        var worldMap = new WorldMap(NullLogger<WorldMap>.Instance);
        var pathfinder = new Pathfinder(worldMap);
        var start = new Point(100, 100);
        var target = new Point(110, 100);

        var path = pathfinder.FindPathToRange(start, target, 2);

        path.Should().NotBeEmpty();
        var finalPos = path[^1];
        finalPos.WithinRange(target, 2).Should().BeTrue();
    }

    #endregion

    #region Ground Items

    [Fact]
    public void GroundItem_IsVisibleToDropper()
    {
        var player = new Player("Test", new Point(0, 0));
        var item = new GroundItem(1, 10, new Point(0, 0), player);

        item.IsVisibleTo(player).Should().BeTrue();
    }

    [Fact]
    public void GroundItem_NotVisibleToOthers_Initially()
    {
        var dropper = new Player("Dropper", new Point(0, 0));
        var other = new Player("Other", new Point(0, 0));
        var item = new GroundItem(1, 10, new Point(0, 0), dropper);

        item.IsVisibleTo(other).Should().BeFalse();
    }

    [Fact]
    public void GroundItem_WithNoDropper_VisibleToAll()
    {
        var player = new Player("Test", new Point(0, 0));
        var item = new GroundItem(1, 10, new Point(0, 0));

        item.IsVisibleTo(player).Should().BeTrue();
    }

    #endregion
}
