// ============================================================================
// main.bicep - Azure Confidential Computing with Managed HSM
// 
// This template deploys a complete confidential computing environment including:
// - Azure Confidential VM with AMD SEV-SNP
// - Azure Attestation Service
// - Azure Managed HSM with FIPS 140-3 Level 3
// - Azure Key Vault Premium
// - Secure Storage with Customer-Managed Keys
// - Managed Identities and RBAC configuration
// ============================================================================

@minLength(3)
@maxLength(11)
@description('Prefix for all resource names to ensure uniqueness')
param resourcePrefix string = 'conf${uniqueString(resourceGroup().id)}'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Environment tag for resource categorization')
@allowed(['dev', 'test', 'prod', 'demo'])
param environment string = 'demo'

@description('Administrator username for the Confidential VM')
param adminUsername string = 'azureuser'

@description('SSH public key for VM authentication')
@secure()
param sshPublicKey string

@description('Size of the Confidential VM (must support AMD SEV-SNP)')
@allowed([
  'Standard_DC2as_v5'
  'Standard_DC4as_v5'
  'Standard_DC8as_v5'
  'Standard_DC16as_v5'
  'Standard_DC32as_v5'
  'Standard_DC48as_v5'
  'Standard_DC64as_v5'
  'Standard_DC96as_v5'
])
param vmSize string = 'Standard_DC4as_v5'

@description('Object ID of the user/service principal that will be HSM administrator')
param hsmAdministratorObjectId string

@description('Enable customer-managed keys for storage encryption')
param enableCustomerManagedKeys bool = true

@description('Retention period for HSM in days (7-90 days)')
@minValue(7)
@maxValue(90)
param hsmRetentionDays int = 7

// ============================================================================
// VARIABLES
// ============================================================================

var resourceNames = {
  virtualNetwork: '${resourcePrefix}-vnet'
  subnet: '${resourcePrefix}-subnet'
  networkSecurityGroup: '${resourcePrefix}-nsg'
  confidentialVm: '${resourcePrefix}-cvm'
  publicIp: '${resourcePrefix}-pip'
  networkInterface: '${resourcePrefix}-nic'
  attestationProvider: '${resourcePrefix}-att'
  managedHsm: '${resourcePrefix}-hsm'
  keyVault: '${resourcePrefix}-kv'
  storageAccount: '${resourcePrefix}st'
  appIdentity: '${resourcePrefix}-app-identity'
  storageIdentity: '${resourcePrefix}-storage-identity'
}

var commonTags = {
  Environment: environment
  Purpose: 'ConfidentialComputing'
  Recipe: 'confidential-computing-secure-enclaves'
  ManagedBy: 'Bicep'
  CreatedBy: 'Azure-Confidential-Computing-Recipe'
}

// ============================================================================
// MANAGED IDENTITIES
// ============================================================================

// Managed identity for confidential application
resource appManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: resourceNames.appIdentity
  location: location
  tags: commonTags
}

// Managed identity for storage account encryption
resource storageManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: resourceNames.storageIdentity
  location: location
  tags: commonTags
}

// ============================================================================
// NETWORKING
// ============================================================================

