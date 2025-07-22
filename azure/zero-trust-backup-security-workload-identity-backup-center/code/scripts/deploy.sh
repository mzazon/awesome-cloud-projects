#!/bin/bash

# =============================================================================
# Azure Zero-Trust Backup Security Deployment Script
# =============================================================================
# This script implements a comprehensive zero-trust backup security architecture
# using Azure Workload Identity and Azure Backup Center
# =============================================================================

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_FILE="deployment_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_STATE_FILE="$SCRIPT_DIR/.deployment_state"
RESOURCE_TRACKING_FILE="$SCRIPT_DIR/.resource_tracking"

# Default configuration
DEFAULT_LOCATION="eastus"
DEFAULT_RESOURCE_GROUP_PREFIX="rg-zerotrust-backup"
DEFAULT_VAULT_RETENTION_DAYS=90
DEFAULT_BACKUP_POLICY_RETENTION_DAYS=30

# =============================================================================
# Utility Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Azure Zero-Trust Backup Security solution with Workload Identity and Backup Center

OPTIONS:
    -h, --help                      Show this help message
    -r, --resource-group NAME       Resource group name (default: auto-generated)
    -l, --location LOCATION         Azure region (default: $DEFAULT_LOCATION)
    -s, --subscription-id ID        Azure subscription ID (default: current)
    -d, --dry-run                   Show what would be deployed without creating resources
    -v, --verbose                   Enable verbose logging
    -f, --force                     Force deployment even if resources exist
    --skip-vm                       Skip creating test VM for backup demonstration
    --storage-redundancy TYPE       Storage redundancy type (default: GeoRedundant)
    --retention-days DAYS           Key Vault retention days (default: $DEFAULT_VAULT_RETENTION_DAYS)

EXAMPLES:
    $0 --resource-group my-backup-rg --location westus2
    $0 --dry-run --verbose
    $0 --force --skip-vm --location centralus

EOF
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check if logged in
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    # Check required permissions
    local current_user=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "")
    if [[ -z "$current_user" ]]; then
        log_warning "Cannot verify user permissions. Proceeding with deployment..."
    else
        log_info "Current user ID: $current_user"
    fi
    
    # Check if required resource providers are registered
    local providers=("Microsoft.KeyVault" "Microsoft.RecoveryServices" "Microsoft.ManagedIdentity" "Microsoft.Storage")
    for provider in "${providers[@]}"; do
        local status=$(az provider show --namespace "$provider" --query registrationState -o tsv 2>/dev/null || echo "NotRegistered")
        if [[ "$status" != "Registered" ]]; then
            log_info "Registering provider: $provider"
            az provider register --namespace "$provider" --wait || {
                log_error "Failed to register provider: $provider"
                exit 1
            }
        fi
    done
    
    log_success "Prerequisites check completed"
}

generate_unique_suffix() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 3
    else
        # Fallback to using date and random
        echo $(date +%s | tail -c 6)$(shuf -i 100-999 -n 1)
    fi
}

save_deployment_state() {
    local key="$1"
    local value="$2"
    
    if [[ ! -f "$DEPLOYMENT_STATE_FILE" ]]; then
        touch "$DEPLOYMENT_STATE_FILE"
    fi
    
    # Remove existing entry if it exists
    sed -i "/^$key=/d" "$DEPLOYMENT_STATE_FILE" 2>/dev/null || true
    
    # Add new entry
    echo "$key=$value" >> "$DEPLOYMENT_STATE_FILE"
}

load_deployment_state() {
    local key="$1"
    
    if [[ -f "$DEPLOYMENT_STATE_FILE" ]]; then
        grep "^$key=" "$DEPLOYMENT_STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo ""
    else
        echo ""
    fi
}

track_resource() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_group="$3"
    
    echo "$resource_type|$resource_name|$resource_group|$(date '+%Y-%m-%d %H:%M:%S')" >> "$RESOURCE_TRACKING_FILE"
}

