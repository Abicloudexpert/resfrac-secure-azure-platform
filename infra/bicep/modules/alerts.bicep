// ---------------------------------------------------------------------------
// Azure Monitor alerting. Delivers the three required alert classes:
//   1. Health / availability  -> Standard availability (web) test on /health
//                                 + location-availability metric alert.
//   2. Application failure     -> failed-requests metric alert on App Insights.
//   3. Infrastructure          -> App Service Plan high-CPU metric alert.
// All fire into a single Action Group (email receiver).
// ---------------------------------------------------------------------------
metadata description = 'Action group + availability, application-failure and infrastructure alerts.'

param namePrefix string
param location string
param tags object

param appInsightsId string
param appServicePlanId string

@description('Public HTTPS URL of the API /health endpoint for the availability test.')
param healthEndpointUrl string

@description('Email address for alert notifications. Leave empty to create the action group with no receivers.')
param alertEmail string = ''

@description('Availability test source locations (Azure web test location ids).')
param webTestLocations array = [
  { Id: 'us-ca-sjc-azr' }
  { Id: 'us-tx-sn1-azr' }
  { Id: 'us-il-ch1-azr' }
  { Id: 'emea-nl-ams-azr' }
  { Id: 'apac-sg-sin-azr' }
]

var webTestName = 'webtest-${namePrefix}-health'

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${namePrefix}'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: take('ag${namePrefix}', 12)
    enabled: true
    emailReceivers: empty(alertEmail) ? [] : [
      {
        name: 'primary'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// ---- 1. Availability: standard web test on the /health endpoint ----
resource healthWebTest 'Microsoft.Insights/webtests@2022-06-15' = {
  name: webTestName
  location: location
  tags: union(tags, {
    'hidden-link:${appInsightsId}': 'Resource'
  })
  kind: 'standard'
  properties: {
    SyntheticMonitorId: webTestName
    Name: '${namePrefix} API health availability'
    Description: 'Pings the API /health endpoint from multiple regions.'
    Enabled: true
    Frequency: 300
    Timeout: 30
    Kind: 'standard'
    RetryEnabled: true
    Locations: webTestLocations
    Request: {
      RequestUrl: healthEndpointUrl
      HttpVerb: 'GET'
      ParseDependentRequests: false
    }
    ValidationRules: {
      ExpectedHttpStatusCode: 200
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
    }
  }
}

resource availabilityAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-${namePrefix}-availability'
  location: 'global'
  tags: tags
  properties: {
    description: 'API /health availability test is failing from multiple locations.'
    severity: 1
    enabled: true
    scopes: [
      healthWebTest.id
      appInsightsId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
      webTestId: healthWebTest.id
      componentId: appInsightsId
      failedLocationCount: 2
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ---- 2. Application failure: failed requests spike on App Insights ----
resource appFailureAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-${namePrefix}-app-failures'
  location: 'global'
  tags: tags
  properties: {
    description: 'API is returning an elevated number of failed (5xx) requests.'
    severity: 2
    enabled: true
    scopes: [
      appInsightsId
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'FailedRequests'
          metricNamespace: 'microsoft.insights/components'
          metricName: 'requests/failed'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Count'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ---- 3. Infrastructure: App Service Plan sustained high CPU ----
resource planCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-${namePrefix}-plan-cpu'
  location: 'global'
  tags: tags
  properties: {
    description: 'App Service Plan CPU is sustained above 80% (scale-out / investigate).'
    severity: 2
    enabled: true
    scopes: [
      appServicePlanId
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCpu'
          metricNamespace: 'Microsoft.Web/serverfarms'
          metricName: 'CpuPercentage'
          operator: 'GreaterThan'
          threshold: 80
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    autoMitigate: true
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

output actionGroupId string = actionGroup.id
output webTestId string = healthWebTest.id
