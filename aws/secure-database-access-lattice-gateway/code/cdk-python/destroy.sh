#!/bin/bash

# Secure Database Access with VPC Lattice Resource Gateway - Cleanup Script
# This script safely removes all AWS resources created by the CDK deployment

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites for Cleanup"
    
    # Check AWS CLI
    if ! command_exists aws; then
        print_error "AWS CLI is required but not installed"
        exit 1
    fi
    
    # Check CDK
    if ! command_exists cdk; then
        print_error "AWS CDK is required but not installed"
        exit 1
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    account_id=$(aws sts get-caller-identity --query Account --output text)
    region=$(aws configure get region)
    print_status "AWS Account: $account_id"
    print_status "AWS Region: $region ✓"
}

# Function to check if stack exists
check_stack_exists() {
    if aws cloudformation describe-stacks --stack-name SecureDatabaseAccessStack >/dev/null 2>&1; then
        return 0  # Stack exists
    else
        return 1  # Stack does not exist
    fi
}

# Function to get stack outputs for manual cleanup reference
get_stack_outputs() {
    print_header "Retrieving Stack Information"
    
    if check_stack_exists; then
        print_status "Current stack outputs:"
        aws cloudformation describe-stacks \
            --stack-name SecureDatabaseAccessStack \
            --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
            --output table 2>/dev/null || print_warning "Could not retrieve stack outputs"
    else
        print_warning "Stack 'SecureDatabaseAccessStack' does not exist"
    fi
}

# Function to confirm deletion
confirm_deletion() {
    print_header "Deletion Confirmation"
    
    print_warning "This will permanently delete all resources created by the Secure Database Access stack"
    print_warning "Resources to be deleted include:"
    echo "  • RDS database instance and backups"
    echo "  • VPC Lattice Service Network and Resource Gateway"
    echo "  • VPC, subnets, and security groups"
    echo "  • IAM roles and policies"
    echo "  • CloudWatch log groups"
    echo "  • AWS RAM resource shares"
    echo "  • Secrets Manager secrets"
    echo
    print_error "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    if [ "$FORCE" != true ]; then
        read -p "Are you sure you want to delete all resources? Type 'DELETE' to confirm: " confirmation
        if [ "$confirmation" != "DELETE" ]; then
            print_status "Deletion cancelled by user"
            exit 0
        fi
        
        echo
        read -p "Last chance! Are you absolutely sure? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deletion cancelled by user"
            exit 0
        fi
    fi
}

# Function to perform manual pre-cleanup for VPC Lattice resources
manual_vpc_lattice_cleanup() {
    print_header "Manual VPC Lattice Cleanup (if needed)"
    
    # Note: This is a placeholder for manual cleanup commands
    # In production, you might want to add specific VPC Lattice cleanup
    print_status "Checking for manual cleanup requirements..."
    
    # Check for any VPC Lattice resources that might need manual deletion
    if command_exists jq; then
        # List service networks
        service_networks=$(aws vpc-lattice list-service-networks --query 'items[?contains(name, `lattice-network`)]' 2>/dev/null || echo "[]")
        if [ "$service_networks" != "[]" ]; then
            print_warning "Found VPC Lattice service networks that may need manual cleanup"
            echo "$service_networks" | jq -r '.[] | "Service Network: \(.name) (\(.arn))"' 2>/dev/null || echo "$service_networks"
        fi
        
        # List resource gateways
        resource_gateways=$(aws vpc-lattice list-resource-gateways --query 'items[?contains(name, `db-gateway`)]' 2>/dev/null || echo "[]")
        if [ "$resource_gateways" != "[]" ]; then
            print_warning "Found VPC Lattice resource gateways that may need manual cleanup"
            echo "$resource_gateways" | jq -r '.[] | "Resource Gateway: \(.name) (\(.arn))"' 2>/dev/null || echo "$resource_gateways"
        fi
    else
        print_warning "jq not installed - skipping detailed VPC Lattice resource check"
    fi
}

# Function to delete the CDK stack
delete_cdk_stack() {
    print_header "Deleting CDK Stack"
    
    if ! check_stack_exists; then
        print_warning "Stack 'SecureDatabaseAccessStack' does not exist - nothing to delete"
        return 0
    fi
    
    print_status "Initiating stack deletion..."
    
    # Activate virtual environment if it exists
    if [ -d "venv" ]; then
        print_status "Activating Python virtual environment..."
        source venv/bin/activate
    fi
    
    # Delete the stack
    cdk destroy --force
    
    print_status "CDK stack deletion initiated ✓"
    
    # Wait for stack deletion to complete
    print_status "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete --stack-name SecureDatabaseAccessStack || {
        print_error "Stack deletion did not complete successfully"
        print_error "Check the AWS CloudFormation console for details"
        return 1
    }
    
    print_status "Stack deletion completed successfully ✓"
}

