using System.Text.Json;
using System.Text.Json.Serialization;

namespace OpenRSC.Server.Infrastructure.Serialization;

/// <summary>
/// JSON serializer adapter - human-readable format for debugging and REST APIs.
/// Uses System.Text.Json for high performance.
/// </summary>
public sealed class JsonSerializerAdapter : ISerializer
{
    private readonly JsonSerializerOptions _options;

    public JsonSerializerAdapter() : this(CreateDefaultOptions())
    {
    }

    public JsonSerializerAdapter(JsonSerializerOptions options)
    {
        _options = options;
    }

    public string FormatName => "Json";

    public byte[] Serialize<T>(T value)
    {
        return JsonSerializer.SerializeToUtf8Bytes(value, _options);
    }

    public int Serialize<T>(T value, Span<byte> buffer)
    {
        using var stream = new MemoryStream();
        JsonSerializer.Serialize(stream, value, _options);
        var data = stream.ToArray();

        if (data.Length > buffer.Length)
            throw new InvalidOperationException($"Buffer too small. Required: {data.Length}, Available: {buffer.Length}");

        data.AsSpan().CopyTo(buffer);
        return data.Length;
    }

    public void Serialize<T>(T value, Stream stream)
    {
        JsonSerializer.Serialize(stream, value, _options);
    }

    public T? Deserialize<T>(ReadOnlySpan<byte> data)
    {
        return JsonSerializer.Deserialize<T>(data, _options);
    }

    public T? Deserialize<T>(Stream stream)
    {
        return JsonSerializer.Deserialize<T>(stream, _options);
    }

    public async ValueTask SerializeAsync<T>(T value, Stream stream, CancellationToken cancellationToken = default)
    {
        await JsonSerializer.SerializeAsync(stream, value, _options, cancellationToken);
    }

    public async ValueTask<T?> DeserializeAsync<T>(Stream stream, CancellationToken cancellationToken = default)
    {
        return await JsonSerializer.DeserializeAsync<T>(stream, _options, cancellationToken);
    }

    /// <summary>
    /// Creates default JSON options optimized for game server use.
    /// </summary>
    private static JsonSerializerOptions CreateDefaultOptions()
    {
        return new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            PropertyNameCaseInsensitive = true,
            WriteIndented = false,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            NumberHandling = JsonNumberHandling.AllowReadingFromString,
            Converters =
            {
                new JsonStringEnumConverter(JsonNamingPolicy.CamelCase)
            }
        };
    }

    /// <summary>
    /// Creates options with indented output for debugging.
    /// </summary>
    public static JsonSerializerOptions CreatePrettyOptions()
    {
        var options = CreateDefaultOptions();
        options.WriteIndented = true;
        return options;
    }
}
