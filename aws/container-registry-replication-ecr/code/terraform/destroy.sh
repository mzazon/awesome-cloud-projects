#!/bin/bash

# Destroy script for ECR Container Registry Replication Strategies
# This script safely destroys the deployed infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}[DESTROY]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured or invalid"
        exit 1
    fi
    
    # Check if Terraform state exists
    if [ ! -f "terraform.tfstate" ]; then
        print_error "Terraform state file not found"
        echo "Nothing to destroy or deployment was not completed."
        exit 1
    fi
    
    print_status "Prerequisites check completed"
}

# Function to show current infrastructure
show_current_infrastructure() {
    print_header "Current Infrastructure"
    
    echo "The following resources will be destroyed:"
    echo "=========================================="
    
    # Get key outputs if available
    local prod_repo=$(terraform output -raw production_repository_name 2>/dev/null || echo "N/A")
    local test_repo=$(terraform output -raw testing_repository_name 2>/dev/null || echo "N/A")
    local source_region=$(terraform output -raw source_region 2>/dev/null || echo "N/A")
    local dest_region=$(terraform output -raw destination_region 2>/dev/null || echo "N/A")
    local secondary_region=$(terraform output -raw secondary_region 2>/dev/null || echo "N/A")
    
    echo "ECR Repositories:"
    echo "  • Production: $prod_repo"
    echo "  • Testing: $test_repo"
    echo ""
    echo "Regions:"
    echo "  • Source: $source_region"
    echo "  • Destination: $dest_region"
    echo "  • Secondary: $secondary_region"
    echo ""
    echo "Additional Resources:"
    echo "  • ECR lifecycle policies"
    echo "  • ECR replication configuration"
    echo "  • IAM roles and policies"
    echo "  • CloudWatch dashboard and alarms"
    echo "  • SNS topic and subscriptions"
    echo "  • Lambda function for cleanup"
    echo "  • EventBridge rules"
    echo ""
}

# Function to check for container images
check_container_images() {
    print_header "Checking Container Images"
    
    local prod_repo=$(terraform output -raw production_repository_name 2>/dev/null || echo "")
    local test_repo=$(terraform output -raw testing_repository_name 2>/dev/null || echo "")
    local source_region=$(terraform output -raw source_region 2>/dev/null || echo "us-east-1")
    
    if [ -n "$prod_repo" ]; then
        local prod_image_count=$(aws ecr describe-images --region "$source_region" --repository-name "$prod_repo" --query 'length(imageDetails)' --output text 2>/dev/null || echo "0")
        echo "Production repository ($prod_repo): $prod_image_count images"
        
        if [ "$prod_image_count" -gt 0 ]; then
            print_warning "Production repository contains $prod_image_count images"
            echo "These images will be PERMANENTLY DELETED when the repository is destroyed."
        fi
    fi
    
    if [ -n "$test_repo" ]; then
        local test_image_count=$(aws ecr describe-images --region "$source_region" --repository-name "$test_repo" --query 'length(imageDetails)' --output text 2>/dev/null || echo "0")
        echo "Testing repository ($test_repo): $test_image_count images"
        
        if [ "$test_image_count" -gt 0 ]; then
            print_warning "Testing repository contains $test_image_count images"
            echo "These images will be PERMANENTLY DELETED when the repository is destroyed."
        fi
    fi
    
    echo ""
}

# Function to create backup information
create_backup_info() {
    print_header "Creating Backup Information"
    
    local backup_file="ecr-backup-info-$(date +%Y%m%d-%H%M%S).json"
    
    print_status "Creating backup information file: $backup_file"
    
    # Create backup information
    cat > "$backup_file" << EOF
{
  "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "terraform_outputs": $(terraform output -json 2>/dev/null || echo "{}"),
  "terraform_state_version": "$(terraform state version 2>/dev/null || echo "unknown")",
  "aws_account": "$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")",
  "aws_region": "$(aws configure get region 2>/dev/null || echo "unknown")",
  "destruction_reason": "Manual destruction via destroy.sh"
}
EOF
    
    print_status "Backup information saved to: $backup_file"
    echo "This file contains configuration information for potential restoration."
    echo ""
}

