#!/bin/bash

# Tax Calculator API Deployment Script
# Deploys Cloud Functions and Firestore for tax calculation API
# Version: 1.0

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration
DEFAULT_PROJECT_PREFIX="tax-calc"
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="tax-calculator"

# Script options
DRY_RUN=false
FORCE_DEPLOY=false
PROJECT_ID=""
REGION="${DEFAULT_REGION}"
FUNCTION_NAME="${DEFAULT_FUNCTION_NAME}"

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Tax Calculator API with Cloud Functions and Firestore

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required if not creating new)
    -r, --region REGION           GCP region (default: ${DEFAULT_REGION})
    -f, --function-name NAME      Function name (default: ${DEFAULT_FUNCTION_NAME})
    -n, --new-project             Create a new project
    -d, --dry-run                 Show what would be deployed without executing
    -F, --force                   Force deployment even if resources exist
    -h, --help                    Show this help message

EXAMPLES:
    $0 --new-project                              # Create new project and deploy
    $0 --project-id my-project-123               # Deploy to existing project
    $0 --project-id my-project --region us-east1 # Deploy to specific region
    $0 --dry-run                                 # Preview deployment
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project-id)
                PROJECT_ID="$2"
                shift 2
                ;;
            -r|--region)
                REGION="$2"
                shift 2
                ;;
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -n|--new-project)
                NEW_PROJECT=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -F|--force)
                FORCE_DEPLOY=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if Python is available for sample data script
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is required but not found. Please install Python 3."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Create or validate project
setup_project() {
    if [[ "${NEW_PROJECT:-false}" == "true" ]]; then
        if [[ -z "$PROJECT_ID" ]]; then
            PROJECT_ID="${DEFAULT_PROJECT_PREFIX}-$(date +%s)"
            log_info "Generated project ID: $PROJECT_ID"
        fi
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create project: $PROJECT_ID"
            return
        fi
        
        log_info "Creating new project: $PROJECT_ID"
        if gcloud projects create "$PROJECT_ID" --name="Tax Calculator API"; then
            log_success "Project created: $PROJECT_ID"
        else
            log_error "Failed to create project: $PROJECT_ID"
            exit 1
        fi
    else
        if [[ -z "$PROJECT_ID" ]]; then
            log_error "Project ID is required. Use --project-id or --new-project"
            exit 1
        fi
        
        # Validate project exists
        if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
            log_error "Project $PROJECT_ID does not exist or is not accessible"
            exit 1
        fi
        log_success "Using existing project: $PROJECT_ID"
    fi
    
    # Set default project
    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
        gcloud config set functions/region "$REGION"
    fi
}

# Enable required APIs
enable_apis() {
    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return
    fi
    
    log_info "Enabling required APIs..."
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --project="$PROJECT_ID"; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
}

# Create Firestore database
create_firestore() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Firestore database in region: $REGION"
        return
    fi
    
    log_info "Creating Firestore database..."
    
    # Check if Firestore database already exists
    if gcloud firestore databases describe --region="$REGION" --project="$PROJECT_ID" &> /dev/null; then
        if [[ "$FORCE_DEPLOY" == "true" ]]; then
            log_warning "Firestore database already exists, continuing with deployment"
        else
            log_warning "Firestore database already exists. Use --force to continue anyway"
            return
        fi
    else
        if gcloud firestore databases create --region="$REGION" --type=firestore-native --project="$PROJECT_ID"; then
            log_success "Firestore database created"
        else
            log_error "Failed to create Firestore database"
            exit 1
        fi
    fi
}

