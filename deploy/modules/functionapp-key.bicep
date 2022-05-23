param functionAppName string
param keyName string = 'apimanagement'

#disable-next-line BCP081
resource FunctionAppKey 'Microsoft.Web/sites/host/functionKeys@2018-11-01' = {
  name: '${functionAppName}/default/${keyName}'
  properties: {}
}

output functionAppKeyName string = keyName
