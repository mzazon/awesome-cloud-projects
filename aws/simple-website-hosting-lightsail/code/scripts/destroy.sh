#!/bin/bash

# AWS Lightsail WordPress Cleanup Script
# This script safely removes all AWS Lightsail resources created by the deploy script
# Includes confirmation prompts and safety checks to prevent accidental deletions

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output formatting
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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    success "Prerequisites check passed"
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Check if environment file exists
    if [[ -f ".lightsail_env" ]]; then
        source .lightsail_env
        success "Environment loaded from .lightsail_env"
    else
        warning "Environment file not found. You'll need to provide resource names manually."
        
        # Prompt for resource names if environment file doesn't exist
        read -p "Enter WordPress instance name (or press Enter to skip): " INSTANCE_NAME
        read -p "Enter static IP name (or press Enter to skip): " STATIC_IP_NAME
        
        # Set AWS region
        export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    fi
    
    # Validate required variables
    if [[ -z "${INSTANCE_NAME:-}" ]] && [[ -z "${STATIC_IP_NAME:-}" ]]; then
        error "No resources specified for cleanup. Exiting safely."
    fi
    
    log "Cleanup configuration:"
    [[ -n "${INSTANCE_NAME:-}" ]] && log "  Instance: ${INSTANCE_NAME}"
    [[ -n "${STATIC_IP_NAME:-}" ]] && log "  Static IP: ${STATIC_IP_NAME}"
    log "  Region: ${AWS_REGION:-$(aws configure get region)}"
}

# Function to display resources to be deleted
show_resources_for_deletion() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                    RESOURCES TO BE DELETED"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    local resources_found=false
    
    # Check instance exists
    if [[ -n "${INSTANCE_NAME:-}" ]]; then
        if aws lightsail get-instance --instance-name "${INSTANCE_NAME}" &>/dev/null; then
            local instance_info=$(aws lightsail get-instance \
                --instance-name "${INSTANCE_NAME}" \
                --query 'instance.{Name:name,State:state.name,IP:publicIpAddress,Blueprint:blueprintName}' \
                --output table 2>/dev/null)
            echo "📦 Lightsail Instance:"
            echo "$instance_info"
            echo ""
            resources_found=true
        else
            warning "Instance ${INSTANCE_NAME} not found"
        fi
    fi
    
    # Check static IP exists
    if [[ -n "${STATIC_IP_NAME:-}" ]]; then
        if aws lightsail get-static-ip --static-ip-name "${STATIC_IP_NAME}" &>/dev/null; then
            local static_ip_info=$(aws lightsail get-static-ip \
                --static-ip-name "${STATIC_IP_NAME}" \
                --query 'staticIp.{Name:name,IP:ipAddress,AttachedTo:attachedTo}' \
                --output table 2>/dev/null)
            echo "🌐 Static IP:"
            echo "$static_ip_info"
            echo ""
            resources_found=true
        else
            warning "Static IP ${STATIC_IP_NAME} not found"
        fi
    fi
    
    if ! $resources_found; then
        log "No resources found to delete."
        return 1
    fi
    
    echo "═══════════════════════════════════════════════════════════════"
    return 0
}

