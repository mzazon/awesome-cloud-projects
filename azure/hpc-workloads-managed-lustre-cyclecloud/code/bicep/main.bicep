@description('The name of the HPC environment')
param hpcEnvironmentName string = 'hpc-lustre-${uniqueString(resourceGroup().id)}'

@description('The Azure region for resource deployment')
param location string = resourceGroup().location

@description('The size of the Azure Managed Lustre file system in TiB')
@minValue(4)
@maxValue(500)
param lustreCapacityTiB int = 4

@description('The throughput per unit in MB/s for the Lustre file system')
@allowed([125, 250, 500, 1000])
param lustreThroughputMBps int = 1000

@description('The storage type for the Lustre file system')
@allowed(['SSD', 'HDD'])
param lustreStorageType string = 'SSD'

@description('The SSH public key for cluster access')
param sshPublicKey string

@description('The admin username for virtual machines')
param adminUsername string = 'azureuser'

@description('The VM size for the CycleCloud server')
@allowed(['Standard_D4s_v3', 'Standard_D8s_v3', 'Standard_D16s_v3'])
param cycleCloudVmSize string = 'Standard_D4s_v3'

@description('The VM size for HPC compute nodes')
@allowed(['Standard_HB120rs_v3', 'Standard_HB60rs', 'Standard_HC44rs'])
param hpcVmSize string = 'Standard_HB120rs_v3'

@description('The maximum number of compute nodes for autoscaling')
@minValue(1)
@maxValue(100)
param maxComputeNodes int = 10

@description('Enable Azure Monitor for HPC monitoring')
param enableMonitoring bool = true

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'hpc-demo'
  environment: 'production'
  workloadType: 'high-performance-computing'
}

// Variables for resource naming
var networkName = 'vnet-${hpcEnvironmentName}'
var storageAccountName = 'sthpc${uniqueString(resourceGroup().id)}'
var lustreName = 'lustre-${hpcEnvironmentName}'
var cycleCloudName = 'cc-${hpcEnvironmentName}'
var logAnalyticsName = 'law-${hpcEnvironmentName}'
var keyVaultName = 'kv-${hpcEnvironmentName}'

// Network Security Group for HPC workloads
resource nsgHpc 'Microsoft.Network/networkSecurityGroups@2023-05-01' = {
  name: 'nsg-hpc-${hpcEnvironmentName}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AllowSSH'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 1001
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'AllowSlurmCommunication'
        properties: {
          priority: 1002
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6817-6818'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowLustreTraffic'
        properties: {
          priority: 1003
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '988'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
      {
        name: 'AllowInfiniBand'
        properties: {
          priority: 1004
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
        }
      }
    ]
  }
}

// Virtual Network for HPC infrastructure
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: networkName
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
        name: 'compute-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsgHpc.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
      {
        name: 'management-subnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: {
            id: nsgHpc.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.Storage'
            }
          ]
        }
      }
      {
        name: 'storage-subnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          networkSecurityGroup: {
            id: nsgHpc.id
          }
          delegations: [
            {
              name: 'Microsoft.StoragePool/diskPools'
              properties: {
                serviceName: 'Microsoft.StoragePool/diskPools'
              }
            }
          ]
        }
      }
    ]
  }
}

// Storage account for CycleCloud and data staging
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    isHnsEnabled: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
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
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: [
        {
          id: '${vnet.id}/subnets/compute-subnet'
          action: 'Allow'
        }
        {
          id: '${vnet.id}/subnets/management-subnet'
          action: 'Allow'
        }
      ]
    }
  }
}

// Key Vault for secure credential storage
resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
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
    enabledForDiskEncryption: true
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: [
        {
          id: '${vnet.id}/subnets/management-subnet'
          ignoreMissingVnetServiceEndpoint: false
        }
      ]
    }
  }
}

// Log Analytics workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = if (enableMonitoring) {
  name: logAnalyticsName
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
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Azure Managed Lustre file system
resource lustreFileSystem 'Microsoft.StorageCache/amlFilesystems@2023-05-01' = {
  name: lustreName
  location: location
  tags: tags
  sku: {
    name: '${lustreStorageType}'
  }
  properties: {
    storageCapacityTiB: lustreCapacityTiB
    filesystemSubnet: '${vnet.id}/subnets/storage-subnet'
    maintenanceWindow: {
      dayOfWeek: 'Sunday'
      timeOfDayUTC: '02:00'
    }
    throughputProvisionedMBps: lustreThroughputMBps
    encryptionSettings: {
      keyEncryptionKey: {
        keyUrl: keyVault.properties.vaultUri
        sourceVault: {
          id: keyVault.id
        }
      }
    }
    hsm: {
      settings: {
        container: storageAccount.name
        importPrefix: '/'
        loggingContainer: storageAccount.name
      }
    }
  }
}

