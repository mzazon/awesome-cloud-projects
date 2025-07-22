#!/bin/bash

# Deploy Azure Elastic SAN and VMSS Database Solution
# This script deploys the complete high-performance database workload infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Enable debug mode if DEBUG=1 is set
if [[ "${DEBUG:-0}" == "1" ]]; then
    set -x
fi

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Azure CLI authentication
check_azure_auth() {
    log_info "Checking Azure CLI authentication..."
    if ! az account show >/dev/null 2>&1; then
        log_error "Azure CLI not authenticated. Please run 'az login' first."
        exit 1
    fi
    log_success "Azure CLI authenticated"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command_exists az; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if openssl is available (for random suffix generation)
    if ! command_exists openssl; then
        log_error "OpenSSL is not installed. Please install it for random suffix generation."
        exit 1
    fi
    
    # Check Azure CLI version
    local az_version=$(az version --query '"azure-cli"' -o tsv)
    log_info "Azure CLI version: $az_version"
    
    # Check authentication
    check_azure_auth
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting environment variables..."
    
    # Default values (can be overridden)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-elastic-san-demo}"
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export ELASTIC_SAN_NAME="esan-db-${RANDOM_SUFFIX}"
    export VMSS_NAME="vmss-db-${RANDOM_SUFFIX}"
    export VNET_NAME="vnet-db-${RANDOM_SUFFIX}"
    export SUBNET_NAME="subnet-db-${RANDOM_SUFFIX}"
    export LB_NAME="lb-db-${RANDOM_SUFFIX}"
    export PG_SERVER_NAME="pg-db-${RANDOM_SUFFIX}"
    
    log_info "Resource Group: $RESOURCE_GROUP"
    log_info "Location: $LOCATION"
    log_info "Subscription ID: $SUBSCRIPTION_ID"
    log_info "Random Suffix: $RANDOM_SUFFIX"
    
    log_success "Environment variables set"
}

# Function to create resource group
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    
    if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
        log_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=demo environment=elastic-san-demo
        log_success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Function to create virtual network
create_virtual_network() {
    log_info "Creating virtual network: $VNET_NAME"
    
    az network vnet create \
        --name "$VNET_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --address-prefixes 10.0.0.0/16 \
        --subnet-name "$SUBNET_NAME" \
        --subnet-prefixes 10.0.1.0/24
    
    log_success "Virtual network and subnet created"
}

# Function to create PostgreSQL setup script
create_postgres_setup_script() {
    log_info "Creating PostgreSQL setup script..."
    
    cat << 'EOF' > /tmp/setup-postgres.sh
#!/bin/bash

# Install PostgreSQL
sudo apt-get update
sudo apt-get install -y postgresql postgresql-contrib

# Install iSCSI utilities for Elastic SAN
sudo apt-get install -y open-iscsi

# Configure PostgreSQL for high performance
sudo systemctl enable postgresql
sudo systemctl start postgresql

# Create database user and database
sudo -u postgres psql -c "CREATE USER dbadmin WITH PASSWORD 'SecurePass123!';"
sudo -u postgres psql -c "CREATE DATABASE appdb OWNER dbadmin;"

echo "PostgreSQL setup completed"
EOF
    
    log_success "PostgreSQL setup script created"
}

# Function to create Elastic SAN
create_elastic_san() {
    log_info "Creating Azure Elastic SAN: $ELASTIC_SAN_NAME"
    
    # Check if Elastic SAN extension is installed
    if ! az extension show --name elastic-san >/dev/null 2>&1; then
        log_info "Installing Azure Elastic SAN extension..."
        az extension add --name elastic-san
    fi
    
    az elastic-san create \
        --name "$ELASTIC_SAN_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --base-size-tib 1 \
        --extended-capacity-size-tib 2 \
        --sku Premium_LRS \
        --tags workload=database performance=high
    
    log_success "Elastic SAN created: $ELASTIC_SAN_NAME"
}

