@description('Location for main resources.')
param location string = resourceGroup().location

@description('A prefix to add to the start of all resource names. Note: A "unique" suffix will also be added')
@minLength(3)
@maxLength(10)
param prefix string = 'mywrkf'

var usablePrefix = toLower(trim(prefix))
var uniqueSuffix = uniqueString(resourceGroup().id, prefix)
var uniqueNameFormat = '${usablePrefix}-{0}-${uniqueSuffix}'
var uniqueShortNameFormat = '${usablePrefix}{0}${uniqueSuffix}'

@description('Tags to apply to all deployed resources')
param tags object = {}

param logicAppArtifact string = 'file:///C:/workspace/azure/ais/logic-apps-functions/bre/MyLogicAppWorkspace/LogicApp/myWorkflowLogicapp.zip'

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: format(uniqueNameFormat, 'logs')
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: format(uniqueNameFormat, 'insights')
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  #disable-next-line BCP334
  name: take(format(uniqueShortNameFormat, 'st'), 24)
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    allowBlobPublicAccess: false
    defaultToOAuthAuthentication: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
  }

  resource blobs 'blobServices' existing = {
    name: 'default'
    resource functionAppContainer 'containers' = {
      name: 'app-package-${format(uniqueNameFormat, 'func')}'
    }
  }
}

resource logicAppPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: format(uniqueNameFormat, 'logicapp')
  location: location
  tags: tags
  sku: {
    tier: 'WorkflowStandard'
    name: 'WS1'
  }
  properties: {
    maximumElasticWorkerCount: 3
    zoneRedundant: false
  }
}

resource logicApp 'Microsoft.Web/sites@2023-12-01' = {
  name: format(uniqueNameFormat, 'logicapp')
  location: location
  tags: tags
  kind: 'functionapp,workflowapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: logicAppPlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      use32BitWorkerProcess: false
      ftpsState: 'FtpsOnly'
      netFrameworkVersion: 'v6.0'
      appSettings: [
        { name: 'APP_KIND', value: 'workflowApp' }
        {
          name: 'AzureFunctionsJobHost__extensionBundle__id'
          value: 'Microsoft.Azure.Functions.ExtensionBundle.Workflows'
        }
        { name: 'AzureFunctionsJobHost__extensionBundle__version', value: '[1.*, 2.0.0)' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'node' }
        { name: 'WEBSITE_NODE_DEFAULT_VERSION', value: '~18' }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storage.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        { name: 'WEBSITE_CONTENTSHARE', value: format(uniqueShortNameFormat, 'logicapp') }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
      ]
    }
  }
  resource disableBasicScm 'basicPublishingCredentialsPolicies' = {
    name: 'scm'
    properties: {
      allow: false
    }
  }
  resource disableBasicFtp 'basicPublishingCredentialsPolicies' = {
    name: 'ftp'
    properties: {
      allow: false
    }
  }
  resource MSDeploy 'extensions@2021-02-01' = if (!empty(trim(logicAppArtifact))) {
    name: 'MSDeploy'
    properties: {
      packageUri: logicAppArtifact
    }
  }
}

