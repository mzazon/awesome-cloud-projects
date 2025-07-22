@description('Main Bicep template for Resilient Stateful Microservices with Azure Service Fabric and Durable Functions')

// Parameters
@description('Resource group location')
param location string = resourceGroup().location

@description('Environment suffix for resource naming')
param environmentSuffix string = uniqueString(resourceGroup().id)

@description('Project name prefix for resource naming')
param projectName string = 'microservices-orchestration'

@description('Service Fabric cluster name')
param serviceFabricClusterName string = 'sf-cluster-${environmentSuffix}'

@description('Service Fabric admin username')
param serviceFabricAdminUsername string = 'sfuser'

@description('Service Fabric admin password')
@secure()
param serviceFabricAdminPassword string

@description('Service Fabric certificate password')
@secure()
param serviceFabricCertificatePassword string

@description('Service Fabric VM SKU')
param serviceFabricVmSku string = 'Standard_D2s_v3'

@description('Service Fabric cluster size (number of nodes)')
@minValue(3)
@maxValue(99)
param serviceFabricClusterSize int = 3

@description('SQL Database server name')
param sqlServerName string = 'sql-orchestration-${environmentSuffix}'

@description('SQL Database name')
param sqlDatabaseName string = 'MicroservicesState'

@description('SQL Database administrator login')
param sqlAdminLogin string = 'sqladmin'

@description('SQL Database administrator password')
@secure()
param sqlAdminPassword string

@description('SQL Database service tier')
param sqlDatabaseServiceTier string = 'Standard'

@description('SQL Database performance level')
param sqlDatabasePerformanceLevel string = 'S1'

@description('Function App name')
param functionAppName string = 'func-orchestrator-${environmentSuffix}'

@description('Storage account name for Function App')
param storageAccountName string = 'st${environmentSuffix}'

@description('Application Insights name')
param appInsightsName string = 'ai-orchestration-${environmentSuffix}'

@description('Enable Application Insights')
param enableApplicationInsights bool = true

@description('Key Vault name for storing secrets')
param keyVaultName string = 'kv-${environmentSuffix}'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'microservices-orchestration'
  environment: 'demo'
  recipe: 'service-fabric-durable-functions'
}

// Variables
var serviceFabricNodeTypeName = 'NodeType1'
var serviceFabricApplicationTypeName = 'MicroservicesApp'
var serviceFabricApplicationTypeVersion = '1.0.0'

// Key Vault for storing secrets
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
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: false
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Application Insights for monitoring
resource appInsights 'Microsoft.Insights/components@2020-02-02' = if (enableApplicationInsights) {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'rest'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Log Analytics Workspace for Service Fabric
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${projectName}-logs-${environmentSuffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Storage Account for Function App
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: 'Account'
        }
        file: {
          enabled: true
          keyType: 'Account'
        }
      }
      keySource: 'Microsoft.Storage'
    }
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// SQL Database Server
resource sqlServer 'Microsoft.Sql/servers@2023-05-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    restrictOutboundNetworkAccess: 'Disabled'
  }

  // SQL Database
  resource sqlDatabase 'databases@2023-05-01-preview' = {
    name: sqlDatabaseName
    location: location
    tags: tags
    sku: {
      name: sqlDatabasePerformanceLevel
      tier: sqlDatabaseServiceTier
    }
    properties: {
      collation: 'SQL_Latin1_General_CP1_CI_AS'
      maxSizeBytes: 1073741824 // 1GB
      catalogCollation: 'SQL_Latin1_General_CP1_CI_AS'
      zoneRedundant: false
      readScale: 'Disabled'
      requestedBackupStorageRedundancy: 'Local'
      isLedgerOn: false
    }
  }

  // Firewall rule to allow Azure services
  resource firewallRuleAzureServices 'firewallRules@2023-05-01-preview' = {
    name: 'AllowAzureServices'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }
}

// Virtual Network for Service Fabric
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${projectName}-vnet-${environmentSuffix}'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: '${serviceFabricNodeTypeName}-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

// Network Security Group for Service Fabric
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${projectName}-nsg-${environmentSuffix}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowServiceFabricGateway'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '19000'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowServiceFabricClientConnection'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '19080'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowServiceFabricApplication'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8080-8090'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowRDP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 130
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Public IP for Service Fabric Load Balancer
resource publicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${serviceFabricClusterName}-ip'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    dnsSettings: {
      domainNameLabel: serviceFabricClusterName
    }
  }
}

