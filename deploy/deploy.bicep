@description('A prefix to use for all resource names')
param prefix string = 'quote'

@description('Location to deploy resources to, by default this is the resource group location')
param location string = resourceGroup().location

@description('Email address to use for API-M')
param email string = 'noreply@microsoft.com'

@description('Location of the Zip file to deploy onto the Azure Function, leave empty to skip zip deploy to Function App')
param funcZipDeploy string = 'https://raw.githubusercontent.com/ScottHolden/FanOutQuote/main/.artifacts/function.zip'

var uniqueName = '${prefix}${uniqueString(prefix, resourceGroup().id)}'
// Should find a better way to do this!
var sharedHeader = guid(resourceGroup().id)

module appinsights 'modules/appinsights.bicep' = {
  name: '${uniqueName}-appinsights'
  params: {
    location: location
    uniqueName: uniqueName
  }
}

module cosmosdb 'modules/cosmosdb.bicep' = {
  name: '${uniqueName}-cosmosdb'
  params: {
    location: location
    uniqueName: uniqueName
  }
}

module functionapp 'modules/functionapp.bicep' = {
  name: '${uniqueName}-functionapp'
  params: {
    location: location
    uniqueName: uniqueName
    cosmosDBName: cosmosdb.outputs.cosmosdbName
    sharedHeader: sharedHeader
    instrumentationKey: appinsights.outputs.instrumentationKey
    funcZipDeploy: funcZipDeploy
  }
}

module functionappkey 'modules/functionapp-key.bicep' = {
  name: '${uniqueName}-functionapp-key'
  params: {
    functionAppName: functionapp.outputs.functionAppName
  }
}

module apim 'modules/apim.bicep' = {
  name: '${uniqueName}-apim'
  params: {
    location: location
    uniqueName: uniqueName
    email: email
    functionAppID: functionapp.outputs.functionAppID
    functionAppKeyName: functionappkey.outputs.functionAppKeyName
    functionAppUrl: functionapp.outputs.functionAppUrl
    sharedHeader: sharedHeader
    instrumentationKey: appinsights.outputs.instrumentationKey
  }
}
