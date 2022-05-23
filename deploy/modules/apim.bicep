param uniqueName string
param location string
param email string
param functionAppID string
param functionAppUrl string
param functionAppKeyName string
param instrumentationKey string
param sharedHeader string

resource Apim 'Microsoft.ApiManagement/service@2021-08-01' = {
  name: uniqueName
  location: location
  sku: {
    capacity: 0
    name: 'Consumption'
  }
  properties: {
    publisherEmail: email
    publisherName: uniqueName
  }

  resource AppInsightsLogger 'loggers@2021-08-01' = {
    name: 'appinsights'
    properties: {
      loggerType: 'applicationInsights'
      credentials: {
        instrumentationKey: instrumentationKey
      }
    }
  }

  resource FunctionKey 'namedValues@2021-08-01' = {
    name: 'QuoteFunctionsKey'
    properties: {
      displayName: 'QuoteFunctionsKey'
      secret: true
      value: listKeys('${functionAppID}/host/default', '2016-08-01').functionKeys[functionAppKeyName]
    }
  }

  resource Backend 'backends@2021-08-01' = {
    name: 'quoteFunctions'
    properties: {
      protocol: 'http'
      url: 'https://${functionAppUrl}/api/quote'
      resourceId: 'https://${environment().resourceManager}${functionAppID}'
      description: 'quoteFunctions'
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
        value: format('''
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
''', Backend.name, sharedHeader)
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
