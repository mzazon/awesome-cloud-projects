#!/bin/bash

# Azure Advanced Network Segmentation with Service Mesh and DNS Private Zones - Cleanup Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[$timestamp] INFO: $message${NC}"
            ;;
        "WARN")
            echo -e "${YELLOW}[$timestamp] WARN: $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}[$timestamp] ERROR: $message${NC}"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[$timestamp] DEBUG: $message${NC}"
            fi
            ;;
    esac
}

# Error handling function
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Cleanup encountered an error. Some resources may remain."
    exit 1
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    echo -e "${BLUE}Progress: [$current/$total] $message${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites for cleanup..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        error_exit "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log "WARN" "kubectl is not installed. Kubernetes resource cleanup will be skipped."
        SKIP_KUBERNETES=true
    fi
    
    # Check if user is logged in
    if ! az account show &> /dev/null; then
        error_exit "Please log in to Azure using 'az login'"
    fi
    
    log "INFO" "Prerequisites check completed"
}

# Function to validate environment variables
validate_environment() {
    log "INFO" "Validating environment variables..."
    
    # Set default values if not provided
    export RESOURCE_GROUP="${RESOURCE_GROUP:-rg-advanced-network-segmentation}"
    export AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-aks-service-mesh-cluster}"
    export DNS_ZONE_NAME="${DNS_ZONE_NAME:-company.internal}"
    export APP_GATEWAY_NAME="${APP_GATEWAY_NAME:-agw-service-mesh}"
    export VNET_NAME="${VNET_NAME:-vnet-service-mesh}"
    export LOG_ANALYTICS_NAME="${LOG_ANALYTICS_NAME:-log-advanced-networking}"
    
    log "INFO" "Environment variables validated:"
    log "INFO" "  Resource Group: ${RESOURCE_GROUP}"
    log "INFO" "  AKS Cluster: ${AKS_CLUSTER_NAME}"
    log "INFO" "  DNS Zone: ${DNS_ZONE_NAME}"
}

# Function to confirm destruction
confirm_destruction() {
    if [[ "${FORCE:-false}" != "true" ]]; then
        log "WARN" "This will permanently delete all resources in resource group: ${RESOURCE_GROUP}"
        log "WARN" "This action cannot be undone!"
        echo -n "Are you sure you want to continue? (yes/no): "
        read -r response
        
        if [[ ! "$response" =~ ^[Yy][Ee][Ss]$ ]]; then
            log "INFO" "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    log "INFO" "Proceeding with resource cleanup..."
}

# Function to configure kubectl if AKS cluster exists
configure_kubectl() {
    if [[ "${SKIP_KUBERNETES:-false}" == "true" ]]; then
        log "WARN" "Skipping kubectl configuration"
        return 0
    fi
    
    log "INFO" "Configuring kubectl for cleanup..."
    
    # Check if AKS cluster exists
    if az aks show --resource-group "${RESOURCE_GROUP}" --name "${AKS_CLUSTER_NAME}" &> /dev/null; then
        log "INFO" "Configuring kubectl for AKS cluster"
        az aks get-credentials \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AKS_CLUSTER_NAME}" \
            --overwrite-existing \
            --output table || log "WARN" "Failed to configure kubectl"
    else
        log "WARN" "AKS cluster not found, skipping kubectl configuration"
        SKIP_KUBERNETES=true
    fi
}

# Function to remove Istio configurations
remove_istio_configurations() {
    if [[ "${SKIP_KUBERNETES:-false}" == "true" ]]; then
        log "WARN" "Skipping Istio configuration cleanup"
        return 0
    fi
    
    show_progress 1 8 "Removing Istio configurations..."
    
    log "INFO" "Removing Istio gateways and virtual services"
    kubectl delete gateway,virtualservice,destinationrule,authorizationpolicy --all -n frontend --ignore-not-found=true || true
    kubectl delete gateway,virtualservice,destinationrule,authorizationpolicy --all -n backend --ignore-not-found=true || true
    kubectl delete gateway,virtualservice,destinationrule,authorizationpolicy --all -n database --ignore-not-found=true || true
    
    log "INFO" "Removing Istio monitoring components"
    kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml --ignore-not-found=true || true
    kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml --ignore-not-found=true || true
    kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/grafana.yaml --ignore-not-found=true || true
    kubectl delete -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml --ignore-not-found=true || true
    
    log "INFO" "Istio configurations removed"
}