# Function to verify cleanup completion
verify_cleanup() {
    print_header "Verifying Cleanup Completion"
    
    # Check if stack still exists
    if check_stack_exists; then
        print_error "Stack still exists after deletion attempt"
        return 1
    fi
    
    print_status "CloudFormation stack successfully deleted ✓"
    
    # Check for any remaining VPC Lattice resources
    print_status "Checking for remaining VPC Lattice resources..."
    
    # Note: These commands might fail if VPC Lattice CLI commands are not available
    remaining_resources=false
    
    if aws vpc-lattice list-service-networks --query 'items[?contains(name, `lattice-network`)]' --output text 2>/dev/null | grep -q "lattice-network"; then
        print_warning "Some VPC Lattice service networks may still exist"
        remaining_resources=true
    fi
    
    if aws vpc-lattice list-resource-gateways --query 'items[?contains(name, `db-gateway`)]' --output text 2>/dev/null | grep -q "db-gateway"; then
        print_warning "Some VPC Lattice resource gateways may still exist"
        remaining_resources=true
    fi
    
    if [ "$remaining_resources" = true ]; then
        print_warning "Some resources may require manual cleanup"
        print_warning "Check the AWS Console for any remaining VPC Lattice resources"
    else
        print_status "No remaining resources detected ✓"
    fi
}

# Function to clean up local files
cleanup_local_files() {
    print_header "Cleaning Up Local Files"
    
    # Remove CDK output files
    if [ -d "cdk.out" ]; then
        print_status "Removing CDK output directory..."
        rm -rf cdk.out
    fi
    
    # Remove Python cache files
    if [ -d "__pycache__" ]; then
        print_status "Removing Python cache files..."
        rm -rf __pycache__
    fi
    
    # Remove test cache files
    if [ -d ".pytest_cache" ]; then
        print_status "Removing pytest cache..."
        rm -rf .pytest_cache
    fi
    
    # Remove any generated CloudFormation templates
    if [ -f "template.yaml" ]; then
        print_status "Removing generated template files..."
        rm -f template.yaml
    fi
    
    # Optionally remove virtual environment
    if [ -d "venv" ] && [ "$CLEAN_VENV" = true ]; then
        print_status "Removing Python virtual environment..."
        rm -rf venv
    fi
    
    print_status "Local cleanup completed ✓"
}

# Function to show manual cleanup instructions
show_manual_cleanup_instructions() {
    print_header "Manual Cleanup Instructions"
    
    print_warning "If you encounter any issues or need to perform manual cleanup:"
    echo
    echo "1. VPC Lattice Resources:"
    echo "   aws vpc-lattice list-service-networks"
    echo "   aws vpc-lattice delete-service-network --service-network-identifier <id>"
    echo
    echo "2. Resource Gateways:"
    echo "   aws vpc-lattice list-resource-gateways"
    echo "   aws vpc-lattice delete-resource-gateway --resource-gateway-identifier <id>"
    echo
    echo "3. AWS RAM Resource Shares:"
    echo "   aws ram get-resource-shares --resource-owner SELF"
    echo "   aws ram delete-resource-share --resource-share-arn <arn>"
    echo
    echo "4. RDS Resources (if stack deletion failed):"
    echo "   aws rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, \`lattice\`)]'"
    echo "   aws rds delete-db-instance --db-instance-identifier <id> --skip-final-snapshot"
    echo
    echo "5. VPC and Networking (if stack deletion failed):"
    echo "   Check AWS Console for any remaining VPCs, security groups, or subnets"
    echo
    print_status "For detailed troubleshooting, check the AWS CloudFormation console"
}

# Function to handle errors
handle_error() {
    print_error "Cleanup failed on line $1"
    print_error "Some resources may still exist and require manual cleanup"
    show_manual_cleanup_instructions
    exit 1
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "  Secure Database Access with VPC Lattice"
    echo "  CDK Python Cleanup Script"
    echo "=========================================="
    echo
    
    # Set error handler
    trap 'handle_error $LINENO' ERR
    
    # Run cleanup steps
    check_prerequisites
    get_stack_outputs
    confirm_deletion
    manual_vpc_lattice_cleanup
    delete_cdk_stack
    verify_cleanup
    cleanup_local_files
    
    echo
    print_status "Cleanup completed successfully!"
    print_status "All AWS resources have been removed"
    echo
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [options]"
            echo
            echo "Options:"
            echo "  --help, -h         Show this help message"
            echo "  --force            Skip confirmation prompts"
            echo "  --clean-venv       Also remove Python virtual environment"
            echo "  --dry-run          Show what would be deleted without deleting"
            echo
            echo "This script safely removes all resources created by the Secure Database Access solution"
            exit 0
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --clean-venv)
            CLEAN_VENV=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Handle dry run
if [ "$DRY_RUN" = true ]; then
    print_header "Dry Run Mode - Showing What Would Be Deleted"
    check_prerequisites
    get_stack_outputs
    print_status "In actual deletion, the following would be removed:"
    echo "  • CDK Stack: SecureDatabaseAccessStack"
    echo "  • All AWS resources created by the stack"
    echo "  • Local CDK output files"
    if [ "$CLEAN_VENV" = true ]; then
        echo "  • Python virtual environment"
    fi
    print_status "Dry run completed. No resources were actually deleted."
    exit 0
fi

# Run main cleanup
main