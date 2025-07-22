// =============================================================================
// FHIR-Compliant Healthcare API Orchestration with Azure Container Apps
// =============================================================================
// This template deploys a complete healthcare API orchestration platform
// using Azure Container Apps, Azure Health Data Services, and supporting services
// for FHIR-compliant healthcare data management and workflow automation.
// =============================================================================

targetScope = 'resourceGroup'

// =============================================================================
// PARAMETERS
// =============================================================================

@description('Prefix for all resource names')
@minLength(3)
@maxLength(10)
param resourcePrefix string = 'hc'

@description('Environment suffix for resource names')
@allowed(['dev', 'test', 'prod'])
param environment string = 'dev'

@description('Azure region for resource deployment')
param location string = resourceGroup().location

@description('Configuration for the Healthcare workspace')
param healthcareWorkspace object = {
  name: '${resourcePrefix}-hw-${environment}-${uniqueString(resourceGroup().id)}'
  publicNetworkAccess: 'Disabled'
  tags: {
    compliance: 'hipaa-hitrust'
    'data-classification': 'phi'
    purpose: 'fhir-orchestration'
  }
}

@description('Configuration for the FHIR service')
param fhirService object = {
  name: '${resourcePrefix}-fhir-${environment}-${uniqueString(resourceGroup().id)}'
  kind: 'fhir-R4'
  enableSmartProxy: true
  corsConfiguration: {
    allowCredentials: false
    maxAge: 1440
    origins: ['*']
    headers: ['*']
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS']
  }
}

@description('Configuration for Container Apps Environment')
param containerAppsEnvironment object = {
  name: '${resourcePrefix}-cae-${environment}-${uniqueString(resourceGroup().id)}'
  skuName: 'Consumption'
  zoneRedundant: false
}

@description('Configuration for API Management')
param apiManagement object = {
  name: '${resourcePrefix}-apim-${environment}-${uniqueString(resourceGroup().id)}'
  skuName: 'Developer'
  skuCapacity: 1
  publisherName: 'Healthcare Organization'
  publisherEmail: 'admin@healthcare.org'
  customProperties: {
    'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
    'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
    'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Ssl30': 'false'
    'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
    'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
    'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Ssl30': 'false'
  }
}

@description('Configuration for Communication Services')
param communicationServices object = {
  name: '${resourcePrefix}-comm-${environment}-${uniqueString(resourceGroup().id)}'
  dataLocation: 'United States'
}

@description('Configuration for Log Analytics workspace')
param logAnalytics object = {
  name: '${resourcePrefix}-law-${environment}-${uniqueString(resourceGroup().id)}'
  sku: 'PerGB2018'
  retentionInDays: 30
  dailyQuotaGb: 10
}

@description('Configuration for Application Insights')
param applicationInsights object = {
  name: '${resourcePrefix}-ai-${environment}-${uniqueString(resourceGroup().id)}'
  applicationType: 'web'
  kind: 'web'
}

@description('Configuration for container apps')
param containerApps object = {
  patientService: {
    name: 'patient-service'
    image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
    targetPort: 80
    minReplicas: 1
    maxReplicas: 10
    cpu: '0.5'
    memory: '1.0Gi'
    external: true
  }
  providerNotificationService: {
    name: 'provider-notification-service'
    image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
    targetPort: 80
    minReplicas: 1
    maxReplicas: 5
    cpu: '0.25'
    memory: '0.5Gi'
    external: true
  }
  workflowOrchestrationService: {
    name: 'workflow-orchestration-service'
    image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
    targetPort: 80
    minReplicas: 2
    maxReplicas: 8
    cpu: '1.0'
    memory: '2.0Gi'
    external: true
  }
}

@description('Common tags to apply to all resources')
param commonTags object = {
  Environment: environment
  Project: 'HealthcareFHIR'
  'Cost-Center': 'Healthcare-IT'
  Owner: 'Healthcare-Team'
  'Data-Classification': 'PHI'
  Compliance: 'HIPAA-HITRUST'
}

