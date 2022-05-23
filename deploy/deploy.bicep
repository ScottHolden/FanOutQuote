@description('A prefix to use for all resource names')
param prefix string = 'quote'

@description('Location to deploy resources to, by default this is the resource group location')
param location string = resourceGroup().location

@description('Email address to use for API-M')
param email string = 'noreply@microsoft.com'

@description('Location of the Zip file to deploy onto the Azure Function, leave empty to skip zip deploy to Function App')
param funcZipDeploy string = 'https://raw.githubusercontent.com/ScottHolden/FanOutQuote/main/.artifacts/function.zip'

var uniqueName = '${prefix}${uniqueString(prefix, resourceGroup().id)}'
var compactLocation = replace(location, ' ', '')

// Should find a better way to do this!
var sharedHeader = guid(resourceGroup().id)

var databaseName = 'quotes'
var databaseThroughput = 400

var collectionName = 'quoteresponses'

var partitionKey = '/RequestID'
var uniqueKey = '/ResponseID'
var documentTtl = 300

var backendName = 'quoteFunctions'

var apiPolicy = format('''
<policies>
<inbound>
  <base />
  <set-backend-service backend-id="{0}" />
  <set-header name="Ocp-Apim-Subscription-Key" exists-action="delete" />
  <set-header name="X-Azure-FDID" exists-action="override">
    <value>{1}</value>
  </set-header>
</inbound>
<backend>
    <base />
</backend>
<outbound>
    <base />
</outbound>
<on-error>
    <base />
</on-error>
</policies>
''', backendName, sharedHeader)

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

resource StorageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: toLower(substring(uniqueName, 0, min(24, length(uniqueName))))
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

resource Workspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: uniqueName
  location: location
}

resource AppInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: uniqueName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: Workspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource FunctionPlan 'Microsoft.Web/serverfarms@2020-12-01' = {
  name: uniqueName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
  }
  properties: {}
}

resource FunctionApp 'Microsoft.Web/sites@2020-12-01' = {
  name: uniqueName
  location: location
  kind: 'functionapp'
  properties: {
    serverFarmId: FunctionPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${StorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(StorageAccount.id, StorageAccount.apiVersion).keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${StorageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${listKeys(StorageAccount.id, StorageAccount.apiVersion).keys[0].value}'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: AppInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${AppInsights.properties.InstrumentationKey}'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'CosmosDB'
          value: CosmosDB.listConnectionStrings().connectionStrings[0].connectionString
        }
      ]
      ipSecurityRestrictions: [
        {
          name: 'AllowApim'
          priority: 100
          action: 'Allow'
          tag: 'ServiceTag'
          ipAddress: 'AzureCloud.${compactLocation}'
          headers: {
            'x-azure-fdid': [
              sharedHeader
            ]
          }
        }
      ]
    }
    httpsOnly: true
  }
  resource ZipDeploy 'extensions@2021-03-01' = if (!empty(trim(funcZipDeploy))) {
    name: 'MSDeploy'
    properties: {
      packageUri: funcZipDeploy
    }
  }
}

#disable-next-line BCP081
resource FunctionAppKey 'Microsoft.Web/sites/host/functionKeys@2018-11-01' = {
  name: '${FunctionApp.name}/default/apimanagement'
  properties: {}
}

resource Apim 'Microsoft.ApiManagement/service@2021-08-01' = {
  name: uniqueName
  location: location
  sku: {
    capacity: 0
    name: 'Consumption'
  }
  properties: {
    publisherEmail: email
    publisherName: prefix
  }

  resource AppInsightsLogger 'loggers@2021-08-01' = {
    name: 'appinsights'
    properties: {
      loggerType: 'applicationInsights'
      credentials: {
        instrumentationKey: AppInsights.properties.InstrumentationKey
      }
    }
  }

  resource FunctionKey 'namedValues@2021-08-01' = {
    name: 'QuoteFunctionsKey'
    properties: {
      displayName: 'QuoteFunctionsKey'
      secret: true
      value: listKeys('${FunctionApp.id}/host/default', '2016-08-01').functionKeys.apimanagement
    }
    dependsOn: [
      FunctionAppKey
    ]
  }

  resource Backend 'backends@2021-08-01' = {
    name: backendName
    properties: {
      protocol: 'http'
      url: 'https://${FunctionApp.properties.defaultHostName}/api/quote'
      resourceId: 'https://${environment().resourceManager}${FunctionApp.id}'
      description: backendName
      credentials: {
        header: {
          'x-functions-key': [
            '{{${FunctionKey.name}}}'
          ]
        }
      }
    }
  }

  resource QuoteApi 'apis@2021-08-01' = {
    name: 'quoteapi'
    properties: {
      displayName: 'Quote API'
      protocols: [
        'https'
      ]
      path: 'api/quote'
      serviceUrl: ''
      subscriptionRequired: true
    }

    resource Policy 'policies@2021-08-01' = {
      name: 'policy'
      properties: {
        format: 'rawxml'
        value: apiPolicy
      }
    }
    
    resource QuoteSchema 'schemas@2021-08-01' = {
      name: 'QuoteSchema'
      properties: {
        contentType: 'application/vnd.oai.openapi.components+json'
        document: {
          components: {
            schemas: {
              requestQuoteResponse: {
                type: 'object'
                properties: {
                  id: {
                    type: 'string'
                  }
                  requestedAt: {
                    type: 'string'
                  }
                }
              }
              queryQuoteResponse: {
                type: 'array'
                items: {
                  type: 'object'
                  properties: {
                    requestID: {
                      type: 'string'
                    }
                    responseID: {
                      type: 'string'
                    }
                    providerName: {
                      type: 'string'
                    }
                    amount: {
                      type: 'number'
                    }
                    providedAt: {
                      type: 'string'
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    resource RequestQuote 'operations@2021-08-01' = {
      name: 'requestquote'
      properties: {
        displayName: 'Request Quote'
        method: 'post'
        urlTemplate: '/'
        responses: [
          {
            statusCode: 200
            description: 'Success'
            representations: [
              {
                contentType: 'application/json'
                schemaId: QuoteSchema.name
                typeName: 'requestQuoteResponse'
              }
            ]
          }
        ]
      }
    }

    resource QueryQuote 'operations@2021-08-01' = {
      name: 'queryquote'
      properties: {
        displayName: 'Query Quote'
        method: 'get'
        urlTemplate: '/{id}'
        templateParameters: [
          {
            name: 'id'
            type: 'string'
          }
        ]
        responses: [
          {
            statusCode: 200
            description: 'Success'
            representations: [
              {
                contentType: 'application/json'
                schemaId: QuoteSchema.name
                typeName: 'queryQuoteResponse'
              }
            ]
          }
        ]
      }
    }
  }
}