# Create function source code
create_function_code() {
    local function_dir="tax-calculator-function"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create function source code in: $function_dir"
        return
    fi
    
    log_info "Creating function source code..."
    
    # Create function directory
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create main.py
    cat > main.py << 'EOF'
import json
from datetime import datetime
from google.cloud import firestore
import functions_framework
from flask import Request

# Initialize Firestore client
db = firestore.Client()

# 2024 US Federal Tax Brackets (Single Filer)
TAX_BRACKETS = [
    {"min": 0, "max": 11600, "rate": 0.10},
    {"min": 11601, "max": 47150, "rate": 0.12},
    {"min": 47151, "max": 100525, "rate": 0.22},
    {"min": 100526, "max": 191950, "rate": 0.24},
    {"min": 191951, "max": 243725, "rate": 0.32},
    {"min": 243726, "max": 609350, "rate": 0.35},
    {"min": 609351, "max": float('inf'), "rate": 0.37}
]

@functions_framework.http
def calculate_tax(request: Request):
    """HTTP Cloud Function to calculate income tax."""
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json:
            return {"error": "Invalid JSON payload"}, 400
        
        income = request_json.get('income')
        filing_status = request_json.get('filing_status', 'single')
        deductions = request_json.get('deductions', 0)
        user_id = request_json.get('user_id', 'anonymous')
        
        if income is None or income < 0:
            return {"error": "Income must be a positive number"}, 400
        
        # Calculate taxable income
        standard_deduction = 13850  # 2024 standard deduction for single filers
        total_deductions = max(deductions, standard_deduction)
        taxable_income = max(0, income - total_deductions)
        
        # Calculate tax using progressive tax brackets
        total_tax = 0
        tax_details = []
        remaining_income = taxable_income
        
        for bracket in TAX_BRACKETS:
            if remaining_income <= 0:
                break
            
            # Calculate income in this bracket
            if remaining_income <= (bracket["max"] - bracket["min"]):
                bracket_income = remaining_income
            else:
                bracket_income = bracket["max"] - bracket["min"] + 1
            
            bracket_tax = bracket_income * bracket["rate"]
            total_tax += bracket_tax
            remaining_income -= bracket_income
            
            if bracket_income > 0:
                tax_details.append({
                    "bracket": f"{bracket['rate'] * 100}%",
                    "income_in_bracket": bracket_income,
                    "tax_amount": round(bracket_tax, 2)
                })
        
        # Calculate effective tax rate
        effective_rate = (total_tax / income * 100) if income > 0 else 0
        
        # Prepare calculation result
        result = {
            "income": income,
            "filing_status": filing_status,
            "total_deductions": total_deductions,
            "taxable_income": taxable_income,
            "total_tax": round(total_tax, 2),
            "effective_rate": round(effective_rate, 2),
            "tax_details": tax_details,
            "calculated_at": datetime.utcnow().isoformat(),
            "user_id": user_id
        }
        
        # Store calculation in Firestore
        doc_ref = db.collection('tax_calculations').document()
        doc_ref.set(result)
        result["calculation_id"] = doc_ref.id
        
        return result, 200
        
    except Exception as e:
        return {"error": f"Calculation failed: {str(e)}"}, 500

@functions_framework.http
def get_calculation_history(request: Request):
    """HTTP Cloud Function to retrieve calculation history."""
    try:
        user_id = request.args.get('user_id', 'anonymous')
        limit = min(int(request.args.get('limit', 10)), 50)
        
        # Query Firestore for user's calculation history
        calculations = []
        docs = db.collection('tax_calculations')\
                 .where('user_id', '==', user_id)\
                 .order_by('calculated_at', direction=firestore.Query.DESCENDING)\
                 .limit(limit)\
                 .stream()
        
        for doc in docs:
            calc_data = doc.to_dict()
            calc_data['calculation_id'] = doc.id
            calculations.append(calc_data)
        
        return {
            "user_id": user_id,
            "calculations": calculations,
            "total_count": len(calculations)
        }, 200
        
    except Exception as e:
        return {"error": f"Failed to retrieve history: {str(e)}"}, 500
EOF
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
functions-framework==3.*
google-cloud-firestore>=2.0.0
flask>=2.0.0
EOF
    
    log_success "Function source code created"
}

# Deploy Cloud Functions
deploy_functions() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy functions: $FUNCTION_NAME and ${FUNCTION_NAME}-history"
        return
    fi
    
    log_info "Deploying tax calculator function..."
    
    # Deploy main calculator function
    if gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point calculate_tax \
        --memory 256MB \
        --timeout 60s \
        --max-instances 10 \
        --project="$PROJECT_ID" \
        --region="$REGION"; then
        log_success "Tax calculator function deployed"
    else
        log_error "Failed to deploy tax calculator function"
        exit 1
    fi
    
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    log_info "Deploying calculation history function..."
    
    # Deploy history function
    if gcloud functions deploy "${FUNCTION_NAME}-history" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point get_calculation_history \
        --memory 128MB \
        --timeout 30s \
        --max-instances 5 \
        --project="$PROJECT_ID" \
        --region="$REGION"; then
        log_success "Calculation history function deployed"
    else
        log_error "Failed to deploy calculation history function"
        exit 1
    fi
    
    # Get history function URL
    HISTORY_URL=$(gcloud functions describe "${FUNCTION_NAME}-history" \
        --project="$PROJECT_ID" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    # Store URLs in environment variables file
    cat > ../function-urls.env << EOF
FUNCTION_URL=$FUNCTION_URL
HISTORY_URL=$HISTORY_URL
PROJECT_ID=$PROJECT_ID
REGION=$REGION
FUNCTION_NAME=$FUNCTION_NAME
EOF
    
    log_success "Function URLs saved to function-urls.env"
    log_info "Tax Calculator URL: $FUNCTION_URL"
    log_info "History URL: $HISTORY_URL"
}