// =============================================================================
// VARIABLES
// =============================================================================

var tenantId = subscription().tenantId
var subscriptionId = subscription().subscriptionId

// =============================================================================
// EXISTING RESOURCES
// =============================================================================

// Reference to the current resource group
resource resourceGroup_existing 'Microsoft.Resources/resourceGroups@2022-09-01' existing = {
  scope: subscription()
  name: resourceGroup().name
}

// =============================================================================
// LOG ANALYTICS WORKSPACE
// =============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalytics.name
  location: location
  tags: union(commonTags, {
    Purpose: 'Healthcare-Monitoring'
  })
  properties: {
    sku: {
      name: logAnalytics.sku
    }
    retentionInDays: logAnalytics.retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: logAnalytics.dailyQuotaGb
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// APPLICATION INSIGHTS
// =============================================================================

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsights.name
  location: location
  tags: union(commonTags, {
    Purpose: 'Healthcare-APM'
  })
  kind: applicationInsights.kind
  properties: {
    Application_Type: applicationInsights.applicationType
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// HEALTHCARE WORKSPACE
// =============================================================================

resource healthcareWorkspaceResource 'Microsoft.HealthcareApis/workspaces@2022-12-01' = {
  name: healthcareWorkspace.name
  location: location
  tags: union(commonTags, healthcareWorkspace.tags)
  properties: {
    publicNetworkAccess: healthcareWorkspace.publicNetworkAccess
  }
}

// =============================================================================
// FHIR SERVICE
// =============================================================================

resource fhirServiceResource 'Microsoft.HealthcareApis/workspaces/fhirservices@2022-12-01' = {
  name: fhirService.name
  parent: healthcareWorkspaceResource
  location: location
  tags: union(commonTags, {
    Purpose: 'FHIR-R4-Service'
    'Data-Standard': 'FHIR-R4'
  })
  kind: fhirService.kind
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    authenticationConfiguration: {
      authority: 'https://login.microsoftonline.com/${tenantId}'
      audience: 'https://${healthcareWorkspace.name}-${fhirService.name}.fhir.azurehealthcareapis.com'
      smartProxyEnabled: fhirService.enableSmartProxy
    }
    corsConfiguration: fhirService.corsConfiguration
    publicNetworkAccess: 'Enabled'
    exportConfiguration: {
      storageAccountName: ''
    }
    importConfiguration: {
      enabled: false
      initialImportMode: false
    }
  }
}

// =============================================================================
// CONTAINER APPS ENVIRONMENT
// =============================================================================

resource containerAppsEnvironmentResource 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppsEnvironment.name
  location: location
  tags: union(commonTags, {
    Purpose: 'Healthcare-Microservices'
  })
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
    zoneRedundant: containerAppsEnvironment.zoneRedundant
  }
}

// =============================================================================
// COMMUNICATION SERVICES
// =============================================================================

resource communicationServicesResource 'Microsoft.Communication/communicationServices@2023-03-31' = {
  name: communicationServices.name
  location: 'global'
  tags: union(commonTags, {
    Purpose: 'Healthcare-Communications'
  })
  properties: {
    dataLocation: communicationServices.dataLocation
  }
}

// =============================================================================
// PATIENT SERVICE CONTAINER APP
// =============================================================================

resource patientServiceApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerApps.patientService.name
  location: location
  tags: union(commonTags, {
    Purpose: 'Patient-Management-Service'
    'Service-Type': 'Healthcare-Microservice'
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentResource.id
    configuration: {
      ingress: {
        external: containerApps.patientService.external
        targetPort: containerApps.patientService.targetPort
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'fhir-endpoint'
          value: 'https://${healthcareWorkspace.name}-${fhirService.name}.fhir.azurehealthcareapis.com'
        }
        {
          name: 'app-insights-key'
          value: appInsights.properties.InstrumentationKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerApps.patientService.name
          image: containerApps.patientService.image
          resources: {
            cpu: json(containerApps.patientService.cpu)
            memory: containerApps.patientService.memory
          }
          env: [
            {
              name: 'FHIR_ENDPOINT'
              secretRef: 'fhir-endpoint'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: fhirServiceResource.identity.principalId
            }
            {
              name: 'AZURE_TENANT_ID'
              value: tenantId
            }
            {
              name: 'SERVICE_NAME'
              value: containerApps.patientService.name
            }
            {
              name: 'COMPLIANCE_MODE'
              value: 'hipaa'
            }
            {
              name: 'LOG_LEVEL'
              value: 'INFO'
            }
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              secretRef: 'app-insights-key'
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerApps.patientService.minReplicas
        maxReplicas: containerApps.patientService.maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '10'
              }
            }
          }
        ]
      }
    }
  }
}

