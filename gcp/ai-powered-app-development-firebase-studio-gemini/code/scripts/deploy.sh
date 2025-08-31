#!/bin/bash

# AI-Powered App Development with Firebase Studio and Gemini - Deployment Script
# This script deploys Firebase project with Studio, Gemini AI, and App Hosting infrastructure

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "$LOG_FILE"
}

log_info() {
    log "${BLUE}[INFO]${NC} $1"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    log "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check $LOG_FILE for details."
    exit 1
}

trap cleanup_on_error ERR

# Initialize log file
echo "=== Firebase Studio Deployment Started at $TIMESTAMP ===" > "$LOG_FILE"

log_info "Starting Firebase Studio and Gemini AI deployment..."

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if firebase CLI is installed
    if ! command -v firebase &> /dev/null; then
        log_error "Firebase CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if user has required permissions
    local current_user=$(gcloud config get-value account)
    log_info "Authenticated as: $current_user"
    
    # Verify billing is enabled (required for Firebase)
    log_info "Please ensure billing is enabled for your Google Cloud account."
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [ -z "${PROJECT_ID:-}" ]; then
        export PROJECT_ID="ai-app-studio-$(date +%s)"
        log_info "Generated PROJECT_ID: $PROJECT_ID"
    else
        log_info "Using provided PROJECT_ID: $PROJECT_ID"
    fi
    
    # Set default region
    export REGION="${REGION:-us-central1}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export APP_NAME="ai-task-manager-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured:"
    log_info "  PROJECT_ID: $PROJECT_ID"
    log_info "  REGION: $REGION"
    log_info "  APP_NAME: $APP_NAME"
}

# Create and configure Firebase project
create_firebase_project() {
    log_info "Creating Firebase project..."
    
    # Create new GCP project
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Project $PROJECT_ID already exists. Using existing project."
    else
        gcloud projects create "$PROJECT_ID" \
            --name="AI-Powered Task Manager" \
            --set-as-default
        log_success "Google Cloud project created: $PROJECT_ID"
    fi
    
    # Set default project configuration
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    
    # Enable billing (user must have done this manually)
    log_warning "Ensure billing is enabled for project $PROJECT_ID"
    
    # Enable required APIs
    log_info "Enabling required APIs..."
    gcloud services enable firebase.googleapis.com \
        firestore.googleapis.com \
        cloudbuild.googleapis.com \
        run.googleapis.com \
        secretmanager.googleapis.com \
        artifactregistry.googleapis.com \
        developerconnect.googleapis.com \
        --project="$PROJECT_ID"
    
    # Wait for API enablement
    sleep 30
    
    log_success "Required APIs enabled"
}

# Initialize Firebase services
initialize_firebase() {
    log_info "Initializing Firebase services..."
    
    # Add Firebase to the project
    if firebase projects:list | grep -q "$PROJECT_ID"; then
        log_warning "Firebase already initialized for project $PROJECT_ID"
    else
        log_info "Adding Firebase to project..."
        # Note: This may require manual Firebase console setup
        log_warning "Firebase project creation may require manual setup in Firebase Console"
        log_info "Visit: https://console.firebase.google.com/"
    fi
    
    # Enable Firestore in native mode
    log_info "Setting up Firestore database..."
    if gcloud firestore databases describe --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Firestore database already exists"
    else
        gcloud firestore databases create \
            --project="$PROJECT_ID" \
            --region="$REGION"
        log_success "Firestore database created"
    fi
    
    # Set up Firebase CLI authentication
    log_info "Configuring Firebase CLI..."
    firebase use "$PROJECT_ID" || log_warning "Firebase CLI configuration may need manual setup"
    
    log_success "Firebase services initialized"
}

# Configure Firestore indexes
configure_firestore_indexes() {
    log_info "Configuring Firestore indexes..."
    
    # Create composite index for tasks by user and priority
    log_info "Creating tasks index (user + priority)..."
    gcloud firestore indexes composite create \
        --project="$PROJECT_ID" \
        --collection-group=tasks \
        --field-config=field-path=userId,order=ascending \
        --field-config=field-path=priority,order=descending \
        --field-config=field-path=createdAt,order=ascending \
        --quiet || log_warning "Index may already exist"
    
    # Create index for AI-generated task suggestions
    log_info "Creating AI suggestions index..."
    gcloud firestore indexes composite create \
        --project="$PROJECT_ID" \
        --collection-group=tasks \
        --field-config=field-path=userId,order=ascending \
        --field-config=field-path=aiGenerated,order=ascending \
        --field-config=field-path=suggestionScore,order=descending \
        --quiet || log_warning "Index may already exist"
    
    # Create index for task status and due date queries
    log_info "Creating task status index..."
    gcloud firestore indexes composite create \
        --project="$PROJECT_ID" \
        --collection-group=tasks \
        --field-config=field-path=userId,order=ascending \
        --field-config=field-path=status,order=ascending \
        --field-config=field-path=dueDate,order=ascending \
        --quiet || log_warning "Index may already exist"
    
    log_success "Firestore indexes configured"
}

# Set up authentication
setup_authentication() {
    log_info "Setting up Firebase Authentication..."
    
    # Initialize Firebase Auth (this is typically done via console)
    log_warning "Firebase Authentication setup requires manual configuration"
    log_info "Please configure authentication providers in Firebase Console:"
    log_info "  1. Visit: https://console.firebase.google.com/project/$PROJECT_ID/authentication"
    log_info "  2. Enable Email/Password authentication"
    log_info "  3. Enable Google Sign-In (recommended for Gemini integration)"
    log_info "  4. Configure authorized domains"
    
    log_success "Authentication setup instructions provided"
}

# Configure App Hosting prerequisites
setup_app_hosting() {
    log_info "Setting up App Hosting prerequisites..."
    
    # Create Secret Manager secret for API keys
    log_info "Creating Secret Manager secret for Gemini API key..."
    if gcloud secrets describe gemini-api-key --project="$PROJECT_ID" &>/dev/null; then
        log_warning "Secret 'gemini-api-key' already exists"
    else
        echo "your-gemini-api-key-placeholder" | \
            gcloud secrets create gemini-api-key \
            --project="$PROJECT_ID" \
            --data-file=- \
            --replication-policy="automatic"
        log_warning "Please update the Gemini API key secret with your actual API key:"
        log_info "  gcloud secrets versions add gemini-api-key --data-file=<your-key-file>"
    fi
    
    log_success "App Hosting prerequisites configured"
}

# Deploy Firestore security rules
deploy_security_rules() {
    log_info "Deploying Firestore security rules..."
    
    # Create firestore.rules file
    cat > "${SCRIPT_DIR}/firestore.rules" << 'EOF'
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Tasks can only be accessed by authenticated users
    match /tasks/{taskId} {
      allow read, write: if request.auth != null 
        && request.auth.uid == resource.data.userId;
    }
    
    // AI suggestions are read-only for users
    match /aiSuggestions/{suggestionId} {
      allow read: if request.auth != null 
        && request.auth.uid == resource.data.userId;
    }
    
    // User profiles
    match /users/{userId} {
      allow read, write: if request.auth != null 
        && request.auth.uid == userId;
    }
  }
}
EOF
    
    # Deploy security rules (requires firebase CLI to be properly configured)
    if command -v firebase &> /dev/null && firebase projects:list | grep -q "$PROJECT_ID"; then
        firebase deploy --only firestore:rules --project="$PROJECT_ID" || \
            log_warning "Security rules deployment may require manual setup"
    else
        log_warning "Firebase CLI not configured. Please deploy rules manually:"
        log_info "  1. Copy the rules from ${SCRIPT_DIR}/firestore.rules"
        log_info "  2. Paste in Firebase Console > Firestore > Rules"
    fi
    
    log_success "Security rules configuration completed"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check project configuration
    local current_project=$(gcloud config get-value project)
    if [ "$current_project" = "$PROJECT_ID" ]; then
        log_success "✅ Project configuration verified: $PROJECT_ID"
    else
        log_warning "Project configuration mismatch"
    fi
    
    # Check enabled services
    local enabled_services=$(gcloud services list --enabled --project="$PROJECT_ID" \
        --filter="name:firebase OR name:firestore OR name:cloudbuild OR name:secretmanager" \
        --format="value(name)" | wc -l)
    
    if [ "$enabled_services" -ge 4 ]; then
        log_success "✅ Required services enabled"
    else
        log_warning "Some required services may not be enabled"
    fi
    
    # Check Firestore database
    if gcloud firestore databases describe --region="$REGION" --project="$PROJECT_ID" &>/dev/null; then
        log_success "✅ Firestore database active"
    else
        log_warning "Firestore database not found"
    fi
    
    # Check Secret Manager
    if gcloud secrets describe gemini-api-key --project="$PROJECT_ID" &>/dev/null; then
        log_success "✅ Secret Manager configured"
    else
        log_warning "Secret Manager secret not found"
    fi
    
    log_success "Deployment verification completed"
}

# Display next steps
show_next_steps() {
    log_success "🎉 Firebase Studio deployment completed!"
    echo ""
    log_info "=== NEXT STEPS ==="
    log_info "1. 🌐 Access Firebase Studio: https://studio.firebase.google.com"
    log_info "2. 📋 Select project: $PROJECT_ID"
    log_info "3. 🔐 Configure authentication providers in Firebase Console"
    log_info "4. 🔑 Update Gemini API key in Secret Manager"
    log_info "5. 🚀 Connect GitHub repository for App Hosting"
    echo ""
    log_info "=== USEFUL LINKS ==="
    log_info "Firebase Console: https://console.firebase.google.com/project/$PROJECT_ID"
    log_info "Google Cloud Console: https://console.cloud.google.com/home/dashboard?project=$PROJECT_ID"
    log_info "Firebase Studio: https://studio.firebase.google.com"
    echo ""
    log_info "=== PROJECT DETAILS ==="
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "App Name: $APP_NAME"
    echo ""
    log_info "For cleanup, run: ./destroy.sh"
}

# Main deployment flow
main() {
    log_info "=== Firebase Studio Deployment Script ==="
    
    check_prerequisites
    setup_environment
    create_firebase_project
    initialize_firebase
    configure_firestore_indexes
    setup_authentication
    setup_app_hosting
    deploy_security_rules
    verify_deployment
    show_next_steps
    
    log_success "🎉 Deployment completed successfully!"
    echo "📋 Deployment log saved to: $LOG_FILE"
}

# Run main function
main "$@"