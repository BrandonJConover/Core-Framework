using System.Text.Json;
using OpenRSC.Server.Simulation;

namespace OpenRSC.Server.Simulation;

/// <summary>
/// Q-Learning agent for training bot behavior.
/// Uses tabular Q-learning with epsilon-greedy exploration.
/// </summary>
public sealed class QLearningAgent
{
    private readonly Random _random;
    private readonly Dictionary<string, Dictionary<BotActionType, double>> _qTable = new();

    // Hyperparameters
    private double _learningRate = 0.1;
    private double _discountFactor = 0.95;
    private double _epsilon = 0.3; // Exploration rate
    private double _epsilonDecay = 0.9999;
    private double _minEpsilon = 0.05;

    // Available actions
    private static readonly BotActionType[] AllActions =
    {
        BotActionType.Idle,
        BotActionType.Attack,
        BotActionType.Gather,
        BotActionType.Bank,
        BotActionType.Eat,
        BotActionType.Train,
        BotActionType.Walk,
        BotActionType.Flee
    };

    // Training statistics
    public int TotalUpdates { get; private set; }
    public double CurrentEpsilon => _epsilon;
    public int StatesExplored => _qTable.Count;

    public QLearningAgent(Random random)
    {
        _random = random;
        InitializeDefaultQValues();
    }

    /// <summary>
    /// Initialize Q-values with domain knowledge (transfer learning from game rules).
    /// </summary>
    private void InitializeDefaultQValues()
    {
        // We'll initialize on-demand, but set some priors
    }

    /// <summary>
    /// Gets or creates Q-values for a state.
    /// </summary>
    private Dictionary<BotActionType, double> GetOrCreateQValues(string stateKey)
    {
        if (!_qTable.TryGetValue(stateKey, out var qValues))
        {
            // Initialize with small random values + domain knowledge
            qValues = new Dictionary<BotActionType, double>();
            foreach (var action in AllActions)
            {
                // Default values based on action type
                qValues[action] = action switch
                {
                    BotActionType.Train => 0.3, // Training is generally good
                    BotActionType.Gather => 0.25,
                    BotActionType.Attack => 0.2,
                    BotActionType.Eat => 0.1,
                    BotActionType.Bank => 0.1,
                    BotActionType.Walk => 0.05,
                    BotActionType.Flee => 0.0,
                    BotActionType.Idle => 0.0,
                    _ => 0.0
                };
                // Add small random noise
                qValues[action] += (_random.NextDouble() - 0.5) * 0.1;
            }
            _qTable[stateKey] = qValues;
        }
        return qValues;
    }

    /// <summary>
    /// Selects an action using epsilon-greedy policy.
    /// </summary>
    public BotActionType SelectAction(GameState state, BotProfile profile)
    {
        var stateKey = state.ToStateKey();
        var qValues = GetOrCreateQValues(stateKey);

        // Apply profile preferences as action masks/bonuses
        var adjustedQValues = ApplyProfilePreferences(qValues, state, profile);

        // Epsilon-greedy selection
        if (_random.NextDouble() < _epsilon)
        {
            // Explore: random action, but weighted by profile
            return SelectWeightedRandomAction(adjustedQValues);
        }

        // Exploit: best action
        return adjustedQValues.OrderByDescending(kv => kv.Value).First().Key;
    }

    /// <summary>
    /// Adjusts Q-values based on the bot's profile preferences.
    /// </summary>
    private Dictionary<BotActionType, double> ApplyProfilePreferences(
        Dictionary<BotActionType, double> qValues,
        GameState state,
        BotProfile profile)
    {
        var adjusted = new Dictionary<BotActionType, double>(qValues);

        // Combat-focused profiles prefer attacking
        if (profile.Aggression > 0.5)
        {
            adjusted[BotActionType.Attack] *= 1.0 + profile.Aggression;
        }

        // Cautious profiles prefer eating/fleeing when low health
        if (state.HealthPercent < 0.5 && profile.Caution > 0.5)
        {
            adjusted[BotActionType.Eat] *= 1.0 + profile.Caution;
            adjusted[BotActionType.Flee] *= 1.0 + profile.Caution * 0.5;
            adjusted[BotActionType.Attack] *= 0.5;
        }

        // Exploration-focused profiles prefer walking
        if (profile.Exploration > 0.5)
        {
            adjusted[BotActionType.Walk] *= 1.0 + profile.Exploration * 0.5;
        }

        // Skillers prefer gathering
        if (profile.PrimaryFocus is Skills.Skill.Woodcutting or Skills.Skill.Mining or Skills.Skill.Fishing)
        {
            adjusted[BotActionType.Gather] *= 1.5;
            adjusted[BotActionType.Attack] *= 0.3;
        }

        // When inventory is getting full, prefer banking
        if (state.InventoryFullness > 0.8)
        {
            adjusted[BotActionType.Bank] *= 2.0;
        }

        // When near bank and have items, prefer banking
        if (state.NearBank && state.InventoryFullness > 0.3)
        {
            adjusted[BotActionType.Bank] *= 1.5;
        }

        // Avoid wilderness unless profile allows
        if (state.IsInWilderness && !profile.WillEnterWilderness)
        {
            adjusted[BotActionType.Flee] *= 3.0;
            adjusted[BotActionType.Attack] *= 0.2;
        }

        return adjusted;
    }