// Load Balancer for Service Fabric
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: '${serviceFabricClusterName}-lb'
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'LoadBalancerIPConfig'
        properties: {
          publicIPAddress: {
            id: publicIP.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: '${serviceFabricNodeTypeName}-pool'
        properties: {}
      }
    ]
    loadBalancingRules: [
      {
        name: 'LBRule-19000'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${serviceFabricClusterName}-lb', 'LoadBalancerIPConfig')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${serviceFabricClusterName}-lb', '${serviceFabricNodeTypeName}-pool')
          }
          protocol: 'Tcp'
          frontendPort: 19000
          backendPort: 19000
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${serviceFabricClusterName}-lb', 'FabricGatewayProbe')
          }
        }
      }
      {
        name: 'LBRule-19080'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${serviceFabricClusterName}-lb', 'LoadBalancerIPConfig')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${serviceFabricClusterName}-lb', '${serviceFabricNodeTypeName}-pool')
          }
          protocol: 'Tcp'
          frontendPort: 19080
          backendPort: 19080
          enableFloatingIP: false
          idleTimeoutInMinutes: 5
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${serviceFabricClusterName}-lb', 'FabricHttpGatewayProbe')
          }
        }
      }
    ]
    probes: [
      {
        name: 'FabricGatewayProbe'
        properties: {
          protocol: 'Tcp'
          port: 19000
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
      {
        name: 'FabricHttpGatewayProbe'
        properties: {
          protocol: 'Tcp'
          port: 19080
          intervalInSeconds: 5
          numberOfProbes: 2
        }
      }
    ]
    inboundNatPools: [
      {
        name: 'LoadBalancerBEAddressNatPool'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${serviceFabricClusterName}-lb', 'LoadBalancerIPConfig')
          }
          protocol: 'Tcp'
          frontendPortRangeStart: 3389
          frontendPortRangeEnd: 4500
          backendPort: 3389
        }
      }
    ]
  }
}

// Virtual Machine Scale Set for Service Fabric
resource vmScaleSet 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: '${serviceFabricNodeTypeName}-vmss'
  location: location
  tags: tags
  sku: {
    name: serviceFabricVmSku
    tier: 'Standard'
    capacity: serviceFabricClusterSize
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          caching: 'ReadOnly'
          createOption: 'FromImage'
          managedDisk: {
            storageAccountType: 'Standard_LRS'
          }
        }
        imageReference: {
          publisher: 'MicrosoftWindowsServer'
          offer: 'WindowsServer'
          sku: '2019-Datacenter'
          version: 'latest'
        }
      }
      osProfile: {
        computerNamePrefix: substring(serviceFabricNodeTypeName, 0, 9)
        adminUsername: serviceFabricAdminUsername
        adminPassword: serviceFabricAdminPassword
        secrets: [
          {
            sourceVault: {
              id: keyVault.id
            }
            vaultCertificates: [
              {
                certificateUrl: serviceFabricCertificate.properties.secretUri
                certificateStore: 'My'
              }
            ]
          }
        ]
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: '${serviceFabricNodeTypeName}-nic'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: '${serviceFabricNodeTypeName}-ipconfig'
                  properties: {
                    primary: true
                    subnet: {
                      id: '${virtualNetwork.id}/subnets/${serviceFabricNodeTypeName}-subnet'
                    }
                    loadBalancerBackendAddressPools: [
                      {
                        id: '${loadBalancer.id}/backendAddressPools/${serviceFabricNodeTypeName}-pool'
                      }
                    ]
                    loadBalancerInboundNatPools: [
                      {
                        id: '${loadBalancer.id}/inboundNatPools/LoadBalancerBEAddressNatPool'
                      }
                    ]
                  }
                }
              ]
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'ServiceFabricNode'
            properties: {
              type: 'ServiceFabricNode'
              autoUpgradeMinorVersion: true
              protectedSettings: {
                StorageAccountKey1: storageAccount.listKeys().keys[0].value
                StorageAccountKey2: storageAccount.listKeys().keys[1].value
              }
              publisher: 'Microsoft.Azure.ServiceFabric'
              settings: {
                clusterEndpoint: serviceFabricCluster.properties.clusterEndpoint
                nodeTypeRef: serviceFabricNodeTypeName
                dataPath: 'D:\\\\SvcFab'
                durabilityLevel: 'Bronze'
                enableParallelJobs: true
                nicPrefixOverride: '10.0.1.0/24'
                certificate: {
                  thumbprint: serviceFabricCertificate.properties.thumbprint
                  x509StoreName: 'My'
                }
              }
              typeHandlerVersion: '1.1'
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    serviceFabricCluster
  ]
}

