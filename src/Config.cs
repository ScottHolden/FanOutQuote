namespace FanOutQuote;

internal class Config
{
    public const string QuoteRequestQueueName = "quoterequests";
    public const string FakeProviderQueueName = "providercallback";
    public const string CosmosDBDatabaseName = "quotes";
    public const string CosmosDBCollectionName = "quoteresponses";
    public const string CosmosDBConnectionStringSetting = "CosmosDB";
}
