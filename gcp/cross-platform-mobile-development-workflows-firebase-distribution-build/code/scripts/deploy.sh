#!/bin/bash

# Cross-Platform Mobile Development Workflows Deployment Script
# This script deploys Firebase App Distribution, Cloud Build, Firebase Test Lab, 
# and Cloud Source Repositories for automated mobile CI/CD workflows

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Script variables
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
readonly DEPLOYMENT_LOG="${PROJECT_DIR}/deployment.log"

# Configuration variables
PROJECT_ID=""
REGION="us-central1"
FIREBASE_PROJECT_ID=""
APP_NAME=""
REPO_NAME=""
ANDROID_APP_ID=""
DRY_RUN=false
SKIP_FIREBASE_INIT=false

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed. Check ${DEPLOYMENT_LOG} for details"
        log_info "Run './destroy.sh' to clean up any partially created resources"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Usage function
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy Cross-Platform Mobile Development Workflows with Firebase and Cloud Build

OPTIONS:
    -p, --project-id ID         Google Cloud Project ID (required)
    -r, --region REGION         GCP region (default: us-central1)
    -a, --app-name NAME         Mobile app name (default: auto-generated)
    -n, --repo-name NAME        Source repository name (default: auto-generated)
    -d, --dry-run              Show what would be deployed without making changes
    -s, --skip-firebase-init   Skip Firebase project initialization
    -h, --help                 Show this help message

EXAMPLES:
    $SCRIPT_NAME --project-id my-mobile-project
    $SCRIPT_NAME --project-id my-project --region us-west1 --app-name my-app
    $SCRIPT_NAME --dry-run --project-id my-project

PREREQUISITES:
    - gcloud CLI installed and authenticated
    - firebase CLI installed and authenticated
    - Project billing enabled
    - Required APIs: Cloud Build, Source Repositories, Firebase, Testing, Artifact Registry

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
            -a|--app-name)
                APP_NAME="$2"
                shift 2
                ;;
            -n|--repo-name)
                REPO_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-firebase-init)
                SKIP_FIREBASE_INIT=true
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

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id flag."
        usage
        exit 1
    fi

    # Set defaults for optional parameters
    if [[ -z "$APP_NAME" ]]; then
        local random_suffix
        random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 7)")
        APP_NAME="mobile-app-${random_suffix}"
    fi

    if [[ -z "$REPO_NAME" ]]; then
        local random_suffix
        random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 7)")
        REPO_NAME="mobile-source-${random_suffix}"
    fi

    FIREBASE_PROJECT_ID="$PROJECT_ID"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running in dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual resources will be created"
        return 0
    fi

    # Check gcloud CLI
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed or not in PATH"
        exit 1
    fi

    # Check firebase CLI
    if ! command -v firebase &> /dev/null; then
        log_error "firebase CLI is not installed or not in PATH"
        exit 1
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login'"
        exit 1
    fi

    # Check project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible"
        exit 1
    fi

    # Check billing is enabled
    local billing_enabled
    billing_enabled=$(gcloud billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" 2>/dev/null || echo "false")
    if [[ "$billing_enabled" != "True" ]]; then
        log_warning "Billing may not be enabled for project '$PROJECT_ID'. Some services may not work."
    fi

    log_success "Prerequisites check completed"
}

# Execute command with logging
execute_command() {
    local cmd="$1"
    local description="$2"
    
    log_info "$description"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: $cmd"
        return 0
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - $description: $cmd" >> "$DEPLOYMENT_LOG"
    
    if ! eval "$cmd" >> "$DEPLOYMENT_LOG" 2>&1; then
        log_error "Failed: $description"
        echo "Command: $cmd" >> "$DEPLOYMENT_LOG"
        return 1
    fi
    
    log_success "$description"
    return 0
}

# Set up project configuration
setup_project_config() {
    log_info "Setting up project configuration..."

    execute_command "gcloud config set project '$PROJECT_ID'" \
        "Setting default project"

    execute_command "gcloud config set compute/region '$REGION'" \
        "Setting default region"

    log_success "Project configuration completed"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."

    local apis=(
        "cloudbuild.googleapis.com"
        "sourcerepo.googleapis.com"
        "firebase.googleapis.com"
        "testing.googleapis.com"
        "artifactregistry.googleapis.com"
    )

    for api in "${apis[@]}"; do
        execute_command "gcloud services enable '$api' --project='$PROJECT_ID'" \
            "Enabling $api"
    done

    # Wait for APIs to be fully enabled
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 10
    fi

    log_success "All required APIs enabled"
}

