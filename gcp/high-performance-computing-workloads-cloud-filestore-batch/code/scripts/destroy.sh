#!/bin/bash

# Destroy script for High-Performance Computing Workloads with Cloud Filestore and Cloud Batch
# This script safely removes all resources created by the HPC deployment

set -euo pipefail

# Enable debug logging if DEBUG is set
if [[ "${DEBUG:-}" == "true" ]]; then
    set -x
fi

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check for required commands
    if ! command_exists "gcloud"; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK"
        exit 1
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "No active gcloud authentication found"
        log_error "Please run 'gcloud auth login' first"
        exit 1
    fi
    
    log_success "Prerequisites validation completed"
}

# Function to detect and set environment variables
detect_environment() {
    log_info "Detecting deployment environment..."
    
    # Try to get current project
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo "")}"
    export REGION="${REGION:-$(gcloud config get-value compute/region 2>/dev/null || echo "us-central1")}"
    export ZONE="${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null || echo "us-central1-a")}"
    
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No project ID detected. Please set PROJECT_ID environment variable or configure gcloud default project"
        exit 1
    fi
    
    log_info "Environment detected:"
    log_info "  PROJECT_ID: $PROJECT_ID"
    log_info "  REGION: $REGION"
    log_info "  ZONE: $ZONE"
    
    log_success "Environment detection completed"
}

