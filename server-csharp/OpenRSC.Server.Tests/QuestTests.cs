using FluentAssertions;
using Moq;
using OpenRSC.Server.Entities;
using OpenRSC.Server.Models;
using OpenRSC.Server.Quests;
using OpenRSC.Server.Skills;
using Xunit;

namespace OpenRSC.Server.Tests;

public class QuestTests
{
    private Player CreatePlayer() => new("TestPlayer", new Point(0, 0));

    private Mock<IQuestRepository> CreateMockRepo(params QuestDefinition[] quests)
    {
        var mock = new Mock<IQuestRepository>();
        foreach (var quest in quests)
        {
            mock.Setup(r => r.GetById(quest.Id)).Returns(quest);
        }
        mock.Setup(r => r.GetAll()).Returns(quests);
        return mock;
    }

    private QuestDefinition CreateQuest(int id = 1, int requiredLevel = 1, int[] questReqs = null!)
    {
        return new QuestDefinition
        {
            Id = id,
            Name = $"Test Quest {id}",
            Description = "A test quest",
            QuestPoints = 1,
            SkillRequirements = requiredLevel > 1
                ? new Dictionary<Skill, int> { [Skill.Attack] = requiredLevel }
                : new Dictionary<Skill, int>(),
            QuestRequirements = questReqs ?? Array.Empty<int>()
        };
    }

    [Fact]
    public void StartQuest_Valid_SetsStatusToInProgress()
    {
        var player = CreatePlayer();
        var quest = CreateQuest();
        var repo = CreateMockRepo(quest);
        var quests = new PlayerQuests(player, repo.Object);

        var result = quests.StartQuest(1);

        result.Success.Should().BeTrue();
        quests.GetStatus(1).Should().Be(QuestStatus.InProgress);
    }

    [Fact]
    public void StartQuest_InsufficientSkillLevel_Fails()
    {
        var player = CreatePlayer();
        var quest = CreateQuest(requiredLevel: 50);
        var repo = CreateMockRepo(quest);
        var quests = new PlayerQuests(player, repo.Object);

        var result = quests.StartQuest(1);

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("level 50");
    }

    [Fact]
    public void StartQuest_MissingQuestRequirement_Fails()
    {
        var player = CreatePlayer();
        var prereq = CreateQuest(id: 1);
        var quest = CreateQuest(id: 2, questReqs: new[] { 1 });
        var repo = CreateMockRepo(prereq, quest);
        var quests = new PlayerQuests(player, repo.Object);

        var result = quests.StartQuest(2);

        result.Success.Should().BeFalse();
        result.Message.Should().Contain("complete");
    }

    [Fact]
    public void StartQuest_WithCompletedPrereq_Succeeds()
    {
        var player = CreatePlayer();
        var prereq = CreateQuest(id: 1);
        var quest = CreateQuest(id: 2, questReqs: new[] { 1 });
        var repo = CreateMockRepo(prereq, quest);
        var quests = new PlayerQuests(player, repo.Object);

        quests.StartQuest(1);
        quests.CompleteQuest(1);

        var result = quests.StartQuest(2);

        result.Success.Should().BeTrue();
    }

    [Fact]
    public void CompleteQuest_GrantsQuestPoints()
    {
        var player = CreatePlayer();
        var quest = CreateQuest();
        var repo = CreateMockRepo(quest);
        var quests = new PlayerQuests(player, repo.Object);

        quests.StartQuest(1);
        quests.CompleteQuest(1);

        quests.QuestPoints.Should().Be(1);
        quests.IsCompleted(1).Should().BeTrue();
    }

    [Fact]
    public void AdvanceStage_UpdatesCurrentStage()
    {
        var player = CreatePlayer();
        var quest = CreateQuest();
        var repo = CreateMockRepo(quest);
        var quests = new PlayerQuests(player, repo.Object);

        quests.StartQuest(1);
        quests.AdvanceStage(1, 5);

        quests.GetStage(1).Should().Be(5);
    }

    [Fact]
    public void GetStatus_NotStarted_ReturnsNotStarted()
    {
        var player = CreatePlayer();
        var repo = CreateMockRepo();
        var quests = new PlayerQuests(player, repo.Object);

        quests.GetStatus(999).Should().Be(QuestStatus.NotStarted);
    }
}