    /// <summary>
    /// Selects a random action weighted by Q-values.
    /// </summary>
    private BotActionType SelectWeightedRandomAction(Dictionary<BotActionType, double> qValues)
    {
        // Shift all values to be positive and normalize
        var minValue = qValues.Values.Min();
        var shifted = qValues.ToDictionary(kv => kv.Key, kv => kv.Value - minValue + 0.1);
        var total = shifted.Values.Sum();

        var roll = _random.NextDouble() * total;
        var cumulative = 0.0;

        foreach (var (action, value) in shifted)
        {
            cumulative += value;
            if (roll <= cumulative)
                return action;
        }

        return BotActionType.Idle;
    }

    /// <summary>
    /// Updates Q-values using the Q-learning update rule.
    /// Q(s,a) = Q(s,a) + α * (r + γ * max(Q(s',a')) - Q(s,a))
    /// </summary>
    public void Update(GameState state, BotActionType action, double reward, GameState nextState)
    {
        var stateKey = state.ToStateKey();
        var nextStateKey = nextState.ToStateKey();

        var qValues = GetOrCreateQValues(stateKey);
        var nextQValues = GetOrCreateQValues(nextStateKey);

        var currentQ = qValues[action];
        var maxNextQ = nextQValues.Values.Max();

        // Q-learning update
        var newQ = currentQ + _learningRate * (reward + _discountFactor * maxNextQ - currentQ);
        qValues[action] = newQ;

        TotalUpdates++;

        // Decay epsilon
        _epsilon = Math.Max(_minEpsilon, _epsilon * _epsilonDecay);
    }

    /// <summary>
    /// Gets Q-values for a state (for analysis).
    /// </summary>
    public Dictionary<BotActionType, double> GetQValues(GameState state)
    {
        return GetOrCreateQValues(state.ToStateKey());
    }

    /// <summary>
    /// Saves the Q-table to a file.
    /// </summary>
    public void SaveQTable(string path)
    {
        var data = new QTableData
        {
            QTable = _qTable,
            Epsilon = _epsilon,
            TotalUpdates = TotalUpdates
        };

        var json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(path, json);
    }

    /// <summary>
    /// Loads the Q-table from a file.
    /// </summary>
    public void LoadQTable(string path)
    {
        if (!File.Exists(path))
            return;

        var json = File.ReadAllText(path);
        var data = JsonSerializer.Deserialize<QTableData>(json);

        if (data != null)
        {
            _qTable.Clear();
            foreach (var (key, value) in data.QTable)
            {
                _qTable[key] = value;
            }
            _epsilon = data.Epsilon;
            TotalUpdates = data.TotalUpdates;
        }
    }

    /// <summary>
    /// Resets the learning state.
    /// </summary>
    public void Reset()
    {
        _qTable.Clear();
        _epsilon = 0.3;
        TotalUpdates = 0;
    }

    /// <summary>
    /// Sets hyperparameters.
    /// </summary>
    public void SetHyperparameters(double learningRate, double discountFactor, double epsilon)
    {
        _learningRate = learningRate;
        _discountFactor = discountFactor;
        _epsilon = epsilon;
    }

    private sealed class QTableData
    {
        public Dictionary<string, Dictionary<BotActionType, double>> QTable { get; set; } = new();
        public double Epsilon { get; set; }
        public int TotalUpdates { get; set; }
    }
}

/// <summary>
/// Neural network-based agent for more complex decision making.
/// Uses a simple feedforward network for function approximation.
/// </summary>
public sealed class NeuralNetworkAgent
{
    private readonly Random _random;
    private readonly int _inputSize;
    private readonly int _hiddenSize;
    private readonly int _outputSize;

    // Network weights
    private double[,] _weightsInputHidden;
    private double[] _biasHidden;
    private double[,] _weightsHiddenOutput;
    private double[] _biasOutput;

    // Hyperparameters
    private double _learningRate = 0.001;
    private double _epsilon = 0.2;

