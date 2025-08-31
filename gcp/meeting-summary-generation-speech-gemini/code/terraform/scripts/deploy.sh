#!/bin/bash
# Deploy Meeting Summary Generation Infrastructure
# This script automates the deployment of the complete infrastructure

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

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
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$(dirname "$TERRAFORM_DIR")")"

# Default values
DRY_RUN=false
SKIP_VALIDATION=false
AUTO_APPROVE=false
TERRAFORM_VARS_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --vars-file)
            TERRAFORM_VARS_FILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run          Show what would be deployed without making changes"
            echo "  --skip-validation  Skip prerequisite validation checks"
            echo "  --auto-approve     Automatically approve Terraform plan"
            echo "  --vars-file FILE   Use custom terraform variables file"
            echo "  --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                                    # Interactive deployment"
            echo "  $0 --dry-run                          # Preview changes only"
            echo "  $0 --auto-approve                     # Non-interactive deployment"
            echo "  $0 --vars-file production.tfvars     # Use custom variables"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_header "Starting Meeting Summary Generation Infrastructure Deployment"

# Change to Terraform directory
cd "$TERRAFORM_DIR"

# Validation checks
if [[ "$SKIP_VALIDATION" != "true" ]]; then
    print_status "Running prerequisite checks..."
    
    # Check if required tools are installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed or not in PATH"
        print_status "Install from: https://www.terraform.io/downloads"
        exit 1
    fi
    
    if ! command -v gcloud &> /dev/null; then
        print_error "Google Cloud SDK (gcloud) is not installed or not in PATH"
        print_status "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check Terraform version
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    print_status "Using Terraform version: $TERRAFORM_VERSION"
    
    # Check if authenticated with Google Cloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        print_error "Not authenticated with Google Cloud"
        print_status "Run: gcloud auth login && gcloud auth application-default login"
        exit 1
    fi
    
    ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
    print_status "Authenticated as: $ACTIVE_ACCOUNT"
    
    # Check if a project is configured
    if ! PROJECT_ID=$(gcloud config get-value project 2>/dev/null) || [[ -z "$PROJECT_ID" ]]; then
        print_error "No Google Cloud project configured"
        print_status "Run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
    
    print_status "Using Google Cloud project: $PROJECT_ID"
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        print_warning "Cannot verify billing status for project $PROJECT_ID"
        print_warning "Ensure billing is enabled for this project"
    fi
    
    print_status "Prerequisite checks completed successfully"
fi

# Handle terraform.tfvars
if [[ -n "$TERRAFORM_VARS_FILE" ]]; then
    if [[ ! -f "$TERRAFORM_VARS_FILE" ]]; then
        print_error "Variables file not found: $TERRAFORM_VARS_FILE"
        exit 1
    fi
    VARS_FILE_ARG="-var-file=$TERRAFORM_VARS_FILE"
    print_status "Using variables file: $TERRAFORM_VARS_FILE"
elif [[ -f "terraform.tfvars" ]]; then
    VARS_FILE_ARG=""
    print_status "Using existing terraform.tfvars file"
else
    print_warning "No terraform.tfvars file found"
    if [[ -f "terraform.tfvars.example" ]]; then
        print_status "Example variables file available: terraform.tfvars.example"
        echo ""
        read -p "Would you like to create terraform.tfvars from the example? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp terraform.tfvars.example terraform.tfvars
            print_status "Created terraform.tfvars from example"
            print_warning "Please edit terraform.tfvars with your project settings before continuing"
            echo ""
            read -p "Press Enter after editing terraform.tfvars, or Ctrl+C to exit..."
        fi
    fi
    VARS_FILE_ARG=""
fi

# Initialize Terraform
print_status "Initializing Terraform..."
if ! terraform init; then
    print_error "Terraform initialization failed"
    exit 1
fi

# Validate Terraform configuration
print_status "Validating Terraform configuration..."
if ! terraform validate; then
    print_error "Terraform validation failed"
    exit 1
fi

# Format Terraform files
print_status "Formatting Terraform files..."
terraform fmt -recursive

# Generate Terraform plan
print_status "Generating Terraform plan..."
PLAN_FILE="deployment.tfplan"

if [[ -n "$VARS_FILE_ARG" ]]; then
    terraform plan $VARS_FILE_ARG -out="$PLAN_FILE"
else
    terraform plan -out="$PLAN_FILE"
fi

if [[ $? -ne 0 ]]; then
    print_error "Terraform plan generation failed"
    exit 1
fi

# Show plan summary
print_status "Plan generated successfully"
echo ""
print_header "Deployment Plan Summary:"
terraform show -no-color "$PLAN_FILE" | grep -E "^(Plan:|Changes to Outputs:)" || true
echo ""

# Dry run mode - exit after showing plan
if [[ "$DRY_RUN" == "true" ]]; then
    print_status "Dry run completed. No changes were made."
    print_status "Plan file saved as: $PLAN_FILE"
    print_status "To apply these changes, run: terraform apply $PLAN_FILE"
    exit 0
fi

# Confirm deployment
if [[ "$AUTO_APPROVE" != "true" ]]; then
    echo ""
    print_warning "This will create real resources in Google Cloud Platform"
    print_warning "Charges may apply based on your usage"
    echo ""
    read -p "Do you want to proceed with the deployment? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled by user"
        exit 0
    fi
fi

# Apply Terraform plan
print_header "Applying Terraform configuration..."
if ! terraform apply "$PLAN_FILE"; then
    print_error "Terraform apply failed"
    print_status "You may need to run 'terraform destroy' to clean up partial deployment"
    exit 1
fi

# Clean up plan file
rm -f "$PLAN_FILE"

# Show deployment outputs
print_header "Deployment completed successfully!"
echo ""
print_status "Resource Information:"
terraform output

# Show usage instructions
echo ""
print_header "Next Steps:"
echo ""
print_status "1. Test the system with an audio file:"
echo "   gsutil cp your-meeting.wav gs://\$(terraform output -raw bucket_name)/"
echo ""
print_status "2. Monitor processing:"
echo "   gcloud functions logs read \$(terraform output -raw function_name) --region \$(terraform output -raw region)"
echo ""
print_status "3. Check results:"
echo "   gsutil ls gs://\$(terraform output -raw bucket_name)/transcripts/"
echo "   gsutil ls gs://\$(terraform output -raw bucket_name)/summaries/"
echo ""
print_status "4. View detailed usage instructions:"
echo "   cat README.md"
echo ""

# Cost reminder
print_warning "Remember: This infrastructure will incur charges based on usage"
print_warning "To avoid charges when not in use, run: ./scripts/destroy.sh"
echo ""

print_header "Deployment completed successfully!"