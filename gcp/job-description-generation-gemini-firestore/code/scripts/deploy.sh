#!/bin/bash

# GCP Job Description Generation with Gemini and Firestore - Deployment Script
# This script deploys the complete infrastructure for automated job description generation

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Help function
show_help() {
    cat << EOF
GCP Job Description Generation Deployment Script

USAGE:
    ./deploy.sh [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID     Set GCP project ID (default: generates unique ID)
    -r, --region REGION            Set deployment region (default: us-central1)
    -f, --force                    Skip confirmation prompts
    -h, --help                     Show this help message
    --dry-run                      Show what would be deployed without executing

EXAMPLES:
    ./deploy.sh                              # Deploy with default settings
    ./deploy.sh -p my-project -r us-east1    # Deploy to specific project and region
    ./deploy.sh --force                      # Deploy without confirmation prompts
    ./deploy.sh --dry-run                    # Preview deployment without executing

EOF
}

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"
FORCE_MODE=false
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_BASE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Parse command line arguments
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
        -f|--force)
            FORCE_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set defaults if not provided
REGION=${REGION:-$DEFAULT_REGION}
ZONE=${ZONE:-$DEFAULT_ZONE}

# Generate unique project ID if not provided
if [[ -z "${PROJECT_ID:-}" ]]; then
    PROJECT_ID="hr-automation-$(date +%s)"
    log "Generated project ID: $PROJECT_ID"
fi

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

log "=== GCP Job Description Generation Deployment ==="
log "Project ID: $PROJECT_ID"
log "Region: $REGION"
log "Zone: $ZONE"
log "Random Suffix: $RANDOM_SUFFIX"

if [[ "$DRY_RUN" == "true" ]]; then
    warning "DRY RUN MODE - No resources will be created"
fi

# Confirmation prompt (unless force mode or dry run)
if [[ "$FORCE_MODE" == "false" && "$DRY_RUN" == "false" ]]; then
    echo
    read -p "Proceed with deployment? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Deployment cancelled"
        exit 0
    fi
fi

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Installing it for JSON processing..."
        if [[ "$DRY_RUN" == "false" ]]; then
            # Try to install jq based on the OS
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y jq
            elif command -v yum &> /dev/null; then
                sudo yum install -y jq
            elif command -v brew &> /dev/null; then
                brew install jq
            else
                error "Could not install jq automatically. Please install it manually."
                exit 1
            fi
        fi
    fi
    
    # Check if authenticated with gcloud
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
            error "Not authenticated with gcloud. Please run 'gcloud auth login' first."
            exit 1
        fi
    fi
    
    success "Prerequisites check completed"
}

# Project setup function
setup_project() {
    log "Setting up GCP project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create project: $PROJECT_ID"
        log "[DRY RUN] Would set default project and region configuration"
        log "[DRY RUN] Would enable required APIs"
        return 0
    fi
    
    # Create project (optional - may already exist)
    if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log "Project $PROJECT_ID already exists"
    else
        log "Creating project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" || {
            error "Failed to create project. You may need billing permissions."
            exit 1
        }
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        warning "Billing is not enabled for this project. Some services may not work."
        warning "Please enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
    fi
    
    success "Project setup completed"
}

