#!/bin/bash

# Network Security Monitoring with VPC Flow Logs and Security Command Center - Cleanup Script
# This script removes all resources created by the deployment script

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output formatting
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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Display banner
display_banner() {
    echo -e "${RED}"
    echo "=============================================================="
    echo "  Network Security Monitoring Infrastructure Cleanup"
    echo "  ⚠️  WARNING: This will DELETE all created resources"
    echo "=============================================================="
    echo -e "${NC}"
}

# Confirmation prompt
confirm_destruction() {
    echo -e "${YELLOW}This script will permanently delete the following resources:${NC}"
    echo "• VPC network and subnet"
    echo "• VM instances"
    echo "• Firewall rules"
    echo "• BigQuery dataset and all data"
    echo "• Cloud Logging sink"
    echo "• Cloud Monitoring alert policies"
    echo "• Pub/Sub topics"
    echo ""
    
    if [[ "${FORCE_DESTROY:-}" == "true" ]]; then
        log_warning "FORCE_DESTROY is set - skipping confirmation"
        return 0
    fi
    
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
    if [[ ! $REPLY =~ ^yes$ ]]; then
        log_info "Cleanup cancelled by user"
        exit 0
    fi
}

# Check prerequisites and setup environment
setup_environment() {
    log_info "Setting up environment for cleanup..."
    
    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed"
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Get project and set environment variables
    export PROJECT_ID=$(gcloud config get-value project)
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "No active project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    # Set default values - these can be overridden by environment variables
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export VPC_NAME="${VPC_NAME:-security-monitoring-vpc}"
    export SUBNET_NAME="${SUBNET_NAME:-monitored-subnet}"
    export DATASET_NAME="${DATASET_NAME:-security_monitoring}"
    
    # Set gcloud defaults
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log_success "Environment configured for project: $PROJECT_ID"
}

# Find and delete VM instances
delete_vm_instances() {
    log_info "Deleting VM instances..."
    
    # Find instances in the monitoring subnet
    local instances
    instances=$(gcloud compute instances list \
        --filter="networkInterfaces.subnetwork:($SUBNET_NAME)" \
        --format="value(name,zone)" 2>/dev/null || echo "")
    
    if [[ -n "$instances" ]]; then
        while read -r instance_name zone_path; do
            if [[ -n "$instance_name" && -n "$zone_path" ]]; then
                local zone_name
                zone_name=$(basename "$zone_path")
                log_info "Deleting instance: $instance_name in zone: $zone_name"
                
                if gcloud compute instances delete "$instance_name" \
                    --zone="$zone_name" \
                    --quiet; then
                    log_success "✓ Deleted instance: $instance_name"
                else
                    log_warning "Failed to delete instance: $instance_name"
                fi
            fi
        done <<< "$instances"
    else
        log_info "No VM instances found in subnet $SUBNET_NAME"
    fi
    
    # Also try to delete by known naming pattern (test-vm-*)
    local test_instances
    test_instances=$(gcloud compute instances list \
        --filter="name~test-vm-.*" \
        --format="value(name,zone)" 2>/dev/null || echo "")
    
    if [[ -n "$test_instances" ]]; then
        while read -r instance_name zone_path; do
            if [[ -n "$instance_name" && -n "$zone_path" ]]; then
                local zone_name
                zone_name=$(basename "$zone_path")
                log_info "Deleting test instance: $instance_name in zone: $zone_name"
                
                if gcloud compute instances delete "$instance_name" \
                    --zone="$zone_name" \
                    --quiet; then
                    log_success "✓ Deleted test instance: $instance_name"
                else
                    log_warning "Failed to delete test instance: $instance_name"
                fi
            fi
        done <<< "$test_instances"
    fi
}