# Function to remove applications
remove_applications() {
    if [[ "${SKIP_KUBERNETES:-false}" == "true" ]]; then
        log "WARN" "Skipping application cleanup"
        return 0
    fi
    
    show_progress 2 8 "Removing sample applications..."
    
    log "INFO" "Removing sample microservices"
    kubectl delete deployment,service --all -n frontend --ignore-not-found=true || true
    kubectl delete deployment,service --all -n backend --ignore-not-found=true || true
    kubectl delete deployment,service --all -n database --ignore-not-found=true || true
    
    log "INFO" "Removing network policies"
    kubectl delete networkpolicy --all -n frontend --ignore-not-found=true || true
    kubectl delete networkpolicy --all -n backend --ignore-not-found=true || true
    kubectl delete networkpolicy --all -n database --ignore-not-found=true || true
    
    log "INFO" "Removing application namespaces"
    kubectl delete namespace frontend --ignore-not-found=true || true
    kubectl delete namespace backend --ignore-not-found=true || true
    kubectl delete namespace database --ignore-not-found=true || true
    
    log "INFO" "Removing CoreDNS custom configuration"
    kubectl delete configmap coredns-custom -n kube-system --ignore-not-found=true || true
    
    log "INFO" "Sample applications removed"
}

# Function to remove Azure Monitor alerts
remove_monitor_alerts() {
    show_progress 3 8 "Removing Azure Monitor alerts..."
    
    log "INFO" "Removing Azure Monitor alerts"
    az monitor metrics alert delete \
        --name "High Service Mesh Latency" \
        --resource-group "${RESOURCE_GROUP}" \
        --yes 2>/dev/null || log "WARN" "Failed to remove High Service Mesh Latency alert"
    
    log "INFO" "Azure Monitor alerts removed"
}

# Function to remove Application Gateway
remove_application_gateway() {
    show_progress 4 8 "Removing Application Gateway..."
    
    # Check if Application Gateway exists
    if az network application-gateway show --resource-group "${RESOURCE_GROUP}" --name "${APP_GATEWAY_NAME}" &> /dev/null; then
        log "INFO" "Removing Application Gateway: ${APP_GATEWAY_NAME}"
        az network application-gateway delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${APP_GATEWAY_NAME}" \
            --output table || log "WARN" "Failed to remove Application Gateway"
    else
        log "WARN" "Application Gateway not found: ${APP_GATEWAY_NAME}"
    fi
    
    # Remove public IP
    if az network public-ip show --resource-group "${RESOURCE_GROUP}" --name appgw-public-ip &> /dev/null; then
        log "INFO" "Removing Application Gateway public IP"
        az network public-ip delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name appgw-public-ip \
            --output table || log "WARN" "Failed to remove public IP"
    else
        log "WARN" "Application Gateway public IP not found"
    fi
    
    log "INFO" "Application Gateway resources removed"
}

# Function to remove DNS Private Zone
remove_dns_private_zone() {
    show_progress 5 8 "Removing DNS Private Zone..."
    
    # Check if DNS Private Zone exists
    if az network private-dns zone show --resource-group "${RESOURCE_GROUP}" --name "${DNS_ZONE_NAME}" &> /dev/null; then
        log "INFO" "Removing DNS Private Zone: ${DNS_ZONE_NAME}"
        az network private-dns zone delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${DNS_ZONE_NAME}" \
            --yes \
            --output table || log "WARN" "Failed to remove DNS Private Zone"
    else
        log "WARN" "DNS Private Zone not found: ${DNS_ZONE_NAME}"
    fi
    
    log "INFO" "DNS Private Zone removed"
}

# Function to remove AKS cluster
remove_aks_cluster() {
    show_progress 6 8 "Removing AKS cluster..."
    
    # Check if AKS cluster exists
    if az aks show --resource-group "${RESOURCE_GROUP}" --name "${AKS_CLUSTER_NAME}" &> /dev/null; then
        log "INFO" "Removing AKS cluster: ${AKS_CLUSTER_NAME}"
        log "WARN" "This may take 10-15 minutes..."
        
        az aks delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${AKS_CLUSTER_NAME}" \
            --yes \
            --no-wait \
            --output table || log "WARN" "Failed to initiate AKS cluster deletion"
        
        log "INFO" "AKS cluster deletion initiated"
    else
        log "WARN" "AKS cluster not found: ${AKS_CLUSTER_NAME}"
    fi
}

# Function to remove virtual network
remove_virtual_network() {
    show_progress 7 8 "Removing virtual network..."
    
    # Check if virtual network exists
    if az network vnet show --resource-group "${RESOURCE_GROUP}" --name "${VNET_NAME}" &> /dev/null; then
        log "INFO" "Removing virtual network: ${VNET_NAME}"
        az network vnet delete \
            --resource-group "${RESOURCE_GROUP}" \
            --name "${VNET_NAME}" \
            --output table || log "WARN" "Failed to remove virtual network"
    else
        log "WARN" "Virtual network not found: ${VNET_NAME}"
    fi
    
    log "INFO" "Virtual network removed"
}

