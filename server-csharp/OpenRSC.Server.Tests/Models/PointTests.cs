using FluentAssertions;
using OpenRSC.Server.Models;

namespace OpenRSC.Server.Tests.Models;

/// <summary>
/// Tests for the Point record struct.
/// </summary>
public class PointTests
{
    [Fact]
    public void Point_ShouldHaveValueEquality()
    {
        // Arrange
        var point1 = new Point(10, 20);
        var point2 = new Point(10, 20);
        var point3 = new Point(10, 21);

        // Assert - record structs have value equality by default
        point1.Should().Be(point2);
        point1.Should().NotBe(point3);
        (point1 == point2).Should().BeTrue();
    }

    [Fact]
    public void DistanceTo_ShouldCalculatePythagoreanDistance()
    {
        // Arrange
        var origin = new Point(0, 0);
        var point = new Point(3, 4);

        // Act
        var distance = origin.DistanceTo(point);

        // Assert - 3-4-5 triangle
        distance.Should().Be(5.0);
    }

    [Fact]
    public void WithinRange_ShouldReturnTrue_WhenInRange()
    {
        // Arrange
        var center = new Point(100, 100);
        var nearby = new Point(101, 101);
        var farAway = new Point(200, 200);

        // Assert
        nearby.WithinRange(center, 2).Should().BeTrue();
        farAway.WithinRange(center, 2).Should().BeFalse();
    }

    [Fact]
    public void InBounds_ShouldCheckRectangularBounds()
    {
        // Arrange
        var inside = new Point(50, 50);
        var outside = new Point(150, 50);

        // Assert
        inside.InBounds(0, 0, 100, 100).Should().BeTrue();
        outside.InBounds(0, 0, 100, 100).Should().BeFalse();
    }

    [Fact]
    public void Translate_ShouldReturnNewPoint()
    {
        // Arrange
        var original = new Point(10, 20);

        // Act
        var translated = original.Translate(5, -5);

        // Assert - original should be unchanged (immutable)
        original.Should().Be(new Point(10, 20));
        translated.Should().Be(new Point(15, 15));
    }

    [Fact]
    public void ToString_ShouldFormatCorrectly()
    {
        // Arrange
        var point = new Point(100, 200);

        // Assert
        point.ToString().Should().Be("(100, 200)");
    }

    [Theory]
    [InlineData(0, 0, 0, 0, 0.0)]
    [InlineData(0, 0, 1, 0, 1.0)]
    [InlineData(0, 0, 0, 1, 1.0)]
    [InlineData(0, 0, 1, 1, 1.4142135623730951)] // sqrt(2)
    public void DistanceTo_ShouldHandleVariousDistances(
        int x1, int y1, int x2, int y2, double expected)
    {
        // Arrange
        var point1 = new Point(x1, y1);
        var point2 = new Point(x2, y2);

        // Act
        var distance = point1.DistanceTo(point2);

        // Assert
        distance.Should().BeApproximately(expected, 0.0001);
    }
}
