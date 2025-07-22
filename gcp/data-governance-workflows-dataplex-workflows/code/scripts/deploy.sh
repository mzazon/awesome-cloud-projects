#!/bin/bash

# Data Governance Workflows with Dataplex and Cloud Workflows - Deployment Script
# This script deploys the intelligent data governance solution using Google Cloud services

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${2:-}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    log "$1" "$BLUE"
}

log_success() {
    log "$1" "$GREEN"
}

log_warning() {
    log "$1" "$YELLOW"
}

log_error() {
    log "$1" "$RED"
}

# Error handling
handle_error() {
    log_error "❌ Deployment failed at line $1"
    log_error "Check the log file for details: $LOG_FILE"
    exit 1
}

trap 'handle_error $LINENO' ERR

# Prerequisites check
check_prerequisites() {
    log_info "🔍 Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "❌ Google Cloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "❌ Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "."; then
        log_error "❌ You are not authenticated with Google Cloud. Please run 'gcloud auth login' first."
        exit 1
    fi
    
    log_success "✅ Prerequisites check passed"
}

# Project configuration
configure_project() {
    log_info "🔧 Configuring project..."
    
    # Get current project or prompt for one
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
    
    if [ -z "$CURRENT_PROJECT" ]; then
        log_info "No project configured. Please set your project ID:"
        read -p "Enter your GCP Project ID: " PROJECT_ID
        export PROJECT_ID
    else
        log_info "Using current project: $CURRENT_PROJECT"
        export PROJECT_ID="$CURRENT_PROJECT"
    fi
    
    # Validate project exists
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_error "❌ Project $PROJECT_ID does not exist or you don't have access to it."
        exit 1
    fi
    
    # Set project
    gcloud config set project "$PROJECT_ID"
    
    # Set default region if not set
    REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "")
    if [ -z "$REGION" ]; then
        export REGION="us-central1"
        gcloud config set compute/region "$REGION"
        log_info "Set default region to: $REGION"
    else
        export REGION
        log_info "Using configured region: $REGION"
    fi
    
    log_success "✅ Project configured: $PROJECT_ID in region $REGION"
}

# Enable required APIs
enable_apis() {
    log_info "🚀 Enabling required APIs..."
    
    local required_apis=(
        "dataplex.googleapis.com"
        "workflows.googleapis.com"
        "dlp.googleapis.com"
        "bigquery.googleapis.com"
        "cloudasset.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "cloudfunctions.googleapis.com"
        "serviceusage.googleapis.com"
        "iam.googleapis.com"
        "cloudresourcemanager.googleapis.com"
        "compute.googleapis.com"
    )
    
    for api in "${required_apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --project="$PROJECT_ID"
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "✅ All required APIs enabled"
}

# Initialize Terraform
init_terraform() {
    log_info "📋 Initializing Terraform..."
    
    if [ ! -d "$TERRAFORM_DIR" ]; then
        log_error "❌ Terraform directory not found: $TERRAFORM_DIR"
        exit 1
    fi
    
    cd "$TERRAFORM_DIR"
    
    # Initialize Terraform
    terraform init
    
    # Create terraform.tfvars if it doesn't exist
    if [ ! -f "terraform.tfvars" ]; then
        log_info "Creating terraform.tfvars from example..."
        if [ -f "terraform.tfvars.example" ]; then
            cp terraform.tfvars.example terraform.tfvars
            
            # Update variables with current values
            sed -i.bak "s/PROJECT_ID_PLACEHOLDER/$PROJECT_ID/g" terraform.tfvars
            sed -i.bak "s/REGION_PLACEHOLDER/$REGION/g" terraform.tfvars
            rm terraform.tfvars.bak
            
            log_info "Please review and update terraform.tfvars with your specific values"
        else
            log_warning "⚠️  terraform.tfvars.example not found. Creating minimal terraform.tfvars..."
            cat > terraform.tfvars << EOF
project_id = "$PROJECT_ID"
region = "$REGION"
EOF
        fi
    fi
    
    log_success "✅ Terraform initialized"
}