// Public IP for CycleCloud server
resource cycleCloudPublicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-${cycleCloudName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: cycleCloudName
    }
  }
}

// Network Interface for CycleCloud server
resource cycleCloudNIC 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'nic-${cycleCloudName}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: cycleCloudPublicIP.id
          }
          subnet: {
            id: '${vnet.id}/subnets/management-subnet'
          }
        }
      }
    ]
    networkSecurityGroup: {
      id: nsgHpc.id
    }
  }
}

// Managed Identity for CycleCloud
resource cycleCloudIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${cycleCloudName}'
  location: location
  tags: tags
}

// Role assignment for CycleCloud to manage resources
resource cycleCloudRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: resourceGroup()
  name: guid(resourceGroup().id, cycleCloudIdentity.id, 'Contributor')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: cycleCloudIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Custom script for CycleCloud initialization
var cycleCloudInitScript = base64('''
#!/bin/bash
set -e

# Update system packages
yum update -y

# Install required packages
yum install -y wget unzip

# Download and install CycleCloud
cd /tmp
wget -O cyclecloud.rpm https://packages.microsoft.com/rhel/7/prod/cyclecloud-8.1.0-1.el7.x86_64.rpm
rpm -ivh cyclecloud.rpm

# Configure CycleCloud
mkdir -p /opt/cycle_server/config
cat > /opt/cycle_server/config/cycle_server.properties << EOF
webserver.port=443
webserver.hostname=0.0.0.0
webserver.ssl.enabled=true
webserver.ssl.keystore.path=/opt/cycle_server/config/keystore.jks
webserver.ssl.keystore.password=password
EOF

# Generate SSL certificate
keytool -genkeypair -alias cyclecloud -keyalg RSA -keysize 2048 -keystore /opt/cycle_server/config/keystore.jks -validity 365 -storepass password -keypass password -dname "CN=cyclecloud"

# Start CycleCloud service
systemctl enable cyclecloud
systemctl start cyclecloud

# Wait for CycleCloud to be ready
sleep 60

# Configure CycleCloud for Azure
/opt/cycle_server/cycle_server initialize --batch --accept-terms

# Install Lustre client packages
yum install -y lustre-client

# Create Lustre mount point
mkdir -p /mnt/lustre

# Log completion
echo "CycleCloud initialization completed at $(date)" >> /var/log/cyclecloud-init.log
''')

// CycleCloud server VM
resource cycleCloudVM 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: cycleCloudName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${cycleCloudIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: cycleCloudVmSize
    }
    osProfile: {
      computerName: cycleCloudName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
      customData: cycleCloudInitScript
    }
    storageProfile: {
      imageReference: {
        publisher: 'microsoft-ads'
        offer: 'azure-cyclecloud'
        sku: 'cyclecloud81'
        version: 'latest'
      }
      osDisk: {
        name: '${cycleCloudName}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
        diskSizeGB: 128
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: cycleCloudNIC.id
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

// Virtual Machine Scale Set for HPC compute nodes (template)
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-03-01' = {
  name: 'vmss-hpc-${hpcEnvironmentName}'
  location: location
  tags: tags
  sku: {
    name: hpcVmSize
    tier: 'Standard'
    capacity: 0 // Start with 0 instances, CycleCloud will manage scaling
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Manual'
    }
    virtualMachineProfile: {
      storageProfile: {
        imageReference: {
          publisher: 'microsoft-hpc'
          offer: 'centos-hpc'
          sku: '7_9'
          version: 'latest'
        }
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
      }
      osProfile: {
        computerNamePrefix: 'hpc-node'
        adminUsername: adminUsername
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              {
                path: '/home/${adminUsername}/.ssh/authorized_keys'
                keyData: sshPublicKey
              }
            ]
          }
        }
        customData: base64('''
#!/bin/bash
set -e

# Install Lustre client
yum install -y lustre-client

# Create Lustre mount point
mkdir -p /mnt/lustre

# Install HPC libraries
yum install -y openmpi openmpi-devel
echo 'export PATH=/usr/lib64/openmpi/bin:$PATH' >> /etc/environment
echo 'export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:$LD_LIBRARY_PATH' >> /etc/environment

# Install Intel MPI (if available)
yum install -y intel-mpi-runtime intel-mpi-devel || true

# Configure InfiniBand
yum install -y infiniband-diags perftest
systemctl enable rdma
systemctl start rdma

# Log completion
echo "HPC node initialization completed at $(date)" >> /var/log/hpc-node-init.log
''')
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-hpc'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    subnet: {
                      id: '${vnet.id}/subnets/compute-subnet'
                    }
                  }
                }
              ]
              enableAcceleratedNetworking: true
              networkSecurityGroup: {
                id: nsgHpc.id
              }
            }
          }
        ]
      }
      extensionProfile: {
        extensions: [
          {
            name: 'HealthExtension'
            properties: {
              publisher: 'Microsoft.ManagedServices'
              type: 'ApplicationHealthLinux'
              typeHandlerVersion: '1.0'
              autoUpgradeMinorVersion: true
              settings: {
                protocol: 'tcp'
                port: 22
              }
            }
          }
        ]
      }
    }
  }
}