# Function to plan destruction
plan_destruction() {
    print_header "Planning Destruction"
    
    print_status "Running terraform plan -destroy..."
    terraform plan -destroy -var-file="terraform.tfvars" -out="destroy.tfplan"
    
    print_status "Destruction plan completed"
    print_warning "Review the destruction plan above carefully"
    echo ""
}

# Function to confirm destruction
confirm_destruction() {
    print_header "Destruction Confirmation"
    
    echo ""
    print_warning "⚠️  CRITICAL WARNING ⚠️"
    echo ""
    echo "This action will PERMANENTLY DELETE all ECR repositories and container images."
    echo "This action CANNOT be undone."
    echo ""
    echo "Resources that will be destroyed:"
    echo "• All ECR repositories and their container images"
    echo "• Replication configuration"
    echo "• CloudWatch dashboards and alarms"
    echo "• Lambda functions"
    echo "• SNS topics and subscriptions"
    echo "• IAM roles and policies"
    echo ""
    
    # Multiple confirmation prompts
    echo "Are you absolutely sure you want to destroy this infrastructure? (type 'yes')"
    read -r confirmation1
    
    if [[ "$confirmation1" != "yes" ]]; then
        print_status "Destruction cancelled"
        exit 0
    fi
    
    echo ""
    echo "This will delete all container images permanently. Type 'DELETE' to confirm:"
    read -r confirmation2
    
    if [[ "$confirmation2" != "DELETE" ]]; then
        print_status "Destruction cancelled"
        exit 0
    fi
    
    echo ""
    echo "Final confirmation - Type the name of the production repository to proceed:"
    local prod_repo=$(terraform output -raw production_repository_name 2>/dev/null || echo "")
    if [ -n "$prod_repo" ]; then
        echo "Repository name: $prod_repo"
        read -r confirmation3
        
        if [[ "$confirmation3" != "$prod_repo" ]]; then
            print_status "Destruction cancelled - repository name mismatch"
            exit 0
        fi
    fi
    
    print_status "Destruction confirmed"
}

# Function to destroy infrastructure
destroy_infrastructure() {
    print_header "Destroying Infrastructure"
    
    print_status "Executing destruction plan..."
    terraform apply "destroy.tfplan"
    
    print_status "Infrastructure destruction completed"
}

# Function to clean up local files
cleanup_local_files() {
    print_header "Cleaning Up Local Files"
    
    # Remove Terraform plan files
    if [ -f "destroy.tfplan" ]; then
        rm -f destroy.tfplan
        print_status "Removed destruction plan file"
    fi
    
    if [ -f "tfplan" ]; then
        rm -f tfplan
        print_status "Removed terraform plan file"
    fi
    
    # Remove Lambda deployment package
    if [ -f "ecr_cleanup_lambda.zip" ]; then
        rm -f ecr_cleanup_lambda.zip
        print_status "Removed Lambda deployment package"
    fi
    
    # Option to remove Terraform state files
    echo ""
    echo "Do you want to remove Terraform state files? (y/n)"
    echo "Warning: This will make it impossible to manage any remaining resources with Terraform."
    read -r remove_state
    
    if [[ "$remove_state" =~ ^[Yy]$ ]]; then
        if [ -f "terraform.tfstate" ]; then
            rm -f terraform.tfstate
            print_status "Removed terraform.tfstate"
        fi
        
        if [ -f "terraform.tfstate.backup" ]; then
            rm -f terraform.tfstate.backup
            print_status "Removed terraform.tfstate.backup"
        fi
        
        if [ -d ".terraform" ]; then
            rm -rf .terraform
            print_status "Removed .terraform directory"
        fi
    fi
    
    # Option to remove configuration files
    echo ""
    echo "Do you want to remove terraform.tfvars? (y/n)"
    echo "Warning: You will need to recreate this file for future deployments."
    read -r remove_tfvars
    
    if [[ "$remove_tfvars" =~ ^[Yy]$ ]]; then
        if [ -f "terraform.tfvars" ]; then
            rm -f terraform.tfvars
            print_status "Removed terraform.tfvars"
        fi
    fi
}

