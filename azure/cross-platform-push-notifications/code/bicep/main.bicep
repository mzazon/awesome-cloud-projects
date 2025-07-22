// Azure Bicep template for Multi-Platform Push Notifications with Azure Notification Hubs and Azure Spring Apps
// This template deploys a complete push notification system supporting iOS, Android, and Web platforms

@description('The name of the environment. This will be used as a prefix for resource names.')
@minLength(2)
@maxLength(10)
param environmentName string = 'pushnotif'

@description('The Azure region where resources will be deployed.')
param location string = resourceGroup().location

@description('The SKU for the Azure Spring Apps service.')
@allowed([
  'Basic'
  'Standard'
  'Enterprise'
])
param springAppsSku string = 'Standard'

@description('The SKU for the Azure Notification Hubs namespace.')
@allowed([
  'Free'
  'Basic'
  'Standard'
])
param notificationHubSku string = 'Standard'

@description('The Firebase Cloud Messaging (FCM) server key for Android notifications.')
@secure()
param fcmServerKey string = ''

@description('The Apple Push Notification Service (APNS) key ID.')
@secure()
param apnsKeyId string = ''

@description('The Apple Push Notification Service (APNS) team ID.')
@secure()
param apnsTeamId string = ''

@description('The Apple Push Notification Service (APNS) bundle ID.')
@secure()
param apnsBundleId string = ''

@description('The Apple Push Notification Service (APNS) private key (base64 encoded).')
@secure()
param apnsPrivateKey string = ''

@description('The VAPID public key for web push notifications.')
@secure()
param vapidPublicKey string = ''

@description('The VAPID private key for web push notifications.')
@secure()
param vapidPrivateKey string = ''

@description('The subject/contact for VAPID (usually a URL or email).')
param vapidSubject string = 'mailto:admin@example.com'

@description('Enable Application Insights for monitoring.')
param enableApplicationInsights bool = true

@description('Enable diagnostic settings for resources.')
param enableDiagnostics bool = true

@description('The retention period in days for Log Analytics workspace.')
@minValue(30)
@maxValue(730)
param logAnalyticsRetentionDays int = 30

@description('Resource tags to be applied to all resources.')
param tags object = {
  Environment: environmentName
  Project: 'PushNotifications'
  DeployedBy: 'Bicep'
  Purpose: 'Demo'
}

// Generate unique resource names
var uniqueSuffix = uniqueString(resourceGroup().id)
var notificationHubNamespaceName = 'nhns-${environmentName}-${uniqueSuffix}'
var notificationHubName = 'nh-multiplatform'
var springAppsName = 'asa-${environmentName}-${uniqueSuffix}'
var springAppName = 'notification-api'
var keyVaultName = 'kv-${environmentName}${uniqueSuffix}'
var applicationInsightsName = 'ai-${environmentName}-${uniqueSuffix}'
var logAnalyticsWorkspaceName = 'law-${environmentName}-${uniqueSuffix}'

// Log Analytics Workspace (required for Application Insights and diagnostics)
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (enableApplicationInsights || enableDiagnostics) {
  name: logAnalyticsWorkspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for monitoring
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: applicationInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    WorkspaceResourceId: enableApplicationInsights ? logAnalyticsWorkspace.id : null
  }
}

// Azure Key Vault for secure credential storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enableRbacAuthorization: false
    enablePurgeProtection: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Azure Notification Hubs Namespace
resource notificationHubNamespace 'Microsoft.NotificationHubs/namespaces@2017-04-01' = {
  name: notificationHubNamespaceName
  location: location
  tags: tags
  sku: {
    name: notificationHubSku
  }
  properties: {
    namespaceType: 'NotificationHub'
  }
}

// Azure Notification Hub
resource notificationHub 'Microsoft.NotificationHubs/namespaces/notificationHubs@2017-04-01' = {
  name: notificationHubName
  parent: notificationHubNamespace
  location: location
  tags: tags
  properties: {
    authorizationRules: [
      {
        name: 'DefaultFullSharedAccessSignature'
        rights: [
          'Listen'
          'Manage'
          'Send'
        ]
      }
    ]
    // Platform-specific configurations will be set via Azure Portal or separate deployment
    // due to the sensitive nature of platform credentials
  }
}

// Azure Spring Apps Service
resource springApps 'Microsoft.AppPlatform/Spring@2023-12-01' = {
  name: springAppsName
  location: location
  tags: tags
  sku: {
    name: springAppsSku
    tier: springAppsSku
  }
  properties: {
    networkProfile: {
      serviceRuntimeSubnetId: null
      appSubnetId: null
    }
    zoneRedundant: false
  }
}

// Azure Spring Apps Application
resource springApp 'Microsoft.AppPlatform/Spring/apps@2023-12-01' = {
  name: springAppName
  parent: springApps
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    public: true
    httpsOnly: true
    temporaryDisk: {
      sizeInGB: 5
      mountPath: '/tmp'
    }
    persistentDisk: {
      sizeInGB: 0
      mountPath: '/persistent'
    }
    enableEndToEndTLS: false
  }
}

// Azure Spring Apps Deployment
resource springAppDeployment 'Microsoft.AppPlatform/Spring/apps/deployments@2023-12-01' = {
  name: 'default'
  parent: springApp
  properties: {
    active: true
    deploymentSettings: {
      resourceRequests: {
        cpu: '1'
        memory: '2Gi'
      }
      environmentVariables: {
        AZURE_KEYVAULT_URI: keyVault.properties.vaultUri
        NOTIFICATION_HUB_NAMESPACE: notificationHubNamespace.name
        NOTIFICATION_HUB_NAME: notificationHub.name
        APPLICATIONINSIGHTS_CONNECTION_STRING: enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''
        SPRING_PROFILES_ACTIVE: 'azure'
        AZURE_CLIENT_ID: springApp.identity.principalId
      }
      jvmOptions: '-Xms1024m -Xmx2048m'
      runtimeVersion: 'Java_11'
    }
    source: {
      type: 'Jar'
      // Note: This would typically reference a jar file or container image
      // For this template, we're providing the configuration structure
    }
  }
}

