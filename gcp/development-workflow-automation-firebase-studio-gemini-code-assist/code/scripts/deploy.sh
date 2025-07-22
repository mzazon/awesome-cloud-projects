#!/bin/bash

# Development Workflow Automation with Firebase Studio and Gemini Code Assist - Deployment Script
# This script deploys the complete infrastructure for AI-powered development workflow automation

set -e  # Exit on any error
set -u  # Exit on undefined variables

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOYMENT_LOG="${SCRIPT_DIR}/deploy.log"

# Default values
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AI-powered development workflow automation infrastructure.

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: ${DEFAULT_REGION})
    -z, --zone ZONE               Deployment zone (default: ${DEFAULT_ZONE})
    -f, --force                   Force deployment without confirmation
    -d, --dry-run                 Show what would be deployed without making changes
    -h, --help                    Show this help message

EXAMPLES:
    $0 --project-id my-ai-dev-project
    $0 -p my-project -r us-west1 -z us-west1-a
    $0 --project-id my-project --dry-run

EOF
}

# Parse command line arguments
FORCE=false
DRY_RUN=false
PROJECT_ID=""
REGION="${DEFAULT_REGION}"
ZONE="${DEFAULT_ZONE}"

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
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if firebase is installed
    if ! command -v firebase &> /dev/null; then
        log_error "Firebase CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check gcloud version
    GCLOUD_VERSION=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "gcloud version: ${GCLOUD_VERSION}"
    
    # Check firebase version
    FIREBASE_VERSION=$(firebase --version 2>/dev/null || echo "unknown")
    log_info "Firebase CLI version: ${FIREBASE_VERSION}"
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Validate project ID
    if [[ -z "${PROJECT_ID}" ]]; then
        log_error "Project ID is required. Use -p or --project-id option."
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_error "Project '${PROJECT_ID}' does not exist or you don't have access to it."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Use timestamp for uniqueness
    TIMESTAMP=$(date +%s)
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Export resource names
    export BUCKET_NAME="dev-artifacts-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="code-review-automation-${RANDOM_SUFFIX}"
    export TOPIC_NAME="code-events-${RANDOM_SUFFIX}"
    export TRIGGER_NAME="code-review-trigger-${RANDOM_SUFFIX}"
    
    log_info "Resource names generated:"
    log_info "  Storage Bucket: ${BUCKET_NAME}"
    log_info "  Cloud Function: ${FUNCTION_NAME}"
    log_info "  Pub/Sub Topic: ${TOPIC_NAME}"
    log_info "  Eventarc Trigger: ${TRIGGER_NAME}"
}

# Set up environment
setup_environment() {
    log_info "Setting up environment..."
    
    # Set project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_success "Environment configured for project: ${PROJECT_ID}"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudbuild.googleapis.com"
        "storage.googleapis.com"
        "cloudfunctions.googleapis.com"
        "eventarc.googleapis.com"
        "firebase.googleapis.com"
        "run.googleapis.com"
        "aiplatform.googleapis.com"
        "pubsub.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would enable APIs: ${apis[*]}"
        return 0
    fi
    
    for api in "${apis[@]}"; do
        log_info "Enabling API: ${api}"
        if gcloud services enable "${api}" --quiet; then
            log_success "Enabled API: ${api}"
        else
            log_error "Failed to enable API: ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Initialize Firebase project
initialize_firebase() {
    log_info "Initializing Firebase project..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would initialize Firebase project: ${PROJECT_ID}"
        return 0
    fi
    
    # Check if Firebase project already exists
    if firebase projects:list | grep -q "${PROJECT_ID}"; then
        log_info "Firebase project already exists"
        firebase use "${PROJECT_ID}"
    else
        log_info "Creating Firebase project..."
        if firebase projects:create "${PROJECT_ID}" --display-name "AI Dev Workflow"; then
            firebase use "${PROJECT_ID}"
            log_success "Firebase project created and selected"
        else
            log_warning "Firebase project creation failed, but continuing with existing project"
            firebase use "${PROJECT_ID}" || true
        fi
    fi
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for development artifacts..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would create bucket: gs://${BUCKET_NAME}"
        return 0
    fi
    
    # Create bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log_success "Created storage bucket: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create storage bucket"
        exit 1
    fi
    
    # Enable versioning
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        log_success "Enabled versioning on bucket"
    else
        log_warning "Failed to enable versioning"
    fi
    
    # Set bucket permissions
    local service_account="${PROJECT_ID}@appspot.gserviceaccount.com"
    if gsutil iam ch "serviceAccount:${service_account}:objectAdmin" "gs://${BUCKET_NAME}"; then
        log_success "Set bucket permissions for service account"
    else
        log_warning "Failed to set bucket permissions"
    fi
}

# Create Pub/Sub topic and subscription
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic and subscription..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would create Pub/Sub topic: ${TOPIC_NAME}"
        return 0
    fi
    
    # Create topic
    if gcloud pubsub topics create "${TOPIC_NAME}"; then
        log_success "Created Pub/Sub topic: ${TOPIC_NAME}"
    else
        log_error "Failed to create Pub/Sub topic"
        exit 1
    fi
    
    # Create subscription
    local subscription_name="${TOPIC_NAME}-sub"
    if gcloud pubsub subscriptions create "${subscription_name}" \
        --topic="${TOPIC_NAME}" \
        --ack-deadline=60; then
        log_success "Created Pub/Sub subscription: ${subscription_name}"
    else
        log_error "Failed to create Pub/Sub subscription"
        exit 1
    fi
}

# Deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying intelligent code review automation function..."
    
    local function_dir="${SCRIPT_DIR}/../functions/code-review"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would deploy Cloud Function: ${FUNCTION_NAME}"
        return 0
    fi
    
    # Create function directory if it doesn't exist
    mkdir -p "${function_dir}"
    
    # Create package.json
    cat > "${function_dir}/package.json" << 'EOF'
{
  "name": "code-review-automation",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/functions-framework": "^3.3.0",
    "@google-cloud/storage": "^7.7.0",
    "@google-cloud/pubsub": "^4.1.0",
    "@google-cloud/aiplatform": "^3.11.0"
  }
}
EOF
    
    # Create function code
    cat > "${function_dir}/index.js" << 'EOF'
const {Storage} = require('@google-cloud/storage');
const {PubSub} = require('@google-cloud/pubsub');
const functions = require('@google-cloud/functions-framework');

const storage = new Storage();
const pubsub = new PubSub();

functions.cloudEvent('codeReviewAutomation', async (cloudEvent) => {
  console.log('Code review automation triggered:', cloudEvent);
  
  const {bucket, name} = cloudEvent.data;
  
  try {
    // Download code artifact
    const file = storage.bucket(bucket).file(name);
    const [content] = await file.download();
    const codeContent = content.toString();
    
    // Perform AI-powered code review
    const reviewResults = await performIntelligentReview(codeContent);
    
    // Store review results
    const reviewFile = `reviews/${name.replace(/\.[^/.]+$/, '')}-review.json`;
    await storage.bucket(bucket).file(reviewFile).save(JSON.stringify(reviewResults, null, 2));
    
    // Publish review completion event
    const topic = pubsub.topic(process.env.TOPIC_NAME);
    await topic.publishMessage({
      json: {
        type: 'review_completed',
        artifact: name,
        reviewFile: reviewFile,
        status: reviewResults.approved ? 'approved' : 'needs_revision',
        timestamp: new Date().toISOString()
      }
    });
    
    console.log('Code review completed successfully');
  } catch (error) {
    console.error('Code review failed:', error);
    throw error;
  }
});

async function performIntelligentReview(code) {
  // Simulate AI-powered code review with multiple checks
  const checks = {
    syntax: checkSyntax(code),
    security: checkSecurity(code),
    performance: checkPerformance(code),
    bestPractices: checkBestPractices(code)
  };
  
  const score = Object.values(checks).reduce((sum, check) => sum + check.score, 0) / 4;
  
  return {
    approved: score >= 80,
    overallScore: score,
    checks: checks,
    suggestions: generateSuggestions(checks),
    reviewedAt: new Date().toISOString()
  };
}

function checkSyntax(code) {
  return { score: 95, issues: [], status: 'passed' };
}

function checkSecurity(code) {
  const securityIssues = [];
  if (code.includes('eval(') || code.includes('innerHTML')) {
    securityIssues.push('Potential XSS vulnerability detected');
  }
  return { 
    score: securityIssues.length === 0 ? 90 : 70, 
    issues: securityIssues, 
    status: securityIssues.length === 0 ? 'passed' : 'warning' 
  };
}