// =============================================================================
// PROVIDER NOTIFICATION SERVICE CONTAINER APP
// =============================================================================

resource providerNotificationServiceApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerApps.providerNotificationService.name
  location: location
  tags: union(commonTags, {
    Purpose: 'Provider-Notification-Service'
    'Service-Type': 'Healthcare-Microservice'
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentResource.id
    configuration: {
      ingress: {
        external: containerApps.providerNotificationService.external
        targetPort: containerApps.providerNotificationService.targetPort
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'fhir-endpoint'
          value: 'https://${healthcareWorkspace.name}-${fhirService.name}.fhir.azurehealthcareapis.com'
        }
        {
          name: 'comm-connection-string'
          value: communicationServicesResource.listKeys().primaryConnectionString
        }
        {
          name: 'app-insights-key'
          value: appInsights.properties.InstrumentationKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerApps.providerNotificationService.name
          image: containerApps.providerNotificationService.image
          resources: {
            cpu: json(containerApps.providerNotificationService.cpu)
            memory: containerApps.providerNotificationService.memory
          }
          env: [
            {
              name: 'FHIR_ENDPOINT'
              secretRef: 'fhir-endpoint'
            }
            {
              name: 'COMM_CONNECTION_STRING'
              secretRef: 'comm-connection-string'
            }
            {
              name: 'SERVICE_NAME'
              value: containerApps.providerNotificationService.name
            }
            {
              name: 'NOTIFICATION_MODE'
              value: 'realtime'
            }
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              secretRef: 'app-insights-key'
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerApps.providerNotificationService.minReplicas
        maxReplicas: containerApps.providerNotificationService.maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '5'
              }
            }
          }
        ]
      }
    }
  }
}

// =============================================================================
// WORKFLOW ORCHESTRATION SERVICE CONTAINER APP
// =============================================================================

resource workflowOrchestrationServiceApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerApps.workflowOrchestrationService.name
  location: location
  tags: union(commonTags, {
    Purpose: 'Workflow-Orchestration-Service'
    'Service-Type': 'Healthcare-Microservice'
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentResource.id
    configuration: {
      ingress: {
        external: containerApps.workflowOrchestrationService.external
        targetPort: containerApps.workflowOrchestrationService.targetPort
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      secrets: [
        {
          name: 'fhir-endpoint'
          value: 'https://${healthcareWorkspace.name}-${fhirService.name}.fhir.azurehealthcareapis.com'
        }
        {
          name: 'comm-connection-string'
          value: communicationServicesResource.listKeys().primaryConnectionString
        }
        {
          name: 'app-insights-key'
          value: appInsights.properties.InstrumentationKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: containerApps.workflowOrchestrationService.name
          image: containerApps.workflowOrchestrationService.image
          resources: {
            cpu: json(containerApps.workflowOrchestrationService.cpu)
            memory: containerApps.workflowOrchestrationService.memory
          }
          env: [
            {
              name: 'FHIR_ENDPOINT'
              secretRef: 'fhir-endpoint'
            }
            {
              name: 'COMM_CONNECTION_STRING'
              secretRef: 'comm-connection-string'
            }
            {
              name: 'SERVICE_NAME'
              value: containerApps.workflowOrchestrationService.name
            }
            {
              name: 'WORKFLOW_ENGINE'
              value: 'healthcare'
            }
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              secretRef: 'app-insights-key'
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerApps.workflowOrchestrationService.minReplicas
        maxReplicas: containerApps.workflowOrchestrationService.maxReplicas
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '8'
              }
            }
          }
        ]
      }
    }
  }
}