# Function to create volume group
create_volume_group() {
    log_info "Creating volume group for database storage..."
    
    az elastic-san volume-group create \
        --name "vg-database-storage" \
        --elastic-san-name "$ELASTIC_SAN_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --protocol-type iSCSI \
        --network-acls-virtual-network-rules \
            "[{\"id\":\"/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Network/virtualNetworks/${VNET_NAME}/subnets/${SUBNET_NAME}\",\"action\":\"Allow\"}]"
    
    log_success "Volume group created with network access controls"
}

# Function to create storage volumes
create_storage_volumes() {
    log_info "Creating storage volumes..."
    
    # Create data volume for PostgreSQL data files
    az elastic-san volume create \
        --name "vol-pg-data" \
        --volume-group-name "vg-database-storage" \
        --elastic-san-name "$ELASTIC_SAN_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --size-gib 500 \
        --creation-data-source-type None
    
    # Create log volume for PostgreSQL transaction logs
    az elastic-san volume create \
        --name "vol-pg-logs" \
        --volume-group-name "vg-database-storage" \
        --elastic-san-name "$ELASTIC_SAN_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --size-gib 200 \
        --creation-data-source-type None
    
    log_success "Storage volumes created for data and logs"
}

# Function to create VMSS
create_vmss() {
    log_info "Creating Virtual Machine Scale Set: $VMSS_NAME"
    
    az vmss create \
        --name "$VMSS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --image Ubuntu2204 \
        --admin-username azureuser \
        --generate-ssh-keys \
        --instance-count 2 \
        --vm-sku Standard_D4s_v3 \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --lb "$LB_NAME" \
        --upgrade-policy-mode manual \
        --custom-data /tmp/setup-postgres.sh
    
    log_success "Virtual Machine Scale Set created: $VMSS_NAME"
}

# Function to configure load balancer
configure_load_balancer() {
    log_info "Configuring load balancer for database access..."
    
    # Create backend pool for database instances
    az network lb address-pool create \
        --lb-name "$LB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "db-backend-pool"
    
    # Create health probe for PostgreSQL
    az network lb probe create \
        --lb-name "$LB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "postgresql-health-probe" \
        --protocol tcp \
        --port 5432 \
        --interval 15 \
        --threshold 2
    
    # Create load balancer rule for PostgreSQL
    az network lb rule create \
        --lb-name "$LB_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --name "postgresql-rule" \
        --protocol tcp \
        --frontend-port 5432 \
        --backend-port 5432 \
        --frontend-ip-name "LoadBalancerFrontEnd" \
        --backend-pool-name "db-backend-pool" \
        --probe-name "postgresql-health-probe"
    
    log_success "Load balancer configured for PostgreSQL access"
}

# Function to create PostgreSQL Flexible Server
create_postgres_flexible_server() {
    log_info "Creating PostgreSQL Flexible Server: $PG_SERVER_NAME"
    
    az postgres flexible-server create \
        --name "$PG_SERVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --admin-user pgadmin \
        --admin-password "SecurePassword123!" \
        --sku-name Standard_D2s_v3 \
        --tier GeneralPurpose \
        --storage-size 128 \
        --storage-type Premium_LRS \
        --version 14 \
        --vnet "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --high-availability Enabled \
        --zone 1 \
        --standby-zone 2
    
    log_success "PostgreSQL Flexible Server created with high availability"
}

# Function to configure auto-scaling
configure_auto_scaling() {
    log_info "Configuring auto-scaling policies..."
    
    # Create autoscale profile for VMSS
    az monitor autoscale create \
        --resource-group "$RESOURCE_GROUP" \
        --name "vmss-autoscale-profile" \
        --resource "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachineScaleSets/${VMSS_NAME}" \
        --min-count 2 \
        --max-count 10 \
        --count 2
    
    # Create scale-out rule based on CPU usage
    az monitor autoscale rule create \
        --resource-group "$RESOURCE_GROUP" \
        --autoscale-name "vmss-autoscale-profile" \
        --scale-out 1 \
        --condition "Percentage CPU > 70 avg 5m" \
        --cooldown 5
    
    # Create scale-in rule based on CPU usage
    az monitor autoscale rule create \
        --resource-group "$RESOURCE_GROUP" \
        --autoscale-name "vmss-autoscale-profile" \
        --scale-in 1 \
        --condition "Percentage CPU < 30 avg 5m" \
        --cooldown 5
    
    log_success "Auto-scaling policies configured"
}

# Function to configure monitoring
configure_monitoring() {
    log_info "Configuring monitoring and alerting..."
    
    # Create Log Analytics workspace
    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "law-db-monitoring-${RANDOM_SUFFIX}" \
        --location "$LOCATION" \
        --sku PerGB2018
    
    # Create action group for alerts
    az monitor action-group create \
        --resource-group "$RESOURCE_GROUP" \
        --name "db-alert-actions" \
        --short-name "DBAlerts"
    
    # Create alert rule for high CPU usage
    az monitor metrics alert create \
        --name "high-cpu-usage" \
        --resource-group "$RESOURCE_GROUP" \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Compute/virtualMachineScaleSets/${VMSS_NAME}" \
        --condition "avg Percentage CPU > 80" \
        --window-size 5m \
        --evaluation-frequency 1m \
        --action "db-alert-actions" \
        --description "Alert when CPU usage exceeds 80%"
    
    log_success "Monitoring and alerting configured"
}

# Function to display deployment summary
display_deployment_summary() {
    log_info "Deployment Summary:"
    echo ""
    echo "Resource Group: $RESOURCE_GROUP"
    echo "Location: $LOCATION"
    echo "Elastic SAN: $ELASTIC_SAN_NAME"
    echo "VMSS: $VMSS_NAME"
    echo "Load Balancer: $LB_NAME"
    echo "PostgreSQL Server: $PG_SERVER_NAME"
    echo "Virtual Network: $VNET_NAME"
    echo ""
    
    # Get load balancer public IP
    if LB_IP=$(az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "${LB_NAME}PublicIP" \
        --query ipAddress --output tsv 2>/dev/null); then
        echo "Load Balancer Public IP: $LB_IP"
        echo "PostgreSQL Connection: psql -h $LB_IP -U pgadmin -d postgres"
    fi
    
    echo ""
    log_success "Deployment completed successfully!"
}

# Function to handle cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code: $exit_code"
        log_warning "Some resources may have been created. Run destroy.sh to clean up."
    fi
    
    # Clean up temporary files
    rm -f /tmp/setup-postgres.sh
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -g, --resource-group    Resource group name (default: rg-elastic-san-demo)"
    echo "  -l, --location          Azure region (default: eastus)"
    echo "  --dry-run              Show what would be deployed without actually deploying"
    echo ""
    echo "Environment Variables:"
    echo "  RESOURCE_GROUP         Override default resource group"
    echo "  LOCATION              Override default location"
    echo "  DEBUG                 Enable debug mode (set to 1)"
    echo ""
    echo "Examples:"
    echo "  $0                                          # Deploy with defaults"
    echo "  $0 -g my-rg -l westus2                     # Deploy to specific resource group and location"
    echo "  DEBUG=1 $0                                  # Deploy with debug logging"
    echo "  $0 --dry-run                               # Show deployment plan"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -g|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        -l|--location)
            LOCATION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set trap for cleanup on exit
trap cleanup_on_exit EXIT

# Main deployment flow
main() {
    log_info "Starting Azure Elastic SAN and VMSS deployment..."
    
    if [[ "${DRY_RUN:-0}" == "1" ]]; then
        log_info "DRY RUN MODE - No resources will be created"
        set_environment_variables
        echo "Would deploy the following resources:"
        echo "- Resource Group: $RESOURCE_GROUP"
        echo "- Elastic SAN: $ELASTIC_SAN_NAME"
        echo "- VMSS: $VMSS_NAME"
        echo "- Load Balancer: $LB_NAME"
        echo "- PostgreSQL Server: $PG_SERVER_NAME"
        echo "- Virtual Network: $VNET_NAME"
        return 0
    fi
    
    check_prerequisites
    set_environment_variables
    create_resource_group
    create_virtual_network
    create_postgres_setup_script
    create_elastic_san
    create_volume_group
    create_storage_volumes
    create_vmss
    configure_load_balancer
    create_postgres_flexible_server
    configure_auto_scaling
    configure_monitoring
    display_deployment_summary
}

# Execute main function
main "$@"