# Initialize Firebase project
initialize_firebase() {
    if [[ "$SKIP_FIREBASE_INIT" == "true" ]]; then
        log_info "Skipping Firebase project initialization"
        return 0
    fi

    log_info "Initializing Firebase project..."

    # Check if Firebase project already exists
    if [[ "$DRY_RUN" != "true" ]]; then
        if firebase projects:list --format=json | jq -r '.[] | select(.projectId=="'"$FIREBASE_PROJECT_ID"'") | .projectId' | grep -q "$FIREBASE_PROJECT_ID"; then
            log_info "Firebase project '$FIREBASE_PROJECT_ID' already exists"
        else
            execute_command "firebase projects:create '$FIREBASE_PROJECT_ID' --display-name 'Mobile CI/CD Pipeline'" \
                "Creating Firebase project"
        fi
    else
        log_info "DRY RUN: Would create Firebase project '$FIREBASE_PROJECT_ID'"
    fi

    # Set Firebase project context
    execute_command "firebase use '$FIREBASE_PROJECT_ID'" \
        "Setting Firebase project context"

    log_success "Firebase project initialization completed"
}

# Create source repository
create_source_repository() {
    log_info "Creating Cloud Source Repository..."

    execute_command "gcloud source repos create '$REPO_NAME' --project='$PROJECT_ID'" \
        "Creating source repository '$REPO_NAME'"

    log_success "Source repository created: $REPO_NAME"
}

# Configure Firebase App Distribution
configure_app_distribution() {
    log_info "Configuring Firebase App Distribution..."

    # Create Android app
    execute_command "gcloud firebase apps create android --display-name='$APP_NAME Android' --package-name='com.example.$(echo "$APP_NAME" | tr '-' '')' --project='$PROJECT_ID'" \
        "Creating Android app in Firebase"

    # Get Android app ID
    if [[ "$DRY_RUN" != "true" ]]; then
        local android_app_id
        android_app_id=$(gcloud firebase apps list --filter="displayName:'$APP_NAME Android'" --format="value(appId)" --project="$PROJECT_ID" | head -n1)
        if [[ -n "$android_app_id" ]]; then
            ANDROID_APP_ID="$android_app_id"
            echo "ANDROID_APP_ID=$ANDROID_APP_ID" >> "$PROJECT_DIR/.env"
            log_success "Android App ID: $ANDROID_APP_ID"
        else
            log_error "Failed to retrieve Android App ID"
            return 1
        fi
    else
        log_info "DRY RUN: Would retrieve Android App ID"
        ANDROID_APP_ID="dummy-app-id"
    fi

    log_success "Firebase App Distribution configured"
}