# Deploy infrastructure
deploy_infrastructure() {
    log_info "🏗️  Deploying infrastructure with Terraform..."
    
    cd "$TERRAFORM_DIR"
    
    # Validate Terraform configuration
    log_info "Validating Terraform configuration..."
    terraform validate
    
    # Plan deployment
    log_info "Planning deployment..."
    terraform plan -out=tfplan
    
    # Confirm deployment
    log_info "About to deploy the data governance infrastructure."
    log_warning "This will create resources in your GCP project that may incur costs."
    
    if [ "${AUTO_APPROVE:-false}" != "true" ]; then
        read -p "Do you want to proceed with the deployment? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Apply deployment
    log_info "Applying deployment..."
    terraform apply tfplan
    
    log_success "✅ Infrastructure deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_info "🔍 Verifying deployment..."
    
    cd "$TERRAFORM_DIR"
    
    # Get outputs
    log_info "Retrieving deployment outputs..."
    terraform output -json > outputs.json
    
    # Check if key resources exist
    log_info "Verifying key resources..."
    
    # Check Dataplex lake
    if terraform output -raw dataplex_lake_name &>/dev/null; then
        LAKE_NAME=$(terraform output -raw dataplex_lake_name)
        if gcloud dataplex lakes describe "$LAKE_NAME" --location="$REGION" &>/dev/null; then
            log_success "✅ Dataplex lake verified: $LAKE_NAME"
        else
            log_error "❌ Dataplex lake not found: $LAKE_NAME"
        fi
    fi
    
    # Check Cloud Workflows
    if terraform output -raw workflow_name &>/dev/null; then
        WORKFLOW_NAME=$(terraform output -raw workflow_name)
        if gcloud workflows describe "$WORKFLOW_NAME" --location="$REGION" &>/dev/null; then
            log_success "✅ Cloud Workflow verified: $WORKFLOW_NAME"
        else
            log_error "❌ Cloud Workflow not found: $WORKFLOW_NAME"
        fi
    fi
    
    # Check BigQuery dataset
    if terraform output -raw dataset_name &>/dev/null; then
        DATASET_NAME=$(terraform output -raw dataset_name)
        if bq show --dataset "$PROJECT_ID:$DATASET_NAME" &>/dev/null; then
            log_success "✅ BigQuery dataset verified: $DATASET_NAME"
        else
            log_error "❌ BigQuery dataset not found: $DATASET_NAME"
        fi
    fi
    
    log_success "✅ Deployment verification completed"
}

# Display deployment summary
display_summary() {
    log_info "📊 Deployment Summary"
    log_info "===================="
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Terraform Directory: $TERRAFORM_DIR"
    log_info "Log File: $LOG_FILE"
    
    if [ -f "$TERRAFORM_DIR/outputs.json" ]; then
        log_info ""
        log_info "🔗 Resource Information:"
        log_info "========================"
        
        # Display key outputs
        cd "$TERRAFORM_DIR"
        
        if terraform output -raw dataplex_lake_name &>/dev/null; then
            log_info "Dataplex Lake: $(terraform output -raw dataplex_lake_name)"
        fi
        
        if terraform output -raw workflow_name &>/dev/null; then
            log_info "Cloud Workflow: $(terraform output -raw workflow_name)"
        fi
        
        if terraform output -raw dataset_name &>/dev/null; then
            log_info "BigQuery Dataset: $(terraform output -raw dataset_name)"
        fi
        
        if terraform output -raw bucket_name &>/dev/null; then
            log_info "Storage Bucket: $(terraform output -raw bucket_name)"
        fi
        
        if terraform output -raw dlp_template_name &>/dev/null; then
            log_info "DLP Template: $(terraform output -raw dlp_template_name)"
        fi
    fi
    
    log_info ""
    log_info "🎉 Next Steps:"
    log_info "=============="
    log_info "1. Review the deployed resources in the Google Cloud Console"
    log_info "2. Execute the governance workflow to test the solution"
    log_info "3. Monitor data governance metrics in BigQuery"
    log_info "4. Configure additional data sources for governance"
    log_info "5. Set up custom alert policies for your requirements"
    log_info ""
    log_info "📚 Documentation:"
    log_info "=================="
    log_info "- Recipe: data-governance-workflows-dataplex-workflows.md"
    log_info "- Terraform: $TERRAFORM_DIR/README.md"
    log_info "- Logs: $LOG_FILE"
    log_info ""
    log_warning "⚠️  Remember to run './destroy.sh' when you're done to avoid ongoing costs"
}

# Main deployment function
main() {
    log_info "🚀 Starting Data Governance Workflows Deployment"
    log_info "================================================="
    
    check_prerequisites
    configure_project
    enable_apis
    init_terraform
    deploy_infrastructure
    verify_deployment
    display_summary
    
    log_success "🎉 Deployment completed successfully!"
    log_info "Total deployment time: $((SECONDS / 60)) minutes and $((SECONDS % 60)) seconds"
}

# Help function
show_help() {
    cat << EOF
Data Governance Workflows Deployment Script

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -y, --yes           Auto-approve deployment (skip confirmation)
    -p, --project       Set GCP project ID
    -r, --region        Set GCP region
    -v, --verbose       Enable verbose logging

Environment Variables:
    PROJECT_ID          GCP project ID to use
    REGION             GCP region to use (default: us-central1)
    AUTO_APPROVE       Skip confirmation prompt (true/false)

Examples:
    $0                  # Interactive deployment
    $0 -y               # Auto-approve deployment
    $0 -p my-project    # Deploy to specific project
    $0 -r us-east1      # Deploy to specific region

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -y|--yes)
            export AUTO_APPROVE=true
            shift
            ;;
        -p|--project)
            export PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            export REGION="$2"
            shift 2
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"