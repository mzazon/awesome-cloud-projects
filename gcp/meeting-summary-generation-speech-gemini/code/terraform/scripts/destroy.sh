#!/bin/bash
# Destroy Meeting Summary Generation Infrastructure
# This script safely removes all deployed resources

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
    echo -e "${BLUE}[DESTROY]${NC} $1"
}

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$(dirname "$SCRIPT_DIR")"

# Default values
DRY_RUN=false
AUTO_APPROVE=false
KEEP_BUCKET_DATA=false
TERRAFORM_VARS_FILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --auto-approve)
            AUTO_APPROVE=true
            shift
            ;;
        --keep-data)
            KEEP_BUCKET_DATA=true
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
            echo "  --dry-run          Show what would be destroyed without making changes"
            echo "  --auto-approve     Automatically approve destruction plan"
            echo "  --keep-data        Download bucket data before destruction"
            echo "  --vars-file FILE   Use custom terraform variables file"
            echo "  --help             Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Interactive destruction"
            echo "  $0 --dry-run                    # Preview destruction plan"
            echo "  $0 --auto-approve               # Non-interactive destruction"
            echo "  $0 --keep-data                  # Backup data before destroying"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_header "Starting Meeting Summary Generation Infrastructure Destruction"

# Change to Terraform directory
cd "$TERRAFORM_DIR"

# Check if Terraform state exists
if [[ ! -f "terraform.tfstate" ]] && [[ ! -f ".terraform/terraform.tfstate" ]]; then
    print_warning "No Terraform state found. Nothing to destroy."
    exit 0
fi

# Check required tools
if ! command -v terraform &> /dev/null; then
    print_error "Terraform is not installed or not in PATH"
    exit 1
fi

if ! command -v gcloud &> /dev/null; then
    print_error "Google Cloud SDK (gcloud) is not installed or not in PATH"
    exit 1
fi

# Get current bucket name and check if data should be backed up
if [[ "$KEEP_BUCKET_DATA" == "true" ]]; then
    print_status "Checking for bucket data to backup..."
    
    if BUCKET_NAME=$(terraform output -raw bucket_name 2>/dev/null); then
        print_status "Found bucket: $BUCKET_NAME"
        
        # Create backup directory with timestamp
        BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$BACKUP_DIR"
        
        print_status "Backing up bucket data to: $BACKUP_DIR"
        
        # Download transcripts
        if gsutil ls "gs://$BUCKET_NAME/transcripts/" &>/dev/null; then
            mkdir -p "$BACKUP_DIR/transcripts"
            gsutil -m cp -r "gs://$BUCKET_NAME/transcripts/*" "$BACKUP_DIR/transcripts/" || true
            print_status "Transcripts backed up"
        fi
        
        # Download summaries
        if gsutil ls "gs://$BUCKET_NAME/summaries/" &>/dev/null; then
            mkdir -p "$BACKUP_DIR/summaries"
            gsutil -m cp -r "gs://$BUCKET_NAME/summaries/*" "$BACKUP_DIR/summaries/" || true
            print_status "Summaries backed up"
        fi
        
        # Download any other files (excluding function source)
        gsutil ls "gs://$BUCKET_NAME/" | grep -v -E "(transcripts/|summaries/|function-source-)" | while read -r file; do
            if [[ -n "$file" ]]; then
                gsutil cp "$file" "$BACKUP_DIR/" || true
            fi
        done 2>/dev/null || true
        
        print_status "Data backup completed in: $BACKUP_DIR"
    else
        print_warning "Could not determine bucket name for backup"
    fi
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
    VARS_FILE_ARG=""
    print_warning "No terraform.tfvars file found"
fi

# Initialize Terraform (in case of state issues)
print_status "Initializing Terraform..."
if ! terraform init; then
    print_error "Terraform initialization failed"
    exit 1
fi

# Generate destruction plan
print_status "Generating destruction plan..."
PLAN_FILE="destroy.tfplan"