// Autoscale settings for compute nodes
resource autoscaleSettings 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (enableMonitoring) {
  name: 'autoscale-hpc-${hpcEnvironmentName}'
  location: location
  tags: tags
  properties: {
    enabled: true
    targetResourceUri: vmss.id
    profiles: [
      {
        name: 'HPC-Autoscale-Profile'
        capacity: {
          minimum: '0'
          maximum: string(maxComputeNodes)
          default: '0'
        }
        rules: [
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'GreaterThan'
              threshold: 70
            }
            scaleAction: {
              direction: 'Increase'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
          {
            metricTrigger: {
              metricName: 'Percentage CPU'
              metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
              metricResourceUri: vmss.id
              timeGrain: 'PT1M'
              statistic: 'Average'
              timeWindow: 'PT5M'
              timeAggregation: 'Average'
              operator: 'LessThan'
              threshold: 30
            }
            scaleAction: {
              direction: 'Decrease'
              type: 'ChangeCount'
              value: '1'
              cooldown: 'PT5M'
            }
          }
        ]
      }
    ]
    notifications: []
  }
}

// Azure Monitor alert rules for HPC performance
resource highCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = if (enableMonitoring) {
  name: 'HPC-High-CPU-Utilization'
  location: 'global'
  tags: tags
  properties: {
    description: 'Alert when HPC cluster CPU utilization exceeds 90%'
    severity: 2
    enabled: true
    scopes: [
      vmss.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPUUtilization'
          metricName: 'Percentage CPU'
          metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
          operator: 'GreaterThan'
          threshold: 90
          timeAggregation: 'Average'
        }
      ]
    }
    actions: []
  }
}

// Outputs
output resourceGroupName string = resourceGroup().name
output vnetName string = vnet.name
output vnetId string = vnet.id
output lustreFileSystemName string = lustreFileSystem.name
output lustreFileSystemId string = lustreFileSystem.id
output lustreMountCommand string = 'sudo mount -t lustre ${lustreFileSystem.properties.mgsAddress}@tcp:/lustrefs /mnt/lustre'
output cycleCloudVmName string = cycleCloudVM.name
output cycleCloudPublicIp string = cycleCloudPublicIP.properties.ipAddress
output cycleCloudFqdn string = cycleCloudPublicIP.properties.dnsSettings.fqdn
output cycleCloudWebUrl string = 'https://${cycleCloudPublicIP.properties.dnsSettings.fqdn}'
output storageAccountName string = storageAccount.name
output storageAccountId string = storageAccount.id
output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output logAnalyticsWorkspaceName string = enableMonitoring ? logAnalyticsWorkspace.name : ''
output logAnalyticsWorkspaceId string = enableMonitoring ? logAnalyticsWorkspace.id : ''
output vmssName string = vmss.name
output vmssId string = vmss.id
output hpcEnvironmentName string = hpcEnvironmentName
output sshConnectionCommand string = 'ssh -i ~/.ssh/id_rsa ${adminUsername}@${cycleCloudPublicIP.properties.ipAddress}'