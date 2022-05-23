param uniqueName string
param location string
param instrumentationKey string
param sharedHeader string
param cosmosDBName string
param funcZipDeploy string = ''

resource CosmosDB 'Microsoft.DocumentDB/databaseAccounts@2021-11-15-preview' existing = {
  name: cosmosDBName
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
          value: instrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: 'InstrumentationKey=${instrumentationKey}'
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
          ipAddress: 'AzureCloud.${replace(location, ' ', '')}'
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

output functionAppName string = FunctionApp.name
output functionAppID string = FunctionApp.id
output functionAppUrl string = FunctionApp.properties.defaultHostName