validate_azure_name() {
    local name="$1"
    local type="$2"
    
    case "$type" in
        "keyvault")
            if [[ ! "$name" =~ ^[a-zA-Z0-9-]{3,24}$ ]]; then
                log_error "Key Vault name must be 3-24 characters, alphanumeric and hyphens only"
                return 1
            fi
            ;;
        "storage")
            if [[ ! "$name" =~ ^[a-z0-9]{3,24}$ ]]; then
                log_error "Storage account name must be 3-24 characters, lowercase letters and numbers only"
                return 1
            fi
            ;;
        "vm")
            if [[ ! "$name" =~ ^[a-zA-Z0-9-]{1,64}$ ]]; then
                log_error "VM name must be 1-64 characters, alphanumeric and hyphens only"
                return 1
            fi
            ;;
    esac
    
    return 0
}

# =============================================================================
# Main Deployment Functions
# =============================================================================

deploy_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create resource group: $RESOURCE_GROUP in $LOCATION"
        return 0
    fi
    
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        if [[ "$FORCE" == "true" ]]; then
            log_warning "Resource group exists, continuing due to --force flag"
        else
            log_error "Resource group already exists. Use --force to continue."
            exit 1
        fi
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=zero-trust-backup environment=demo \
                   security-level=high compliance=required \
                   deployed-by="$USER" deployment-date="$(date +%Y-%m-%d)" || {
            log_error "Failed to create resource group"
            exit 1
        }
        
        track_resource "ResourceGroup" "$RESOURCE_GROUP" "$RESOURCE_GROUP"
    fi
    
    save_deployment_state "RESOURCE_GROUP" "$RESOURCE_GROUP"
    log_success "Resource group created successfully"
}

