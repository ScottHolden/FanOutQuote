using System;

namespace FanOutQuote;

public record QuoteResponse(string RequestID, string ResponseID, string ProviderName, double Amount, DateTimeOffset ProvidedAt)
{
    public static QuoteResponse NewResponse(string providerName, string requestID, double amount)
        => new(requestID, Guid.NewGuid().ToString(), providerName, amount, DateTimeOffset.UtcNow);
}
