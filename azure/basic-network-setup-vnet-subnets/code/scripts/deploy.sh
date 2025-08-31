#!/bin/bash

# Azure Basic Network Setup - Deployment Script
# This script creates a Virtual Network with three subnets and associated Network Security Groups
# Based on recipe: Basic Network Setup with Virtual Network and Subnets

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error "Azure CLI is not installed. Please install it from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check Azure CLI version (minimum 2.57.0)
    local az_version=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "0.0.0")
    local min_version="2.57.0"
    
    if ! printf '%s\n%s\n' "$min_version" "$az_version" | sort -V -C; then
        warning "Azure CLI version $az_version is older than recommended minimum $min_version"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        error "Not logged in to Azure. Please run 'az login' first."
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        error "openssl is required for generating random suffixes. Please install it."
    fi
    
    success "Prerequisites check passed"
}

# Set environment variables
set_environment_variables() {
    log "Setting up environment variables..."
    
    # Default values - can be overridden by environment variables
    export LOCATION="${LOCATION:-eastus}"
    export SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-basic-network-${RANDOM_SUFFIX}}"
    
    # Virtual Network and subnet configuration
    export VNET_NAME="${VNET_NAME:-vnet-basic-network-${RANDOM_SUFFIX}}"
    export VNET_ADDRESS_SPACE="${VNET_ADDRESS_SPACE:-10.0.0.0/16}"
    export FRONTEND_SUBNET_NAME="${FRONTEND_SUBNET_NAME:-subnet-frontend}"
    export BACKEND_SUBNET_NAME="${BACKEND_SUBNET_NAME:-subnet-backend}"
    export DATABASE_SUBNET_NAME="${DATABASE_SUBNET_NAME:-subnet-database}"
    
    log "Configuration:"
    log "  Location: $LOCATION"
    log "  Resource Group: $RESOURCE_GROUP"
    log "  VNet Name: $VNET_NAME"
    log "  Address Space: $VNET_ADDRESS_SPACE"
    log "  Frontend Subnet: $FRONTEND_SUBNET_NAME"
    log "  Backend Subnet: $BACKEND_SUBNET_NAME"
    log "  Database Subnet: $DATABASE_SUBNET_NAME"
}

# Create resource group
create_resource_group() {
    log "Creating resource group..."
    
    # Check if resource group already exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        warning "Resource group $RESOURCE_GROUP already exists. Continuing with existing group."
    else
        az group create \
            --name "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo tier=networking \
            --output none
        
        success "Resource group created: $RESOURCE_GROUP"
    fi
}

# Create Virtual Network with initial subnet
create_virtual_network() {
    log "Creating Virtual Network with frontend subnet..."
    
    # Check if VNet already exists
    if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" &> /dev/null; then
        warning "Virtual Network $VNET_NAME already exists. Skipping creation."
    else
        az network vnet create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$VNET_NAME" \
            --location "$LOCATION" \
            --address-prefixes "$VNET_ADDRESS_SPACE" \
            --subnet-name "$FRONTEND_SUBNET_NAME" \
            --subnet-prefixes "10.0.1.0/24" \
            --tags purpose=recipe environment=demo \
            --output none
        
        success "Virtual Network created: $VNET_NAME"
    fi
}

# Create backend subnet
create_backend_subnet() {
    log "Creating backend subnet..."
    
    # Check if subnet already exists
    if az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$BACKEND_SUBNET_NAME" &> /dev/null; then
        warning "Backend subnet $BACKEND_SUBNET_NAME already exists. Skipping creation."
    else
        az network vnet subnet create \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$BACKEND_SUBNET_NAME" \
            --address-prefixes "10.0.2.0/24" \
            --output none
        
        success "Backend subnet created: $BACKEND_SUBNET_NAME"
    fi
}

