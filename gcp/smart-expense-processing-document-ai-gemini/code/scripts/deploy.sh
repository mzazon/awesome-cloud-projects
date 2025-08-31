#!/bin/bash

# Smart Expense Processing with Document AI and Gemini - Deployment Script
# This script deploys the complete expense processing infrastructure on GCP
# Version: 1.0
# Last Updated: 2025-07-12

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="/tmp/expense-ai-deploy-$(date +%Y%m%d-%H%M%S).log"
readonly REQUIRED_APIS=(
    "documentai.googleapis.com"
    "aiplatform.googleapis.com"
    "workflows.googleapis.com"
    "sqladmin.googleapis.com"
    "storage.googleapis.com"
    "run.googleapis.com"
    "cloudfunctions.googleapis.com"
    "monitoring.googleapis.com"
    "logging.googleapis.com"
)

# Default configuration values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check log file: $LOG_FILE"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Performing cleanup due to deployment failure..."
    # Note: This is a basic cleanup - full cleanup should use destroy.sh
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || true
    fi
}

trap cleanup_on_error ERR

# Prerequisites checking functions
check_gcloud_auth() {
    log_info "Checking Google Cloud authentication..."
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | grep -q .; then
        error_exit "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
    fi
    log_success "Google Cloud authentication verified"
}

check_required_tools() {
    log_info "Checking required tools..."
    local missing_tools=()
    
    for tool in gcloud gsutil curl openssl python3; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error_exit "Missing required tools: ${missing_tools[*]}"
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "Using Google Cloud SDK version: $gcloud_version"
    
    log_success "All required tools are available"
}

check_billing_account() {
    log_info "Checking billing account configuration..."
    local billing_accounts
    billing_accounts=$(gcloud billing accounts list --format="value(name)" 2>/dev/null || echo "")
    
    if [[ -z "$billing_accounts" ]]; then
        log_warning "No billing accounts found. You may need to link a billing account to enable APIs."
    else
        log_success "Billing accounts available"
    fi
}

# Project setup functions
setup_project_variables() {
    log_info "Setting up project variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="expense-ai-$(date +%s)"
        log_info "Generated project ID: $PROJECT_ID"
    fi
    
    # Set region and zone with defaults
    export REGION="${REGION:-$DEFAULT_REGION}"
    export ZONE="${ZONE:-$DEFAULT_ZONE}"
    
    # Generate random suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    # Set derived variables
    export BUCKET_NAME="expense-receipts-${RANDOM_SUFFIX}"
    export DB_INSTANCE="expense-db-${RANDOM_SUFFIX}"
    export DB_PASSWORD="ExpenseDB_$(openssl rand -base64 12)"
    export PROCESSOR_NAME="expense-parser-${RANDOM_SUFFIX}"
    
    log_success "Project variables configured"
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Bucket: $BUCKET_NAME"
    log_info "Database: $DB_INSTANCE"
}

configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project"
    gcloud config set compute/region "$REGION" || error_exit "Failed to set region"
    gcloud config set compute/zone "$ZONE" || error_exit "Failed to set zone"
    
    log_success "gcloud configuration updated"
}

create_project() {
    log_info "Creating or verifying project: $PROJECT_ID"
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_info "Project $PROJECT_ID already exists"
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" \
            --name="Smart Expense Processing" \
            --set-as-default || error_exit "Failed to create project"
        
        log_success "Project created successfully"
        
        # Note about billing
        log_warning "Remember to link a billing account to enable APIs:"
        log_warning "gcloud billing projects link $PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT_ID"
    fi
}

enable_apis() {
    log_info "Enabling required APIs..."
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" || error_exit "Failed to enable $api"
    done
    
    log_success "All required APIs enabled"
    
    # Wait for APIs to be fully available
    log_info "Waiting for APIs to be fully available..."
    sleep 30
}

# Infrastructure deployment functions
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: $BUCKET_NAME"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_info "Bucket $BUCKET_NAME already exists"
    else
        gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://${BUCKET_NAME}" \
            || error_exit "Failed to create storage bucket"
        
        # Set bucket policies
        gsutil lifecycle set - "gs://${BUCKET_NAME}" <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
        "condition": {"age": 30}
      },
      {
        "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
        "condition": {"age": 90}
      }
    ]
  }
}
EOF
        
        log_success "Storage bucket created with lifecycle policies"
    fi
}