if [[ -n "$VARS_FILE_ARG" ]]; then
    terraform plan -destroy $VARS_FILE_ARG -out="$PLAN_FILE"
else
    terraform plan -destroy -out="$PLAN_FILE"
fi

if [[ $? -ne 0 ]]; then
    print_error "Terraform destroy plan generation failed"
    exit 1
fi

# Show destruction plan summary
print_status "Destruction plan generated successfully"
echo ""
print_header "Destruction Plan Summary:"
terraform show -no-color "$PLAN_FILE" | grep -E "^Plan:" || true
echo ""

# Show what will be destroyed
print_warning "The following resources will be PERMANENTLY DELETED:"
terraform show -no-color "$PLAN_FILE" | grep -E "^  # .* will be destroyed" | sed 's/^  # /  - /' || true
echo ""

# Dry run mode - exit after showing plan
if [[ "$DRY_RUN" == "true" ]]; then
    print_status "Dry run completed. No resources were destroyed."
    print_status "Plan file saved as: $PLAN_FILE"
    print_status "To apply destruction, run: terraform apply $PLAN_FILE"
    exit 0
fi

# Show important warnings
print_header "⚠️  IMPORTANT WARNINGS ⚠️"
echo ""
print_error "This action will PERMANENTLY DELETE all infrastructure resources!"
print_error "This includes:"
print_error "  - Cloud Storage bucket and ALL data inside"
print_error "  - Cloud Functions and their configurations"
print_error "  - Service accounts and IAM bindings"
print_error "  - Monitoring policies and logs"
echo ""
print_warning "Data loss will be IRREVERSIBLE unless you have backups!"
if [[ "$KEEP_BUCKET_DATA" != "true" ]]; then
    print_warning "Use --keep-data flag to backup bucket contents before destruction"
fi
echo ""

# Confirm destruction
if [[ "$AUTO_APPROVE" != "true" ]]; then
    echo ""
    print_warning "Are you absolutely sure you want to destroy all resources?"
    read -p "Type 'yes' to confirm destruction: " -r
    echo ""
    if [[ "$REPLY" != "yes" ]]; then
        print_status "Destruction cancelled by user"
        rm -f "$PLAN_FILE"
        exit 0
    fi
    
    # Second confirmation for extra safety
    echo ""
    print_error "FINAL CONFIRMATION: This will delete everything!"
    read -p "Type 'DESTROY' in capital letters to proceed: " -r
    echo ""
    if [[ "$REPLY" != "DESTROY" ]]; then
        print_status "Destruction cancelled - confirmation text did not match"
        rm -f "$PLAN_FILE"
        exit 0
    fi
fi

# Apply destruction plan
print_header "Destroying infrastructure..."
if ! terraform apply "$PLAN_FILE"; then
    print_error "Terraform destroy failed"
    print_warning "Some resources may have been partially destroyed"
    print_status "Check the Terraform state and Google Cloud Console for remaining resources"
    exit 1
fi

# Clean up plan file
rm -f "$PLAN_FILE"

# Additional cleanup
print_status "Performing additional cleanup..."

# Check for any remaining function source archives
if ls function-source*.zip &>/dev/null; then
    rm -f function-source*.zip
    print_status "Removed local function source archives"
fi

# Offer to clean up Terraform state
echo ""
read -p "Remove Terraform state files? This will prevent future terraform operations in this directory (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
    rm -rf .terraform/
    print_status "Terraform state files removed"
fi

# Show completion message
print_header "Destruction completed successfully!"
echo ""
print_status "All infrastructure resources have been destroyed"

if [[ "$KEEP_BUCKET_DATA" == "true" ]] && [[ -n "${BACKUP_DIR:-}" ]]; then
    print_status "Your data has been backed up to: $BACKUP_DIR"
fi

echo ""
print_warning "Remember to:"
print_warning "  - Check Google Cloud Console to verify all resources are deleted"
print_warning "  - Review your billing to ensure no unexpected charges"
print_warning "  - Clean up any manual configurations you may have made"
echo ""

print_header "Infrastructure destruction completed!"