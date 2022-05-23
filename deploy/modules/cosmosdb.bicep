param uniqueName string
param location string
param databaseName string = 'quotes'
param databaseThroughput int = 400
param collectionName string = 'quoteresponses'
param partitionKey string = '/RequestID'
param uniqueKey string = '/ResponseID'
param documentTtl int = 300

resource CosmosDB 'Microsoft.DocumentDB/databaseAccounts@2021-11-15-preview' = {
  name: uniqueName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    locations: [
      {
        locationName: location
      }
    ]
  }
  resource Database 'sqlDatabases' = {
    name: databaseName
    properties: {
      resource: {
        id: databaseName
      }
      options: {
        throughput: databaseThroughput
      }
    }
    resource Collection 'containers' = {
      name: collectionName
      properties: {
        resource: {
          id: collectionName
          defaultTtl: documentTtl
          partitionKey: {
            paths: [
              partitionKey
            ]
            kind: 'Hash'
          }
          uniqueKeyPolicy: {
            uniqueKeys: [
              {
                paths: [
                  uniqueKey
                ]
              }
            ]
          }
          indexingPolicy: {
            automatic: true
            indexingMode: 'consistent'
            includedPaths: [
              {
                path: '/*'
              }
            ]
            excludedPaths: []
          }
          conflictResolutionPolicy: {
            mode: 'LastWriterWins'
            conflictResolutionPath: '/_ts'
          }
        }
      }
    }
  }
}

output cosmosdbName string = CosmosDB.name
