using System;

namespace FanOutQuote;

public record QuoteRequest(string ID, DateTimeOffset RequestedAt)
{
    public static QuoteRequest NewRequest()
        => new(Guid.NewGuid().ToString(), DateTimeOffset.UtcNow);
}