deploy_key_vault() {
    log_info "Creating Azure Key Vault: $KEY_VAULT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Key Vault: $KEY_VAULT_NAME"
        return 0
    fi
    
    validate_azure_name "$KEY_VAULT_NAME" "keyvault" || exit 1
    
    # Create Key Vault with advanced security features
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku premium \
        --enable-rbac-authorization true \
        --enable-purge-protection true \
        --retention-days "$RETENTION_DAYS" \
        --enable-soft-delete true \
        --tags purpose=zero-trust-backup security-level=high || {
        log_error "Failed to create Key Vault"
        exit 1
    }
    
    # Configure network access restrictions
    az keyvault network-rule add \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --default-action Deny || {
        log_warning "Failed to configure Key Vault network restrictions"
    }
    
    # Get Key Vault resource ID
    KEY_VAULT_ID=$(az keyvault show \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    save_deployment_state "KEY_VAULT_NAME" "$KEY_VAULT_NAME"
    save_deployment_state "KEY_VAULT_ID" "$KEY_VAULT_ID"
    track_resource "KeyVault" "$KEY_VAULT_NAME" "$RESOURCE_GROUP"
    
    log_success "Key Vault created with zero-trust security configuration"
}

deploy_workload_identity() {
    log_info "Creating User-Assigned Managed Identity: $WORKLOAD_IDENTITY_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create managed identity: $WORKLOAD_IDENTITY_NAME"
        return 0
    fi
    
    # Create user-assigned managed identity
    az identity create \
        --name "$WORKLOAD_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags purpose=workload-identity security-level=high || {
        log_error "Failed to create managed identity"
        exit 1
    }
    
    # Get managed identity details
    IDENTITY_CLIENT_ID=$(az identity show \
        --name "$WORKLOAD_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query clientId --output tsv)
    
    IDENTITY_PRINCIPAL_ID=$(az identity show \
        --name "$WORKLOAD_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId --output tsv)
    
    save_deployment_state "WORKLOAD_IDENTITY_NAME" "$WORKLOAD_IDENTITY_NAME"
    save_deployment_state "IDENTITY_CLIENT_ID" "$IDENTITY_CLIENT_ID"
    save_deployment_state "IDENTITY_PRINCIPAL_ID" "$IDENTITY_PRINCIPAL_ID"
    track_resource "ManagedIdentity" "$WORKLOAD_IDENTITY_NAME" "$RESOURCE_GROUP"
    
    log_success "Workload identity created: $IDENTITY_CLIENT_ID"
}

configure_key_vault_access() {
    log_info "Configuring Key Vault access policies"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure Key Vault RBAC permissions"
        return 0
    fi
    
    # Assign Key Vault Secrets Officer role to workload identity
    az role assignment create \
        --assignee "$IDENTITY_PRINCIPAL_ID" \
        --role "Key Vault Secrets Officer" \
        --scope "$KEY_VAULT_ID" || {
        log_error "Failed to assign Key Vault Secrets Officer role"
        exit 1
    }
    
    # Assign Key Vault Certificate Officer role
    az role assignment create \
        --assignee "$IDENTITY_PRINCIPAL_ID" \
        --role "Key Vault Certificate Officer" \
        --scope "$KEY_VAULT_ID" || {
        log_error "Failed to assign Key Vault Certificate Officer role"
        exit 1
    }
    
    # Assign current user as Key Vault Administrator
    CURRENT_USER_ID=$(az ad signed-in-user show --query id --output tsv)
    az role assignment create \
        --assignee "$CURRENT_USER_ID" \
        --role "Key Vault Administrator" \
        --scope "$KEY_VAULT_ID" || {
        log_warning "Failed to assign Key Vault Administrator role to current user"
    }
    
    log_success "Key Vault RBAC permissions configured"
}

deploy_recovery_vault() {
    log_info "Creating Recovery Services Vault: $RECOVERY_VAULT_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Recovery Services Vault: $RECOVERY_VAULT_NAME"
        return 0
    fi
    
    # Create Recovery Services Vault
    az backup vault create \
        --name "$RECOVERY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --storage-redundancy "$STORAGE_REDUNDANCY" || {
        log_error "Failed to create Recovery Services Vault"
        exit 1
    }
    
    # Configure vault security settings
    az backup vault backup-properties set \
        --name "$RECOVERY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --cross-region-restore-flag true \
        --soft-delete-feature-state Enabled || {
        log_warning "Failed to configure vault security settings"
    }
    
    # Get vault resource ID
    VAULT_ID=$(az backup vault show \
        --name "$RECOVERY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id --output tsv)
    
    save_deployment_state "RECOVERY_VAULT_NAME" "$RECOVERY_VAULT_NAME"
    save_deployment_state "VAULT_ID" "$VAULT_ID"
    track_resource "RecoveryVault" "$RECOVERY_VAULT_NAME" "$RESOURCE_GROUP"
    
    log_success "Recovery Services Vault created with advanced security"
}

create_backup_policies() {
    log_info "Creating backup policies with zero-trust security controls"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup policies"
        return 0
    fi
    
    # Create VM backup policy
    cat > /tmp/vm_policy.json << EOF
{
  "schedulePolicy": {
    "schedulePolicyType": "SimpleSchedulePolicy",
    "scheduleRunFrequency": "Daily",
    "scheduleRunTimes": ["2024-01-01T02:00:00Z"],
    "scheduleRunDays": null
  },
  "retentionPolicy": {
    "retentionPolicyType": "LongTermRetentionPolicy",
    "dailySchedule": {
      "retentionTimes": ["2024-01-01T02:00:00Z"],
      "retentionDuration": {
        "count": $BACKUP_POLICY_RETENTION_DAYS,
        "durationType": "Days"
      }
    },
    "weeklySchedule": {
      "daysOfTheWeek": ["Sunday"],
      "retentionTimes": ["2024-01-01T02:00:00Z"],
      "retentionDuration": {
        "count": 12,
        "durationType": "Weeks"
      }
    },
    "monthlySchedule": {
      "retentionScheduleFormatType": "Weekly",
      "retentionScheduleWeekly": {
        "daysOfTheWeek": ["Sunday"],
        "weeksOfTheMonth": ["First"]
      },
      "retentionTimes": ["2024-01-01T02:00:00Z"],
      "retentionDuration": {
        "count": 12,
        "durationType": "Months"
      }
    }
  }
}
EOF
    
    az backup policy create \
        --name "ZeroTrustVMPolicy" \
        --resource-group "$RESOURCE_GROUP" \
        --vault-name "$RECOVERY_VAULT_NAME" \
        --backup-management-type AzureIaasVM \
        --policy @/tmp/vm_policy.json || {
        log_error "Failed to create VM backup policy"
        exit 1
    }
    
    # Clean up temporary file
    rm -f /tmp/vm_policy.json
    
    log_success "Zero-trust backup policies created"
}

deploy_test_vm() {
    if [[ "$SKIP_VM" == "true" ]]; then
        log_info "Skipping test VM creation (--skip-vm flag)"
        return 0
    fi
    
    log_info "Creating test virtual machine: $VM_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create test VM and network resources"
        return 0
    fi
    
    validate_azure_name "$VM_NAME" "vm" || exit 1
    
    # Create virtual network
    az network vnet create \
        --name "vnet-backup-test" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --address-prefix 10.0.0.0/16 \
        --subnet-name "subnet-backup-test" \
        --subnet-prefix 10.0.1.0/24 || {
        log_error "Failed to create virtual network"
        exit 1
    }
    
    # Create network security group
    az network nsg create \
        --name "nsg-backup-test" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" || {
        log_error "Failed to create network security group"
        exit 1
    }
    
    # Create public IP
    az network public-ip create \
        --name "pip-backup-test" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --allocation-method Static \
        --sku Standard || {
        log_error "Failed to create public IP"
        exit 1
    }
    
    # Create network interface
    az network nic create \
        --name "nic-backup-test" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --vnet-name "vnet-backup-test" \
        --subnet "subnet-backup-test" \
        --public-ip-address "pip-backup-test" \
        --network-security-group "nsg-backup-test" || {
        log_error "Failed to create network interface"
        exit 1
    }
    
    # Generate secure password
    VM_PASSWORD=$(az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "vm-admin-password" \
        --value "$(openssl rand -base64 32 | tr -d /=+ | cut -c -16)Aa1!" \
        --query value -o tsv)
    
    # Create virtual machine
    az vm create \
        --name "$VM_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --image UbuntuLTS \
        --size Standard_B2s \
        --nics "nic-backup-test" \
        --authentication-type password \
        --admin-username azureuser \
        --admin-password "$VM_PASSWORD" \
        --tags purpose=backup-test security-level=high || {
        log_error "Failed to create virtual machine"
        exit 1
    }
    
    save_deployment_state "VM_NAME" "$VM_NAME"
    track_resource "VirtualMachine" "$VM_NAME" "$RESOURCE_GROUP"
    
    log_success "Test VM created: $VM_NAME"
}

