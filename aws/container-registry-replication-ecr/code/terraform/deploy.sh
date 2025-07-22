#!/bin/bash

# Deployment script for ECR Container Registry Replication Strategies
# This script provides a guided deployment process for the Terraform infrastructure

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
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if required tools are installed
    local tools=("terraform" "aws" "jq")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools and run this script again."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured or invalid"
        echo "Please run 'aws configure' to set up your credentials."
        exit 1
    fi
    
    # Check Terraform version
    local tf_version=$(terraform version -json | jq -r '.terraform_version')
    print_status "Terraform version: $tf_version"
    
    # Get AWS account information
    local aws_account=$(aws sts get-caller-identity --query Account --output text)
    local aws_region=$(aws configure get region)
    print_status "AWS Account: $aws_account"
    print_status "AWS Region: $aws_region"
    
    print_status "Prerequisites check completed"
}

# Function to initialize Terraform
initialize_terraform() {
    print_header "Initializing Terraform"
    
    if [ ! -f "versions.tf" ]; then
        print_error "Terraform configuration files not found"
        echo "Please ensure you're in the correct directory with Terraform files."
        exit 1
    fi
    
    print_status "Running terraform init..."
    terraform init
    
    print_status "Terraform initialization completed"
}

# Function to create terraform.tfvars if it doesn't exist
create_tfvars() {
    print_header "Configuration Setup"
    
    if [ ! -f "terraform.tfvars" ]; then
        print_warning "terraform.tfvars not found"
        
        if [ -f "terraform.tfvars.example" ]; then
            echo "Would you like to create terraform.tfvars from the example file? (y/n)"
            read -r response
            
            if [[ "$response" =~ ^[Yy]$ ]]; then
                cp terraform.tfvars.example terraform.tfvars
                print_status "Created terraform.tfvars from example"
                print_warning "Please edit terraform.tfvars to customize your deployment"
                
                # Prompt to edit the file
                echo "Would you like to edit terraform.tfvars now? (y/n)"
                read -r edit_response
                
                if [[ "$edit_response" =~ ^[Yy]$ ]]; then
                    "${EDITOR:-vi}" terraform.tfvars
                fi
            else
                print_error "terraform.tfvars is required for deployment"
                exit 1
            fi
        else
            print_error "terraform.tfvars.example not found"
            echo "Please create a terraform.tfvars file with your configuration."
            exit 1
        fi
    else
        print_status "Using existing terraform.tfvars"
    fi
}

# Function to validate configuration
validate_configuration() {
    print_header "Validating Configuration"
    
    # Run terraform validate
    print_status "Running terraform validate..."
    terraform validate
    
    # Check for required variables
    if [ -f "terraform.tfvars" ]; then
        print_status "Checking required variables..."
        
        # Extract some key variables
        local notification_email=$(grep -E "^notification_email" terraform.tfvars | cut -d'"' -f2 || echo "")
        local source_region=$(grep -E "^source_region" terraform.tfvars | cut -d'"' -f2 || echo "us-east-1")
        
        print_status "Source region: $source_region"
        
        if [ -n "$notification_email" ]; then
            print_status "Notifications will be sent to: $notification_email"
        else
            print_warning "No notification email configured"
        fi
    fi
    
    print_status "Configuration validation completed"
}

# Function to plan deployment
plan_deployment() {
    print_header "Planning Deployment"
    
    print_status "Running terraform plan..."
    terraform plan -var-file="terraform.tfvars" -out="tfplan"
    
    print_status "Terraform plan completed"
    print_warning "Review the plan above carefully before proceeding"
}

# Function to estimate costs
estimate_costs() {
    print_header "Cost Estimation"
    
    if [ -f "cost-estimate.sh" ]; then
        print_status "Running cost estimation..."
        ./cost-estimate.sh
    else
        print_warning "Cost estimation script not found"
        echo "Manual cost estimation recommended before deployment"
    fi
}

# Function to deploy infrastructure
deploy_infrastructure() {
    print_header "Deploying Infrastructure"
    
    echo ""
    print_warning "This will deploy AWS resources that may incur costs."
    echo "Are you sure you want to proceed? (type 'yes' to confirm)"
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        print_status "Deployment cancelled"
        exit 0
    fi
    
    print_status "Deploying infrastructure..."
    terraform apply "tfplan"
    
    print_status "Infrastructure deployment completed"
}