// =============================================================================
// API MANAGEMENT
// =============================================================================

resource apiManagementResource 'Microsoft.ApiManagement/service@2023-03-01-preview' = {
  name: apiManagement.name
  location: location
  tags: union(commonTags, {
    Purpose: 'Healthcare-API-Gateway'
  })
  sku: {
    name: apiManagement.skuName
    capacity: apiManagement.skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherName: apiManagement.publisherName
    publisherEmail: apiManagement.publisherEmail
    customProperties: apiManagement.customProperties
    apiVersionConstraint: {
      minApiVersion: '2021-01-01-preview'
    }
    publicNetworkAccess: 'Enabled'
    virtualNetworkType: 'None'
  }
}

// =============================================================================
// API MANAGEMENT POLICIES AND APIS
// =============================================================================

// Healthcare API Policy
resource healthcareApiPolicy 'Microsoft.ApiManagement/service/policies@2023-03-01-preview' = {
  name: 'policy'
  parent: apiManagementResource
  properties: {
    value: '''
    <policies>
      <inbound>
        <rate-limit-by-key calls="1000" renewal-period="60" counter-key="@(context.Request.IpAddress)" />
        <validate-jwt header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized. Access token is missing or invalid.">
          <openid-config url="https://login.microsoftonline.com/${tenantId}/v2.0/.well-known/openid_configuration" />
          <required-claims>
            <claim name="aud">
              <value>https://${healthcareWorkspace.name}-${fhirService.name}.fhir.azurehealthcareapis.com</value>
            </claim>
          </required-claims>
        </validate-jwt>
        <set-header name="X-Healthcare-Compliance" exists-action="override">
          <value>HIPAA-HITRUST</value>
        </set-header>
        <cors>
          <allowed-origins>
            <origin>*</origin>
          </allowed-origins>
          <allowed-methods>
            <method>GET</method>
            <method>POST</method>
            <method>PUT</method>
            <method>DELETE</method>
          </allowed-methods>
          <allowed-headers>
            <header>*</header>
          </allowed-headers>
        </cors>
      </inbound>
      <backend>
        <forward-request />
      </backend>
      <outbound>
        <set-header name="X-Powered-By" exists-action="delete" />
        <set-header name="X-Healthcare-API-Version" exists-action="override">
          <value>1.0</value>
        </set-header>
      </outbound>
      <on-error>
        <base />
      </on-error>
    </policies>
    '''
  }
}

// Patient Service API
resource patientServiceApi 'Microsoft.ApiManagement/service/apis@2023-03-01-preview' = {
  name: 'patient-service-api'
  parent: apiManagementResource
  properties: {
    displayName: 'Patient Service API'
    description: 'FHIR-compliant patient management service'
    path: 'patient'
    protocols: ['https']
    serviceUrl: 'https://${patientServiceApp.properties.configuration.ingress.fqdn}'
    subscriptionRequired: true
    apiVersion: 'v1'
    apiVersionSetId: null
  }
}

// Provider Notification Service API
resource providerNotificationServiceApi 'Microsoft.ApiManagement/service/apis@2023-03-01-preview' = {
  name: 'provider-notification-service-api'
  parent: apiManagementResource
  properties: {
    displayName: 'Provider Notification Service API'
    description: 'Healthcare provider notification and communication service'
    path: 'notifications'
    protocols: ['https']
    serviceUrl: 'https://${providerNotificationServiceApp.properties.configuration.ingress.fqdn}'
    subscriptionRequired: true
    apiVersion: 'v1'
    apiVersionSetId: null
  }
}