create_document_ai_processor() {
    log_info "Creating Document AI expense processor..."
    
    # Get access token for API calls
    local access_token
    access_token=$(gcloud auth application-default print-access-token) \
        || error_exit "Failed to get access token"
    
    # Create processor via REST API
    local processor_response
    processor_response=$(curl -s -X POST \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: application/json" \
        "https://${REGION}-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/processors" \
        -d "{
            \"displayName\": \"${PROCESSOR_NAME}\",
            \"type\": \"EXPENSE_PROCESSOR\"
        }") || error_exit "Failed to create Document AI processor"
    
    # Extract processor ID
    export PROCESSOR_ID
    PROCESSOR_ID=$(echo "$processor_response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data['name'].split('/')[-1])
except:
    sys.exit(1)
") || error_exit "Failed to extract processor ID"
    
    log_success "Document AI processor created: $PROCESSOR_ID"
}

create_cloud_sql_database() {
    log_info "Creating Cloud SQL PostgreSQL database..."
    
    # Check if instance already exists
    if gcloud sql instances describe "$DB_INSTANCE" &>/dev/null; then
        log_info "Cloud SQL instance $DB_INSTANCE already exists"
    else
        log_info "Creating Cloud SQL instance: $DB_INSTANCE"
        gcloud sql instances create "$DB_INSTANCE" \
            --database-version=POSTGRES_15 \
            --tier=db-f1-micro \
            --region="$REGION" \
            --storage-type=SSD \
            --storage-size=10GB \
            --backup \
            --deletion-protection \
            --availability-type=zonal \
            || error_exit "Failed to create Cloud SQL instance"
        
        log_success "Cloud SQL instance created"
    fi
    
    # Set root password
    log_info "Setting database password..."
    gcloud sql users set-password postgres \
        --instance="$DB_INSTANCE" \
        --password="$DB_PASSWORD" \
        || error_exit "Failed to set database password"
    
    # Create expense database
    log_info "Creating expense database..."
    gcloud sql databases create expenses --instance="$DB_INSTANCE" \
        || log_warning "Database may already exist"
    
    log_success "Database configuration completed"
}

setup_database_schema() {
    log_info "Setting up database schema..."
    
    # Create schema file
    cat > "/tmp/expense_schema.sql" << 'EOF'
CREATE TABLE IF NOT EXISTS expenses (
    id SERIAL PRIMARY KEY,
    employee_email VARCHAR(255) NOT NULL,
    vendor_name VARCHAR(255),
    expense_date DATE,
    total_amount DECIMAL(10,2),
    currency VARCHAR(3) DEFAULT 'USD',
    category VARCHAR(100),
    description TEXT,
    receipt_url VARCHAR(500),
    extracted_data JSONB,
    validation_status VARCHAR(50) DEFAULT 'pending',
    approval_status VARCHAR(50) DEFAULT 'pending',
    approver_email VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_expenses_employee ON expenses(employee_email);
CREATE INDEX IF NOT EXISTS idx_expenses_status ON expenses(approval_status);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(expense_date);

-- Create sample data for testing
INSERT INTO expenses (employee_email, vendor_name, expense_date, total_amount, category, description)
VALUES 
    ('test@company.com', 'Sample Restaurant', '2025-01-15', 45.50, 'meals', 'Business lunch')
ON CONFLICT DO NOTHING;
EOF
    
    # Download Cloud SQL Proxy if needed
    local proxy_path="/tmp/cloud-sql-proxy"
    if [[ ! -f "$proxy_path" ]]; then
        log_info "Downloading Cloud SQL Proxy..."
        curl -o "$proxy_path" \
            "https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64" \
            || error_exit "Failed to download Cloud SQL Proxy"
        chmod +x "$proxy_path"
    fi
    
    # Start Cloud SQL Proxy
    log_info "Starting Cloud SQL Proxy..."
    local connection_name="${PROJECT_ID}:${REGION}:${DB_INSTANCE}"
    "$proxy_path" -instances="$connection_name"=tcp:5432 &
    local proxy_pid=$!
    
    # Wait for proxy to start
    sleep 10
    
    # Execute schema using psql
    if command -v psql &> /dev/null; then
        log_info "Executing database schema..."
        PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -p 5432 \
            -U postgres -d expenses < "/tmp/expense_schema.sql" \
            || log_warning "Schema creation may have failed"
        log_success "Database schema created"
    else
        log_warning "psql not available - schema must be applied manually"
    fi
    
    # Stop proxy
    kill $proxy_pid || true
    
    # Cleanup
    rm -f "/tmp/expense_schema.sql"
}

deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Deploy expense validator function
    local validator_dir="$PROJECT_DIR/terraform/functions/validator"
    if [[ -d "$validator_dir" ]]; then
        log_info "Deploying expense validator function..."
        (
            cd "$validator_dir"
            gcloud functions deploy expense-validator \
                --runtime python311 \
                --trigger-http \
                --allow-unauthenticated \
                --source . \
                --entry-point validate_expense \
                --set-env-vars "PROJECT_ID=${PROJECT_ID},REGION=${REGION}" \
                --memory 256MB \
                --timeout 60s \
                || error_exit "Failed to deploy validator function"
        )
        
        # Get function URL
        export VALIDATOR_URL
        VALIDATOR_URL=$(gcloud functions describe expense-validator \
            --format="value(httpsTrigger.url)") \
            || error_exit "Failed to get validator URL"
        
        log_success "Validator function deployed: $VALIDATOR_URL"
    else
        log_warning "Validator function source not found at $validator_dir"
    fi
    
    # Deploy report generator function
    local report_dir="$PROJECT_DIR/terraform/functions/report-generator"
    if [[ -d "$report_dir" ]]; then
        log_info "Deploying report generator function..."
        (
            cd "$report_dir"
            gcloud functions deploy expense-report-generator \
                --runtime python311 \
                --trigger-http \
                --allow-unauthenticated \
                --source . \
                --entry-point generate_expense_report \
                --set-env-vars "BUCKET_NAME=${BUCKET_NAME},PROJECT_ID=${PROJECT_ID}" \
                --memory 256MB \
                --timeout 60s \
                || error_exit "Failed to deploy report generator function"
        )
        
        log_success "Report generator function deployed"
    else
        log_warning "Report generator function source not found at $report_dir"
    fi
}

deploy_workflows() {
    log_info "Deploying Cloud Workflows..."
    
    local workflow_file="$PROJECT_DIR/terraform/workflows/expense-workflow.yaml"
    if [[ -f "$workflow_file" ]]; then
        # Substitute environment variables in workflow file
        local temp_workflow="/tmp/expense-workflow.yaml"
        envsubst < "$workflow_file" > "$temp_workflow"
        
        gcloud workflows deploy expense-processing-workflow \
            --source="$temp_workflow" \
            --location="$REGION" \
            || error_exit "Failed to deploy workflow"
        
        rm -f "$temp_workflow"
        log_success "Workflow deployed successfully"
    else
        log_warning "Workflow file not found at $workflow_file"
    fi
}

setup_monitoring() {
    log_info "Setting up monitoring dashboard..."
    
    local dashboard_file="$PROJECT_DIR/terraform/monitoring/dashboard.json"
    if [[ -f "$dashboard_file" ]]; then
        # Create monitoring dashboard
        gcloud monitoring dashboards create --config-from-file="$dashboard_file" \
            || log_warning "Dashboard creation failed - may already exist"
        
        log_success "Monitoring dashboard configured"
    else
        log_warning "Dashboard configuration not found at $dashboard_file"
    fi
}

# Testing functions
run_deployment_tests() {
    log_info "Running deployment validation tests..."
    
    # Test Document AI processor
    if [[ -n "${PROCESSOR_ID:-}" ]]; then
        log_info "Testing Document AI processor..."
        local processor_status
        processor_status=$(curl -s -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
            "https://${REGION}-documentai.googleapis.com/v1/projects/${PROJECT_ID}/locations/${REGION}/processors/${PROCESSOR_ID}" \
            | python3 -c "import sys, json; print(json.load(sys.stdin).get('state', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
        
        if [[ "$processor_status" == "ENABLED" ]]; then
            log_success "Document AI processor is enabled"
        else
            log_warning "Document AI processor status: $processor_status"
        fi
    fi
    
    # Test Cloud SQL connectivity
    log_info "Testing Cloud SQL connectivity..."
    if gcloud sql instances describe "$DB_INSTANCE" --format="value(state)" | grep -q "RUNNABLE"; then
        log_success "Cloud SQL instance is running"
    else
        log_warning "Cloud SQL instance may not be ready"
    fi
    
    # Test Cloud Functions
    if [[ -n "${VALIDATOR_URL:-}" ]]; then
        log_info "Testing validator function..."
        local test_response
        test_response=$(curl -s -X POST "$VALIDATOR_URL" \
            -H "Content-Type: application/json" \
            -d '{"vendor_name":"Test","total_amount":25.00,"category":"meals"}' \
            || echo "ERROR")
        
        if [[ "$test_response" != "ERROR" ]] && echo "$test_response" | grep -q "approved"; then
            log_success "Validator function is responding"
        else
            log_warning "Validator function may not be working correctly"
        fi
    fi
    
    # Test Storage bucket
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "Storage bucket is accessible"
    else
        log_warning "Storage bucket access test failed"
    fi
}

# Output functions
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local output_file="$PROJECT_DIR/deployment-info.txt"
    cat > "$output_file" << EOF
# Smart Expense Processing Deployment Information
# Generated on: $(date)

## Project Configuration
PROJECT_ID=$PROJECT_ID
REGION=$REGION
ZONE=$ZONE

## Resource Names
BUCKET_NAME=$BUCKET_NAME
DB_INSTANCE=$DB_INSTANCE
PROCESSOR_ID=${PROCESSOR_ID:-}
VALIDATOR_URL=${VALIDATOR_URL:-}

## Database Connection
DB_PASSWORD=$DB_PASSWORD

## Important Commands
# Connect to database:
gcloud sql connect $DB_INSTANCE --user=postgres --database=expenses

# View workflow executions:
gcloud workflows executions list expense-processing-workflow --location=$REGION

# View function logs:
gcloud functions logs read expense-validator
gcloud functions logs read expense-report-generator

# Access monitoring dashboard:
echo "Check Google Cloud Console > Monitoring > Dashboards"

## Cleanup Command
# To destroy all resources:
./scripts/destroy.sh
EOF
    
    log_success "Deployment information saved to: $output_file"
}

display_completion_summary() {
    echo
    echo "=================================================================="
    echo -e "${GREEN}Smart Expense Processing Deployment Complete!${NC}"
    echo "=================================================================="
    echo
    echo -e "${BLUE}Project Information:${NC}"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Storage Bucket: gs://$BUCKET_NAME"
    echo "  Database Instance: $DB_INSTANCE"
    echo
    echo -e "${BLUE}Key Resources:${NC}"
    echo "  Document AI Processor: ${PROCESSOR_ID:-'Not created'}"
    echo "  Validator Function URL: ${VALIDATOR_URL:-'Not deployed'}"
    echo "  Cloud SQL Database: $DB_INSTANCE"
    echo "  Workflow: expense-processing-workflow"
    echo
    echo -e "${BLUE}Next Steps:${NC}"
    echo "  1. Link billing account if not already done:"
    echo "     gcloud billing projects link $PROJECT_ID --billing-account=YOUR_BILLING_ACCOUNT_ID"
    echo "  2. Upload sample receipts to test the system"
    echo "  3. Check the monitoring dashboard in Cloud Console"
    echo "  4. Review deployment info: $PROJECT_DIR/deployment-info.txt"
    echo
    echo -e "${BLUE}Access Your Resources:${NC}"
    echo "  Console: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
    echo "  Workflows: https://console.cloud.google.com/workflows?project=$PROJECT_ID"
    echo "  Functions: https://console.cloud.google.com/functions?project=$PROJECT_ID"
    echo
    echo -e "${YELLOW}Important:${NC} Save the deployment info file - it contains database passwords!"
    echo -e "${YELLOW}Log file available at:${NC} $LOG_FILE"
    echo
}

# Main execution function
main() {
    echo "=================================================================="
    echo "Smart Expense Processing with Document AI and Gemini"
    echo "Deployment Script v1.0"
    echo "=================================================================="
    echo
    
    log_info "Starting deployment at $(date)"
    log_info "Log file: $LOG_FILE"
    
    # Prerequisites
    check_required_tools
    check_gcloud_auth
    check_billing_account
    
    # Project setup
    setup_project_variables
    configure_gcloud
    create_project
    enable_apis
    
    # Infrastructure deployment
    create_storage_bucket
    create_document_ai_processor
    create_cloud_sql_database
    setup_database_schema
    deploy_cloud_functions
    deploy_workflows
    setup_monitoring
    
    # Validation and completion
    run_deployment_tests
    save_deployment_info
    display_completion_summary
    
    log_success "Deployment completed successfully at $(date)"
}

# Handle command line arguments
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Deploy Smart Expense Processing infrastructure on Google Cloud"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID    GCP project ID (default: auto-generated)"
    echo "  REGION        GCP region (default: us-central1)"
    echo "  ZONE          GCP zone (default: us-central1-a)"
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  PROJECT_ID=my-expense-project $0      # Deploy to specific project"
    echo "  REGION=us-west1 $0                    # Deploy to specific region"
    echo
    echo "Prerequisites:"
    echo "  - Google Cloud CLI installed and configured"
    echo "  - Valid Google Cloud account with billing enabled"
    echo "  - Appropriate IAM permissions for resource creation"
    echo
    exit 0
fi

# Execute main function
main "$@"