function checkPerformance(code) {
  return { score: 85, issues: [], status: 'passed' };
}

function checkBestPractices(code) {
  return { score: 88, issues: [], status: 'passed' };
}

function generateSuggestions(checks) {
  const suggestions = [];
  Object.entries(checks).forEach(([category, result]) => {
    if (result.score < 80) {
      suggestions.push(`Improve ${category}: ${result.issues.join(', ')}`);
    }
  });
  return suggestions;
}
EOF
    
    # Deploy the function
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime nodejs20 \
        --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
        --trigger-event-filters="bucket=${BUCKET_NAME}" \
        --source "${function_dir}" \
        --entry-point codeReviewAutomation \
        --memory 512MB \
        --timeout 300s \
        --set-env-vars="TOPIC_NAME=${TOPIC_NAME}" \
        --region="${REGION}"; then
        log_success "Deployed Cloud Function: ${FUNCTION_NAME}"
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
}

# Create Eventarc trigger
create_eventarc_trigger() {
    log_info "Creating Eventarc trigger for development workflow..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would create Eventarc trigger: ${TRIGGER_NAME}"
        return 0
    fi
    
    # Create Eventarc trigger
    if gcloud eventarc triggers create "${TRIGGER_NAME}" \
        --location="${REGION}" \
        --destination-cloud-function="${FUNCTION_NAME}" \
        --destination-cloud-function-service="${PROJECT_ID}" \
        --event-filters="type=google.cloud.storage.object.v1.finalized" \
        --event-filters="bucket=${BUCKET_NAME}" \
        --service-account="${PROJECT_ID}@appspot.gserviceaccount.com"; then
        log_success "Created Eventarc trigger: ${TRIGGER_NAME}"
    else
        log_error "Failed to create Eventarc trigger"
        exit 1
    fi
}

# Create Firebase Studio workspace
create_firebase_workspace() {
    log_info "Creating Firebase Studio development workspace..."
    
    local workspace_dir="${SCRIPT_DIR}/../workspace"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would create Firebase Studio workspace"
        return 0
    fi
    
    # Create workspace directory
    mkdir -p "${workspace_dir}/templates/fullstack-ai-app"
    
    # Create workspace configuration
    cat > "${workspace_dir}/dev.nix" << EOF
{ pkgs, ... }: {
  packages = [
    pkgs.nodejs_20
    pkgs.firebase-tools
    pkgs.google-cloud-sdk
  ];
  
  bootstrap = ''
    npm install -g @angular/cli
    npm install -g create-react-app
    npm install -g typescript
    echo "Firebase Studio workspace ready for AI-powered development"
  '';
  
  services.docker.enable = true;
  
  idx = {
    extensions = [
      "ms-vscode.vscode-typescript-next"
      "bradlc.vscode-tailwindcss"
      "ms-vscode.vscode-json"
    ];
    
    workspace = {
      onCreate = {
        install-deps = "npm install";
      };
      onStart = {
        setup-env = ''
          export GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
          export STORAGE_BUCKET=${BUCKET_NAME}
        '';
      };
    };
  };
}
EOF
    
    # Create template metadata
    cat > "${workspace_dir}/templates/fullstack-ai-app/template.json" << 'EOF'
{
  "name": "AI-Powered Full-Stack Application",
  "description": "Complete full-stack application with AI integration and automated workflows",
  "category": "ai-development",
  "technologies": ["React", "Node.js", "Firebase", "Gemini API"],
  "aiAssistance": {
    "enabled": true,
    "codeGeneration": true,
    "reviewAutomation": true
  }
}
EOF
    
    log_success "Created Firebase Studio workspace"
}

# Create monitoring dashboard
create_monitoring() {
    log_info "Setting up development workflow monitoring..."
    
    local monitoring_dir="${SCRIPT_DIR}/../monitoring"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "DRY RUN: Would create monitoring dashboard"
        return 0
    fi
    
    mkdir -p "${monitoring_dir}"
    
    # Create monitoring configuration
    cat > "${monitoring_dir}/workflow-metrics.json" << 'EOF'
{
  "displayName": "AI Development Workflow Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Code Generation Rate",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"cloud_function\""
                }
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "Review Automation Success Rate",
          "scorecard": {
            "timeSeriesQuery": {
              "timeSeriesFilter": {
                "filter": "resource.type=\"gcs_bucket\""
              }
            }
          }
        }
      }
    ]
  }
}
EOF
    
    log_success "Created monitoring configuration"
}