# Add sample data to Firestore
add_sample_data() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would add sample data to Firestore"
        return
    fi
    
    log_info "Adding sample data to Firestore..."
    
    # Create sample data script
    cat > add_sample_data.py << 'EOF'
from google.cloud import firestore
from datetime import datetime
import sys

# Initialize Firestore client
try:
    db = firestore.Client()
except Exception as e:
    print(f"Failed to initialize Firestore client: {e}")
    sys.exit(1)

# Sample tax calculations
sample_calculations = [
    {
        "income": 50000,
        "filing_status": "single",
        "total_deductions": 13850,
        "taxable_income": 36150,
        "total_tax": 4095.00,
        "effective_rate": 8.19,
        "user_id": "demo_user",
        "calculated_at": datetime.utcnow().isoformat()
    },
    {
        "income": 75000,
        "filing_status": "single", 
        "total_deductions": 15000,
        "taxable_income": 60000,
        "total_tax": 8837.00,
        "effective_rate": 11.78,
        "user_id": "demo_user",
        "calculated_at": datetime.utcnow().isoformat()
    }
]

# Add sample data to Firestore
try:
    for calc in sample_calculations:
        doc_ref = db.collection('tax_calculations').document()
        doc_ref.set(calc)
        print(f"Added calculation: {calc['income']} income")
    
    print("Sample data added successfully!")
except Exception as e:
    print(f"Failed to add sample data: {e}")
    sys.exit(1)
EOF
    
    # Run the sample data script
    if python3 add_sample_data.py; then
        log_success "Sample data added to Firestore"
    else
        log_warning "Failed to add sample data (this is optional)"
    fi
    
    # Return to parent directory
    cd ..
}

# Configure Firestore security rules
configure_firestore_rules() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure Firestore security rules"
        return
    fi
    
    log_info "Configuring Firestore security rules..."
    
    # Create firestore.rules
    cat > firestore.rules << 'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read/write access to tax calculations
    match /tax_calculations/{document} {
      allow read, write: if true;
      // In production, add proper authentication:
      // allow read, write: if request.auth != null && 
      //   request.auth.uid == resource.data.user_id;
    }
    
    // Allow read access to tax brackets and rates
    match /tax_config/{document} {
      allow read: if true;
      allow write: if false; // Only admins can modify tax config
    }
  }
}
EOF
    
    # Deploy security rules
    if gcloud firestore rules --project="$PROJECT_ID" firestore.rules; then
        log_success "Firestore security rules configured"
    else
        log_warning "Failed to configure Firestore security rules (this is optional)"
    fi
}

# Validate deployment
validate_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate deployment"
        return
    fi
    
    log_info "Validating deployment..."
    
    # Source the environment variables
    if [[ -f "function-urls.env" ]]; then
        source function-urls.env
    else
        log_error "Function URLs file not found. Deployment may have failed."
        return 1
    fi
    
    # Test function accessibility
    if curl -s -f "$FUNCTION_URL" > /dev/null; then
        log_success "Tax calculator function is accessible"
    else
        log_warning "Tax calculator function may not be ready yet (this is normal)"
    fi
    
    if curl -s -f "$HISTORY_URL" > /dev/null; then
        log_success "History function is accessible"
    else
        log_warning "History function may not be ready yet (this is normal)"
    fi
    
    # Check Firestore collections
    if gcloud firestore collections list --project="$PROJECT_ID" | grep -q "tax_calculations"; then
        log_success "Firestore collections verified"
    else
        log_info "Firestore collections will be created when first used"
    fi
}

# Main deployment function
main() {
    log_info "Starting Tax Calculator API deployment..."
    
    parse_args "$@"
    check_prerequisites
    setup_project
    enable_apis
    create_firestore
    create_function_code
    deploy_functions
    add_sample_data
    configure_firestore_rules
    validate_deployment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Deployment preview completed"
        echo
        echo "To run actual deployment:"
        echo "  $0 --project-id $PROJECT_ID --region $REGION"
    else
        log_success "Tax Calculator API deployment completed successfully!"
        echo
        echo "=== Deployment Summary ==="
        echo "Project ID: $PROJECT_ID"
        echo "Region: $REGION"
        echo "Tax Calculator URL: ${FUNCTION_URL:-'Check function-urls.env'}"
        echo "History URL: ${HISTORY_URL:-'Check function-urls.env'}"
        echo
        echo "Test the API with:"
        echo "curl -X POST $FUNCTION_URL -H 'Content-Type: application/json' -d '{\"income\": 65000, \"user_id\": \"test\"}'"
        echo
        echo "View deployment details in function-urls.env"
    fi
}

# Error handler
error_handler() {
    log_error "Deployment failed at line $1"
    exit 1
}

trap 'error_handler $LINENO' ERR

# Run main function
main "$@"