# Function to remove resource group
remove_resource_group() {
    show_progress 8 8 "Removing resource group..."
    
    if [[ "${KEEP_RESOURCE_GROUP:-false}" == "true" ]]; then
        log "INFO" "Keeping resource group as requested"
        return 0
    fi
    
    # Check if resource group exists
    if az group exists --name "${RESOURCE_GROUP}" --output table 2>/dev/null | grep -q "True"; then
        log "INFO" "Removing resource group: ${RESOURCE_GROUP}"
        log "WARN" "This will remove ALL resources in the resource group"
        log "WARN" "This may take 10-15 minutes to complete..."
        
        az group delete \
            --name "${RESOURCE_GROUP}" \
            --yes \
            --no-wait \
            --output table || log "WARN" "Failed to initiate resource group deletion"
        
        log "INFO" "Resource group deletion initiated"
    else
        log "WARN" "Resource group not found: ${RESOURCE_GROUP}"
    fi
}

# Function to wait for resource deletion
wait_for_deletion() {
    if [[ "${WAIT_FOR_COMPLETION:-false}" == "true" ]]; then
        log "INFO" "Waiting for resource deletion to complete..."
        
        local max_attempts=120  # 20 minutes
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if ! az group exists --name "${RESOURCE_GROUP}" --output table 2>/dev/null | grep -q "True"; then
                log "INFO" "Resource group deletion completed"
                return 0
            fi
            
            log "INFO" "Waiting for deletion to complete... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        log "WARN" "Resource deletion is taking longer than expected"
        log "WARN" "Please check the Azure portal for completion status"
    else
        log "INFO" "Resource deletion initiated. Use --wait to wait for completion."
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "INFO" "Cleaning up local files..."
    
    # Remove kubectl config context
    if command -v kubectl &> /dev/null; then
        local context_name="${AKS_CLUSTER_NAME}"
        if kubectl config get-contexts -o name | grep -q "${context_name}"; then
            log "INFO" "Removing kubectl context: ${context_name}"
            kubectl config delete-context "${context_name}" 2>/dev/null || true
        fi
    fi
    
    # Clean up any temporary files
    rm -f /tmp/istio-*.yaml 2>/dev/null || true
    rm -f /tmp/azure-*.json 2>/dev/null || true
    
    log "INFO" "Local files cleaned up"
}

# Function to verify resource deletion
verify_deletion() {
    log "INFO" "Verifying resource deletion..."
    
    # Check if resource group still exists
    if az group exists --name "${RESOURCE_GROUP}" --output table 2>/dev/null | grep -q "True"; then
        log "WARN" "Resource group still exists: ${RESOURCE_GROUP}"
        log "WARN" "Deletion may still be in progress"
        
        # List remaining resources
        log "INFO" "Remaining resources in resource group:"
        az resource list --resource-group "${RESOURCE_GROUP}" --output table 2>/dev/null || true
    else
        log "INFO" "Resource group successfully deleted: ${RESOURCE_GROUP}"
    fi
}

# Function to display cleanup summary
display_summary() {
    log "INFO" "Cleanup Summary:"
    log "INFO" "==============="
    log "INFO" "Resource Group: ${RESOURCE_GROUP}"
    log "INFO" "AKS Cluster: ${AKS_CLUSTER_NAME}"
    log "INFO" "DNS Zone: ${DNS_ZONE_NAME}"
    log "INFO" "Application Gateway: ${APP_GATEWAY_NAME}"
    log "INFO" ""
    
    if az group exists --name "${RESOURCE_GROUP}" --output table 2>/dev/null | grep -q "True"; then
        log "WARN" "Resource group still exists - deletion may be in progress"
        log "INFO" "Check deletion status: az group show --name ${RESOURCE_GROUP}"
    else
        log "INFO" "All resources successfully removed"
    fi
    
    log "INFO" ""
    log "INFO" "Cleanup completed!"
}

# Main cleanup function
main() {
    log "INFO" "Starting Azure Advanced Network Segmentation cleanup..."
    log "INFO" "======================================================"
    
    # Set script directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --resource-group)
                RESOURCE_GROUP="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --keep-resource-group)
                KEEP_RESOURCE_GROUP=true
                shift
                ;;
            --wait)
                WAIT_FOR_COMPLETION=true
                shift
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --resource-group NAME    Resource group name (default: rg-advanced-network-segmentation)"
                echo "  --force                  Skip confirmation prompts"
                echo "  --keep-resource-group    Keep the resource group after cleanup"
                echo "  --wait                   Wait for deletion to complete"
                echo "  --debug                  Enable debug logging"
                echo "  --help                   Show this help message"
                exit 0
                ;;
            *)
                error_exit "Unknown option: $1"
                ;;
        esac
    done
    
    # Execute cleanup steps
    check_prerequisites
    validate_environment
    confirm_destruction
    configure_kubectl
    remove_istio_configurations
    remove_applications
    remove_monitor_alerts
    remove_application_gateway
    remove_dns_private_zone
    remove_aks_cluster
    remove_virtual_network
    remove_resource_group
    wait_for_deletion
    cleanup_local_files
    verify_deletion
    display_summary
    
    log "INFO" "Cleanup process completed!"
    log "INFO" "Total cleanup time: $SECONDS seconds"
}

# Run main function
main "$@"