# Save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    local config_file="${SCRIPT_DIR}/deployment-config.env"
    
    cat > "${config_file}" << EOF
# Deployment Configuration
# Generated on: $(date)

PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
ZONE="${ZONE}"
BUCKET_NAME="${BUCKET_NAME}"
FUNCTION_NAME="${FUNCTION_NAME}"
TOPIC_NAME="${TOPIC_NAME}"
TRIGGER_NAME="${TRIGGER_NAME}"
TIMESTAMP="$(date +%s)"
EOF
    
    log_success "Deployment configuration saved to: ${config_file}"
}

# Verification function
verify_deployment() {
    log_info "Verifying deployment..."
    
    local errors=0
    
    # Check bucket exists
    if gsutil ls "gs://${BUCKET_NAME}" &> /dev/null; then
        log_success "Storage bucket verified: gs://${BUCKET_NAME}"
    else
        log_error "Storage bucket not found: gs://${BUCKET_NAME}"
        ((errors++))
    fi
    
    # Check function exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &> /dev/null; then
        log_success "Cloud Function verified: ${FUNCTION_NAME}"
    else
        log_error "Cloud Function not found: ${FUNCTION_NAME}"
        ((errors++))
    fi
    
    # Check topic exists
    if gcloud pubsub topics describe "${TOPIC_NAME}" &> /dev/null; then
        log_success "Pub/Sub topic verified: ${TOPIC_NAME}"
    else
        log_error "Pub/Sub topic not found: ${TOPIC_NAME}"
        ((errors++))
    fi
    
    # Check trigger exists
    if gcloud eventarc triggers describe "${TRIGGER_NAME}" --location="${REGION}" &> /dev/null; then
        log_success "Eventarc trigger verified: ${TRIGGER_NAME}"
    else
        log_error "Eventarc trigger not found: ${TRIGGER_NAME}"
        ((errors++))
    fi
    
    if [[ ${errors} -eq 0 ]]; then
        log_success "All resources verified successfully!"
        return 0
    else
        log_error "Verification failed with ${errors} errors"
        return 1
    fi
}

# Confirmation prompt
confirm_deployment() {
    if [[ "${FORCE}" == "true" ]]; then
        return 0
    fi
    
    echo
    log_info "Deployment Summary:"
    log_info "  Project ID: ${PROJECT_ID}"
    log_info "  Region: ${REGION}"
    log_info "  Zone: ${ZONE}"
    log_info "  Storage Bucket: ${BUCKET_NAME}"
    log_info "  Cloud Function: ${FUNCTION_NAME}"
    log_info "  Pub/Sub Topic: ${TOPIC_NAME}"
    log_info "  Eventarc Trigger: ${TRIGGER_NAME}"
    echo
    
    read -p "Do you want to proceed with deployment? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Main deployment function
main() {
    log_info "Starting AI Development Workflow Automation deployment..."
    echo "Deployment started at: $(date)" > "${DEPLOYMENT_LOG}"
    
    # Run all deployment steps
    check_prerequisites
    generate_resource_names
    confirm_deployment
    setup_environment
    enable_apis
    initialize_firebase
    create_storage_bucket
    create_pubsub_resources
    deploy_cloud_function
    create_eventarc_trigger
    create_firebase_workspace
    create_monitoring
    save_deployment_config
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        verify_deployment
    fi
    
    echo
    log_success "🎉 AI Development Workflow Automation deployment completed successfully!"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        echo
        log_info "Next steps:"
        log_info "1. Access Firebase Studio in the Firebase Console"
        log_info "2. Configure Gemini Code Assist in your workspace"
        log_info "3. Upload code artifacts to test the automation pipeline"
        log_info "4. Monitor workflows in Cloud Monitoring"
        echo
        log_info "Storage bucket: gs://${BUCKET_NAME}"
        log_info "Function name: ${FUNCTION_NAME}"
        log_info "Project console: https://console.cloud.google.com/home/dashboard?project=${PROJECT_ID}"
    fi
    
    echo "Deployment completed at: $(date)" >> "${DEPLOYMENT_LOG}"
}

# Execute main function
main "$@"