enable_vm_backup() {
    if [[ "$SKIP_VM" == "true" ]]; then
        log_info "Skipping VM backup enablement (--skip-vm flag)"
        return 0
    fi
    
    log_info "Enabling VM backup protection"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable VM backup protection"
        return 0
    fi
    
    # Enable backup for the VM
    az backup protection enable-for-vm \
        --vm "$VM_NAME" \
        --vault-name "$RECOVERY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --policy-name "ZeroTrustVMPolicy" || {
        log_error "Failed to enable VM backup protection"
        exit 1
    }
    
    # Wait for backup protection to be enabled
    sleep 30
    
    # Verify backup protection
    az backup item show \
        --vault-name "$RECOVERY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --container-name "$VM_NAME" \
        --item-name "$VM_NAME" \
        --backup-management-type AzureIaasVM \
        --workload-type VM &> /dev/null || {
        log_warning "Backup protection may not be fully enabled yet"
    }
    
    log_success "VM backup protection enabled with zero-trust policy"
}

configure_backup_center() {
    log_info "Configuring Azure Backup Center infrastructure"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure backup center infrastructure"
        return 0
    fi
    
    validate_azure_name "$STORAGE_ACCOUNT_NAME" "storage" || exit 1
    
    # Create storage account for backup reports
    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --kind StorageV2 \
        --access-tier Hot \
        --https-only true \
        --min-tls-version TLS1_2 || {
        log_error "Failed to create storage account"
        exit 1
    }
    
    # Get storage account key
    STORAGE_KEY=$(az storage account keys list \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query '[0].value' --output tsv)
    
    # Create container for backup reports
    az storage container create \
        --name "backup-reports" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --public-access off || {
        log_error "Failed to create storage container"
        exit 1
    }
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --name "law-backup-center-$RANDOM_SUFFIX" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku PerGB2018 || {
        log_error "Failed to create Log Analytics workspace"
        exit 1
    }
    
    save_deployment_state "STORAGE_ACCOUNT_NAME" "$STORAGE_ACCOUNT_NAME"
    save_deployment_state "STORAGE_KEY" "$STORAGE_KEY"
    track_resource "StorageAccount" "$STORAGE_ACCOUNT_NAME" "$RESOURCE_GROUP"
    
    log_success "Azure Backup Center infrastructure configured"
}

