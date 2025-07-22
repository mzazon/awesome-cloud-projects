@description('Virtual Machine module for health monitoring demonstration')

// Parameters
@description('Name of the virtual machine')
param vmName string

@description('Azure region for deployment')
param location string

@description('Resource tags')
param tags object

@description('VM admin username')
param adminUsername string

@description('VM admin password or SSH key')
@secure()
param adminPassword string

@description('Size of the virtual machine')
param vmSize string = 'Standard_B1s'

@description('Operating system type')
@allowed(['Windows', 'Linux'])
param osType string = 'Linux'

@description('Action Group resource ID for health alerts')
param actionGroupId string

@description('Enable monitoring agent')
param enableMonitoring bool = true

// Variables
var networkSecurityGroupName = '${vmName}-nsg'
var virtualNetworkName = '${vmName}-vnet'
var subnetName = 'default'
var publicIPAddressName = '${vmName}-pip'
var networkInterfaceName = '${vmName}-nic'
var osDiskName = '${vmName}-osdisk'

// Operating system configurations
var osConfigurations = {
  Linux: {
    imageReference: {
      publisher: 'Canonical'
      offer: '0001-com-ubuntu-server-jammy'
      sku: '22_04-lts-gen2'
      version: 'latest'
    }
    osDisk: {
      osType: 'Linux'
      createOption: 'FromImage'
      caching: 'ReadWrite'
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    linuxConfiguration: {
      disablePasswordAuthentication: false
      ssh: {
        publicKeys: []
      }
    }
  }
  Windows: {
    imageReference: {
      publisher: 'MicrosoftWindowsServer'
      offer: 'WindowsServer'
      sku: '2022-datacenter-azure-edition'
      version: 'latest'
    }
    osDisk: {
      osType: 'Windows'
      createOption: 'FromImage'
      caching: 'ReadWrite'
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
    }
    windowsConfiguration: {
      enableAutomaticUpdates: true
      provisionVMAgent: true
    }
  }
}

// Network Security Group
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-04-01' = {
  name: networkSecurityGroupName
  location: location
  tags: tags
  properties: {
    securityRules: osType == 'Linux' ? [
      {
        name: 'SSH'
        properties: {
          description: 'Allow SSH'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
    ] : [
      {
        name: 'RDP'
        properties: {
          description: 'Allow RDP'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-04-01' = {
  name: virtualNetworkName
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
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
        }
      }
    ]
  }
}

// Public IP Address
resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: publicIPAddressName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    dnsSettings: {
      domainNameLabel: toLower('${vmName}-${uniqueString(resourceGroup().id)}')
    }
  }
}

// Network Interface
resource networkInterface 'Microsoft.Network/networkInterfaces@2023-04-01' = {
  name: networkInterfaceName
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

// Virtual Machine
resource virtualMachine 'Microsoft.Compute/virtualMachines@2023-03-01' = {
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
      linuxConfiguration: osType == 'Linux' ? osConfigurations[osType].linuxConfiguration : null
      windowsConfiguration: osType == 'Windows' ? osConfigurations[osType].windowsConfiguration : null
    }
    storageProfile: {
      imageReference: osConfigurations[osType].imageReference
      osDisk: union(osConfigurations[osType].osDisk, {
        name: osDiskName
      })
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
      }
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
}

// Azure Monitor Agent Extension (Linux)
resource azureMonitorAgentLinux 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = if (enableMonitoring && osType == 'Linux') {
  parent: virtualMachine
  name: 'AzureMonitorLinuxAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {}
  }
}

// Azure Monitor Agent Extension (Windows)
resource azureMonitorAgentWindows 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = if (enableMonitoring && osType == 'Windows') {
  parent: virtualMachine
  name: 'AzureMonitorWindowsAgent'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    settings: {}
  }
}

