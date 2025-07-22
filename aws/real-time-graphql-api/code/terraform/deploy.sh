#!/bin/bash

# ==============================================================================
# AWS AppSync GraphQL API Deployment Script
# ==============================================================================
# This script deploys the AppSync GraphQL API infrastructure using Terraform.
# It includes validation, planning, and deployment steps with proper error handling.
# ==============================================================================

set -e  # Exit on any error

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

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install Terraform >= 1.0"
        exit 1
    fi
    
    # Check Terraform version
    TERRAFORM_VERSION=$(terraform --version | head -n1 | cut -d' ' -f2 | cut -d'v' -f2)
    print_status "Terraform version: $TERRAFORM_VERSION"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install AWS CLI v2"
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure'"
        exit 1
    fi
    
    # Get AWS account info
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    print_status "AWS Account: $AWS_ACCOUNT_ID"
    print_status "AWS Region: $AWS_REGION"
    
    print_success "Prerequisites check passed!"
}

# Function to initialize Terraform
init_terraform() {
    print_status "Initializing Terraform..."
    
    if terraform init; then
        print_success "Terraform initialization completed!"
    else
        print_error "Terraform initialization failed!"
        exit 1
    fi
}

# Function to validate Terraform configuration
validate_terraform() {
    print_status "Validating Terraform configuration..."
    
    if terraform validate; then
        print_success "Terraform validation passed!"
    else
        print_error "Terraform validation failed!"
        exit 1
    fi
}

# Function to plan Terraform deployment
plan_terraform() {
    print_status "Planning Terraform deployment..."
    
    if terraform plan -out=tfplan; then
        print_success "Terraform plan completed successfully!"
        echo ""
        print_warning "Review the plan above carefully before proceeding."
        echo ""
    else
        print_error "Terraform plan failed!"
        exit 1
    fi
}

# Function to apply Terraform deployment
apply_terraform() {
    print_status "Applying Terraform deployment..."
    
    if terraform apply tfplan; then
        print_success "Terraform deployment completed successfully!"
        rm -f tfplan
    else
        print_error "Terraform deployment failed!"
        exit 1
    fi
}

# Function to display outputs
show_outputs() {
    print_status "Displaying deployment outputs..."
    echo ""
    
    # Show key outputs
    echo "=== AppSync GraphQL API Information ==="
    echo "API ID: $(terraform output -raw appsync_api_id)"
    echo "GraphQL Endpoint: $(terraform output -raw graphql_endpoint)"
    echo "Real-time Endpoint: $(terraform output -raw realtime_endpoint)"
    echo ""
    
    echo "=== Authentication Information ==="
    echo "User Pool ID: $(terraform output -raw cognito_user_pool_id)"
    echo "User Pool Client ID: $(terraform output -raw cognito_user_pool_client_id)"
    
    if terraform output -raw api_key 2>/dev/null; then
        echo "API Key: $(terraform output -raw api_key)"
    fi
    echo ""
    
    echo "=== DynamoDB Information ==="
    echo "Table Name: $(terraform output -raw dynamodb_table_name)"
    echo "Table ARN: $(terraform output -raw dynamodb_table_arn)"
    echo ""
    
    echo "=== Quick Test Command ==="
    if terraform output -raw api_key 2>/dev/null; then
        echo "curl -X POST $(terraform output -raw graphql_endpoint) \\"
        echo "  -H 'Content-Type: application/json' \\"
        echo "  -H 'x-api-key: $(terraform output -raw api_key)' \\"
        echo "  -d '{\"query\": \"query { __typename }\"}'"
    else
        echo "Configure authentication to test the API"
    fi
    echo ""
    
    echo "=== AppSync Console URL ==="
    echo "https://console.aws.amazon.com/appsync/home?region=$(terraform output -raw aws_region)#/apis/$(terraform output -raw appsync_api_id)/v1/home"
    echo ""
}

# Function to check if terraform.tfvars exists
check_tfvars() {
    if [ ! -f "terraform.tfvars" ]; then
        print_warning "terraform.tfvars not found. Using default values."
        print_status "You can copy terraform.tfvars.example to terraform.tfvars and customize it."
        echo ""
    fi
}

# Main deployment function
main() {
    echo "=== AWS AppSync GraphQL API Deployment ==="
    echo ""
    
    # Check if terraform.tfvars exists
    check_tfvars
    
    # Check prerequisites
    check_prerequisites
    echo ""
    
    # Initialize Terraform
    init_terraform
    echo ""
    
    # Validate configuration
    validate_terraform
    echo ""
    
    # Plan deployment
    plan_terraform
    
    # Ask for confirmation
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        apply_terraform
        echo ""
        show_outputs
        
        print_success "Deployment completed successfully!"
        print_status "You can now test your GraphQL API using the information above."
    else
        print_status "Deployment cancelled."
        rm -f tfplan
    fi
}

# Run main function
main "$@"