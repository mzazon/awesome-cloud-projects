#!/bin/bash

# Security Compliance Auditing CDK Destruction Script
# This script safely removes all infrastructure created by the security compliance auditing stack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command_exists aws; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    if ! command_exists cdk; then
        print_error "AWS CDK is not installed. Install with: npm install -g aws-cdk"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    print_success "All prerequisites satisfied"
}

# Parse command line arguments
parse_arguments() {
    FORCE=false
    KEEP_DATA=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE=true
                shift
                ;;
            --keep-data)
                KEEP_DATA=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Show help message
show_help() {
    cat << EOF
Security Compliance Auditing CDK Destruction Script

Usage: $0 [OPTIONS]

Options:
    --force              Skip confirmation prompts
    --keep-data         Keep S3 bucket and data (manual cleanup required)
    -h, --help          Show this help message

Examples:
    $0                  # Interactive destruction with confirmations
    $0 --force          # Destroy without prompts
    $0 --keep-data      # Destroy stack but preserve S3 data

Warning: This will permanently delete all resources and data created by the stack!

EOF
}

# Confirm destruction
confirm_destruction() {
    if [ "$FORCE" = true ]; then
        return 0
    fi
    
    echo ""
    print_warning "This will permanently delete the following resources:"
    echo "  • GuardDuty detector (threat detection will stop)"
    echo "  • Lambda function and logs"
    echo "  • CloudWatch dashboard and metrics"
    echo "  • SNS topic and subscriptions"
    echo "  • VPC Lattice service network (if created)"
    echo "  • CloudWatch log groups"
    
    if [ "$KEEP_DATA" = false ]; then
        echo "  • S3 bucket with ALL compliance reports and data"
    fi
    
    echo ""
    read -p "Are you sure you want to proceed? (type 'yes' to confirm): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        print_status "Destruction cancelled"
        exit 0
    fi
}

# Get stack information
get_stack_info() {
    print_status "Getting stack information..."
    
    # Get current AWS account and region
    ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    
    if [ -z "$REGION" ]; then
        REGION="us-east-1"
        print_warning "No default region set, using us-east-1"
    fi
    
    print_status "Operating on account $ACCOUNT in region $REGION"
    
    # Check if stack exists
    if ! aws cloudformation describe-stacks --stack-name SecurityComplianceAuditingStack --region "$REGION" >/dev/null 2>&1; then
        print_warning "SecurityComplianceAuditingStack not found in region $REGION"
        print_status "Checking for stacks with similar names..."
        
        # Look for similar stack names
        SIMILAR_STACKS=$(aws cloudformation list-stacks --region "$REGION" --query 'StackSummaries[?contains(StackName, `SecurityCompliance`) && StackStatus != `DELETE_COMPLETE`].StackName' --output text)
        
        if [ -n "$SIMILAR_STACKS" ]; then
            print_status "Found similar stacks: $SIMILAR_STACKS"
            print_status "You may need to specify the exact stack name"
        fi
        
        exit 1
    fi
}

# Backup critical data (optional)
backup_data() {
    if [ "$KEEP_DATA" = true ]; then
        print_status "Keeping S3 data - skipping backup"
        return 0
    fi
    
    print_status "Checking for S3 bucket with compliance reports..."
    
    # Get bucket name from stack outputs
    BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name SecurityComplianceAuditingStack \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ComplianceReportsBucketName`].OutputValue' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$BUCKET_NAME" ] && [ "$BUCKET_NAME" != "None" ]; then
        # Check if bucket has objects
        OBJECT_COUNT=$(aws s3 ls s3://"$BUCKET_NAME" --recursive 2>/dev/null | wc -l || echo "0")
        
        if [ "$OBJECT_COUNT" -gt 0 ]; then
            print_warning "Found $OBJECT_COUNT objects in S3 bucket: $BUCKET_NAME"
            print_status "All compliance reports and data will be permanently deleted"
            
            if [ "$FORCE" = false ]; then
                read -p "Do you want to create a backup first? (y/N): " backup_choice
                if [[ "$backup_choice" =~ ^[Yy]$ ]]; then
                    BACKUP_DIR="./compliance-backup-$(date +%Y%m%d-%H%M%S)"
                    print_status "Creating backup in $BACKUP_DIR..."
                    mkdir -p "$BACKUP_DIR"
                    aws s3 sync s3://"$BUCKET_NAME" "$BACKUP_DIR"/
                    print_success "Backup created in $BACKUP_DIR"
                fi
            fi
        fi
    fi
}

# Destroy the stack
destroy_stack() {
    print_status "Destroying Security Compliance Auditing stack..."
    
    # Destroy with force approval
    cdk destroy --force
    
    print_success "Stack destruction initiated"
    
    # Wait for destruction to complete
    print_status "Waiting for stack destruction to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name SecurityComplianceAuditingStack \
        --region "$REGION"
    
    print_success "Stack destroyed successfully!"
}

# Clean up any remaining resources
cleanup_remaining_resources() {
    print_status "Checking for any remaining resources..."
    
    # Check for any remaining GuardDuty detectors (in case of cleanup issues)
    DETECTORS=$(aws guardduty list-detectors --region "$REGION" --query 'DetectorIds' --output text 2>/dev/null || echo "")
    
    if [ -n "$DETECTORS" ] && [ "$DETECTORS" != "None" ]; then
        print_warning "Found GuardDuty detectors that may need manual cleanup"
        print_status "Detectors: $DETECTORS"
    fi
    
    print_success "Cleanup check completed"
}

# Show post-destruction information
show_destruction_info() {
    print_success "Destruction completed!"
    echo ""
    print_status "What was removed:"
    echo "  ✓ CDK stack and all managed resources"
    echo "  ✓ GuardDuty detector (threat detection stopped)"
    echo "  ✓ Lambda function and execution logs"
    echo "  ✓ CloudWatch dashboard and custom metrics"
    echo "  ✓ SNS topic and email subscriptions"
    echo "  ✓ VPC Lattice service network (if created)"
    echo "  ✓ CloudWatch log groups"
    
    if [ "$KEEP_DATA" = false ]; then
        echo "  ✓ S3 bucket with all compliance reports"
    else
        echo "  ⚠ S3 bucket and data preserved (manual cleanup required)"
    fi
    
    echo ""
    print_status "Important notes:"
    echo "  • Email subscriptions are automatically cancelled"
    echo "  • Custom CloudWatch metrics will expire naturally"
    echo "  • No ongoing charges from this stack"
    
    if [ "$KEEP_DATA" = true ]; then
        echo "  • S3 bucket still exists and may incur storage charges"
        echo "  • Remember to manually delete the S3 bucket when no longer needed"
    fi
    
    echo ""
    print_success "Security compliance auditing infrastructure successfully removed!"
}

# Main execution
main() {
    echo "🗑️  Security Compliance Auditing CDK Destruction"
    echo "=============================================="
    echo ""
    
    parse_arguments "$@"
    check_prerequisites
    get_stack_info
    confirm_destruction
    backup_data
    destroy_stack
    cleanup_remaining_resources
    show_destruction_info
}

# Run main function with all arguments
main "$@"