# Function to discover HPC resources
discover_resources() {
    log_info "Discovering HPC resources to clean up..."
    
    # Discover Filestore instances
    log_info "Discovering Filestore instances..."
    readarray -t FILESTORE_INSTANCES < <(gcloud filestore instances list \
        --locations="$ZONE" \
        --filter="name~'hpc-storage-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    # Discover Batch jobs
    log_info "Discovering Batch jobs..."
    readarray -t BATCH_JOBS < <(gcloud batch jobs list \
        --location="$REGION" \
        --filter="name~'hpc-simulation-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    # Discover VPC networks
    log_info "Discovering VPC networks..."
    readarray -t VPC_NETWORKS < <(gcloud compute networks list \
        --filter="name~'hpc-network-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    # Discover instance groups
    log_info "Discovering instance groups..."
    readarray -t INSTANCE_GROUPS < <(gcloud compute instance-groups managed list \
        --zones="$ZONE" \
        --filter="name~'hpc-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    # Discover instance templates
    log_info "Discovering instance templates..."
    readarray -t INSTANCE_TEMPLATES < <(gcloud compute instance-templates list \
        --filter="name~'hpc-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    # Discover test VMs
    log_info "Discovering test VMs..."
    readarray -t TEST_VMS < <(gcloud compute instances list \
        --zones="$ZONE" \
        --filter="name~'hpc-test-'" \
        --format="value(name)" 2>/dev/null || echo "")
    
    log_success "Resource discovery completed"
}

# Function to confirm destruction
confirm_destruction() {
    local total_resources=0
    
    total_resources=$((${#FILESTORE_INSTANCES[@]} + ${#BATCH_JOBS[@]} + ${#VPC_NETWORKS[@]} + ${#INSTANCE_GROUPS[@]} + ${#INSTANCE_TEMPLATES[@]} + ${#TEST_VMS[@]}))
    
    if [[ $total_resources -eq 0 ]]; then
        log_warning "No HPC resources found to clean up"
        return 0
    fi
    
    echo ""
    log_warning "The following resources will be PERMANENTLY DELETED:"
    echo "==========================================================="
    
    if [[ ${#FILESTORE_INSTANCES[@]} -gt 0 && -n "${FILESTORE_INSTANCES[0]}" ]]; then
        echo "Filestore Instances:"
        printf "  - %s\n" "${FILESTORE_INSTANCES[@]}"
    fi
    
    if [[ ${#BATCH_JOBS[@]} -gt 0 && -n "${BATCH_JOBS[0]}" ]]; then
        echo "Batch Jobs:"
        printf "  - %s\n" "${BATCH_JOBS[@]}"
    fi
    
    if [[ ${#INSTANCE_GROUPS[@]} -gt 0 && -n "${INSTANCE_GROUPS[0]}" ]]; then
        echo "Instance Groups:"
        printf "  - %s\n" "${INSTANCE_GROUPS[@]}"
    fi
    
    if [[ ${#INSTANCE_TEMPLATES[@]} -gt 0 && -n "${INSTANCE_TEMPLATES[0]}" ]]; then
        echo "Instance Templates:"
        printf "  - %s\n" "${INSTANCE_TEMPLATES[@]}"
    fi
    
    if [[ ${#TEST_VMS[@]} -gt 0 && -n "${TEST_VMS[0]}" ]]; then
        echo "Test VMs:"
        printf "  - %s\n" "${TEST_VMS[@]}"
    fi
    
    if [[ ${#VPC_NETWORKS[@]} -gt 0 && -n "${VPC_NETWORKS[0]}" ]]; then
        echo "VPC Networks (and associated subnets/firewall rules):"
        printf "  - %s\n" "${VPC_NETWORKS[@]}"
    fi
    
    echo "==========================================================="
    echo "Total resources to delete: $total_resources"
    echo ""
    
    # Skip confirmation if FORCE_DESTROY is set
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set. Proceeding with deletion..."
        return 0
    fi
    
    # Prompt for confirmation
    while true; do
        read -p "Are you sure you want to delete these resources? (yes/no): " yn
        case $yn in
            [Yy]es ) 
                log_info "Proceeding with resource deletion..."
                break
                ;;
            [Nn]o ) 
                log_info "Deletion cancelled by user"
                exit 0
                ;;
            * ) 
                echo "Please answer yes or no."
                ;;
        esac
    done
}

# Function to delete batch jobs
delete_batch_jobs() {
    if [[ ${#BATCH_JOBS[@]} -eq 0 || -z "${BATCH_JOBS[0]}" ]]; then
        log_info "No Batch jobs to delete"
        return 0
    fi
    
    log_info "Deleting Batch jobs..."
    
    for job in "${BATCH_JOBS[@]}"; do
        if [[ -n "$job" ]]; then
            log_info "Deleting Batch job: $job"
            if gcloud batch jobs delete "$job" \
                --location="$REGION" \
                --quiet; then
                log_success "Deleted Batch job: $job"
            else
                log_warning "Failed to delete Batch job: $job (may not exist)"
            fi
        fi
    done
    
    log_success "Batch jobs cleanup completed"
}

# Function to delete test VMs
delete_test_vms() {
    if [[ ${#TEST_VMS[@]} -eq 0 || -z "${TEST_VMS[0]}" ]]; then
        log_info "No test VMs to delete"
        return 0
    fi
    
    log_info "Deleting test VMs..."
    
    for vm in "${TEST_VMS[@]}"; do
        if [[ -n "$vm" ]]; then
            log_info "Deleting test VM: $vm"
            if gcloud compute instances delete "$vm" \
                --zone="$ZONE" \
                --quiet; then
                log_success "Deleted test VM: $vm"
            else
                log_warning "Failed to delete test VM: $vm (may not exist)"
            fi
        fi
    done
    
    log_success "Test VMs cleanup completed"
}

# Function to delete instance groups
delete_instance_groups() {
    if [[ ${#INSTANCE_GROUPS[@]} -eq 0 || -z "${INSTANCE_GROUPS[0]}" ]]; then
        log_info "No instance groups to delete"
        return 0
    fi
    
    log_info "Deleting managed instance groups..."
    
    for group in "${INSTANCE_GROUPS[@]}"; do
        if [[ -n "$group" ]]; then
            log_info "Deleting instance group: $group"
            if gcloud compute instance-groups managed delete "$group" \
                --zone="$ZONE" \
                --quiet; then
                log_success "Deleted instance group: $group"
            else
                log_warning "Failed to delete instance group: $group (may not exist)"
            fi
        fi
    done
    
    log_success "Instance groups cleanup completed"
}

# Function to delete instance templates
delete_instance_templates() {
    if [[ ${#INSTANCE_TEMPLATES[@]} -eq 0 || -z "${INSTANCE_TEMPLATES[0]}" ]]; then
        log_info "No instance templates to delete"
        return 0
    fi
    
    log_info "Deleting instance templates..."
    
    for template in "${INSTANCE_TEMPLATES[@]}"; do
        if [[ -n "$template" ]]; then
            log_info "Deleting instance template: $template"
            if gcloud compute instance-templates delete "$template" \
                --quiet; then
                log_success "Deleted instance template: $template"
            else
                log_warning "Failed to delete instance template: $template (may not exist)"
            fi
        fi
    done
    
    log_success "Instance templates cleanup completed"
}

# Function to delete Filestore instances
delete_filestore_instances() {
    if [[ ${#FILESTORE_INSTANCES[@]} -eq 0 || -z "${FILESTORE_INSTANCES[0]}" ]]; then
        log_info "No Filestore instances to delete"
        return 0
    fi
    
    log_info "Deleting Filestore instances..."
    
    for instance in "${FILESTORE_INSTANCES[@]}"; do
        if [[ -n "$instance" ]]; then
            log_info "Deleting Filestore instance: $instance"
            if gcloud filestore instances delete "$instance" \
                --location="$ZONE" \
                --quiet; then
                log_success "Deleted Filestore instance: $instance"
            else
                log_warning "Failed to delete Filestore instance: $instance (may not exist)"
            fi
        fi
    done
    
    # Wait for Filestore instances to be fully deleted
    log_info "Waiting for Filestore instances to be fully deleted..."
    sleep 30
    
    log_success "Filestore instances cleanup completed"
}

# Function to delete VPC networks and associated resources
delete_vpc_networks() {
    if [[ ${#VPC_NETWORKS[@]} -eq 0 || -z "${VPC_NETWORKS[0]}" ]]; then
        log_info "No VPC networks to delete"
        return 0
    fi
    
    log_info "Deleting VPC networks and associated resources..."
    
    for network in "${VPC_NETWORKS[@]}"; do
        if [[ -n "$network" ]]; then
            log_info "Processing VPC network: $network"
            
            # Delete firewall rules for this network
            log_info "Deleting firewall rules for network: $network"
            local firewall_rules
            readarray -t firewall_rules < <(gcloud compute firewall-rules list \
                --filter="network:$network" \
                --format="value(name)" 2>/dev/null || echo "")
            
            for rule in "${firewall_rules[@]}"; do
                if [[ -n "$rule" ]]; then
                    log_info "Deleting firewall rule: $rule"
                    if gcloud compute firewall-rules delete "$rule" \
                        --quiet; then
                        log_success "Deleted firewall rule: $rule"
                    else
                        log_warning "Failed to delete firewall rule: $rule"
                    fi
                fi
            done
            
            # Delete subnets for this network
            log_info "Deleting subnets for network: $network"
            local subnets
            readarray -t subnets < <(gcloud compute networks subnets list \
                --filter="network:$network" \
                --format="value(name,region)" 2>/dev/null || echo "")
            
            for subnet_info in "${subnets[@]}"; do
                if [[ -n "$subnet_info" ]]; then
                    local subnet_name subnet_region
                    subnet_name=$(echo "$subnet_info" | cut -d' ' -f1)
                    subnet_region=$(echo "$subnet_info" | cut -d' ' -f2)
                    
                    log_info "Deleting subnet: $subnet_name in region: $subnet_region"
                    if gcloud compute networks subnets delete "$subnet_name" \
                        --region="$subnet_region" \
                        --quiet; then
                        log_success "Deleted subnet: $subnet_name"
                    else
                        log_warning "Failed to delete subnet: $subnet_name"
                    fi
                fi
            done
            
            # Delete the VPC network
            log_info "Deleting VPC network: $network"
            if gcloud compute networks delete "$network" \
                --quiet; then
                log_success "Deleted VPC network: $network"
            else
                log_warning "Failed to delete VPC network: $network"
            fi
        fi
    done
    
    log_success "VPC networks cleanup completed"
}

# Function to clean up local files
cleanup_local_files() {
    log_info "Cleaning up local configuration files..."
    
    local files_to_remove=(
        "hpc-job-config.json"
        "job-metric-descriptor.json"
        "alert-policy.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_success "Removed local file: $file"
        fi
    done
    
    log_success "Local file cleanup completed"
}

# Function to verify cleanup
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local remaining_resources=0
    
    # Check for remaining Filestore instances
    local remaining_filestore
    remaining_filestore=$(gcloud filestore instances list \
        --locations="$ZONE" \
        --filter="name~'hpc-storage-'" \
        --format="value(name)" 2>/dev/null | wc -l)
    remaining_resources=$((remaining_resources + remaining_filestore))
    
    # Check for remaining Batch jobs
    local remaining_batch
    remaining_batch=$(gcloud batch jobs list \
        --location="$REGION" \
        --filter="name~'hpc-simulation-'" \
        --format="value(name)" 2>/dev/null | wc -l)
    remaining_resources=$((remaining_resources + remaining_batch))
    
    # Check for remaining VPC networks
    local remaining_vpc
    remaining_vpc=$(gcloud compute networks list \
        --filter="name~'hpc-network-'" \
        --format="value(name)" 2>/dev/null | wc -l)
    remaining_resources=$((remaining_resources + remaining_vpc))
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "Cleanup verification passed - no HPC resources remain"
    else
        log_warning "Cleanup verification found $remaining_resources remaining resources"
        log_warning "Some resources may require manual cleanup"
    fi
    
    log_success "Cleanup verification completed"
}

# Function to display cleanup summary
display_cleanup_summary() {
    log_info "Cleanup Summary"
    echo "==============="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Zone: $ZONE"
    echo ""
    echo "Resources Cleaned Up:"
    echo "- Batch Jobs: ${#BATCH_JOBS[@]}"
    echo "- Test VMs: ${#TEST_VMS[@]}"
    echo "- Instance Groups: ${#INSTANCE_GROUPS[@]}"
    echo "- Instance Templates: ${#INSTANCE_TEMPLATES[@]}"
    echo "- Filestore Instances: ${#FILESTORE_INSTANCES[@]}"
    echo "- VPC Networks: ${#VPC_NETWORKS[@]}"
    echo ""
    echo "Post-Cleanup Actions:"
    echo "- Check Cloud Console for any remaining resources"
    echo "- Review billing for stopped charges"
    echo "- Verify no unexpected resources remain"
    echo ""
    echo "If you encounter issues:"
    echo "- Check Cloud Console for resources in ERROR state"
    echo "- Some resources may require manual deletion"
    echo "- Contact Google Cloud Support if needed"
    echo "==============="
}

# Function to handle cleanup errors
handle_cleanup_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Cleanup failed with exit code: $exit_code"
        log_warning "Some resources may still exist. Please check Cloud Console."
        log_warning "You may need to manually delete remaining resources."
    fi
    exit $exit_code
}

# Main cleanup function
main() {
    # Set trap for error handling
    trap handle_cleanup_error EXIT
    
    log_info "Starting HPC infrastructure cleanup..."
    log_info "Destroy script for: High-Performance Computing Workloads with Cloud Filestore and Cloud Batch"
    
    # Execute cleanup steps
    validate_prerequisites
    detect_environment
    discover_resources
    confirm_destruction
    
    # Delete resources in reverse order of dependencies
    delete_batch_jobs
    delete_test_vms
    delete_instance_groups
    delete_instance_templates
    delete_filestore_instances
    delete_vpc_networks
    cleanup_local_files
    verify_cleanup
    
    log_success "HPC infrastructure cleanup completed successfully!"
    display_cleanup_summary
    
    # Remove error trap
    trap - EXIT
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi