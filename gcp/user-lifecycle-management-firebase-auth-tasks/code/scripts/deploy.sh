#!/bin/bash

# User Lifecycle Management with Firebase Authentication and Cloud Tasks - Deployment Script
# This script deploys the complete user lifecycle management infrastructure on Google Cloud Platform

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Color codes for output formatting
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

# Error handling function
handle_error() {
    log_error "Deployment failed at line $1. Exiting..."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Banner
echo -e "${BLUE}"
echo "=================================================="
echo "  User Lifecycle Management Deployment"
echo "  Firebase Auth + Cloud Tasks + Cloud SQL"
echo "=================================================="
echo -e "${NC}"

# Default configuration
DEFAULT_PROJECT_PREFIX="user-lifecycle"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Check if running in non-interactive mode
if [[ "${1:-}" == "--non-interactive" ]]; then
    NON_INTERACTIVE=true
    shift
else
    NON_INTERACTIVE=false
fi

# Parse command line arguments
DRY_RUN=false
SKIP_FIREBASE=false
FORCE_DEPLOY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-firebase)
            SKIP_FIREBASE=true
            shift
            ;;
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        --project-id)
            PROJECT_ID="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run              Show what would be deployed without making changes"
            echo "  --skip-firebase        Skip Firebase initialization (if already configured)"
            echo "  --force                Force deployment even if resources exist"
            echo "  --project-id PROJECT   Use specific project ID"
            echo "  --region REGION        Use specific region (default: us-central1)"
            echo "  --non-interactive      Run without prompts"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if firebase CLI is installed
    if ! command -v firebase &> /dev/null; then
        log_warning "Firebase CLI is not installed. Installing via npm..."
        if command -v npm &> /dev/null; then
            npm install -g firebase-tools
        else
            log_error "npm is not available. Please install Node.js and npm first."
            exit 1
        fi
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed."
        exit 1
    fi
    
    # Check if authenticated with gcloud
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Get user input for configuration
get_user_input() {
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        # Use defaults in non-interactive mode
        PROJECT_ID="${PROJECT_ID:-${DEFAULT_PROJECT_PREFIX}-$(date +%s)}"
        REGION="${REGION:-$DEFAULT_REGION}"
        ZONE="${REGION%-*}-a"
        return
    fi
    
    echo ""
    log_info "Configuration Setup"
    echo "==================="
    
    # Get project ID
    if [[ -z "${PROJECT_ID:-}" ]]; then
        read -p "Enter project ID (or press Enter for auto-generated): " PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            PROJECT_ID="${DEFAULT_PROJECT_PREFIX}-$(date +%s)"
        fi
    fi
    
    # Get region
    if [[ -z "${REGION:-}" ]]; then
        read -p "Enter region [${DEFAULT_REGION}]: " REGION
        REGION="${REGION:-$DEFAULT_REGION}"
    fi
    
    # Set zone based on region
    ZONE="${REGION%-*}-a"
    
    echo ""
    log_info "Configuration Summary:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Zone: $ZONE"
    echo ""
    
    if [[ "$FORCE_DEPLOY" != "true" ]]; then
        read -p "Continue with deployment? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Set environment variables
set_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DB_INSTANCE_NAME="user-analytics-${RANDOM_SUFFIX}"
    export TASK_QUEUE_NAME="user-lifecycle-queue"
    export WORKER_SERVICE_NAME="lifecycle-worker"
    
    # Set gcloud configuration
    gcloud config set project "$PROJECT_ID" --quiet
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log_success "Environment configured"
    echo "  DB Instance: $DB_INSTANCE_NAME"
    echo "  Task Queue: $TASK_QUEUE_NAME"
    echo "  Worker Service: $WORKER_SERVICE_NAME"
}

# Create or verify project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create/verify project: $PROJECT_ID"
        return
    fi
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_success "Project $PROJECT_ID already exists"
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --quiet
        log_success "Project created successfully"
    fi
    
    # Link billing account (prompt user to do this manually if needed)
    if ! gcloud billing projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Billing is not enabled for this project."
        log_warning "Please enable billing in the Google Cloud Console:"
        log_warning "https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
        
        if [[ "$NON_INTERACTIVE" != "true" ]]; then
            read -p "Press Enter after enabling billing to continue..."
        fi
    fi
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "firebase.googleapis.com"
        "sqladmin.googleapis.com"
        "cloudtasks.googleapis.com"
        "cloudscheduler.googleapis.com"
        "run.googleapis.com"
        "cloudbuild.googleapis.com"
        "firestore.googleapis.com"
        "cloudfunctions.googleapis.com"
        "appengine.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable APIs: ${apis[*]}"
        return
    fi
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        gcloud services enable "$api" --quiet
    done
    
    log_success "All required APIs enabled"
}

# Initialize Firebase
setup_firebase() {
    if [[ "$SKIP_FIREBASE" == "true" ]]; then
        log_info "Skipping Firebase initialization"
        return
    fi
    
    log_info "Setting up Firebase..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would initialize Firebase for project: $PROJECT_ID"
        return
    fi
    
    # Add Firebase to project
    firebase projects:addfirebase "$PROJECT_ID" --quiet || log_warning "Firebase may already be configured"
    
    # Create Firestore database
    log_info "Creating Firestore database..."
    gcloud alpha firestore databases create \
        --location="$REGION" \
        --type=firestore-native \
        --quiet || log_warning "Firestore database may already exist"
    
    log_success "Firebase configuration completed"
}

# Create Cloud SQL instance
setup_cloud_sql() {
    log_info "Setting up Cloud SQL PostgreSQL instance..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Cloud SQL instance: $DB_INSTANCE_NAME"
        return
    fi
    
    # Check if instance already exists
    if gcloud sql instances describe "$DB_INSTANCE_NAME" &>/dev/null; then
        log_warning "Cloud SQL instance $DB_INSTANCE_NAME already exists"
        return
    fi
    
    # Create Cloud SQL instance
    log_info "Creating Cloud SQL PostgreSQL instance (this may take several minutes)..."
    gcloud sql instances create "$DB_INSTANCE_NAME" \
        --database-version=POSTGRES_15 \
        --tier=db-f1-micro \
        --region="$REGION" \
        --storage-type=SSD \
        --storage-size=10GB \
        --backup-start-time=03:00 \
        --quiet
    
    # Generate and set password
    export DB_PASSWORD=$(openssl rand -base64 32)
    gcloud sql users set-password postgres \
        --instance="$DB_INSTANCE_NAME" \
        --password="$DB_PASSWORD" \
        --quiet
    
    # Create application database
    gcloud sql databases create user_analytics \
        --instance="$DB_INSTANCE_NAME" \
        --quiet
    
    log_success "Cloud SQL instance created successfully"
    echo "  Instance: $DB_INSTANCE_NAME"
    echo "  Database: user_analytics"
    echo "  Password: [Generated securely]"
}

# Create database schema
setup_database_schema() {
    log_info "Setting up database schema..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create database schema"
        return
    fi
    
    # Create schema SQL file
    cat > /tmp/schema.sql << 'EOF'
-- User engagement tracking table
CREATE TABLE IF NOT EXISTS user_engagement (
    id SERIAL PRIMARY KEY,
    firebase_uid VARCHAR(128) NOT NULL UNIQUE,
    email VARCHAR(255),
    last_login TIMESTAMP WITH TIME ZONE,
    session_count INTEGER DEFAULT 0,
    total_session_duration INTEGER DEFAULT 0,
    last_activity TIMESTAMP WITH TIME ZONE,
    engagement_score DECIMAL(5,2) DEFAULT 0.00,
    lifecycle_stage VARCHAR(50) DEFAULT 'new',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- User activity events table
CREATE TABLE IF NOT EXISTS user_activities (
    id SERIAL PRIMARY KEY,
    firebase_uid VARCHAR(128) NOT NULL,
    activity_type VARCHAR(100) NOT NULL,
    activity_data JSONB,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Lifecycle automation log table
CREATE TABLE IF NOT EXISTS lifecycle_actions (
    id SERIAL PRIMARY KEY,
    firebase_uid VARCHAR(128) NOT NULL,
    action_type VARCHAR(100) NOT NULL,
    action_status VARCHAR(50) DEFAULT 'pending',
    scheduled_at TIMESTAMP WITH TIME ZONE,
    executed_at TIMESTAMP WITH TIME ZONE,
    result_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_user_engagement_uid ON user_engagement(firebase_uid);
CREATE INDEX IF NOT EXISTS idx_user_engagement_last_login ON user_engagement(last_login);
CREATE INDEX IF NOT EXISTS idx_user_engagement_lifecycle ON user_engagement(lifecycle_stage);
CREATE INDEX IF NOT EXISTS idx_user_activities_uid_timestamp ON user_activities(firebase_uid, timestamp);
CREATE INDEX IF NOT EXISTS idx_lifecycle_actions_uid_status ON lifecycle_actions(firebase_uid, action_status);
EOF
    
    # Execute schema creation
    log_info "Creating database schema..."
    gcloud sql connect "$DB_INSTANCE_NAME" --user=postgres --quiet < /tmp/schema.sql
    
    # Clean up temporary file
    rm -f /tmp/schema.sql
    
    log_success "Database schema created successfully"
}

# Create App Engine application (required for Cloud Tasks)
setup_app_engine() {
    log_info "Setting up App Engine application..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create App Engine application"
        return
    fi
    
    # Check if App Engine app already exists
    if gcloud app describe &>/dev/null; then
        log_warning "App Engine application already exists"
        return
    fi
    
    # Create App Engine application
    gcloud app create --region="$REGION" --quiet
    
    log_success "App Engine application created"
}

# Create Cloud Tasks queue
setup_cloud_tasks() {
    log_info "Setting up Cloud Tasks queue..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Cloud Tasks queue: $TASK_QUEUE_NAME"
        return
    fi
    
    # Check if queue already exists
    if gcloud tasks queues describe "$TASK_QUEUE_NAME" --location="$REGION" &>/dev/null; then
        log_warning "Cloud Tasks queue $TASK_QUEUE_NAME already exists"
        return
    fi
    
    # Create Cloud Tasks queue
    gcloud tasks queues create "$TASK_QUEUE_NAME" \
        --location="$REGION" \
        --max-concurrent-dispatches=10 \
        --max-dispatches-per-second=5 \
        --max-retry-duration=3600s \
        --quiet
    
    # Configure retry settings
    gcloud tasks queues update "$TASK_QUEUE_NAME" \
        --location="$REGION" \
        --min-backoff=5s \
        --max-backoff=300s \
        --max-attempts=5 \
        --quiet
    
    log_success "Cloud Tasks queue created and configured"
}

# Deploy Cloud Run worker service
deploy_worker_service() {
    log_info "Deploying Cloud Run worker service..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Cloud Run service: $WORKER_SERVICE_NAME"
        return
    fi
    
    # Get Cloud SQL connection name
    local connection_name
    connection_name=$(gcloud sql instances describe "$DB_INSTANCE_NAME" \
        --format="value(connectionName)")
    
    # Change to worker application directory
    local worker_dir="../terraform/worker-app"
    if [[ ! -d "$worker_dir" ]]; then
        worker_dir="./terraform/worker-app"
    fi
    
    if [[ ! -d "$worker_dir" ]]; then
        log_error "Worker application directory not found"
        exit 1
    fi
    
    pushd "$worker_dir" > /dev/null
    
    # Deploy to Cloud Run
    log_info "Building and deploying worker service (this may take several minutes)..."
    gcloud run deploy "$WORKER_SERVICE_NAME" \
        --source . \
        --platform managed \
        --region "$REGION" \
        --allow-unauthenticated \
        --set-env-vars="PROJECT_ID=$PROJECT_ID,REGION=$REGION,TASK_QUEUE_NAME=$TASK_QUEUE_NAME,CONNECTION_NAME=$connection_name,DB_PASSWORD=$DB_PASSWORD" \
        --cpu=1 \
        --memory=512Mi \
        --timeout=300s \
        --quiet
    
    popd > /dev/null
    
    log_success "Cloud Run worker service deployed successfully"
}

# Set up Cloud Scheduler jobs
setup_cloud_scheduler() {
    log_info "Setting up Cloud Scheduler jobs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create scheduled jobs"
        return
    fi
    
    # Get worker service URL
    local worker_url
    worker_url=$(gcloud run services describe "$WORKER_SERVICE_NAME" \
        --region="$REGION" \
        --format="value(status.url)")
    
    local jobs=(
        "daily-engagement-analysis|0 2 * * *|process-engagement|daily_analysis"
        "weekly-retention-check|0 10 * * 1|retention-campaign|weekly_retention"
        "monthly-lifecycle-review|0 8 1 * *|retention-campaign|lifecycle_review"
    )
    
    for job_config in "${jobs[@]}"; do
        IFS='|' read -r job_name schedule endpoint task_type <<< "$job_config"
        
        # Check if job already exists
        if gcloud scheduler jobs describe "$job_name" --location="$REGION" &>/dev/null; then
            log_warning "Scheduler job $job_name already exists, updating..."
            gcloud scheduler jobs delete "$job_name" --location="$REGION" --quiet
        fi
        
        # Create scheduler job
        gcloud scheduler jobs create http "$job_name" \
            --location="$REGION" \
            --schedule="$schedule" \
            --time-zone="UTC" \
            --uri="$worker_url/tasks/$endpoint" \
            --http-method=POST \
            --headers="Content-Type=application/json" \
            --message-body="{\"task_type\":\"$task_type\"}" \
            --attempt-deadline=300s \
            --quiet
        
        log_success "Created scheduler job: $job_name"
    done
}

# Deploy Firebase Functions
deploy_firebase_functions() {
    log_info "Deploying Firebase Functions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy Firebase Functions"
        return
    fi
    
    # Create temporary functions directory
    local functions_dir="/tmp/firebase-functions-$$"
    mkdir -p "$functions_dir/functions"
    
    # Create package.json
    cat > "$functions_dir/functions/package.json" << 'EOF'
{
  "name": "user-lifecycle-functions",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "firebase-functions": "^4.0.0",
    "firebase-admin": "^12.0.0",
    "@google-cloud/tasks": "^3.0.0"
  }
}
EOF
    
    # Create Firebase configuration
    cat > "$functions_dir/firebase.json" << EOF
{
  "functions": {
    "source": "functions",
    "runtime": "nodejs18"
  }
}
EOF
    
    # Create Functions code
    cat > "$functions_dir/functions/index.js" << 'EOF'
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { CloudTasksClient } = require('@google-cloud/tasks');

admin.initializeApp();
const tasksClient = new CloudTasksClient();

// Process new user registration
exports.onUserCreate = functions.auth.user().onCreate(async (user) => {
  await scheduleEngagementTask(user.uid, 'user_registration', {
    email: user.email,
    provider: user.providerData[0]?.providerId || 'email',
    created_at: user.metadata.creationTime
  });
});

// Process user sign-in events  
exports.onUserSignIn = functions.auth.user().onSignIn(async (user) => {
  await scheduleEngagementTask(user.uid, 'user_signin', {
    last_sign_in: user.metadata.lastSignInTime,
    provider: user.providerData[0]?.providerId || 'email'
  });
});

// Process user deletion
exports.onUserDelete = functions.auth.user().onDelete(async (user) => {
  await scheduleEngagementTask(user.uid, 'user_deletion', {
    deleted_at: new Date().toISOString()
  });
});

async function scheduleEngagementTask(firebase_uid, activity_type, activity_data) {
  const parent = `projects/${process.env.GCLOUD_PROJECT}/locations/us-central1/queues/user-lifecycle-queue`;
  
  const task = {
    httpRequest: {
      httpMethod: 'POST',
      url: `https://lifecycle-worker-${process.env.GCLOUD_PROJECT}.a.run.app/tasks/process-engagement`,
      body: Buffer.from(JSON.stringify({
        firebase_uid,
        activity_type, 
        activity_data
      })).toString('base64'),
      headers: { 'Content-Type': 'application/json' },
    },
  };
  
  await tasksClient.createTask({ parent, task });
}
EOF
    
    # Deploy functions
    pushd "$functions_dir" > /dev/null
    
    # Authenticate Firebase CLI
    firebase use "$PROJECT_ID" --token "$FIREBASE_TOKEN" 2>/dev/null || firebase use "$PROJECT_ID"
    
    # Deploy functions
    firebase deploy --only functions --project="$PROJECT_ID" --force
    
    popd > /dev/null
    
    # Clean up temporary directory
    rm -rf "$functions_dir"
    
    log_success "Firebase Functions deployed successfully"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify deployment"
        return
    fi
    
    local errors=0
    
    # Check Cloud SQL instance
    if gcloud sql instances describe "$DB_INSTANCE_NAME" --format="value(state)" | grep -q "RUNNABLE"; then
        log_success "✅ Cloud SQL instance is running"
    else
        log_error "❌ Cloud SQL instance is not running"
        ((errors++))
    fi
    
    # Check Cloud Tasks queue
    if gcloud tasks queues describe "$TASK_QUEUE_NAME" --location="$REGION" --format="value(state)" | grep -q "RUNNING"; then
        log_success "✅ Cloud Tasks queue is running"
    else
        log_error "❌ Cloud Tasks queue is not running"
        ((errors++))
    fi
    
    # Check Cloud Run service
    local worker_url
    worker_url=$(gcloud run services describe "$WORKER_SERVICE_NAME" \
        --region="$REGION" \
        --format="value(status.url)" 2>/dev/null || echo "")
    
    if [[ -n "$worker_url" ]]; then
        if curl -s "$worker_url/health" | grep -q "healthy"; then
            log_success "✅ Cloud Run worker service is healthy"
        else
            log_warning "⚠️ Cloud Run service exists but health check failed"
        fi
    else
        log_error "❌ Cloud Run worker service not found"
        ((errors++))
    fi
    
    # Check scheduler jobs
    local job_count
    job_count=$(gcloud scheduler jobs list --location="$REGION" --filter="name:daily-engagement-analysis OR name:weekly-retention-check OR name:monthly-lifecycle-review" --format="value(name)" | wc -l)
    
    if [[ "$job_count" -eq 3 ]]; then
        log_success "✅ All scheduler jobs created"
    else
        log_warning "⚠️ Expected 3 scheduler jobs, found $job_count"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Deployment verification completed successfully"
    else
        log_warning "Deployment verification completed with $errors errors"
    fi
}

# Display deployment summary
show_deployment_summary() {
    echo ""
    echo -e "${GREEN}=================================================="
    echo "           DEPLOYMENT COMPLETED"
    echo "==================================================${NC}"
    echo ""
    echo "Project Information:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo ""
    echo "Resources Created:"
    echo "  🗄️  Cloud SQL Instance: $DB_INSTANCE_NAME"
    echo "  📋 Cloud Tasks Queue: $TASK_QUEUE_NAME"
    echo "  🏃 Cloud Run Service: $WORKER_SERVICE_NAME"
    echo "  ⏰ Scheduler Jobs: 3 jobs created"
    echo "  🔥 Firebase Functions: Auth triggers deployed"
    echo ""
    echo "Next Steps:"
    echo "  1. Configure Firebase Authentication in the console:"
    echo "     https://console.firebase.google.com/project/$PROJECT_ID/authentication"
    echo ""
    echo "  2. Test the worker service health endpoint:"
    local worker_url
    worker_url=$(gcloud run services describe "$WORKER_SERVICE_NAME" \
        --region="$REGION" \
        --format="value(status.url)" 2>/dev/null || echo "Not available")
    echo "     curl $worker_url/health"
    echo ""
    echo "  3. Monitor logs:"
    echo "     gcloud logs read \"resource.type=cloud_run_revision\" --project=$PROJECT_ID"
    echo ""
    echo "  4. View Cloud SQL connection info:"
    echo "     gcloud sql instances describe $DB_INSTANCE_NAME"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo ""
}

# Main deployment workflow
main() {
    # Parse arguments and check prerequisites
    check_prerequisites
    get_user_input
    set_environment
    
    # Deploy infrastructure
    setup_project
    enable_apis
    setup_firebase
    setup_cloud_sql
    setup_database_schema
    setup_app_engine
    setup_cloud_tasks
    deploy_worker_service
    setup_cloud_scheduler
    
    # Deploy application code
    if [[ "$SKIP_FIREBASE" != "true" ]]; then
        deploy_firebase_functions
    fi
    
    # Verify and summarize
    verify_deployment
    show_deployment_summary
    
    log_success "User lifecycle management system deployed successfully!"
}

# Run main function with all arguments
main "$@"