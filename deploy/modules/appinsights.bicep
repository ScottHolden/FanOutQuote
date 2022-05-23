param uniqueName string
param location string

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

output instrumentationKey string = AppInsights.properties.InstrumentationKey
