using System.Threading.Tasks;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using System.Threading;
using System.Linq;
using System;
using Azure.Storage.Queues;
using Newtonsoft.Json;

namespace FanOutQuote;

public static class QuoteProcessor
{
    record Provider(string Name, (int Min, int Max) Delay);

    private static readonly Random _r = new();
    private static readonly Provider[] _providers = new[]
    {
        new Provider("Provider A", (1, 5)),
        new Provider("Provider B", (1, 20)),
        new Provider("Provider C", (10, 25)),
        new Provider("Provider D", (30, 60)),
        new Provider("Provider E", (1, 120)),
        new Provider("Provider F", (1, 120)),
        new Provider("Provider G", (1, 120)),
    };

    [FunctionName(nameof(FanOutQuoteRequest))]
    public static async Task FanOutQuoteRequest(
        [QueueTrigger(Config.QuoteRequestQueueName)] QuoteRequest request,
        [Queue(Config.FakeProviderQueueName)] QueueClient fakeProviderQueue,
        [CosmosDB(
            databaseName: Config.CosmosDBDatabaseName,
            collectionName: Config.CosmosDBCollectionName,
            ConnectionStringSetting = Config.CosmosDBConnectionStringSetting)
        ] IAsyncCollector<QuoteResponse> responseCollection,
        ILogger log,
        CancellationToken cancellationToken)
    {
        await fakeProviderQueue.CreateIfNotExistsAsync(cancellationToken: cancellationToken);

        log.LogInformation("Fanning out {QuoteID} to {ProviderCount} providers", request.ID, _providers.Length);

        // In this demo we call out to "fake" providers using a queue
        //  In reality, this would be where we call provders over http, etc.
        await Task.WhenAll(
            _providers.Select(
                x => fakeProviderQueue.SendMessageAsync(
                    JsonConvert.SerializeObject(new ProviderRequest(x.Name, request)),
                    TimeSpan.FromSeconds(_r.Next(x.Delay.Min, x.Delay.Max)),
                    null,
                    cancellationToken
                )
            ).Append(
                // Add a blank response to show it has been submitted
                responseCollection.AddAsync(QuoteResponse.NewResponse(null, request.ID, 0), cancellationToken)
            )
        );
    }

    [FunctionName(nameof(FakeProviderQuoteResponse))]
    public static Task FakeProviderQuoteResponse(
        [QueueTrigger(Config.FakeProviderQueueName)] string rawRequest,
        [CosmosDB(
            databaseName: Config.CosmosDBDatabaseName,
            collectionName: Config.CosmosDBCollectionName,
            ConnectionStringSetting = Config.CosmosDBConnectionStringSetting)
        ] IAsyncCollector<QuoteResponse> responseCollection,
        ILogger log,
        CancellationToken cancellationToken)
    {
        ProviderRequest request = JsonConvert.DeserializeObject<ProviderRequest>(rawRequest);

        TimeSpan responseTime = DateTimeOffset.UtcNow - request.Request.RequestedAt;

        log.LogInformation("Provider {Provder} responding to {QuoteID} took {ResponseTime}", request.ProviderName, request.Request.ID, responseTime);

        QuoteResponse response = QuoteResponse.NewResponse(request.ProviderName, request.Request.ID, Math.Round(_r.NextDouble() * 200 + 50, 2));

        return responseCollection.AddAsync(response, cancellationToken);
    }
}