# Enable APIs function
enable_apis() {
    log "Enabling required APIs..."
    
    local apis=(
        "aiplatform.googleapis.com"
        "firestore.googleapis.com"
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        for api in "${apis[@]}"; do
            log "[DRY RUN] Would enable API: $api"
        done
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            success "Enabled $api"
        else
            error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log "Waiting for APIs to be fully enabled..."
    sleep 30
    
    success "All APIs enabled successfully"
}

# Initialize Firestore function
setup_firestore() {
    log "Setting up Firestore database..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create Firestore database in region: $REGION"
        return 0
    fi
    
    # Check if Firestore is already initialized
    if gcloud firestore databases describe --region="$REGION" >/dev/null 2>&1; then
        log "Firestore database already exists"
    else
        log "Creating Firestore database in Native mode..."
        gcloud firestore databases create --region="$REGION" --quiet
    fi
    
    success "Firestore database ready"
}

# Setup Firestore data function
setup_firestore_data() {
    log "Setting up initial Firestore data..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would create company culture and job template documents"
        return 0
    fi
    
    # Create Python script for Firestore setup
    cat > /tmp/setup_firestore_data.py << 'EOF'
import sys
import os
from google.cloud import firestore

def setup_firestore_data(project_id):
    """Set up initial Firestore data for the HR automation system."""
    try:
        # Initialize Firestore client
        db = firestore.Client(project=project_id)
        
        # Create company culture document
        culture_data = {
            "company_name": "TechInnovate Solutions",
            "mission": "Empowering businesses through innovative technology solutions",
            "values": ["Innovation", "Collaboration", "Integrity", "Excellence"],
            "culture_description": "Fast-paced, collaborative environment with focus on continuous learning and growth",
            "benefits": ["Competitive salary", "Health insurance", "Remote work options", "Professional development budget", "Flexible hours", "Stock options"],
            "work_environment": "Hybrid office model with flexible hours",
            "company_size": "Growing startup (50-200 employees)",
            "industry": "Technology Consulting"
        }
        
        db.collection('company_culture').document('default').set(culture_data)
        print("✅ Company culture data stored successfully")
        
        # Create software engineer template
        software_engineer_template = {
            "title": "Software Engineer",
            "department": "Engineering",
            "level": "mid",
            "required_skills": ["JavaScript", "Python", "React", "Node.js", "Git"],
            "nice_to_have": ["Google Cloud", "Docker", "GraphQL", "Kubernetes", "CI/CD"],
            "education": "Bachelor degree in Computer Science or equivalent experience",
            "experience_years": "2-4 years",
            "responsibilities": [
                "Develop and maintain web applications",
                "Collaborate with cross-functional teams",
                "Write clean, maintainable code",
                "Participate in code reviews",
                "Contribute to technical documentation"
            ],
            "compliance_notes": "Equal opportunity employer statement required"
        }
        
        # Create marketing manager template
        marketing_manager_template = {
            "title": "Marketing Manager",
            "department": "Marketing",
            "level": "senior",
            "required_skills": ["Digital Marketing", "Campaign Management", "Analytics", "Content Strategy", "SEO/SEM"],
            "nice_to_have": ["Adobe Creative Suite", "Marketing Automation", "SQL", "A/B Testing", "CRM Platforms"],
            "education": "Bachelor degree in Marketing, Business, or related field",
            "experience_years": "5-7 years",
            "responsibilities": [
                "Develop marketing strategies and campaigns",
                "Manage marketing budget and ROI",
                "Lead marketing team and initiatives",
                "Analyze market trends and competitor activities",
                "Coordinate with sales and product teams"
            ],
            "compliance_notes": "Equal opportunity employer statement required"
        }
        
        # Create data scientist template
        data_scientist_template = {
            "title": "Senior Data Scientist",
            "department": "Analytics",
            "level": "senior",
            "required_skills": ["Python", "R", "Machine Learning", "SQL", "Statistics"],
            "nice_to_have": ["TensorFlow", "PyTorch", "Google Cloud AI", "BigQuery", "Jupyter"],
            "education": "Master's degree in Data Science, Statistics, or related field",
            "experience_years": "4-6 years",
            "responsibilities": [
                "Build and deploy machine learning models",
                "Analyze complex datasets for business insights",
                "Collaborate with engineering teams on data pipelines",
                "Present findings to stakeholders",
                "Mentor junior data scientists"
            ],
            "compliance_notes": "Equal opportunity employer statement required"
        }
        
        # Store templates in Firestore
        db.collection('job_templates').document('software_engineer').set(software_engineer_template)
        db.collection('job_templates').document('marketing_manager').set(marketing_manager_template)
        db.collection('job_templates').document('data_scientist').set(data_scientist_template)
        
        print("✅ Job role templates created successfully")
        print(f"✅ Firestore setup completed for project: {project_id}")
        
    except Exception as e:
        print(f"❌ Error setting up Firestore data: {e}")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 setup_firestore_data.py <project_id>")
        sys.exit(1)
    
    project_id = sys.argv[1]
    setup_firestore_data(project_id)
EOF
    
    # Install Google Cloud Firestore client if not already installed
    pip3 install google-cloud-firestore >/dev/null 2>&1 || {
        error "Failed to install Google Cloud Firestore client"
        exit 1
    }
    
    # Run the Firestore setup script
    python3 /tmp/setup_firestore_data.py "$PROJECT_ID"
    
    # Clean up temporary file
    rm -f /tmp/setup_firestore_data.py
    
    success "Firestore data setup completed"
}

# Deploy Cloud Functions
deploy_functions() {
    log "Deploying Cloud Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would deploy generate-job-description function"
        log "[DRY RUN] Would deploy validate-compliance function"
        return 0
    fi
    
    # Create temporary directory for function deployment
    TEMP_FUNCTION_DIR="/tmp/job-description-functions-$RANDOM_SUFFIX"
    mkdir -p "$TEMP_FUNCTION_DIR"
    
    # Copy function templates from terraform directory
    local terraform_templates_dir="$PROJECT_BASE_DIR/code/terraform/templates"
    
    if [[ -d "$terraform_templates_dir" ]]; then
        cp "$terraform_templates_dir"/*.py "$TEMP_FUNCTION_DIR/"
        cp "$terraform_templates_dir"/requirements.txt "$TEMP_FUNCTION_DIR/"
    else
        error "Function templates not found at: $terraform_templates_dir"
        exit 1
    fi
    
    cd "$TEMP_FUNCTION_DIR"
    
    # Deploy job description generation function
    log "Deploying generate-job-description function..."
    gcloud functions deploy generate-job-description \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point generate_job_description_http \
        --memory 512MB \
        --timeout 300s \
        --region="$REGION" \
        --set-env-vars "GCP_PROJECT=$PROJECT_ID,FUNCTION_REGION=$REGION" \
        --quiet
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe generate-job-description \
        --gen2 \
        --region="$REGION" \
        --format="value(serviceConfig.uri)")
    
    success "Job description generation function deployed at: $function_url"
    
    # Deploy compliance validation function  
    log "Deploying validate-compliance function..."
    gcloud functions deploy validate-compliance \
        --gen2 \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point validate_compliance \
        --memory 256MB \
        --timeout 60s \
        --region="$REGION" \
        --set-env-vars "GCP_PROJECT=$PROJECT_ID,FUNCTION_REGION=$REGION" \
        --quiet
    
    # Get compliance function URL
    local compliance_url
    compliance_url=$(gcloud functions describe validate-compliance \
        --gen2 \
        --region="$REGION" \
        --format="value(serviceConfig.uri)")
    
    success "Compliance validation function deployed at: $compliance_url"
    
    # Clean up temporary directory
    cd "$SCRIPT_DIR"
    rm -rf "$TEMP_FUNCTION_DIR"
    
    # Store URLs in environment file for later use
    cat > "$SCRIPT_DIR/deployment.env" << EOF
PROJECT_ID=$PROJECT_ID
REGION=$REGION
FUNCTION_URL=$function_url
COMPLIANCE_URL=$compliance_url
DEPLOYMENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    
    success "Cloud Functions deployment completed"
}

# Test deployment function
test_deployment() {
    log "Testing deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would test function endpoints and Firestore data"
        return 0
    fi
    
    # Source deployment environment
    if [[ -f "$SCRIPT_DIR/deployment.env" ]]; then
        source "$SCRIPT_DIR/deployment.env"
    else
        error "Deployment environment file not found"
        return 1
    fi
    
    # Test job description generation
    log "Testing job description generation..."
    local test_response
    test_response=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{
            "role_id": "software_engineer",
            "custom_requirements": "Experience with cloud-native applications"
        }' || echo "ERROR")
    
    if [[ "$test_response" == "ERROR" ]] || ! echo "$test_response" | jq -e '.success' >/dev/null 2>&1; then
        warning "Job description generation test failed"
        log "Response: $test_response"
    else
        success "Job description generation test passed"
    fi
    
    # Test compliance validation
    log "Testing compliance validation..."
    local compliance_response
    compliance_response=$(curl -s -X POST "$COMPLIANCE_URL" \
        -H "Content-Type: application/json" \
        -d '{
            "job_description": "Software Engineer position requiring innovative thinking and collaborative spirit"
        }' || echo "ERROR")
    
    if [[ "$compliance_response" == "ERROR" ]] || ! echo "$compliance_response" | jq -e '.success' >/dev/null 2>&1; then
        warning "Compliance validation test failed"
        log "Response: $compliance_response"
    else
        success "Compliance validation test passed"
    fi
    
    success "Deployment testing completed"
}

# Display deployment summary
show_summary() {
    log "=== Deployment Summary ==="
    
    if [[ -f "$SCRIPT_DIR/deployment.env" ]]; then
        source "$SCRIPT_DIR/deployment.env"
        
        echo
        echo "📋 Deployment Information:"
        echo "  Project ID: $PROJECT_ID"
        echo "  Region: $REGION"
        echo "  Deployment Time: $DEPLOYMENT_TIME"
        echo
        echo "🔗 Service URLs:"
        echo "  Job Description Generator: $FUNCTION_URL"
        echo "  Compliance Validator: $COMPLIANCE_URL"
        echo
        echo "💾 Firestore Collections:"
        echo "  - company_culture (default document)"
        echo "  - job_templates (software_engineer, marketing_manager, data_scientist)"
        echo "  - generated_jobs (populated during usage)"
        echo
        echo "🧪 Test Commands:"
        echo "  curl -X POST $FUNCTION_URL \\"
        echo "    -H 'Content-Type: application/json' \\"
        echo "    -d '{\"role_id\": \"software_engineer\", \"custom_requirements\": \"Cloud experience\"}'"
        echo
        echo "🔧 Management Console:"
        echo "  https://console.cloud.google.com/functions/list?project=$PROJECT_ID"
        echo
        echo "💰 Cost Monitoring:"
        echo "  https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
    else
        warning "Deployment environment file not found. Summary unavailable."
    fi
    
    echo
    success "Deployment completed successfully! 🎉"
    echo
    warning "Remember to run './destroy.sh' when you're done to avoid ongoing charges."
}

# Main deployment flow
main() {
    log "Starting GCP Job Description Generation deployment..."
    
    check_prerequisites
    setup_project
    enable_apis
    setup_firestore
    setup_firestore_data
    deploy_functions
    test_deployment
    show_summary
    
    success "All deployment steps completed successfully!"
}

# Error handling
trap 'error "Deployment failed at line $LINENO. Check the logs above for details."' ERR

# Run main function
main "$@"