create_backup_secrets() {
    log_info "Creating backup secrets in Key Vault"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create backup secrets in Key Vault"
        return 0
    fi
    
    # Store backup-related secrets
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "backup-storage-key" \
        --value "$STORAGE_KEY" \
        --description "Storage account key for backup reports" || {
        log_error "Failed to store backup storage key"
        exit 1
    }
    
    # Store example database connection string
    az keyvault secret set \
        --vault-name "$KEY_VAULT_NAME" \
        --name "sql-connection-string" \
        --value "Server=tcp:example.database.windows.net,1433;Database=mydb;User ID=admin;Password=SecurePassword123!;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;" \
        --description "SQL database connection string for backup operations" || {
        log_warning "Failed to store SQL connection string"
    }
    
    # Create certificate for backup encryption
    az keyvault certificate create \
        --vault-name "$KEY_VAULT_NAME" \
        --name "backup-encryption-cert" \
        --policy '{
          "issuerParameters": {
            "name": "Self"
          },
          "keyProperties": {
            "exportable": true,
            "keySize": 2048,
            "keyType": "RSA",
            "reuseKey": false
          },
          "x509CertificateProperties": {
            "subject": "CN=backup-encryption",
            "validityInMonths": 12
          }
        }' || {
        log_warning "Failed to create backup encryption certificate"
    }
    
    log_success "Backup secrets stored in Key Vault"
}