# Create database subnet
create_database_subnet() {
    log "Creating database subnet..."
    
    # Check if subnet already exists
    if az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$DATABASE_SUBNET_NAME" &> /dev/null; then
        warning "Database subnet $DATABASE_SUBNET_NAME already exists. Skipping creation."
    else
        az network vnet subnet create \
            --resource-group "$RESOURCE_GROUP" \
            --vnet-name "$VNET_NAME" \
            --name "$DATABASE_SUBNET_NAME" \
            --address-prefixes "10.0.3.0/24" \
            --output none
        
        success "Database subnet created: $DATABASE_SUBNET_NAME"
    fi
}

# Create frontend NSG
create_frontend_nsg() {
    log "Creating Network Security Group for frontend subnet..."
    
    local nsg_name="nsg-${FRONTEND_SUBNET_NAME}"
    
    # Check if NSG already exists
    if az network nsg show --resource-group "$RESOURCE_GROUP" --name "$nsg_name" &> /dev/null; then
        warning "Frontend NSG $nsg_name already exists. Skipping creation."
    else
        # Create NSG
        az network nsg create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$nsg_name" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo tier=frontend \
            --output none
        
        # Add HTTP rule
        az network nsg rule create \
            --resource-group "$RESOURCE_GROUP" \
            --nsg-name "$nsg_name" \
            --name "Allow-HTTP" \
            --protocol tcp \
            --priority 1000 \
            --destination-port-ranges 80 \
            --access allow \
            --direction inbound \
            --source-address-prefixes "*" \
            --output none
        
        success "Frontend NSG created with HTTP rule: $nsg_name"
    fi
}

# Create backend NSG
create_backend_nsg() {
    log "Creating Network Security Group for backend subnet..."
    
    local nsg_name="nsg-${BACKEND_SUBNET_NAME}"
    
    # Check if NSG already exists
    if az network nsg show --resource-group "$RESOURCE_GROUP" --name "$nsg_name" &> /dev/null; then
        warning "Backend NSG $nsg_name already exists. Skipping creation."
    else
        # Create NSG
        az network nsg create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$nsg_name" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo tier=backend \
            --output none
        
        # Add rule to allow traffic from frontend subnet
        az network nsg rule create \
            --resource-group "$RESOURCE_GROUP" \
            --nsg-name "$nsg_name" \
            --name "Allow-From-Frontend" \
            --protocol tcp \
            --priority 1000 \
            --destination-port-ranges 8080 \
            --access allow \
            --direction inbound \
            --source-address-prefixes "10.0.1.0/24" \
            --output none
        
        success "Backend NSG created with frontend access rule: $nsg_name"
    fi
}

# Create database NSG
create_database_nsg() {
    log "Creating Network Security Group for database subnet..."
    
    local nsg_name="nsg-${DATABASE_SUBNET_NAME}"
    
    # Check if NSG already exists
    if az network nsg show --resource-group "$RESOURCE_GROUP" --name "$nsg_name" &> /dev/null; then
        warning "Database NSG $nsg_name already exists. Skipping creation."
    else
        # Create NSG
        az network nsg create \
            --resource-group "$RESOURCE_GROUP" \
            --name "$nsg_name" \
            --location "$LOCATION" \
            --tags purpose=recipe environment=demo tier=database \
            --output none
        
        # Add rule to allow database traffic from backend
        az network nsg rule create \
            --resource-group "$RESOURCE_GROUP" \
            --nsg-name "$nsg_name" \
            --name "Allow-Database-From-Backend" \
            --protocol tcp \
            --priority 1000 \
            --destination-port-ranges 5432 \
            --access allow \
            --direction inbound \
            --source-address-prefixes "10.0.2.0/24" \
            --output none
        
        success "Database NSG created with backend access rule: $nsg_name"
    fi
}