// Key Vault access policy for Spring Apps managed identity
resource keyVaultAccessPolicy 'Microsoft.KeyVault/vaults/accessPolicies@2023-07-01' = {
  name: 'add'
  parent: keyVault
  properties: {
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: springApp.identity.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
        }
      }
    ]
  }
}

// Store notification hub connection string in Key Vault
resource notificationHubConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: 'notification-hub-connection'
  parent: keyVault
  properties: {
    value: 'Endpoint=sb://${notificationHubNamespace.name}.servicebus.windows.net/;SharedAccessKeyName=DefaultFullSharedAccessSignature;SharedAccessKey=${listKeys(resourceId('Microsoft.NotificationHubs/namespaces/authorizationRules', notificationHubNamespace.name, 'RootManageSharedAccessKey'), '2017-04-01').primaryKey}'
  }
}

// Store FCM server key in Key Vault (if provided)
resource fcmServerKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (fcmServerKey != '') {
  name: 'fcm-server-key'
  parent: keyVault
  properties: {
    value: fcmServerKey
  }
}

// Store APNS credentials in Key Vault (if provided)
resource apnsKeyIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (apnsKeyId != '') {
  name: 'apns-key-id'
  parent: keyVault
  properties: {
    value: apnsKeyId
  }
}

resource apnsTeamIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (apnsTeamId != '') {
  name: 'apns-team-id'
  parent: keyVault
  properties: {
    value: apnsTeamId
  }
}

resource apnsBundleIdSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (apnsBundleId != '') {
  name: 'apns-bundle-id'
  parent: keyVault
  properties: {
    value: apnsBundleId
  }
}

resource apnsPrivateKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (apnsPrivateKey != '') {
  name: 'apns-private-key'
  parent: keyVault
  properties: {
    value: apnsPrivateKey
  }
}

// Store VAPID keys in Key Vault (if provided)
resource vapidPublicKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (vapidPublicKey != '') {
  name: 'vapid-public-key'
  parent: keyVault
  properties: {
    value: vapidPublicKey
  }
}

resource vapidPrivateKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (vapidPrivateKey != '') {
  name: 'vapid-private-key'
  parent: keyVault
  properties: {
    value: vapidPrivateKey
  }
}

resource vapidSubjectSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (vapidSubject != '') {
  name: 'vapid-subject'
  parent: keyVault
  properties: {
    value: vapidSubject
  }
}

// Diagnostic settings for Notification Hub Namespace
resource notificationHubDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'notification-hub-diagnostics'
  scope: notificationHubNamespace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'OperationalLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
  }
}

// Diagnostic settings for Spring Apps
resource springAppsDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: 'spring-apps-diagnostics'
  scope: springApps
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ApplicationConsole'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'SystemLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
      {
        category: 'IngressLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: logAnalyticsRetentionDays
        }
      }
    ]
  }
}

// Outputs
@description('The resource group name')
output resourceGroupName string = resourceGroup().name

@description('The Azure region where resources were deployed')
output location string = location

@description('The name of the Azure Notification Hubs namespace')
output notificationHubNamespaceName string = notificationHubNamespace.name

@description('The name of the Azure Notification Hub')
output notificationHubName string = notificationHub.name

@description('The name of the Azure Spring Apps service')
output springAppsName string = springApps.name

@description('The name of the Spring Boot application')
output springAppName string = springApp.name

@description('The URL of the Spring Boot application')
output springAppUrl string = springApp.properties.url

@description('The name of the Azure Key Vault')
output keyVaultName string = keyVault.name

@description('The URI of the Azure Key Vault')
output keyVaultUri string = keyVault.properties.vaultUri

@description('The name of the Application Insights component')
output applicationInsightsName string = enableApplicationInsights ? applicationInsights.name : ''

@description('The instrumentation key for Application Insights')
output applicationInsightsInstrumentationKey string = enableApplicationInsights ? applicationInsights.properties.InstrumentationKey : ''

@description('The connection string for Application Insights')
output applicationInsightsConnectionString string = enableApplicationInsights ? applicationInsights.properties.ConnectionString : ''

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = (enableApplicationInsights || enableDiagnostics) ? logAnalyticsWorkspace.name : ''

@description('The principal ID of the Spring Apps managed identity')
output springAppManagedIdentityPrincipalId string = springApp.identity.principalId

@description('The notification hub connection string (for reference - actual value is stored in Key Vault)')
output notificationHubConnectionStringReference string = 'Stored in Key Vault secret: notification-hub-connection'

@description('Instructions for completing the setup')
output setupInstructions string = '''
Next steps to complete the setup:

1. Configure platform-specific credentials in Azure Portal:
   - Navigate to Notification Hub > Google (GCM/FCM) and enter FCM Server Key
   - Navigate to Notification Hub > Apple (APNS) and configure APNS credentials
   - Navigate to Notification Hub > Windows (WNS) for Windows notifications if needed

2. Deploy your Spring Boot application:
   - Build your notification service JAR file
   - Deploy to Azure Spring Apps using Azure CLI or Azure DevOps

3. Test the notification system:
   - Register test devices using the API endpoints
   - Send test notifications to verify platform connectivity

4. Monitor the system:
   - Use Application Insights dashboard for application monitoring
   - Check Log Analytics workspace for detailed logs
   - Monitor Notification Hub metrics for delivery success rates

For detailed implementation guidance, refer to the recipe documentation.
'''