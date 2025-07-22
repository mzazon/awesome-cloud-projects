// =============================================================================
// Azure Zero-Trust Backup Security Infrastructure
// This template deploys a comprehensive zero-trust backup solution using
// Azure Workload Identity, Azure Backup Center, and Azure Key Vault
// =============================================================================

@description('The Azure region where all resources will be deployed')
param location string = resourceGroup().location

@description('Environment name (e.g., dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Unique suffix for resource names to ensure global uniqueness')
param resourceSuffix string = uniqueString(resourceGroup().id)

@description('Enable soft delete for Key Vault (recommended for production)')
param enableSoftDelete bool = true

@description('Soft delete retention period in days (7-90 days)')
@minValue(7)
@maxValue(90)
param softDeleteRetentionDays int = 90

@description('Enable purge protection for Key Vault (recommended for production)')
param enablePurgeProtection bool = true

@description('Storage account replication type for backup reports')
@allowed(['LRS', 'GRS', 'RAGRS', 'ZRS'])
param storageReplication string = 'LRS'

@description('Virtual machine size for the test VM')
@allowed(['Standard_B2s', 'Standard_D2s_v3', 'Standard_D2as_v4'])
param vmSize string = 'Standard_B2s'

@description('Administrator username for the test VM')
param adminUsername string = 'azureuser'

@description('Administrator password for the test VM')
@secure()
param adminPassword string

@description('GitHub repository for workload identity federation (format: org/repo)')
param githubRepository string = ''

@description('Kubernetes service account for workload identity federation')
param kubernetesServiceAccount string = 'system:serviceaccount:backup-system:backup-operator'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'zero-trust-backup'
  environment: environment
  'security-level': 'high'
  compliance: 'required'
}

// =============================================================================
// Variables
// =============================================================================

var keyVaultName = 'kv-backup-${resourceSuffix}'
var workloadIdentityName = 'wi-backup-${resourceSuffix}'
var recoveryVaultName = 'rsv-backup-${resourceSuffix}'
var storageAccountName = 'stbackup${resourceSuffix}'
var vmName = 'vm-backup-test-${resourceSuffix}'
var vnetName = 'vnet-backup-test-${resourceSuffix}'
var subnetName = 'subnet-backup-test'
var nsgName = 'nsg-backup-test-${resourceSuffix}'
var publicIpName = 'pip-backup-test-${resourceSuffix}'
var nicName = 'nic-backup-test-${resourceSuffix}'
var logAnalyticsName = 'law-backup-center-${resourceSuffix}'
var diskName = '${vmName}-osdisk'

// Role definition IDs for Azure built-in roles
var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
var keyVaultCertificateOfficerRoleId = 'a4417e6f-fecd-4de8-b567-7b0420556985'
var backupContributorRoleId = '5e467623-bb1f-42f4-a55d-6e525e11384b'

// =============================================================================
// User-Assigned Managed Identity for Workload Identity
// =============================================================================

resource workloadIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: workloadIdentityName
  location: location
  tags: tags
}

// =============================================================================
// Azure Key Vault with Zero-Trust Configuration
// =============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'premium'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: softDeleteRetentionDays
    enablePurgeProtection: enablePurgeProtection
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: 'Enabled' // Can be set to 'Disabled' for private endpoint only access
  }
}

// =============================================================================
// Role Assignments for Workload Identity
// =============================================================================

resource keyVaultSecretsOfficerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, workloadIdentity.id, keyVaultSecretsOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
    principalId: workloadIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource keyVaultCertificateOfficerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, workloadIdentity.id, keyVaultCertificateOfficerRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultCertificateOfficerRoleId)
    principalId: workloadIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// =============================================================================
// Recovery Services Vault with Advanced Security
// =============================================================================

resource recoveryVault 'Microsoft.RecoveryServices/vaults@2023-06-01' = {
  name: recoveryVaultName
  location: location
  tags: tags
  sku: {
    name: 'RS0'
    tier: 'Standard'
  }
  properties: {
    redundancySettings: {
      standardTierStorageRedundancy: 'GeoRedundant'
      crossRegionRestore: 'Enabled'
    }
    securitySettings: {
      softDeleteSettings: {
        softDeleteState: 'Enabled'
        softDeleteRetentionPeriodInDays: 14
      }
      immutabilitySettings: {
        state: 'Disabled'
      }
    }
    publicNetworkAccess: 'Enabled'
    restoreSettings: {
      crossSubscriptionRestoreSettings: {
        crossSubscriptionRestoreState: 'Enabled'
      }
    }
  }
}

// =============================================================================
// Backup Policies
// =============================================================================