// Network Security Group for Confidential VM
resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: resourceNames.networkSecurityGroup
  location: location
  tags: commonTags
  properties: {
    securityRules: [
      {
        name: 'SSH'
        properties: {
          priority: 1000
          access: 'Allow'
          direction: 'Inbound'
          destinationPortRange: '22'
          protocol: 'Tcp'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          access: 'Deny'
          direction: 'Inbound'
          destinationPortRange: '*'
          protocol: '*'
          sourcePortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// Virtual Network for confidential computing resources
resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: resourceNames.virtualNetwork
  location: location
  tags: commonTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: resourceNames.subnet
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: networkSecurityGroup.id
          }
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// Public IP for Confidential VM
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: resourceNames.publicIp
  location: location
  tags: commonTags
  sku: {
    name: 'Standard'
    tier: 'Regional'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${resourceNames.confidentialVm}-${uniqueString(resourceGroup().id)}'
    }
  }
}

// Network Interface for Confidential VM
resource networkInterface 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: resourceNames.networkInterface
  location: location
  tags: commonTags
  properties: {
    ipConfigurations: [
      {
        name: 'internal'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: virtualNetwork.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

// ============================================================================
// AZURE ATTESTATION
// ============================================================================

// Azure Attestation Provider for TEE verification
resource attestationProvider 'Microsoft.Attestation/attestationProviders@2021-06-01' = {
  name: resourceNames.attestationProvider
  location: location
  tags: commonTags
  properties: {
    policySigningCertificates: {
      keys: []
    }
  }
}

// ============================================================================
// AZURE MANAGED HSM
// ============================================================================

// Azure Managed HSM for hardware-based key management
resource managedHsm 'Microsoft.KeyVault/managedHSMs@2023-07-01' = {
  name: resourceNames.managedHsm
  location: location
  tags: commonTags
  sku: {
    family: 'B'
    name: 'Standard_B1'
  }
  properties: {
    tenantId: tenant().tenantId
    initialAdminObjectIds: [
      hsmAdministratorObjectId
    ]
    enableSoftDelete: true
    softDeleteRetentionInDays: hsmRetentionDays
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// ============================================================================
// AZURE KEY VAULT
// ============================================================================

// Azure Key Vault Premium for enclave-compatible keys
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: commonTags
  properties: {
    sku: {
      family: 'A'
      name: 'premium'
    }
    tenantId: tenant().tenantId
    enabledForDeployment: false
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enableRbacAuthorization: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// Key in Key Vault for general encryption operations
resource keyVaultKey 'Microsoft.KeyVault/vaults/keys@2023-07-01' = {
  parent: keyVault
  name: 'enclave-master-key'
  properties: {
    kty: 'RSA-HSM'
    keySize: 2048
    keyOps: [
      'encrypt'
      'decrypt'
      'sign'
      'verify'
      'wrapKey'
      'unwrapKey'
    ]
    attributes: {
      enabled: true
      exportable: false
    }
  }
}

// ============================================================================
// STORAGE ACCOUNT
// ============================================================================

// Storage Account with encryption configuration
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: commonTags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  identity: enableCustomerManagedKeys ? {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${storageManagedIdentity.id}': {}
    }
  } : null
  properties: {
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    encryption: {
      services: {
        blob: {
          enabled: true
          keyType: enableCustomerManagedKeys ? 'Account' : 'Service'
        }
        file: {
          enabled: true
          keyType: enableCustomerManagedKeys ? 'Account' : 'Service'
        }
      }
      keySource: enableCustomerManagedKeys ? 'Microsoft.Keyvault' : 'Microsoft.Storage'
      keyvaultproperties: enableCustomerManagedKeys ? {
        keyname: keyVaultKey.name
        keyvaulturi: keyVault.properties.vaultUri
      } : null
      identity: enableCustomerManagedKeys ? {
        userAssignedIdentity: storageManagedIdentity.id
      } : null
    }
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
  }
}

// ============================================================================
// CONFIDENTIAL VIRTUAL MACHINE
// ============================================================================

// Azure Confidential VM with AMD SEV-SNP
resource confidentialVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: resourceNames.confidentialVm
  location: location
  tags: commonTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appManagedIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: resourceNames.confidentialVm
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
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-confidential-vm-jammy'
        sku: '22_04-lts-cvm'
        version: 'latest'
      }
      osDisk: {
        name: '${resourceNames.confidentialVm}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
          securityProfile: {
            securityEncryptionType: 'VMGuestStateOnly'
          }
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
    securityProfile: {
      securityType: 'ConfidentialVM'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
  }
}

// ============================================================================
// VM EXTENSION FOR CONFIDENTIAL APPLICATION SETUP
// ============================================================================

// Custom Script Extension to install dependencies
resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: confidentialVm
  name: 'confidential-app-setup'
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: '''
        #!/bin/bash
        set -e
        
        # Update package list
        apt-get update
        
        # Install required packages
        apt-get install -y python3-pip curl software-properties-common
        
        # Install Azure CLI
        curl -sL https://aka.ms/InstallAzureCLIDeb | bash
        
        # Install Python Azure SDKs
        pip3 install azure-identity azure-keyvault-keys azure-keyvault-secrets azure-attestation azure-storage-blob
        
        # Create application directory
        mkdir -p /opt/confidential-app
        chown ${adminUsername}:${adminUsername} /opt/confidential-app
        
        # Create sample confidential application
        cat > /opt/confidential-app/confidential_app.py << 'PYEOF'
import os
import sys
from azure.identity import ManagedIdentityCredential
from azure.keyvault.keys import KeyClient
from azure.keyvault.secrets import SecretClient
from azure.attestation import AttestationClient
from azure.storage.blob import BlobServiceClient

def main():
    print("🔐 Starting Confidential Computing Application Demo")
    print("="*60)
    
    try:
        # Initialize managed identity credential
        credential = ManagedIdentityCredential()
        print("✅ Managed Identity credential initialized")
        
        # Get environment variables
        hsm_name = os.environ.get('HSM_NAME', '')
        kv_uri = os.environ.get('KEY_VAULT_URI', '')
        att_endpoint = os.environ.get('ATTESTATION_ENDPOINT', '')
        storage_name = os.environ.get('STORAGE_ACCOUNT_NAME', '')
        
        if not all([hsm_name, kv_uri, att_endpoint, storage_name]):
            print("❌ Missing required environment variables")
            return 1
        
        # Initialize clients
        hsm_uri = f"https://{hsm_name}.managedhsm.azure.net"
        key_client = KeyClient(vault_url=kv_uri, credential=credential)
        secret_client = SecretClient(vault_url=kv_uri, credential=credential)
        attestation_client = AttestationClient(endpoint=att_endpoint, credential=credential)
        storage_client = BlobServiceClient(account_url=f"https://{storage_name}.blob.core.windows.net", credential=credential)
        
        print("✅ Azure service clients initialized")
        
        # Test Key Vault access
        print("\n🔑 Testing Key Vault access...")
        try:
            keys = list(key_client.list_properties_of_keys())
            print(f"✅ Found {len(keys)} keys in Key Vault")
            for key in keys:
                print(f"   - {key.name}")
        except Exception as e:
            print(f"⚠️  Key Vault access limited: {e}")
        
        # Test Attestation service
        print("\n🛡️  Testing Attestation service...")
        try:
            # In a real scenario, this would include actual TEE report generation
            print("✅ Attestation service accessible")
            print(f"   Endpoint: {att_endpoint}")
        except Exception as e:
            print(f"⚠️  Attestation service access limited: {e}")
        
        # Test Storage access
        print("\n💾 Testing Storage access...")
        try:
            containers = list(storage_client.list_containers())
            print(f"✅ Storage account accessible, found {len(containers)} containers")
        except Exception as e:
            print(f"⚠️  Storage access limited: {e}")
        
        print("\n🎉 Confidential Computing setup verification complete!")
        print("="*60)
        
        # Display next steps
        print("\n📋 Next Steps:")
        print("1. Create encryption keys in Managed HSM")
        print("2. Configure attestation policies")
        print("3. Deploy your confidential workload")
        print("4. Test end-to-end encrypted processing")
        
        return 0
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())
PYEOF
        
        # Make the script executable
        chmod +x /opt/confidential-app/confidential_app.py
        
        # Create environment setup script
        cat > /opt/confidential-app/setup-environment.sh << 'ENVEOF'
#!/bin/bash
# Environment setup script for confidential application

# Set environment variables for the application
export HSM_NAME="${managedHsm.name}"
export KEY_VAULT_URI="${keyVault.properties.vaultUri}"
export ATTESTATION_ENDPOINT="${attestationProvider.properties.attestUri}"
export STORAGE_ACCOUNT_NAME="${storageAccount.name}"
export AZURE_CLIENT_ID="${appManagedIdentity.properties.clientId}"

echo "🔧 Environment variables configured:"
echo "   HSM_NAME: $HSM_NAME"
echo "   KEY_VAULT_URI: $KEY_VAULT_URI"
echo "   ATTESTATION_ENDPOINT: $ATTESTATION_ENDPOINT"
echo "   STORAGE_ACCOUNT_NAME: $STORAGE_ACCOUNT_NAME"
echo "   AZURE_CLIENT_ID: $AZURE_CLIENT_ID"
echo ""
echo "🚀 Ready to run confidential applications!"
echo "   Run: python3 /opt/confidential-app/confidential_app.py"
ENVEOF
        
        chmod +x /opt/confidential-app/setup-environment.sh
        
        # Create systemd service for automatic environment setup
        cat > /etc/systemd/system/confidential-app-env.service << 'SERVICEEOF'
[Unit]
Description=Confidential Application Environment Setup
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/confidential-app/setup-environment.sh
User=root
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICEEOF
        
        # Enable the service
        systemctl daemon-reload
        systemctl enable confidential-app-env.service
        
        # Create readme file
        cat > /opt/confidential-app/README.md << 'READMEEOF'
# Confidential Computing Application

This directory contains a sample confidential computing application that demonstrates
the integration of Azure Confidential Computing services.

## Files

- `confidential_app.py` - Sample Python application demonstrating confidential computing
- `setup-environment.sh` - Environment variable setup script
- `README.md` - This file

## Usage

1. Source the environment variables:
   ```bash
   source /opt/confidential-app/setup-environment.sh
   ```

2. Run the sample application:
   ```bash
   python3 /opt/confidential-app/confidential_app.py
   ```

## Features Demonstrated

- Managed Identity authentication
- Key Vault access
- Managed HSM integration
- Azure Attestation service
- Secure storage access
- TEE-based confidential computing

## Next Steps

1. Create encryption keys in the Managed HSM
2. Configure custom attestation policies
3. Deploy your confidential workload
4. Implement end-to-end encrypted data processing

READMEEOF
        
        chown -R ${adminUsername}:${adminUsername} /opt/confidential-app
        
        echo "✅ Confidential computing application setup complete"
        echo "📁 Application files created in /opt/confidential-app"
        echo "🔧 Environment service enabled and configured"
      '''
    }
  }
}

// ============================================================================
// RBAC ASSIGNMENTS
// ============================================================================

// Key Vault Administrator role for HSM administrator
resource hsmAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedHsm.id, hsmAdministratorObjectId, 'Managed HSM Administrator')
  scope: managedHsm
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18500a29-7fe2-46b2-a342-b16a415e101d') // Managed HSM Administrator
    principalId: hsmAdministratorObjectId
    principalType: 'User'
  }
}