// Service Fabric Certificate
resource serviceFabricCertificate 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ServiceFabricCertificate'
  properties: {
    value: base64(json({
      data: 'base64encodedcertificate'
      dataType: 'pfx'
      password: serviceFabricCertificatePassword
    }))
    contentType: 'application/x-pkcs12'
    attributes: {
      enabled: true
    }
  }
}

// Service Fabric Cluster
resource serviceFabricCluster 'Microsoft.ServiceFabric/clusters@2023-11-01-preview' = {
  name: serviceFabricClusterName
  location: location
  tags: tags
  properties: {
    addonFeatures: [
      'DnsService'
      'RepairManager'
    ]
    clusterCodeVersion: '10.1.1951.9590'
    diagnosticsStorageAccountConfig: {
      blobEndpoint: storageAccount.properties.primaryEndpoints.blob
      protectedAccountKeyName: 'StorageAccountKey1'
      queueEndpoint: storageAccount.properties.primaryEndpoints.queue
      storageAccountName: storageAccount.name
      tableEndpoint: storageAccount.properties.primaryEndpoints.table
    }
    fabricSettings: [
      {
        name: 'Setup'
        parameters: [
          {
            name: 'FabricDataRoot'
            value: 'C:\\\\ProgramData\\\\SF'
          }
          {
            name: 'FabricLogRoot'
            value: 'C:\\\\ProgramData\\\\SF\\\\Log'
          }
        ]
      }
      {
        name: 'Diagnostics'
        parameters: [
          {
            name: 'ConsumerInstances'
            value: 'AzureWinFabCsv, AzureWinFabCrashDump, AzureTableWinFabEtwQueryable'
          }
        ]
      }
    ]
    managementEndpoint: 'https://${publicIP.properties.dnsSettings.fqdn}:19080'
    nodeTypes: [
      {
        name: serviceFabricNodeTypeName
        applicationPorts: {
          endPort: 30000
          startPort: 20000
        }
        clientConnectionEndpointPort: 19000
        durabilityLevel: 'Bronze'
        ephemeralPorts: {
          endPort: 65534
          startPort: 49152
        }
        httpGatewayEndpointPort: 19080
        isPrimary: true
        vmInstanceCount: serviceFabricClusterSize
      }
    ]
    reliabilityLevel: 'Bronze'
    upgradeMode: 'Automatic'
    vmImage: 'Windows'
    certificate: {
      thumbprint: serviceFabricCertificate.properties.thumbprint
      x509StoreName: 'My'
    }
  }
}

// App Service Plan for Function App
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: '${functionAppName}-plan'
  location: location
  tags: tags
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    reserved: false
  }
}

// Function App for Durable Functions
resource functionApp 'Microsoft.Web/sites@2023-01-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp'
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableApplicationInsights ? appInsights.properties.ConnectionString : ''
        }
        {
          name: 'SqlConnectionString'
          value: 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName};User ID=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;'
        }
        {
          name: 'ServiceFabricConnectionString'
          value: 'https://${publicIP.properties.dnsSettings.fqdn}:19080'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      netFrameworkVersion: 'v6.0'
      use32BitWorkerProcess: false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      cors: {
        allowedOrigins: [
          'https://portal.azure.com'
        ]
      }
    }
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    clientAffinityEnabled: false
  }
}

// Outputs
@description('Service Fabric Cluster endpoint')
output serviceFabricEndpoint string = serviceFabricCluster.properties.clusterEndpoint

@description('Service Fabric Explorer URL')
output serviceFabricExplorerUrl string = 'https://${publicIP.properties.dnsSettings.fqdn}:19080/Explorer'

@description('Function App URL')
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'

@description('SQL Database connection string')
output sqlConnectionString string = 'Server=tcp:${sqlServer.properties.fullyQualifiedDomainName},1433;Database=${sqlDatabaseName};User ID=${sqlAdminLogin};Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;'

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Application Insights instrumentation key')
output appInsightsInstrumentationKey string = enableApplicationInsights ? appInsights.properties.InstrumentationKey : ''

@description('Application Insights connection string')
output appInsightsConnectionString string = enableApplicationInsights ? appInsights.properties.ConnectionString : ''

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Service Fabric certificate thumbprint')
output serviceFabricCertificateThumbprint string = serviceFabricCertificate.properties.thumbprint