resource vmBackupPolicy 'Microsoft.RecoveryServices/vaults/backupPolicies@2023-06-01' = {
  parent: recoveryVault
  name: 'ZeroTrustVMPolicy'
  properties: {
    backupManagementType: 'AzureIaasVM'
    schedulePolicy: {
      schedulePolicyType: 'SimpleSchedulePolicy'
      scheduleRunFrequency: 'Daily'
      scheduleRunTimes: [
        '2024-01-01T02:00:00Z'
      ]
    }
    retentionPolicy: {
      retentionPolicyType: 'LongTermRetentionPolicy'
      dailySchedule: {
        retentionTimes: [
          '2024-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 30
          durationType: 'Days'
        }
      }
      weeklySchedule: {
        daysOfTheWeek: [
          'Sunday'
        ]
        retentionTimes: [
          '2024-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 12
          durationType: 'Weeks'
        }
      }
      monthlySchedule: {
        retentionScheduleFormatType: 'Weekly'
        retentionScheduleWeekly: {
          daysOfTheWeek: [
            'Sunday'
          ]
          weeksOfTheMonth: [
            'First'
          ]
        }
        retentionTimes: [
          '2024-01-01T02:00:00Z'
        ]
        retentionDuration: {
          count: 12
          durationType: 'Months'
        }
      }
    }
    timeZone: 'UTC'
  }
}

// =============================================================================
// Storage Account for Backup Reports
// =============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_${storageReplication}'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
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
  }
}

resource backupReportsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccount.name}/default/backup-reports'
  properties: {
    publicAccess: 'None'
  }
}

// =============================================================================
// Log Analytics Workspace for Backup Center
// =============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// =============================================================================
// Virtual Network and Security Groups
// =============================================================================

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 1001
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 2000
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
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
        name: subnetName
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

resource publicIP 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: publicIpName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: 'backup-test-${resourceSuffix}'
    }
  }
}

resource networkInterface 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: nicName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIP.id
          }
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: networkSecurityGroup.id
    }
  }
}

// =============================================================================
// Test Virtual Machine
// =============================================================================

resource virtualMachine 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  tags: tags
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
      linuxConfiguration: {
        disablePasswordAuthentication: false
        provisionVMAgent: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: diskName
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
        storageUri: storageAccount.properties.primaryEndpoints.blob
      }
    }
  }
}

// =============================================================================
// VM Backup Protection
// =============================================================================

resource vmBackupProtection 'Microsoft.RecoveryServices/vaults/backupFabrics/protectionContainers/protectedItems@2023-06-01' = {
  name: '${recoveryVault.name}/Azure/iaasvmcontainer;iaasvmcontainerv2;${resourceGroup().name};${vmName}/vm;iaasvmcontainerv2;${resourceGroup().name};${vmName}'
  properties: {
    protectedItemType: 'Microsoft.Compute/virtualMachines'
    sourceResourceId: virtualMachine.id
    policyId: vmBackupPolicy.id
  }
}

// =============================================================================
// Workload Identity Federation Credentials
// =============================================================================

resource githubFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = if (!empty(githubRepository)) {
  parent: workloadIdentity
  name: 'github-actions-fed-cred'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubRepository}:ref:refs/heads/main'
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

resource kubernetesFederatedCredential 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: workloadIdentity
  name: 'k8s-backup-fed-cred'
  properties: {
    issuer: 'https://kubernetes.default.svc.cluster.local'
    subject: kubernetesServiceAccount
    audiences: [
      'api://AzureADTokenExchange'
    ]
  }
}

// =============================================================================
// Key Vault Secrets
// =============================================================================

resource backupStorageKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'backup-storage-key'
  properties: {
    value: storageAccount.listKeys().keys[0].value
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
  dependsOn: [
    keyVaultSecretsOfficerAssignment
  ]
}

resource sqlConnectionStringSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-connection-string'
  properties: {
    value: 'Server=tcp:server.database.windows.net,1433;Database=mydb;User ID=admin;Password=SecurePassword123!;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;'
    contentType: 'text/plain'
    attributes: {
      enabled: true
    }
  }
  dependsOn: [
    keyVaultSecretsOfficerAssignment
  ]
}

// =============================================================================
// Outputs
// =============================================================================

@description('The resource ID of the Key Vault')
output keyVaultId string = keyVault.id

@description('The name of the Key Vault')
output keyVaultName string = keyVault.name

@description('The resource ID of the Recovery Services Vault')
output recoveryVaultId string = recoveryVault.id

@description('The name of the Recovery Services Vault')
output recoveryVaultName string = recoveryVault.name

@description('The resource ID of the workload identity')
output workloadIdentityId string = workloadIdentity.id

@description('The client ID of the workload identity')
output workloadIdentityClientId string = workloadIdentity.properties.clientId

@description('The principal ID of the workload identity')
output workloadIdentityPrincipalId string = workloadIdentity.properties.principalId

@description('The resource ID of the storage account')
output storageAccountId string = storageAccount.id

@description('The name of the storage account')
output storageAccountName string = storageAccount.name

@description('The resource ID of the test virtual machine')
output virtualMachineId string = virtualMachine.id

@description('The name of the test virtual machine')
output virtualMachineName string = virtualMachine.name

@description('The public IP address of the test virtual machine')
output virtualMachinePublicIP string = publicIP.properties.ipAddress

@description('The resource ID of the Log Analytics workspace')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id

@description('The name of the Log Analytics workspace')
output logAnalyticsWorkspaceName string = logAnalyticsWorkspace.name

@description('Configuration for external systems using workload identity')
output workloadIdentityConfiguration object = {
  clientId: workloadIdentity.properties.clientId
  tenantId: tenant().tenantId
  subscriptionId: subscription().subscriptionId
}