# Delete firewall rules
delete_firewall_rules() {
    log_info "Deleting firewall rules..."
    
    # Find firewall rules for our VPC
    local firewall_rules
    firewall_rules=$(gcloud compute firewall-rules list \
        --filter="network:($VPC_NAME)" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$firewall_rules" ]]; then
        while read -r rule_name; do
            if [[ -n "$rule_name" ]]; then
                log_info "Deleting firewall rule: $rule_name"
                if gcloud compute firewall-rules delete "$rule_name" --quiet; then
                    log_success "✓ Deleted firewall rule: $rule_name"
                else
                    log_warning "Failed to delete firewall rule: $rule_name"
                fi
            fi
        done <<< "$firewall_rules"
    else
        log_info "No firewall rules found for VPC: $VPC_NAME"
    fi
}

# Delete logging sinks
delete_logging_sinks() {
    log_info "Deleting logging sinks..."
    
    # Find sinks that contain our naming pattern
    local sinks
    sinks=$(gcloud logging sinks list \
        --filter="name~.*vpc-flow-security-sink.*" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$sinks" ]]; then
        while read -r sink_name; do
            if [[ -n "$sink_name" ]]; then
                log_info "Deleting logging sink: $sink_name"
                if gcloud logging sinks delete "$sink_name" --quiet; then
                    log_success "✓ Deleted logging sink: $sink_name"
                else
                    log_warning "Failed to delete logging sink: $sink_name"
                fi
            fi
        done <<< "$sinks"
    else
        log_info "No logging sinks found with pattern: vpc-flow-security-sink"
    fi
}

# Delete BigQuery dataset
delete_bigquery_dataset() {
    log_info "Deleting BigQuery dataset..."
    
    if ! command -v bq &> /dev/null; then
        log_warning "BigQuery CLI (bq) not found - skipping dataset deletion"
        return
    fi
    
    if bq show --dataset "$PROJECT_ID:$DATASET_NAME" &>/dev/null; then
        log_info "Deleting BigQuery dataset: $DATASET_NAME"
        
        # Force delete dataset and all tables
        if bq rm -r -f "$DATASET_NAME"; then
            log_success "✓ Deleted BigQuery dataset: $DATASET_NAME"
        else
            log_warning "Failed to delete BigQuery dataset: $DATASET_NAME"
        fi
    else
        log_info "BigQuery dataset $DATASET_NAME not found"
    fi
}

# Delete Cloud Monitoring alert policies
delete_alert_policies() {
    log_info "Deleting Cloud Monitoring alert policies..."
    
    # Find alert policies with our naming pattern
    local policies
    policies=$(gcloud alpha monitoring policies list \
        --filter="displayName~.*(High Network Traffic Volume Alert|Suspicious Connection Patterns Alert).*" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$policies" ]]; then
        while read -r policy_name; do
            if [[ -n "$policy_name" ]]; then
                log_info "Deleting alert policy: $policy_name"
                if gcloud alpha monitoring policies delete "$policy_name" --quiet; then
                    log_success "✓ Deleted alert policy: $policy_name"
                else
                    log_warning "Failed to delete alert policy: $policy_name"
                fi
            fi
        done <<< "$policies"
    else
        log_info "No alert policies found with monitoring patterns"
    fi
}

# Delete Pub/Sub topics
delete_pubsub_topics() {
    log_info "Deleting Pub/Sub topics..."
    
    # Find topics with our naming pattern
    local topics
    topics=$(gcloud pubsub topics list \
        --filter="name~.*security-findings.*" \
        --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -n "$topics" ]]; then
        while read -r topic_path; do
            if [[ -n "$topic_path" ]]; then
                local topic_name
                topic_name=$(basename "$topic_path")
                log_info "Deleting Pub/Sub topic: $topic_name"
                if gcloud pubsub topics delete "$topic_name" --quiet; then
                    log_success "✓ Deleted Pub/Sub topic: $topic_name"
                else
                    log_warning "Failed to delete Pub/Sub topic: $topic_name"
                fi
            fi
        done <<< "$topics"
    else
        log_info "No Pub/Sub topics found with pattern: security-findings"
    fi
}

# Delete VPC subnet
delete_subnet() {
    log_info "Deleting VPC subnet..."
    
    if gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" --quiet &>/dev/null; then
        log_info "Deleting subnet: $SUBNET_NAME"
        if gcloud compute networks subnets delete "$SUBNET_NAME" \
            --region="$REGION" \
            --quiet; then
            log_success "✓ Deleted subnet: $SUBNET_NAME"
        else
            log_warning "Failed to delete subnet: $SUBNET_NAME"
        fi
    else
        log_info "Subnet $SUBNET_NAME not found"
    fi
}

# Delete VPC network
delete_vpc_network() {
    log_info "Deleting VPC network..."
    
    if gcloud compute networks describe "$VPC_NAME" --quiet &>/dev/null; then
        log_info "Deleting VPC network: $VPC_NAME"
        if gcloud compute networks delete "$VPC_NAME" --quiet; then
            log_success "✓ Deleted VPC network: $VPC_NAME"
        else
            log_warning "Failed to delete VPC network: $VPC_NAME"
        fi
    else
        log_info "VPC network $VPC_NAME not found"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove any temporary policy files that might exist
    rm -f /tmp/high-traffic-alert-*.yaml
    rm -f /tmp/suspicious-connections-alert-*.yaml
    
    log_success "✓ Temporary files cleaned up"
}

# Validate cleanup
validate_cleanup() {
    log_info "Validating resource cleanup..."
    
    local remaining_resources=0
    
    # Check VPC network
    if gcloud compute networks describe "$VPC_NAME" --quiet &>/dev/null; then
        log_warning "✗ VPC network still exists: $VPC_NAME"
        ((remaining_resources++))
    else
        log_success "✓ VPC network deleted"
    fi
    
    # Check subnet
    if gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" --quiet &>/dev/null; then
        log_warning "✗ Subnet still exists: $SUBNET_NAME"
        ((remaining_resources++))
    else
        log_success "✓ Subnet deleted"
    fi
    
    # Check for remaining instances in the project that match our pattern
    local remaining_instances
    remaining_instances=$(gcloud compute instances list \
        --filter="name~test-vm-.*" \
        --format="value(name)" 2>/dev/null | wc -l)
    
    if [[ $remaining_instances -gt 0 ]]; then
        log_warning "✗ $remaining_instances test VM instances still exist"
        ((remaining_resources++))
    else
        log_success "✓ All test VM instances deleted"
    fi
    
    # Check BigQuery dataset
    if command -v bq &> /dev/null && bq show --dataset "$PROJECT_ID:$DATASET_NAME" &>/dev/null; then
        log_warning "✗ BigQuery dataset still exists: $DATASET_NAME"
        ((remaining_resources++))
    else
        log_success "✓ BigQuery dataset deleted"
    fi
    
    if [[ $remaining_resources -eq 0 ]]; then
        log_success "🎉 All resources successfully cleaned up!"
        return 0
    else
        log_warning "$remaining_resources resources still exist - manual cleanup may be required"
        return 1
    fi
}

# Display cleanup summary
display_summary() {
    echo ""
    log_info "Cleanup Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "VPC Network: $VPC_NAME (deleted)"
    echo "Subnet: $SUBNET_NAME (deleted)"
    echo "BigQuery Dataset: $DATASET_NAME (deleted)"
    echo ""
    
    log_info "What was cleaned up:"
    echo "• VM instances matching test-vm-* pattern"
    echo "• Firewall rules for the VPC network"
    echo "• VPC subnet with flow logs"
    echo "• VPC network"
    echo "• BigQuery dataset and all contained data"
    echo "• Cloud Logging sinks"
    echo "• Cloud Monitoring alert policies"
    echo "• Pub/Sub topics for security findings"
    echo "• Temporary files"
    echo ""
    
    log_warning "Note: Some IAM policy bindings may remain and need manual cleanup"
    log_info "All billable resources have been removed"
}

# Error handling function
cleanup_on_error() {
    local exit_code=$?
    log_error "Cleanup script failed with exit code: $exit_code"
    log_warning "Some resources may still exist. Check the output above for details."
    exit $exit_code
}

# Set error trap
trap cleanup_on_error ERR

# Main cleanup function
main() {
    display_banner
    confirm_destruction
    setup_environment
    
    log_info "Starting resource cleanup..."
    
    # Delete resources in reverse order of creation
    delete_vm_instances
    sleep 10  # Wait for instances to be fully deleted
    
    delete_firewall_rules
    delete_logging_sinks
    delete_bigquery_dataset
    delete_alert_policies
    delete_pubsub_topics
    delete_subnet
    sleep 5   # Wait for subnet deletion
    
    delete_vpc_network
    cleanup_temp_files
    
    # Validate and summarize
    if validate_cleanup; then
        log_success "🎉 Cleanup completed successfully!"
    else
        log_warning "Cleanup completed with some remaining resources"
        log_info "You may need to manually remove some resources from the Google Cloud Console"
    fi
    
    display_summary
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            export FORCE_DESTROY="true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompt"
            echo "  --help     Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  REGION     GCP region (default: us-central1)"
            echo "  ZONE       GCP zone (default: us-central1-a)"
            echo "  VPC_NAME   VPC network name (default: security-monitoring-vpc)"
            echo "  SUBNET_NAME Subnet name (default: monitored-subnet)"
            echo "  DATASET_NAME BigQuery dataset name (default: security_monitoring)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main "$@"