# Function to display deployment results
show_deployment_results() {
    print_header "Deployment Results"
    
    # Display key outputs
    echo ""
    echo "Key Infrastructure Components:"
    echo "=============================="
    
    local prod_repo=$(terraform output -raw production_repository_name 2>/dev/null || echo "N/A")
    local test_repo=$(terraform output -raw testing_repository_name 2>/dev/null || echo "N/A")
    local prod_uri=$(terraform output -raw production_repository_uri 2>/dev/null || echo "N/A")
    local test_uri=$(terraform output -raw testing_repository_uri 2>/dev/null || echo "N/A")
    
    echo "Production Repository: $prod_repo"
    echo "Testing Repository: $test_repo"
    echo ""
    echo "Repository URIs:"
    echo "Production: $prod_uri"
    echo "Testing: $test_uri"
    echo ""
    
    # Display useful commands
    echo "Useful Commands:"
    echo "================"
    echo ""
    
    local docker_login=$(terraform output -raw docker_login_command 2>/dev/null || echo "N/A")
    echo "Docker Login:"
    echo "$docker_login"
    echo ""
    
    local dashboard_name=$(terraform output -raw cloudwatch_dashboard_name 2>/dev/null || echo "N/A")
    if [ "$dashboard_name" != "N/A" ]; then
        local source_region=$(terraform output -raw source_region 2>/dev/null || echo "us-east-1")
        echo "CloudWatch Dashboard:"
        echo "https://${source_region}.console.aws.amazon.com/cloudwatch/home?region=${source_region}#dashboards:name=${dashboard_name}"
        echo ""
    fi
    
    echo "Validation:"
    echo "Run './validate.sh' to validate your deployment"
    echo ""
    
    echo "Next Steps:"
    echo "==========="
    echo "1. Run the validation script: ./validate.sh"
    echo "2. Push test images to verify replication"
    echo "3. Monitor CloudWatch dashboard for metrics"
    echo "4. Configure additional monitoring as needed"
    echo "5. Review and adjust lifecycle policies"
    echo ""
}

# Function to clean up temporary files
cleanup() {
    print_header "Cleaning Up"
    
    # Remove terraform plan file
    if [ -f "tfplan" ]; then
        rm -f tfplan
        print_status "Removed temporary plan file"
    fi
    
    # Remove Lambda zip file if it exists
    if [ -f "ecr_cleanup_lambda.zip" ]; then
        rm -f ecr_cleanup_lambda.zip
        print_status "Removed Lambda deployment package"
    fi
}

# Function to show deployment summary
show_summary() {
    print_header "Deployment Summary"
    
    echo ""
    echo "ECR Container Registry Replication Strategies deployment completed successfully!"
    echo ""
    echo "What was deployed:"
    echo "• ECR repositories with lifecycle policies"
    echo "• Cross-region replication configuration"
    echo "• CloudWatch monitoring and alarms"
    echo "• Lambda function for automated cleanup"
    echo "• SNS notifications for alerts"
    echo "• IAM roles and policies for secure access"
    echo ""
    echo "Important files:"
    echo "• terraform.tfvars - Your configuration"
    echo "• terraform.tfstate - Terraform state (keep secure)"
    echo "• validate.sh - Validation script"
    echo "• cost-estimate.sh - Cost estimation tool"
    echo ""
    print_status "Deployment completed successfully!"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy ECR Container Registry Replication Strategies infrastructure"
    echo ""
    echo "Options:"
    echo "  --skip-validation   Skip configuration validation"
    echo "  --skip-cost         Skip cost estimation"
    echo "  --auto-approve      Auto-approve deployment (use with caution)"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                  # Interactive deployment"
    echo "  $0 --skip-cost      # Skip cost estimation"
    echo "  $0 --auto-approve   # Auto-approve deployment"
    echo ""
}

# Main execution function
main() {
    echo "ECR Container Registry Replication Strategies - Deployment Script"
    echo "=================================================================="
    echo ""
    
    # Parse command line arguments
    local skip_validation=false
    local skip_cost=false
    local auto_approve=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-validation)
                skip_validation=true
                shift
                ;;
            --skip-cost)
                skip_cost=true
                shift
                ;;
            --auto-approve)
                auto_approve=true
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
    
    # Execute deployment steps
    check_prerequisites
    initialize_terraform
    create_tfvars
    
    if [ "$skip_validation" = false ]; then
        validate_configuration
    fi
    
    plan_deployment
    
    if [ "$skip_cost" = false ]; then
        estimate_costs
    fi
    
    if [ "$auto_approve" = false ]; then
        deploy_infrastructure
    else
        print_status "Auto-approving deployment..."
        terraform apply -var-file="terraform.tfvars" -auto-approve
    fi
    
    show_deployment_results
    cleanup
    show_summary
}

# Trap to clean up on exit
trap cleanup EXIT

# Run main function
main "$@"