using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using System.Threading;
using Microsoft.Azure.Documents.Client;
using System;
using Microsoft.Azure.Documents.Linq;
using System.Linq;
using System.Collections.Generic;

namespace FanOutQuote;

public static class InboundAPI
{
    [FunctionName(nameof(RequestQuote))]
    public static async Task<IActionResult> RequestQuote(
        [HttpTrigger(AuthorizationLevel.Function, "post", Route = "quote")] HttpRequest req,
        [Queue(Config.QuoteRequestQueueName)] IAsyncCollector<QuoteRequest> requestQueue,
        ILogger log,
        CancellationToken cancellationToken)
    {
        QuoteRequest quoteRequest = QuoteRequest.NewRequest();

        log.LogInformation("Creating new quote request {QuoteID}", quoteRequest.ID);

        await requestQueue.AddAsync(quoteRequest, cancellationToken);

        return new OkObjectResult(quoteRequest);
    }

    [FunctionName(nameof(QueryQuote))]
    public static async Task<IActionResult> QueryQuote(
        [HttpTrigger(AuthorizationLevel.Function, "get", Route = "quote/{id:guid}")] HttpRequest req,
            [CosmosDB(
            databaseName: Config.CosmosDBDatabaseName,
            collectionName: Config.CosmosDBCollectionName,
            ConnectionStringSetting = Config.CosmosDBConnectionStringSetting)
        ] DocumentClient client,
        Guid? id,
        ILogger log,
        CancellationToken cancellationToken)
    {
        if (id == null || id == Guid.Empty) return new BadRequestObjectResult("Invalid quote request");

        string partitionKey = id.ToString();

        Uri collectionUri = UriFactory.CreateDocumentCollectionUri(Config.CosmosDBDatabaseName, Config.CosmosDBCollectionName);

        IDocumentQuery<QuoteResponse> query = client.CreateDocumentQuery<QuoteResponse>(collectionUri)
            .Where(p => p.RequestID == partitionKey)
            .AsDocumentQuery();

        List<QuoteResponse> responses = new();

        while (query.HasMoreResults)
        {
            var feedResponse = await query.ExecuteNextAsync<QuoteResponse>(cancellationToken);

            responses.AddRange(feedResponse);
        }

        if (responses.Count < 1)
        {
            log.LogInformation("Quote request {ID} does not exist", id);
            return new BadRequestObjectResult("Couldn't find quote request");
        }

        QuoteResponse[] providerResponses = responses
                                                .Where(x => !string.IsNullOrEmpty(x.ProviderName))
                                                .GroupBy(x => x.ProviderName)
                                                .Select(x => x.OrderByDescending(x => x.ProvidedAt).First())
                                                .ToArray();

        log.LogInformation("Found {ResponseCount} responses for {ID}", providerResponses.Length, id);

        return new OkObjectResult(providerResponses);
    }
}