# Associate NSGs with subnets
associate_nsgs_with_subnets() {
    log "Associating Network Security Groups with subnets..."
    
    # Associate frontend NSG
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$FRONTEND_SUBNET_NAME" \
        --network-security-group "nsg-${FRONTEND_SUBNET_NAME}" \
        --output none
    
    # Associate backend NSG
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$BACKEND_SUBNET_NAME" \
        --network-security-group "nsg-${BACKEND_SUBNET_NAME}" \
        --output none
    
    # Associate database NSG
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$DATABASE_SUBNET_NAME" \
        --network-security-group "nsg-${DATABASE_SUBNET_NAME}" \
        --output none
    
    success "All NSGs associated with respective subnets"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    # Check Virtual Network
    if az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" --query "provisioningState" -o tsv 2>/dev/null | grep -q "Succeeded"; then
        success "Virtual Network validation passed"
    else
        error "Virtual Network validation failed"
    fi
    
    # Check subnets
    local subnet_count=$(az network vnet subnet list --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --query "length(@)" -o tsv 2>/dev/null || echo "0")
    if [ "$subnet_count" -eq 3 ]; then
        success "Subnet validation passed (3 subnets found)"
    else
        error "Subnet validation failed (expected 3 subnets, found $subnet_count)"
    fi
    
    # Check NSG associations
    local associated_nsgs=0
    for subnet in "$FRONTEND_SUBNET_NAME" "$BACKEND_SUBNET_NAME" "$DATABASE_SUBNET_NAME"; do
        if az network vnet subnet show --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --name "$subnet" --query "networkSecurityGroup.id" -o tsv 2>/dev/null | grep -q "nsg-"; then
            ((associated_nsgs++))
        fi
    done
    
    if [ "$associated_nsgs" -eq 3 ]; then
        success "NSG association validation passed"
    else
        error "NSG association validation failed (expected 3 associations, found $associated_nsgs)"
    fi
}

# Display deployment summary
display_summary() {
    echo
    echo "=========================================="
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY"
    echo "=========================================="
    echo
    echo "📋 Deployment Summary:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Virtual Network: $VNET_NAME ($VNET_ADDRESS_SPACE)"
    echo
    echo "🌐 Subnets Created:"
    echo "  • Frontend: $FRONTEND_SUBNET_NAME (10.0.1.0/24)"
    echo "  • Backend: $BACKEND_SUBNET_NAME (10.0.2.0/24)"
    echo "  • Database: $DATABASE_SUBNET_NAME (10.0.3.0/24)"
    echo
    echo "🔒 Network Security Groups:"
    echo "  • nsg-$FRONTEND_SUBNET_NAME (allows HTTP on port 80)"
    echo "  • nsg-$BACKEND_SUBNET_NAME (allows traffic from frontend on port 8080)"
    echo "  • nsg-$DATABASE_SUBNET_NAME (allows database traffic from backend on port 5432)"
    echo
    echo "💰 Estimated Cost: $0.00/month (Virtual Networks are free in Azure)"
    echo
    echo "🧹 To clean up resources, run: ./destroy.sh"
    echo "=========================================="
    echo
}

# Main execution function
main() {
    echo "🚀 Starting Azure Basic Network Setup Deployment"
    echo "=================================================="
    echo
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --location)
                LOCATION="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Options:"
                echo "  --dry-run              Show what would be deployed without making changes"
                echo "  --resource-group NAME  Use specific resource group name"
                echo "  --location LOCATION    Deploy to specific Azure region (default: eastus)"
                echo "  --help, -h             Show this help message"
                echo
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "DRY RUN MODE - No resources will be created"
    fi
    
    check_prerequisites
    set_environment_variables
    
    # Exit early if dry run
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "Dry run completed. No resources would be created."
        display_summary
        exit 0
    fi
    
    # Execute deployment steps
    create_resource_group
    create_virtual_network
    create_backend_subnet
    create_database_subnet
    create_frontend_nsg
    create_backend_nsg
    create_database_nsg
    associate_nsgs_with_subnets
    
    # Validate deployment
    validate_deployment
    
    # Display summary
    display_summary
}

# Error handling
trap 'error "Script failed at line $LINENO. Exit code: $?"' ERR

# Execute main function
main "$@"