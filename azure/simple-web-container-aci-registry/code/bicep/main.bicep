@description('Bicep template for deploying a simple web container with Azure Container Instances and Azure Container Registry')

// Parameters
@description('The base name for all resources. A unique suffix will be appended.')
param baseName string = 'simpleweb'

@description('The Azure region where resources will be deployed')
param location string = resourceGroup().location

@description('The SKU for the Azure Container Registry')
@allowed(['Basic', 'Standard', 'Premium'])
param acrSku string = 'Basic'

@description('Enable admin user access to the container registry')
param enableAdminUser bool = true

@description('The container image name')
param containerImageName string = 'simple-nginx'

@description('The container image tag')
param containerImageTag string = 'v1'

@description('Number of CPU cores for the container instance')
@minValue(1)
@maxValue(4)
param containerCpuCores int = 1

@description('Amount of memory in GB for the container instance')
@minValue(1)
@maxValue(16)
param containerMemoryInGb int = 1

@description('The port number the container listens on')
param containerPort int = 80

@description('The restart policy for the container instance')
@allowed(['Always', 'Never', 'OnFailure'])
param restartPolicy string = 'Always'

@description('Tags to apply to all resources')
param tags object = {
  purpose: 'recipe'
  environment: 'demo'
  recipe: 'simple-web-container-aci-registry'
}

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id, deployment().name)
var containerRegistryName = 'acr${baseName}${uniqueSuffix}'
var containerInstanceName = 'aci-${baseName}-${uniqueSuffix}'
var containerGroupName = 'cg-${baseName}-${uniqueSuffix}'

// Resources

// Azure Container Registry
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: acrSku
  }
  properties: {
    adminUserEnabled: enableAdminUser
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
    policies: {
      retentionPolicy: {
        status: 'disabled'
      }
      trustPolicy: {
        status: 'disabled'
      }
    }
    encryption: {
      status: 'disabled'
    }
    dataEndpointEnabled: false
    networkRuleBypassOptions: 'AzureServices'
  }
}

// Container Instance Group
resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: containerGroupName
  location: location
  tags: tags
  properties: {
    containers: [
      {
        name: containerInstanceName
        properties: {
          image: '${containerRegistry.properties.loginServer}/${containerImageName}:${containerImageTag}'
          ports: [
            {
              port: containerPort
              protocol: 'TCP'
            }
          ]
          resources: {
            requests: {
              cpu: containerCpuCores
              memoryInGB: containerMemoryInGb
            }
          }
          environmentVariables: []
        }
      }
    ]
    osType: 'Linux'
    restartPolicy: restartPolicy
    ipAddress: {
      type: 'Public'
      ports: [
        {
          port: containerPort
          protocol: 'TCP'
        }
      ]
      dnsNameLabel: 'aci-${baseName}-${uniqueSuffix}'
    }
    imageRegistryCredentials: [
      {
        server: containerRegistry.properties.loginServer
        username: containerRegistry.listCredentials().username
        password: containerRegistry.listCredentials().passwords[0].value
      }
    ]
  }
  dependsOn: [
    containerRegistry
  ]
}

// Outputs
@description('The name of the resource group')
output resourceGroupName string = resourceGroup().name

@description('The name of the container registry')
output containerRegistryName string = containerRegistry.name

@description('The login server URL for the container registry')
output containerRegistryLoginServer string = containerRegistry.properties.loginServer

@description('The admin username for the container registry')
output containerRegistryUsername string = containerRegistry.listCredentials().username

@description('The name of the container group')
output containerGroupName string = containerGroup.name

@description('The name of the container instance')
output containerInstanceName string = containerInstanceName

@description('The public IP address of the container instance')
output containerPublicIpAddress string = containerGroup.properties.ipAddress.ip

@description('The FQDN of the container instance')
output containerFqdn string = containerGroup.properties.ipAddress.fqdn

@description('The complete web application URL')
output webApplicationUrl string = 'http://${containerGroup.properties.ipAddress.fqdn}'

@description('The container image reference')
output containerImageReference string = '${containerRegistry.properties.loginServer}/${containerImageName}:${containerImageTag}'

@description('Deployment summary')
output deploymentSummary object = {
  containerRegistry: {
    name: containerRegistry.name
    loginServer: containerRegistry.properties.loginServer
    sku: acrSku
  }
  containerInstance: {
    name: containerInstanceName
    groupName: containerGroup.name
    publicIp: containerGroup.properties.ipAddress.ip
    fqdn: containerGroup.properties.ipAddress.fqdn
    url: 'http://${containerGroup.properties.ipAddress.fqdn}'
  }
  image: {
    name: containerImageName
    tag: containerImageTag
    fullReference: '${containerRegistry.properties.loginServer}/${containerImageName}:${containerImageTag}'
  }
  resources: {
    cpu: containerCpuCores
    memory: '${containerMemoryInGb}GB'
    port: containerPort
  }
}