# Function to verify destruction
verify_destruction() {
    print_header "Verifying Destruction"
    
    # Check if any ECR repositories still exist
    local source_region=$(terraform output -raw source_region 2>/dev/null || echo "us-east-1")
    local repository_prefix=$(grep -E "^repository_prefix" terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "enterprise-apps")
    
    print_status "Checking for remaining ECR repositories..."
    
    local remaining_repos=$(aws ecr describe-repositories --region "$source_region" --query "repositories[?starts_with(repositoryName, '$repository_prefix')].repositoryName" --output text 2>/dev/null || echo "")
    
    if [ -z "$remaining_repos" ]; then
        print_status "✓ No ECR repositories found with prefix '$repository_prefix'"
    else
        print_warning "Found remaining repositories: $remaining_repos"
        echo "These may need to be manually deleted."
    fi
    
    # Check CloudWatch resources
    print_status "Checking CloudWatch resources..."
    local dashboard_name="ecr-replication-monitoring"
    if aws cloudwatch get-dashboard --region "$source_region" --dashboard-name "$dashboard_name" &> /dev/null; then
        print_warning "CloudWatch dashboard still exists: $dashboard_name"
    else
        print_status "✓ CloudWatch dashboard removed"
    fi
    
    print_status "Verification completed"
}

# Function to show destruction summary
show_destruction_summary() {
    print_header "Destruction Summary"
    
    echo ""
    echo "ECR Container Registry Replication Strategies infrastructure has been destroyed."
    echo ""
    echo "What was destroyed:"
    echo "• ECR repositories and all container images"
    echo "• Cross-region replication configuration"
    echo "• CloudWatch monitoring and alarms"
    echo "• Lambda functions and EventBridge rules"
    echo "• SNS topics and subscriptions"
    echo "• IAM roles and policies"
    echo ""
    echo "Remaining files:"
    if [ -f "terraform.tfvars" ]; then
        echo "• terraform.tfvars (configuration file)"
    fi
    if [ -f "terraform.tfstate" ]; then
        echo "• terraform.tfstate (state file)"
    fi
    
    local backup_files=$(ls ecr-backup-info-*.json 2>/dev/null || echo "")
    if [ -n "$backup_files" ]; then
        echo "• Backup information files:"
        for file in $backup_files; do
            echo "  - $file"
        done
    fi
    
    echo ""
    echo "Next steps:"
    echo "• Review AWS console to ensure all resources are removed"
    echo "• Check for any unexpected charges in AWS Cost Explorer"
    echo "• Archive backup files if needed"
    echo ""
    print_status "Destruction completed successfully!"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Destroy ECR Container Registry Replication Strategies infrastructure"
    echo ""
    echo "Options:"
    echo "  --force             Skip confirmation prompts (dangerous!)"
    echo "  --keep-state        Keep Terraform state files after destruction"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                  # Interactive destruction"
    echo "  $0 --keep-state     # Destroy but keep state files"
    echo ""
    echo "Warning: The --force option will destroy infrastructure without confirmation!"
    echo ""
}

# Main execution function
main() {
    echo "ECR Container Registry Replication Strategies - Destruction Script"
    echo "=================================================================="
    echo ""
    
    # Parse command line arguments
    local force_destroy=false
    local keep_state=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_destroy=true
                shift
                ;;
            --keep-state)
                keep_state=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Execute destruction steps
    check_prerequisites
    show_current_infrastructure
    check_container_images
    create_backup_info
    plan_destruction
    
    if [ "$force_destroy" = false ]; then
        confirm_destruction
    else
        print_warning "Force mode enabled - skipping confirmation"
    fi
    
    destroy_infrastructure
    
    if [ "$keep_state" = false ]; then
        cleanup_local_files
    else
        print_status "Keeping state files as requested"
    fi
    
    verify_destruction
    show_destruction_summary
}

# Run main function
main "$@"