# Create sample application structure
create_app_structure() {
    log_info "Creating sample mobile application structure..."

    local app_dir="$PROJECT_DIR/mobile-app"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create application structure in $app_dir"
        return 0
    fi

    # Create directory structure
    mkdir -p "$app_dir/android/app/src/main/java/com/example/app"
    mkdir -p "$app_dir/android/app/src/main/res/values"
    mkdir -p "$app_dir/android/app/src/androidTest/java/com/example/app"

    # Create Android manifest
    cat > "$app_dir/android/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.app">
    <application
        android:allowBackup="true"
        android:label="@string/app_name"
        android:theme="@style/AppTheme">
        <activity android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

    # Create Gradle build configuration
    cat > "$app_dir/android/build.gradle" << 'EOF'
buildscript {
    dependencies {
        classpath 'com.android.tools.build:gradle:7.4.0'
        classpath 'com.google.gms:google-services:4.3.14'
        classpath 'com.google.firebase:firebase-appdistribution-gradle:4.0.0'
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
EOF

    log_success "Sample application structure created"
}

# Configure Cloud Build pipeline
configure_cloud_build() {
    log_info "Configuring Cloud Build pipeline..."

    local app_dir="$PROJECT_DIR/mobile-app"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create Cloud Build configuration"
        return 0
    fi

    # Create Cloud Build configuration
    cat > "$app_dir/cloudbuild.yaml" << EOF
steps:
# Install dependencies and prepare build environment
- name: 'gcr.io/cloud-builders/git'
  args: ['clone', 'https://github.com/GoogleCloudPlatform/buildpack-samples.git']

# Build Android application
- name: 'gcr.io/cloud-builders/gradle'
  dir: 'android'
  args: ['clean', 'assembleDebug', 'assembleDebugAndroidTest']
  env:
  - 'GRADLE_OPTS=-Dorg.gradle.daemon=false'

# Run Firebase Test Lab testing
- name: 'gcr.io/cloud-builders/gcloud'
  args: 
  - 'firebase'
  - 'test'
  - 'android'
  - 'run'
  - '--type=instrumentation'
  - '--app=android/app/build/outputs/apk/debug/app-debug.apk'
  - '--test=android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
  - '--device=model=Pixel2,version=28,locale=en,orientation=portrait'
  - '--timeout=10m'
  env:
  - 'PROJECT_ID=$PROJECT_ID'

# Distribute to Firebase App Distribution
- name: 'gcr.io/cloud-builders/gcloud'
  args:
  - 'firebase'
  - 'appdistribution:distribute'
  - 'android/app/build/outputs/apk/debug/app-debug.apk'
  - '--app=\${_ANDROID_APP_ID}'
  - '--groups=qa-team,stakeholders'
  - '--release-notes=Automated build from commit \${SHORT_SHA}'
  env:
  - 'PROJECT_ID=$PROJECT_ID'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_HIGHCPU_8'

substitutions:
  _ANDROID_APP_ID: '$ANDROID_APP_ID'

timeout: '1800s'
EOF

    log_success "Cloud Build pipeline configured"
}

# Create build triggers
create_build_triggers() {
    log_info "Creating Cloud Build triggers..."

    # Main branch trigger
    execute_command "gcloud builds triggers create cloud-source-repositories --repo='$REPO_NAME' --branch-pattern='^main\$' --build-config=cloudbuild.yaml --description='Mobile CI/CD Pipeline' --substitutions='_ANDROID_APP_ID=$ANDROID_APP_ID' --project='$PROJECT_ID'" \
        "Creating main branch build trigger"

    # Feature branch trigger
    execute_command "gcloud builds triggers create cloud-source-repositories --repo='$REPO_NAME' --branch-pattern='^feature/.*' --build-config=cloudbuild.yaml --description='Feature Branch Testing' --substitutions='_ANDROID_APP_ID=$ANDROID_APP_ID' --project='$PROJECT_ID'" \
        "Creating feature branch build trigger"

    log_success "Build triggers created"
}

# Configure Firebase Test Lab
configure_test_lab() {
    log_info "Configuring Firebase Test Lab..."

    local app_dir="$PROJECT_DIR/mobile-app"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create Test Lab configuration"
        return 0
    fi

    # Create test matrix configuration
    cat > "$app_dir/test-matrix.yml" << 'EOF'
# Firebase Test Lab device matrix configuration
environmentType: ANDROID
androidDeviceList:
  androidDevices:
  - androidModelId: Pixel2
    androidVersionId: "28"
    locale: en
    orientation: portrait
  - androidModelId: Pixel3
    androidVersionId: "29"
    locale: en
    orientation: portrait
  - androidModelId: Pixel4
    androidVersionId: "30"
    locale: en
    orientation: portrait
  - androidModelId: NexusLowRes
    androidVersionId: "26"
    locale: en
    orientation: portrait
EOF

    # Create Firebase configuration
    cat > "$app_dir/.firebaserc" << EOF
{
  "projects": {
    "default": "$FIREBASE_PROJECT_ID"
  }
}
EOF

    log_success "Firebase Test Lab configured"
}

# Set up tester groups
setup_tester_groups() {
    log_info "Setting up Firebase App Distribution tester groups..."

    execute_command "firebase appdistribution:group:create qa-team --project='$FIREBASE_PROJECT_ID'" \
        "Creating QA team tester group"

    execute_command "firebase appdistribution:group:create stakeholders --project='$FIREBASE_PROJECT_ID'" \
        "Creating stakeholders tester group"

    execute_command "firebase appdistribution:group:create beta-users --project='$FIREBASE_PROJECT_ID'" \
        "Creating beta users tester group"

    log_success "Tester groups configured"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."

    local info_file="$PROJECT_DIR/deployment-info.txt"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would save deployment information to $info_file"
        return 0
    fi

    cat > "$info_file" << EOF
Cross-Platform Mobile Development Workflows Deployment Information
================================================================

Deployment Date: $(date)
Project ID: $PROJECT_ID
Region: $REGION
Firebase Project ID: $FIREBASE_PROJECT_ID

Resources Created:
- App Name: $APP_NAME
- Source Repository: $REPO_NAME
- Android App ID: $ANDROID_APP_ID

Cloud Build Triggers:
- Main branch trigger for repository: $REPO_NAME
- Feature branch trigger for repository: $REPO_NAME

Firebase App Distribution Groups:
- qa-team
- stakeholders
- beta-users

Firebase Test Lab Configuration:
- Multi-device testing matrix configured
- Devices: Pixel2, Pixel3, Pixel4, NexusLowRes

Next Steps:
1. Clone the source repository: gcloud source repos clone $REPO_NAME
2. Add your mobile application code to the repository
3. Commit and push to trigger the CI/CD pipeline
4. Add testers to distribution groups using Firebase console

Cleanup:
To remove all resources, run: ./destroy.sh --project-id $PROJECT_ID

EOF

    echo "PROJECT_ID=$PROJECT_ID" > "$PROJECT_DIR/.env"
    echo "REGION=$REGION" >> "$PROJECT_DIR/.env"
    echo "FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID" >> "$PROJECT_DIR/.env"
    echo "APP_NAME=$APP_NAME" >> "$PROJECT_DIR/.env"
    echo "REPO_NAME=$REPO_NAME" >> "$PROJECT_DIR/.env"
    echo "ANDROID_APP_ID=$ANDROID_APP_ID" >> "$PROJECT_DIR/.env"

    log_success "Deployment information saved to $info_file"
}

# Print deployment summary
print_summary() {
    log_success "Cross-Platform Mobile Development Workflows deployment completed!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo ""
        log_info "DRY RUN SUMMARY - No actual resources were created"
        echo ""
        echo "Resources that would be created:"
        echo "  ✓ Project: $PROJECT_ID"
        echo "  ✓ App Name: $APP_NAME"
        echo "  ✓ Source Repository: $REPO_NAME"
        echo "  ✓ Firebase Project: $FIREBASE_PROJECT_ID"
        echo "  ✓ Cloud Build triggers"
        echo "  ✓ Firebase App Distribution groups"
        echo "  ✓ Firebase Test Lab configuration"
        echo ""
        log_info "Run without --dry-run to actually deploy resources"
        return 0
    fi

    echo ""
    echo "Deployment Summary:"
    echo "==================="
    echo "Project ID: $PROJECT_ID"
    echo "App Name: $APP_NAME"
    echo "Source Repository: $REPO_NAME"
    echo "Android App ID: $ANDROID_APP_ID"
    echo ""
    echo "Next Steps:"
    echo "1. Clone the repository: gcloud source repos clone $REPO_NAME"
    echo "2. Add your mobile app code"
    echo "3. Commit and push to trigger CI/CD"
    echo "4. Configure testers in Firebase console"
    echo ""
    echo "Useful Commands:"
    echo "- View builds: gcloud builds list"
    echo "- View repositories: gcloud source repos list"
    echo "- Firebase console: https://console.firebase.google.com/project/$FIREBASE_PROJECT_ID"
    echo ""
    echo "Documentation: See deployment-info.txt for detailed information"
    echo ""
    log_success "Ready for mobile development workflows!"
}

# Main deployment function
main() {
    log_info "Starting Cross-Platform Mobile Development Workflows deployment..."
    
    # Initialize log file
    echo "Cross-Platform Mobile Development Workflows Deployment Log" > "$DEPLOYMENT_LOG"
    echo "Started: $(date)" >> "$DEPLOYMENT_LOG"
    echo "Project: $PROJECT_ID" >> "$DEPLOYMENT_LOG"
    echo "========================================" >> "$DEPLOYMENT_LOG"

    parse_args "$@"
    check_prerequisites
    setup_project_config
    enable_apis
    initialize_firebase
    create_source_repository
    configure_app_distribution
    create_app_structure
    configure_cloud_build
    create_build_triggers
    configure_test_lab
    setup_tester_groups
    save_deployment_info
    print_summary

    log_success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"