// Custom Script Extension for Linux (Health Monitoring Setup)
resource customScriptExtensionLinux 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = if (osType == 'Linux') {
  parent: virtualMachine
  name: 'HealthMonitoringSetup'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: []
      commandToExecute: '''
        #!/bin/bash
        # Install monitoring tools
        apt-get update
        apt-get install -y htop iotop sysstat curl jq
        
        # Create health check script
        cat > /usr/local/bin/health-check.sh << 'EOF'
        #!/bin/bash
        # Simple health check script
        CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
        MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.2f", $3/$2 * 100.0)}')
        DISK_USAGE=$(df -h / | awk 'NR==2{printf "%s", $5}' | sed 's/%//')
        
        echo "$(date): CPU: ${CPU_USAGE}%, Memory: ${MEMORY_USAGE}%, Disk: ${DISK_USAGE}%" >> /var/log/health-metrics.log
        
        # Send metrics to Azure Monitor (placeholder - would need actual implementation)
        # curl -X POST "https://management.azure.com/..." -H "Authorization: Bearer $TOKEN" -d "$METRICS"
        EOF
        
        chmod +x /usr/local/bin/health-check.sh
        
        # Add cron job for health checks
        echo "*/5 * * * * root /usr/local/bin/health-check.sh" >> /etc/crontab
        
        # Restart cron service
        systemctl restart cron
        
        echo "Health monitoring setup completed" > /var/log/health-setup.log
      '''
    }
  }
  dependsOn: [
    azureMonitorAgentLinux
  ]
}

// PowerShell Script Extension for Windows (Health Monitoring Setup)
resource customScriptExtensionWindows 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = if (osType == 'Windows') {
  parent: virtualMachine
  name: 'HealthMonitoringSetup'
  location: location
  tags: tags
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {
      fileUris: []
      commandToExecute: '''
        powershell -ExecutionPolicy Unrestricted -Command "
        # Create health check script
        $healthScript = @'
        # Get system metrics
        $cpu = Get-Counter '\Processor(_Total)\% Processor Time' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
        $memory = Get-Counter '\Memory\Available MBytes' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
        $disk = Get-Counter '\LogicalDisk(C:)\% Free Space' | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue
        
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $logEntry = '$timestamp: CPU: $([math]::Round($cpu, 2))%, Available Memory: $([math]::Round($memory, 2))MB, Free Disk: $([math]::Round($disk, 2))%'
        
        Add-Content -Path 'C:\health-metrics.log' -Value $logEntry
        
        # Send metrics to Azure Monitor (placeholder)
        # Invoke-RestMethod -Uri 'https://management.azure.com/...' -Method POST -Headers @{Authorization='Bearer $token'} -Body $metrics
        '@
        
        # Save the health script
        $healthScript | Out-File -FilePath 'C:\health-check.ps1' -Encoding UTF8
        
        # Create scheduled task for health checks
        $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument '-ExecutionPolicy Bypass -File C:\health-check.ps1'
        $trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365) -At (Get-Date)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName 'HealthMonitoring' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force
        
        'Health monitoring setup completed' | Out-File -FilePath 'C:\health-setup.log'
        "
      '''
    }
  }
  dependsOn: [
    azureMonitorAgentWindows
  ]
}

// Resource Health Alert for this specific VM
resource vmHealthAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: '${vmName}-health-alert'
  location: 'Global'
  tags: tags
  properties: {
    enabled: true
    description: 'Alert when VM health status changes'
    scopes: [
      virtualMachine.id
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'ResourceHealth'
        }
        {
          field: 'resourceId'
          equals: virtualMachine.id
        }
        {
          field: 'properties.currentHealthStatus'
          containsAny: [
            'Unavailable'
            'Degraded'
            'Unknown'
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroupId
          webhookProperties: {
            resourceType: 'VirtualMachine'
            resourceName: vmName
          }
        }
      ]
    }
  }
}

// VM Insights (Azure Monitor for VMs)
resource vmInsights 'Microsoft.Insights/vmInsightOnboardingStatuses@2018-11-27-preview' = if (enableMonitoring) {
  name: 'default'
  scope: virtualMachine
  properties: {
    resourceId: virtualMachine.id
  }
}

// Outputs
@description('Virtual machine resource ID')
output vmId string = virtualMachine.id

@description('Virtual machine name')
output vmName string = virtualMachine.name

@description('Public IP address')
output publicIPAddress string = publicIPAddress.properties.ipAddress

@description('FQDN of the VM')
output fqdn string = publicIPAddress.properties.dnsSettings.fqdn

@description('SSH/RDP connection command')
output connectionCommand string = osType == 'Linux' 
  ? 'ssh ${adminUsername}@${publicIPAddress.properties.dnsSettings.fqdn}'
  : 'mstsc /v:${publicIPAddress.properties.dnsSettings.fqdn}'

@description('Network Security Group resource ID')
output networkSecurityGroupId string = networkSecurityGroup.id

@description('Virtual Network resource ID')
output virtualNetworkId string = virtualNetwork.id

@description('VM health alert resource ID')
output vmHealthAlertId string = vmHealthAlert.id