configure_workload_identity_federation() {
    log_info "Configuring workload identity federation"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure workload identity federation"
        return 0
    fi
    
    # Create federated identity credential for GitHub Actions
    az identity federated-credential create \
        --name "github-actions-fed-cred" \
        --identity-name "$WORKLOAD_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --issuer "https://token.actions.githubusercontent.com" \
        --subject "repo:organization/repository:ref:refs/heads/main" \
        --audience "api://AzureADTokenExchange" \
        --description "Federated credential for GitHub Actions backup automation" || {
        log_warning "Failed to create GitHub Actions federated credential"
    }
    
    # Create federated identity credential for Kubernetes workloads
    az identity federated-credential create \
        --name "k8s-backup-fed-cred" \
        --identity-name "$WORKLOAD_IDENTITY_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --issuer "https://kubernetes.default.svc.cluster.local" \
        --subject "system:serviceaccount:backup-system:backup-operator" \
        --audience "api://AzureADTokenExchange" \
        --description "Federated credential for Kubernetes backup operations" || {
        log_warning "Failed to create Kubernetes federated credential"
    }
    
    log_success "Workload identity federation configured"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    log_info "Starting Azure Zero-Trust Backup Security deployment"
    log_info "Log file: $LOG_FILE"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -r|--resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            -l|--location)
                LOCATION="$2"
                shift 2
                ;;
            -s|--subscription-id)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                VERBOSE="true"
                shift
                ;;
            -f|--force)
                FORCE="true"
                shift
                ;;
            --skip-vm)
                SKIP_VM="true"
                shift
                ;;
            --storage-redundancy)
                STORAGE_REDUNDANCY="$2"
                shift 2
                ;;
            --retention-days)
                RETENTION_DAYS="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Set default values
    RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    LOCATION="${LOCATION:-$DEFAULT_LOCATION}"
    SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
    DRY_RUN="${DRY_RUN:-false}"
    VERBOSE="${VERBOSE:-false}"
    FORCE="${FORCE:-false}"
    SKIP_VM="${SKIP_VM:-false}"
    STORAGE_REDUNDANCY="${STORAGE_REDUNDANCY:-GeoRedundant}"
    RETENTION_DAYS="${RETENTION_DAYS:-$DEFAULT_VAULT_RETENTION_DAYS}"
    BACKUP_POLICY_RETENTION_DAYS="${BACKUP_POLICY_RETENTION_DAYS:-$DEFAULT_BACKUP_POLICY_RETENTION_DAYS}"
    
    # Generate unique suffix and resource names
    RANDOM_SUFFIX=$(generate_unique_suffix)
    RESOURCE_GROUP="${RESOURCE_GROUP:-$DEFAULT_RESOURCE_GROUP_PREFIX-$RANDOM_SUFFIX}"
    
    # Set resource names
    KEY_VAULT_NAME="kv-backup-$RANDOM_SUFFIX"
    WORKLOAD_IDENTITY_NAME="wi-backup-$RANDOM_SUFFIX"
    RECOVERY_VAULT_NAME="rsv-backup-$RANDOM_SUFFIX"
    STORAGE_ACCOUNT_NAME="stbackup$RANDOM_SUFFIX"
    VM_NAME="vm-backup-test-$RANDOM_SUFFIX"
    
    # Get tenant ID
    TENANT_ID=$(az account show --query tenantId --output tsv)
    
    # Set subscription context
    az account set --subscription "$SUBSCRIPTION_ID" || {
        log_error "Failed to set subscription context"
        exit 1
    }
    
    log_info "Deployment Configuration:"
    log_info "  Resource Group: $RESOURCE_GROUP"
    log_info "  Location: $LOCATION"
    log_info "  Subscription ID: $SUBSCRIPTION_ID"
    log_info "  Tenant ID: $TENANT_ID"
    log_info "  Dry Run: $DRY_RUN"
    log_info "  Skip VM: $SKIP_VM"
    log_info "  Storage Redundancy: $STORAGE_REDUNDANCY"
    log_info "  Retention Days: $RETENTION_DAYS"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Execute deployment steps
    log_info "Starting deployment process..."
    
    deploy_resource_group
    deploy_key_vault
    deploy_workload_identity
    configure_key_vault_access
    deploy_recovery_vault
    create_backup_policies
    deploy_test_vm
    enable_vm_backup
    configure_backup_center
    create_backup_secrets
    configure_workload_identity_federation
    
    # Display summary
    log_success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        echo
        echo "=== DEPLOYMENT SUMMARY ==="
        echo "Resource Group: $RESOURCE_GROUP"
        echo "Key Vault: $KEY_VAULT_NAME"
        echo "Workload Identity: $WORKLOAD_IDENTITY_NAME"
        echo "Recovery Vault: $RECOVERY_VAULT_NAME"
        echo "Storage Account: $STORAGE_ACCOUNT_NAME"
        if [[ "$SKIP_VM" == "false" ]]; then
            echo "Test VM: $VM_NAME"
        fi
        echo
        echo "Workload Identity Configuration:"
        echo "  Client ID: $IDENTITY_CLIENT_ID"
        echo "  Tenant ID: $TENANT_ID"
        echo "  Subscription ID: $SUBSCRIPTION_ID"
        echo
        echo "Next steps:"
        echo "1. Configure external systems to use the workload identity"
        echo "2. Test backup operations using Azure Backup Center"
        echo "3. Review Key Vault access logs and audit trails"
        echo "4. Configure monitoring and alerting for backup operations"
        echo
        echo "Log file: $LOG_FILE"
        echo "Resource tracking: $RESOURCE_TRACKING_FILE"
    fi
}

# Trap to handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Execute main function
main "$@"