    public NeuralNetworkAgent(Random random, int inputSize = 11, int hiddenSize = 32, int outputSize = 8)
    {
        _random = random;
        _inputSize = inputSize;
        _hiddenSize = hiddenSize;
        _outputSize = outputSize;

        // Initialize weights with Xavier initialization
        _weightsInputHidden = new double[_inputSize, _hiddenSize];
        _biasHidden = new double[_hiddenSize];
        _weightsHiddenOutput = new double[_hiddenSize, _outputSize];
        _biasOutput = new double[_outputSize];

        InitializeWeights();
    }

    private void InitializeWeights()
    {
        var scale1 = Math.Sqrt(2.0 / _inputSize);
        var scale2 = Math.Sqrt(2.0 / _hiddenSize);

        for (var i = 0; i < _inputSize; i++)
        {
            for (var j = 0; j < _hiddenSize; j++)
            {
                _weightsInputHidden[i, j] = (_random.NextDouble() * 2 - 1) * scale1;
            }
        }

        for (var i = 0; i < _hiddenSize; i++)
        {
            _biasHidden[i] = 0;
            for (var j = 0; j < _outputSize; j++)
            {
                _weightsHiddenOutput[i, j] = (_random.NextDouble() * 2 - 1) * scale2;
            }
        }

        for (var i = 0; i < _outputSize; i++)
        {
            _biasOutput[i] = 0;
        }
    }

    /// <summary>
    /// Converts game state to input vector.
    /// </summary>
    public double[] StateToInput(GameState state)
    {
        return new double[]
        {
            state.HealthPercent,
            state.InventoryFullness,
            state.FoodCount / 10.0,
            state.InCombat ? 1.0 : 0.0,
            state.NearbyEnemyCount / 5.0,
            state.NearbyResourceCount / 5.0,
            state.IsInWilderness ? 1.0 : 0.0,
            state.NearBank ? 1.0 : 0.0,
            state.CombatLevel / 126.0,
            state.TotalLevel / 1000.0,
            state.PrimarySkillLevel / 99.0
        };
    }

    /// <summary>
    /// Forward pass through the network.
    /// </summary>
    public double[] Forward(double[] input)
    {
        // Hidden layer
        var hidden = new double[_hiddenSize];
        for (var j = 0; j < _hiddenSize; j++)
        {
            var sum = _biasHidden[j];
            for (var i = 0; i < _inputSize; i++)
            {
                sum += input[i] * _weightsInputHidden[i, j];
            }
            hidden[j] = ReLU(sum);
        }

        // Output layer
        var output = new double[_outputSize];
        for (var j = 0; j < _outputSize; j++)
        {
            var sum = _biasOutput[j];
            for (var i = 0; i < _hiddenSize; i++)
            {
                sum += hidden[i] * _weightsHiddenOutput[i, j];
            }
            output[j] = sum;
        }

        return output;
    }

    /// <summary>
    /// Selects an action using epsilon-greedy policy.
    /// </summary>
    public BotActionType SelectAction(GameState state)
    {
        var input = StateToInput(state);
        var qValues = Forward(input);

        if (_random.NextDouble() < _epsilon)
        {
            // Random action
            return (BotActionType)_random.Next(_outputSize);
        }

        // Best action
        var bestAction = 0;
        for (var i = 1; i < _outputSize; i++)
        {
            if (qValues[i] > qValues[bestAction])
                bestAction = i;
        }

        return (BotActionType)bestAction;
    }

    private static double ReLU(double x) => Math.Max(0, x);
}

/// <summary>
/// Experience replay buffer for DQN training.
/// </summary>
public sealed class ReplayBuffer
{
    private readonly int _capacity;
    private readonly List<Experience> _buffer;
    private readonly Random _random;
    private int _position;

    public ReplayBuffer(int capacity, Random random)
    {
        _capacity = capacity;
        _buffer = new List<Experience>(capacity);
        _random = random;
    }

    public void Add(Experience experience)
    {
        if (_buffer.Count < _capacity)
        {
            _buffer.Add(experience);
        }
        else
        {
            _buffer[_position] = experience;
        }
        _position = (_position + 1) % _capacity;
    }

    public List<Experience> Sample(int batchSize)
    {
        var samples = new List<Experience>();
        for (var i = 0; i < batchSize && i < _buffer.Count; i++)
        {
            samples.Add(_buffer[_random.Next(_buffer.Count)]);
        }
        return samples;
    }

    public int Count => _buffer.Count;
}

/// <summary>
/// A single experience tuple for replay.
/// </summary>
public readonly record struct Experience(
    GameState State,
    BotActionType Action,
    double Reward,
    GameState NextState,
    bool Done
);
