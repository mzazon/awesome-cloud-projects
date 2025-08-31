#!/bin/bash

# AWS CDK Python Cleanup Script for Lightsail WordPress
# This script safely removes all resources created by the CDK deployment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VENV_NAME="venv"
STACK_NAME="LightsailWordPressStack"
DNS_STACK_NAME="LightsailDNSStack"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        print_error "AWS CLI is required but not installed."
        exit 1
    fi
    
    # Check CDK CLI
    if ! command_exists cdk; then
        print_error "AWS CDK CLI is required but not installed."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured."
        exit 1
    fi
    
    print_success "Prerequisites verified"
}

# Function to activate virtual environment if it exists
activate_venv() {
    if [ -d "$VENV_NAME" ]; then
        print_status "Activating virtual environment..."
        source "$VENV_NAME/bin/activate"
        print_success "Virtual environment activated"
    else
        print_warning "Virtual environment not found, using system Python"
    fi
}

# Function to check if stack exists
stack_exists() {
    local stack_name="$1"
    aws cloudformation describe-stacks --stack-name "$stack_name" >/dev/null 2>&1
}

# Function to destroy DNS stack
destroy_dns_stack() {
    if stack_exists "$DNS_STACK_NAME"; then
        print_status "Found DNS stack, destroying..."
        cdk destroy "$DNS_STACK_NAME" --force
        print_success "DNS stack destroyed"
    else
        print_status "DNS stack not found, skipping"
    fi
}

# Function to destroy WordPress stack
destroy_wordpress_stack() {
    if stack_exists "$STACK_NAME"; then
        print_status "Found WordPress stack, destroying..."
        cdk destroy "$STACK_NAME" --force
        print_success "WordPress stack destroyed"
    else
        print_status "WordPress stack not found, skipping"
    fi
}

# Function to verify cleanup
verify_cleanup() {
    print_status "Verifying cleanup..."
    
    # Check for remaining Lightsail instances
    local instances=$(aws lightsail get-instances \
        --query 'instances[?contains(name, `wordpress-site-`)].[name]' \
        --output text 2>/dev/null | wc -l)
    
    if [ "$instances" -gt 0 ]; then
        print_warning "Found $instances remaining Lightsail instances"
        print_warning "You may need to manually delete them from the console"
    else
        print_success "No remaining Lightsail instances found"
    fi
    
    # Check for remaining static IPs
    local static_ips=$(aws lightsail get-static-ips \
        --query 'staticIps[?contains(name, `wordpress-ip-`)].[name]' \
        --output text 2>/dev/null | wc -l)
    
    if [ "$static_ips" -gt 0 ]; then
        print_warning "Found $static_ips remaining static IPs"
        print_warning "You may need to manually release them from the console"
    else
        print_success "No remaining static IPs found"
    fi
    
    # Check CloudFormation stacks
    if stack_exists "$STACK_NAME" || stack_exists "$DNS_STACK_NAME"; then
        print_warning "Some CloudFormation stacks still exist"
        print_warning "Check the AWS CloudFormation console"
    else
        print_success "All CloudFormation stacks removed"
    fi
}

# Function to show manual cleanup instructions
show_manual_cleanup() {
    print_status "Manual cleanup verification (if needed):"
    echo ""
    echo "1. Check Lightsail Console:"
    echo "   - Go to AWS Lightsail console"
    echo "   - Verify all instances are deleted"
    echo "   - Verify all static IPs are released"
    echo "   - Check DNS zones (if created)"
    echo ""
    echo "2. Check CloudFormation Console:"
    echo "   - Go to AWS CloudFormation console"
    echo "   - Verify stacks are deleted:"
    echo "     * $STACK_NAME"
    echo "     * $DNS_STACK_NAME"
    echo ""
    echo "3. AWS CLI verification:"
    echo "   aws lightsail get-instances"
    echo "   aws lightsail get-static-ips"
    echo "   aws lightsail get-domains"
}

# Function to create snapshot before deletion (optional)
create_backup_snapshot() {
    print_status "Checking for instances to backup..."
    
    # Get WordPress instances
    local instances=$(aws lightsail get-instances \
        --query 'instances[?contains(name, `wordpress-site-`)].name' \
        --output text 2>/dev/null)
    
    if [ -n "$instances" ]; then
        while IFS= read -r instance; do
            if [ -n "$instance" ]; then
                local snapshot_name="${instance}-final-backup-$(date +%Y%m%d-%H%M%S)"
                print_status "Creating backup snapshot: $snapshot_name"
                
                aws lightsail create-instance-snapshot \
                    --instance-name "$instance" \
                    --instance-snapshot-name "$snapshot_name" \
                    >/dev/null 2>&1
                
                if [ $? -eq 0 ]; then
                    print_success "Backup snapshot created: $snapshot_name"
                else
                    print_warning "Failed to create backup snapshot for $instance"
                fi
            fi
        done <<< "$instances"
    else
        print_status "No instances found to backup"
    fi
}

# Function to confirm destructive action
confirm_deletion() {
    local force="$1"
    
    if [ "$force" != "true" ]; then
        echo ""
        print_warning "This will permanently delete all Lightsail WordPress resources!"
        print_warning "This action cannot be undone."
        echo ""
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Cleanup cancelled"
            exit 0
        fi
    fi
}

# Function to show help
show_help() {
    echo "AWS CDK Python Cleanup Script for Lightsail WordPress"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -f, --force           Skip confirmation prompt"
    echo "  -b, --backup          Create snapshots before deletion"
    echo "  -h, --help           Show this help message"
    echo "  --verify-only        Only verify cleanup, don't delete"
    echo ""
    echo "Examples:"
    echo "  $0                    # Interactive cleanup"
    echo "  $0 --force           # Force cleanup without confirmation"
    echo "  $0 --backup --force  # Backup and cleanup"
    echo "  $0 --verify-only     # Check what would be deleted"
}

# Main cleanup function
main() {
    local force=false
    local backup=false
    local verify_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force=true
                shift
                ;;
            -b|--backup)
                backup=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --verify-only)
                verify_only=true
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "======================================="
    echo "AWS Lightsail WordPress CDK Cleanup"
    echo "======================================="
    echo ""
    
    check_prerequisites
    activate_venv
    
    if [ "$verify_only" = true ]; then
        print_status "Verification mode - checking resources..."
        verify_cleanup
        exit 0
    fi
    
    if [ "$backup" = true ]; then
        create_backup_snapshot
        echo ""
    fi
    
    confirm_deletion "$force"
    
    print_status "Starting cleanup process..."
    echo ""
    
    # Destroy stacks in reverse order (DNS first, then WordPress)
    destroy_dns_stack
    destroy_wordpress_stack
    
    # Wait a moment for resources to be fully deleted
    print_status "Waiting for resources to be fully deleted..."
    sleep 10
    
    verify_cleanup
    
    echo ""
    print_success "Cleanup completed!"
    echo ""
    
    show_manual_cleanup
    
    if [ "$backup" = true ]; then
        echo ""
        print_warning "Remember: Snapshots were created and are not automatically deleted"
        print_warning "Manually delete snapshots from Lightsail console when no longer needed"
    fi
}

# Run main function with all arguments
main "$@"