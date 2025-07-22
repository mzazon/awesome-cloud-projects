@description('Azure region for resource deployment')
param location string

@description('Region name identifier (primary, secondary, tertiary)')
param regionName string

@description('Unique suffix for resource names')
param uniqueSuffix string

@description('Admin username for VM Scale Set')
param adminUsername string

@description('SSH public key for VM Scale Set')
@secure()
param sshPublicKey string

@description('VM Scale Set instance count')
param vmssInstanceCount int

@description('VM Scale Set SKU')
param vmssSkuName string

@description('Application Gateway capacity')
param appGatewayCapacity int

@description('Application Gateway name')
param appGatewayName string

@description('Region display name for web content')
param regionDisplayName string

@description('Resource tags')
param tags object

// Variables for consistent naming
var vnetName = 'vnet-${regionName}-${uniqueSuffix}'
var vmssName = 'vmss-${regionName}-${uniqueSuffix}'
var pipName = 'pip-appgw-${regionName}-${uniqueSuffix}'
var wafPolicyName = 'waf-policy-${regionName}-${uniqueSuffix}'
var nsgName = 'nsg-${regionName}-${uniqueSuffix}'

// Virtual Network
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        regionName == 'primary' ? '10.1.0.0/16' : regionName == 'secondary' ? '10.2.0.0/16' : '10.3.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'subnet-appgw'
        properties: {
          addressPrefix: regionName == 'primary' ? '10.1.1.0/24' : regionName == 'secondary' ? '10.2.1.0/24' : '10.3.1.0/24'
          networkSecurityGroup: {
            id: appGatewayNsg.id
          }
        }
      }
      {
        name: 'subnet-backend'
        properties: {
          addressPrefix: regionName == 'primary' ? '10.1.2.0/24' : regionName == 'secondary' ? '10.2.2.0/24' : '10.3.2.0/24'
          networkSecurityGroup: {
            id: backendNsg.id
          }
        }
      }
    ]
  }
}

// Network Security Group for Application Gateway subnet
resource appGatewayNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${nsgName}-appgw'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-HTTPS'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-AppGateway-Management'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1002
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-Health-Probes'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1003
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Network Security Group for backend subnet
resource backendNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${nsgName}-backend'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP-from-AppGateway'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: regionName == 'primary' ? '10.1.1.0/24' : regionName == 'secondary' ? '10.2.1.0/24' : '10.3.1.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-SSH'
        properties: {
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
      {
        name: 'Allow-Health-Probes'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1002
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Public IP for Application Gateway
resource appGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: pipName
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${appGatewayName}-${uniqueSuffix}'
    }
  }
}

// VM Scale Set
resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = {
  name: vmssName
  location: location
  tags: tags
  zones: [
    '1'
    '2'
    '3'
  ]
  sku: {
    name: vmssSkuName
    tier: 'Standard'
    capacity: vmssInstanceCount
  }
  properties: {
    overprovision: false
    upgradePolicy: {
      mode: 'Automatic'
    }
    virtualMachineProfile: {
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          caching: 'ReadWrite'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-lts-gen2'
          version: 'latest'
        }
      }
      osProfile: {
        computerNamePrefix: '${regionName}vm'
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
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'nic-${regionName}'
            properties: {
              primary: true
              ipConfigurations: [
                {
                  name: 'ipconfig-${regionName}'
                  properties: {
                    subnet: {
                      id: virtualNetwork.properties.subnets[1].id
                    }
                    applicationGatewayBackendAddressPools: [
                      {
                        id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'appGatewayBackendPool')
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
            name: 'customScript'
            properties: {
              publisher: 'Microsoft.Azure.Extensions'
              type: 'CustomScript'
              typeHandlerVersion: '2.1'
              autoUpgradeMinorVersion: true
              settings: {
                commandToExecute: 'apt-get update && apt-get install -y nginx && systemctl start nginx && systemctl enable nginx && echo "<h1>${regionDisplayName}</h1><p>Server: $(hostname)</p><p>Region: ${location}</p><p>Timestamp: $(date)</p>" > /var/www/html/index.html'
              }
            }
          }
        ]
      }
    }
  }
  dependsOn: [
    applicationGateway
  ]
}

// WAF Policy
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2023-09-01' = {
  name: wafPolicyName
  location: location
  tags: tags
  properties: {
    policySettings: {
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
      state: 'Enabled'
      mode: 'Prevention'
      requestBodyInspectLimitInKB: 128
      fileUploadEnforcement: true
      requestBodyEnforcement: true
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
          ruleGroupOverrides: []
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '0.1'
          ruleGroupOverrides: []
        }
      ]
    }
  }
}

// Application Gateway
resource applicationGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: appGatewayName
  location: location
  tags: tags
  zones: [
    '1'
    '2'
    '3'
  ]
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: appGatewayCapacity
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGatewayFrontendIP'
        properties: {
          publicIPAddress: {
            id: appGatewayPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'appGatewayBackendPool'
        properties: {}
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'appGatewayBackendHttpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, 'healthProbe')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'appGatewayHttpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', appGatewayName, 'appGatewayFrontendIP')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'port_80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rule1'
        properties: {
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'appGatewayHttpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'appGatewayBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', appGatewayName, 'appGatewayBackendHttpSettings')
          }
          priority: 1
        }
      }
    ]
    probes: [
      {
        name: 'healthProbe'
        properties: {
          protocol: 'Http'
          path: '/'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: true
          minServers: 0
          match: {
            statusCodes: [
              '200-399'
            ]
          }
        }
      }
    ]
    webApplicationFirewallConfiguration: {
      enabled: true
      firewallMode: 'Prevention'
      ruleSetType: 'OWASP'
      ruleSetVersion: '3.2'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    firewallPolicy: {
      id: wafPolicy.id
    }
  }
}

// Diagnostic settings for Application Gateway
resource appGatewayDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'appgw-${regionName}-diagnostics'
  scope: applicationGateway
  properties: {
    workspaceId: resourceId('Microsoft.OperationalInsights/workspaces', 'law-global-traffic-${uniqueSuffix}')
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'ApplicationGatewayPerformanceLog'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
      {
        category: 'ApplicationGatewayFirewallLog'
        enabled: true
        retentionPolicy: {
          days: 30
          enabled: true
        }
      }
    ]
  }
}

// Outputs
@description('Application Gateway Public IP Address')
output appGatewayPublicIp string = appGatewayPublicIp.properties.ipAddress

@description('Application Gateway Name')
output appGatewayName string = applicationGateway.name

@description('Virtual Network Name')
output virtualNetworkName string = virtualNetwork.name

@description('VM Scale Set Name')
output vmssName string = vmss.name

@description('WAF Policy Name')
output wafPolicyName string = wafPolicy.name

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Public IP FQDN')
output publicIpFqdn string = appGatewayPublicIp.properties.dnsSettings.fqdn