# Function to get user confirmation
get_user_confirmation() {
    echo ""
    warning "This will permanently delete the resources shown above."
    warning "Any data stored on the WordPress instance will be lost."
    echo ""
    
    # Multiple confirmation prompts for safety
    read -p "Are you sure you want to proceed? (type 'yes' to continue): " confirmation1
    if [[ "$confirmation1" != "yes" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    read -p "Last chance! Type 'DELETE' to confirm deletion: " confirmation2
    if [[ "$confirmation2" != "DELETE" ]]; then
        log "Cleanup cancelled by user."
        exit 0
    fi
    
    success "User confirmation received. Proceeding with cleanup..."
}

# Function to create backup snapshot (optional)
offer_backup() {
    if [[ -n "${INSTANCE_NAME:-}" ]] && aws lightsail get-instance --instance-name "${INSTANCE_NAME}" &>/dev/null; then
        echo ""
        read -p "Would you like to create a backup snapshot before deletion? (y/N): " create_backup
        
        if [[ "$create_backup" =~ ^[Yy]$ ]]; then
            local snapshot_name="${INSTANCE_NAME}-final-backup-$(date +%Y%m%d-%H%M%S)"
            
            log "Creating backup snapshot: ${snapshot_name}"
            aws lightsail create-instance-snapshot \
                --instance-snapshot-name "${snapshot_name}" \
                --instance-name "${INSTANCE_NAME}"
            
            success "Backup snapshot ${snapshot_name} created"
            warning "Remember to delete this snapshot later to avoid ongoing charges"
        fi
    fi
}

# Function to detach and release static IP
cleanup_static_ip() {
    if [[ -z "${STATIC_IP_NAME:-}" ]]; then
        return 0
    fi
    
    log "Cleaning up static IP: ${STATIC_IP_NAME}"
    
    # Check if static IP exists
    if ! aws lightsail get-static-ip --static-ip-name "${STATIC_IP_NAME}" &>/dev/null; then
        warning "Static IP ${STATIC_IP_NAME} not found. Skipping."
        return 0
    fi
    
    # Check if attached to an instance
    local attached_instance=$(aws lightsail get-static-ip \
        --static-ip-name "${STATIC_IP_NAME}" \
        --query 'staticIp.attachedTo' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$attached_instance" != "None" ]] && [[ "$attached_instance" != "" ]]; then
        log "Detaching static IP from instance: ${attached_instance}"
        aws lightsail detach-static-ip \
            --static-ip-name "${STATIC_IP_NAME}" || warning "Failed to detach static IP"
        
        # Wait a moment for detachment to complete
        sleep 5
    fi
    
    # Release static IP
    log "Releasing static IP: ${STATIC_IP_NAME}"
    if aws lightsail release-static-ip --static-ip-name "${STATIC_IP_NAME}"; then
        success "Static IP ${STATIC_IP_NAME} released"
    else
        error "Failed to release static IP ${STATIC_IP_NAME}"
    fi
}

# Function to delete WordPress instance
cleanup_instance() {
    if [[ -z "${INSTANCE_NAME:-}" ]]; then
        return 0
    fi
    
    log "Cleaning up WordPress instance: ${INSTANCE_NAME}"
    
    # Check if instance exists
    if ! aws lightsail get-instance --instance-name "${INSTANCE_NAME}" &>/dev/null; then
        warning "Instance ${INSTANCE_NAME} not found. Skipping."
        return 0
    fi
    
    # Delete Lightsail instance
    log "Deleting Lightsail instance: ${INSTANCE_NAME}"
    if aws lightsail delete-instance --instance-name "${INSTANCE_NAME}"; then
        success "WordPress instance ${INSTANCE_NAME} deletion initiated"
        
        # Wait for deletion to complete
        log "Waiting for instance deletion to complete..."
        local max_attempts=20
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if ! aws lightsail get-instance --instance-name "${INSTANCE_NAME}" &>/dev/null; then
                success "Instance deletion completed"
                return 0
            fi
            
            log "Waiting for deletion... (attempt $attempt/$max_attempts)"
            sleep 15
            ((attempt++))
        done
        
        warning "Instance deletion is taking longer than expected but was initiated successfully"
    else
        error "Failed to delete instance ${INSTANCE_NAME}"
    fi
}

# Function to clean up DNS zone (if created)
cleanup_dns() {
    # This is optional since DNS setup was optional in the deploy script
    if [[ -n "${DOMAIN_NAME:-}" ]]; then
        log "Checking for DNS zone cleanup..."
        
        read -p "Do you want to delete the DNS zone for ${DOMAIN_NAME}? (y/N): " delete_dns
        if [[ "$delete_dns" =~ ^[Yy]$ ]]; then
            if aws lightsail delete-domain --domain-name "${DOMAIN_NAME}"; then
                success "DNS zone ${DOMAIN_NAME} deleted"
            else
                warning "Failed to delete DNS zone or zone doesn't exist"
            fi
        fi
    fi
}

# Function to clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    # Remove environment file
    if [[ -f ".lightsail_env" ]]; then
        rm -f .lightsail_env
        success "Environment file removed"
    fi
    
    # Clean up any other temporary files
    if [[ -f ".lightsail_deployment.log" ]]; then
        rm -f .lightsail_deployment.log
        success "Deployment log removed"
    fi
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_success=true
    
    # Verify instance deletion
    if [[ -n "${INSTANCE_NAME:-}" ]]; then
        if aws lightsail get-instance --instance-name "${INSTANCE_NAME}" &>/dev/null; then
            warning "Instance ${INSTANCE_NAME} still exists"
            cleanup_success=false
        else
            success "Instance cleanup verified"
        fi
    fi
    
    # Verify static IP release
    if [[ -n "${STATIC_IP_NAME:-}" ]]; then
        if aws lightsail get-static-ip --static-ip-name "${STATIC_IP_NAME}" &>/dev/null; then
            warning "Static IP ${STATIC_IP_NAME} still exists"
            cleanup_success=false
        else
            success "Static IP cleanup verified"
        fi
    fi
    
    if $cleanup_success; then
        success "All resources successfully cleaned up"
    else
        warning "Some resources may still exist. Check AWS Lightsail console."
    fi
}

# Function to display cleanup summary
display_cleanup_summary() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    success "Cleanup process completed!"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Resources removed:"
    [[ -n "${INSTANCE_NAME:-}" ]] && echo "  📦 Instance: ${INSTANCE_NAME}"
    [[ -n "${STATIC_IP_NAME:-}" ]] && echo "  🌐 Static IP: ${STATIC_IP_NAME}"
    echo ""
    echo "💡 Important reminders:"
    echo "  • Check AWS Lightsail console to verify all resources are removed"
    echo "  • Review AWS billing to ensure no unexpected charges"
    echo "  • Any snapshots created are NOT automatically deleted"
    echo "  • Domain DNS zones (if created) may need manual cleanup"
    echo ""
    echo "Thank you for using AWS Lightsail! 🚀"
    echo "═══════════════════════════════════════════════════════════════"
}

# Function to list all Lightsail resources (debug mode)
list_all_resources() {
    if [[ "${1:-}" == "--list-all" ]]; then
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "                    ALL LIGHTSAIL RESOURCES"
        echo "═══════════════════════════════════════════════════════════════"
        
        log "Listing all Lightsail instances..."
        aws lightsail get-instances --query 'instances[].{Name:name,State:state.name,Blueprint:blueprintName}' --output table 2>/dev/null || echo "No instances found"
        
        log "Listing all static IPs..."
        aws lightsail get-static-ips --query 'staticIps[].{Name:name,IP:ipAddress,AttachedTo:attachedTo}' --output table 2>/dev/null || echo "No static IPs found"
        
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        read -p "Press Enter to continue with cleanup..."
    fi
}

# Main execution function
main() {
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "           AWS Lightsail WordPress Cleanup Script"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Handle debug mode
    list_all_resources "${1:-}"
    
    check_prerequisites
    load_environment
    
    # Show resources and get confirmation
    if show_resources_for_deletion; then
        get_user_confirmation
        offer_backup
        
        # Perform cleanup in correct order
        cleanup_static_ip
        cleanup_instance
        cleanup_dns
        cleanup_local_files
        
        # Verify and summarize
        verify_cleanup
        display_cleanup_summary
    else
        log "No resources found to delete. Cleanup complete."
    fi
}

# Handle script interruption
trap 'warning "Cleanup interrupted. Some resources may still exist."' INT TERM

# Show help information
show_help() {
    echo "AWS Lightsail WordPress Cleanup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --help       Show this help message"
    echo "  --list-all   List all Lightsail resources before cleanup"
    echo "  --force      Skip confirmation prompts (use with caution)"
    echo ""
    echo "This script will safely remove AWS Lightsail resources created by"
    echo "the deploy.sh script, including WordPress instances and static IPs."
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --force)
        warning "Force mode not implemented for safety reasons"
        warning "Please run interactively to confirm deletions"
        exit 1
        ;;
    *)
        # Execute main function if script is run directly
        if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
            main "$@"
        fi
        ;;
esac