// Workflow Orchestration Service API
resource workflowOrchestrationServiceApi 'Microsoft.ApiManagement/service/apis@2023-03-01-preview' = {
  name: 'workflow-orchestration-service-api'
  parent: apiManagementResource
  properties: {
    displayName: 'Workflow Orchestration Service API'
    description: 'Healthcare workflow orchestration and automation service'
    path: 'workflows'
    protocols: ['https']
    serviceUrl: 'https://${workflowOrchestrationServiceApp.properties.configuration.ingress.fqdn}'
    subscriptionRequired: true
    apiVersion: 'v1'
    apiVersionSetId: null
  }
}

// =============================================================================
// RBAC ASSIGNMENTS
// =============================================================================

// Healthcare Data Contributor role for FHIR service
resource fhirDataContributorRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '5a1fc7df-4bf1-4951-a576-89034ee01acd' // FHIR Data Contributor
}

// Assign FHIR Data Contributor to Patient Service
resource patientServiceFhirRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: fhirServiceResource
  name: guid(fhirServiceResource.id, patientServiceApp.id, fhirDataContributorRoleDefinition.id)
  properties: {
    roleDefinitionId: fhirDataContributorRoleDefinition.id
    principalId: patientServiceApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Assign FHIR Data Contributor to Workflow Orchestration Service
resource workflowServiceFhirRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: fhirServiceResource
  name: guid(fhirServiceResource.id, workflowOrchestrationServiceApp.id, fhirDataContributorRoleDefinition.id)
  properties: {
    roleDefinitionId: fhirDataContributorRoleDefinition.id
    principalId: workflowOrchestrationServiceApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// OUTPUTS
// =============================================================================

@description('The name of the deployed healthcare workspace')
output healthcareWorkspaceName string = healthcareWorkspaceResource.name

@description('The FHIR service endpoint URL')
output fhirServiceEndpoint string = 'https://${healthcareWorkspace.name}-${fhirService.name}.fhir.azurehealthcareapis.com'

@description('The name of the deployed FHIR service')
output fhirServiceName string = fhirServiceResource.name

@description('Container Apps Environment name')
output containerAppsEnvironmentName string = containerAppsEnvironmentResource.name

@description('Patient Service URL')
output patientServiceUrl string = 'https://${patientServiceApp.properties.configuration.ingress.fqdn}'

@description('Provider Notification Service URL')
output providerNotificationServiceUrl string = 'https://${providerNotificationServiceApp.properties.configuration.ingress.fqdn}'

@description('Workflow Orchestration Service URL')
output workflowOrchestrationServiceUrl string = 'https://${workflowOrchestrationServiceApp.properties.configuration.ingress.fqdn}'

@description('API Management gateway URL')
output apiManagementGatewayUrl string = 'https://${apiManagementResource.properties.gatewayUrl}'

@description('API Management developer portal URL')
output apiManagementDeveloperPortalUrl string = 'https://${apiManagementResource.properties.developerPortalUrl}'

@description('Communication Services name')
output communicationServicesName string = communicationServicesResource.name

@description('Communication Services endpoint')
output communicationServicesEndpoint string = communicationServicesResource.properties.hostName

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('Application Insights Instrumentation Key')
output applicationInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Subscription ID')
output subscriptionId string = subscriptionId

@description('Tenant ID')
output tenantId string = tenantId

@description('Deployment summary')
output deploymentSummary object = {
  healthcareWorkspace: healthcareWorkspaceResource.name
  fhirService: fhirServiceResource.name
  fhirEndpoint: 'https://${healthcareWorkspace.name}-${fhirService.name}.fhir.azurehealthcareapis.com'
  containerAppsEnvironment: containerAppsEnvironmentResource.name
  services: {
    patientService: patientServiceApp.name
    providerNotificationService: providerNotificationServiceApp.name
    workflowOrchestrationService: workflowOrchestrationServiceApp.name
  }
  apiManagement: apiManagementResource.name
  communicationServices: communicationServicesResource.name
  monitoring: {
    logAnalytics: logAnalyticsWorkspace.name
    applicationInsights: appInsights.name
  }
}