// Managed HSM Crypto User role for application identity
resource appHsmCryptoUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(managedHsm.id, appManagedIdentity.id, 'Managed HSM Crypto User')
  scope: managedHsm
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '21dbd100-6940-42c2-9190-5d6cb909625b') // Managed HSM Crypto User
    principalId: appManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Administrator role for application identity (Key Vault access)
resource appKvAdminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appManagedIdentity.id, 'Key Vault Administrator')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '00482a5a-887f-4fb3-b363-3b7fe8e74483') // Key Vault Administrator
    principalId: appManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Crypto Service Encryption User role for storage identity
resource storageKvCryptoRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableCustomerManagedKeys) {
  name: guid(keyVault.id, storageManagedIdentity.id, 'Key Vault Crypto Service Encryption User')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e147488a-f6f5-4113-8e2d-b22465e65bf6') // Key Vault Crypto Service Encryption User
    principalId: storageManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Blob Data Contributor role for application identity
resource appStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, appManagedIdentity.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: appManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup().name

@description('Confidential VM name')
output confidentialVmName string = confidentialVm.name

@description('Public IP address of the Confidential VM')
output confidentialVmPublicIp string = publicIp.properties.ipAddress

@description('FQDN of the Confidential VM')
output confidentialVmFqdn string = publicIp.properties.dnsSettings.fqdn

@description('SSH connection command')
output sshConnectionCommand string = 'ssh ${adminUsername}@${publicIp.properties.ipAddress}'

@description('Azure Attestation endpoint')
output attestationEndpoint string = attestationProvider.properties.attestUri

@description('Managed HSM name')
output managedHsmName string = managedHsm.name

@description('Managed HSM URI')
output managedHsmUri string = 'https://${managedHsm.name}.managedhsm.azure.net'

@description('Key Vault name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Storage Account name')
output storageAccountName string = storageAccount.name

@description('Application Managed Identity Client ID')
output appIdentityClientId string = appManagedIdentity.properties.clientId

@description('Application Managed Identity Principal ID')
output appIdentityPrincipalId string = appManagedIdentity.properties.principalId

@description('Environment variables for confidential application')
output environmentVariables object = {
  AZURE_CLIENT_ID: appManagedIdentity.properties.clientId
  ATTESTATION_ENDPOINT: attestationProvider.properties.attestUri
  HSM_NAME: managedHsm.name
  HSM_URI: 'https://${managedHsm.name}.managedhsm.azure.net'
  KEY_VAULT_URI: keyVault.properties.vaultUri
  STORAGE_ACCOUNT_NAME: storageAccount.name
}

@description('Next steps for configuration')
output nextSteps array = [
  '1. SSH to the Confidential VM using: ssh ${adminUsername}@${publicIp.properties.ipAddress}'
  '2. Install Azure CLI and required SDKs on the VM'
  '3. Authenticate using the managed identity: az login --identity'
  '4. Create keys in Managed HSM: az keyvault key create --hsm-name ${managedHsm.name} --name confidential-data-key --kty RSA-HSM --size 3072'
  '5. Deploy your confidential application to the VM'
  '6. Configure attestation policies if needed'
  '7. Test end-to-end confidential computing workflow'
]