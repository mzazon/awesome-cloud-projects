#!/bin/bash

# Visitor Counter with Cloud Functions and Firestore - Deployment Script
# This script deploys a serverless visitor counter using Google Cloud Functions and Firestore
# 
# Requirements:
# - Google Cloud SDK (gcloud) installed and configured
# - Appropriate GCP permissions for Cloud Functions, Firestore, and IAM
# - Node.js 20+ (for local development/testing)
# 
# Usage: ./deploy.sh [PROJECT_ID] [REGION]

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FUNCTION_DIR="${SCRIPT_DIR}/../function"
readonly DEFAULT_REGION="us-central1"
readonly FUNCTION_NAME="visit-counter"

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    # Add any necessary cleanup here
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Visitor Counter Deployment Script

USAGE:
    $0 [PROJECT_ID] [REGION]

ARGUMENTS:
    PROJECT_ID  Google Cloud Project ID (optional, will prompt if not provided)
    REGION      GCP region for resources (default: ${DEFAULT_REGION})

EXAMPLES:
    $0                                    # Interactive mode
    $0 my-project-123                     # Use specific project
    $0 my-project-123 us-east1           # Use specific project and region

REQUIREMENTS:
    - Google Cloud SDK installed and configured
    - Billing enabled on the project
    - Appropriate IAM permissions
    - Node.js 20+ for local development

For more information, see the README.md file.
EOF
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if jq is installed (for JSON parsing)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some features may not work properly"
        log_warning "Install with: sudo apt-get install jq (Ubuntu) or brew install jq (macOS)"
    fi
    
    # Check if node is installed and version is 20+
    if command -v node &> /dev/null; then
        local node_version
        node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
        if [ "$node_version" -lt 20 ]; then
            log_warning "Node.js version $node_version detected. Node.js 20+ is recommended"
        fi
    else
        log_warning "Node.js not found. Install Node.js 20+ for local development"
    fi
    
    log_success "Prerequisites check completed"
}

# Validate and set project
setup_project() {
    local project_id="$1"
    
    if [ -z "$project_id" ]; then
        log_info "No project ID provided. Checking current gcloud configuration..."
        project_id=$(gcloud config get-value project 2>/dev/null || echo "")
        
        if [ -z "$project_id" ]; then
            log_error "No project configured in gcloud"
            echo -n "Please enter your Google Cloud Project ID: "
            read -r project_id
            
            if [ -z "$project_id" ]; then
                log_error "Project ID is required"
                exit 1
            fi
        fi
    fi
    
    # Validate project exists and is accessible
    log_info "Validating project: $project_id"
    if ! gcloud projects describe "$project_id" &>/dev/null; then
        log_error "Project '$project_id' does not exist or is not accessible"
        log_error "Please check your project ID and permissions"
        exit 1
    fi
    
    # Set the project
    gcloud config set project "$project_id"
    
    # Check if billing is enabled
    local billing_enabled
    billing_enabled=$(gcloud beta billing projects describe "$project_id" \
        --format="value(billingEnabled)" 2>/dev/null || echo "false")
    
    if [ "$billing_enabled" != "True" ]; then
        log_warning "Billing is not enabled for project '$project_id'"
        log_warning "Some services may not work properly without billing enabled"
        echo -n "Continue anyway? (y/n): "
        read -r continue_choice
        if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
            log_error "Deployment cancelled"
            exit 1
        fi
    fi
    
    export PROJECT_ID="$project_id"
    log_success "Project set to: $PROJECT_ID"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "cloudbuild.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_info "Waiting for APIs to be fully enabled..."
    sleep 10
    
    log_success "All required APIs enabled"
}

# Initialize Firestore
initialize_firestore() {
    local region="$1"
    
    log_info "Checking Firestore database status..."
    
    # Check if Firestore database already exists
    local db_exists
    db_exists=$(gcloud firestore databases list --format="value(name)" 2>/dev/null | wc -l)
    
    if [ "$db_exists" -eq 0 ]; then
        log_info "Creating Firestore database in Native mode..."
        if gcloud firestore databases create --region="$region" --quiet; then
            log_success "Firestore database created successfully"
            
            # Wait for database to be ready
            log_info "Waiting for Firestore database to be ready..."
            sleep 30
        else
            log_error "Failed to create Firestore database"
            exit 1
        fi
    else
        log_success "Firestore database already exists"
    fi
}

# Create function source code
create_function_code() {
    log_info "Creating Cloud Function source code..."
    
    # Create function directory
    mkdir -p "$FUNCTION_DIR"
    cd "$FUNCTION_DIR"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "visit-counter",
  "version": "1.0.0",
  "description": "Simple visitor counter using Cloud Functions and Firestore",
  "main": "index.js",
  "engines": {
    "node": "20"
  },
  "dependencies": {
    "@google-cloud/firestore": "^7.1.0",
    "@google-cloud/functions-framework": "^3.3.0"
  },
  "scripts": {
    "start": "npx functions-framework --target=visitCounter --port=8080",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "author": "Google Cloud Recipe",
  "license": "Apache-2.0"
}
EOF
    
    # Create main function file
    cat > index.js << 'EOF'
const { Firestore, FieldValue } = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

// Initialize Firestore client
const firestore = new Firestore();

// Register HTTP function
functions.http('visitCounter', async (req, res) => {
  // Enable CORS for browser requests
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  try {
    // Get page parameter or use default
    const page = req.query.page || req.body?.page || 'default';
    
    // Validate page parameter to prevent injection
    if (!/^[a-zA-Z0-9_-]+$/.test(page)) {
      return res.status(400).json({
        error: 'Invalid page parameter',
        message: 'Page parameter must contain only letters, numbers, hyphens, and underscores'
      });
    }
    
    // Reference to the counter document
    const counterDoc = firestore.collection('counters').doc(page);
    
    // Atomically increment the counter
    await counterDoc.set({
      count: FieldValue.increment(1),
      lastVisit: FieldValue.serverTimestamp()
    }, { merge: true });
    
    // Get the updated count
    const doc = await counterDoc.get();
    const currentCount = doc.exists ? doc.data().count : 1;
    
    // Return the current count
    res.json({
      page: page,
      visits: currentCount,
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('Error updating counter:', error);
    res.status(500).json({
      error: 'Failed to update counter',
      message: error.message
    });
  }
});
EOF
    
    # Create .gcloudignore file
    cat > .gcloudignore << 'EOF'
# Node.js dependencies
node_modules/

# Local development files
.env
.env.local

# IDE files
.vscode/
.idea/

# OS files
.DS_Store
Thumbs.db

# Logs
*.log
logs/

# Test files
test/
tests/
*.test.js
EOF
    
    log_success "Function source code created"
}

# Deploy Cloud Function
deploy_function() {
    local region="$1"
    
    log_info "Deploying Cloud Function to region: $region"
    
    cd "$FUNCTION_DIR"
    
    # Deploy the function
    if gcloud functions deploy "$FUNCTION_NAME" \
        --gen2 \
        --runtime nodejs20 \
        --trigger-http \
        --allow-unauthenticated \
        --source . \
        --entry-point visitCounter \
        --memory 256MB \
        --timeout 60s \
        --region "$region" \
        --quiet; then
        
        log_success "Cloud Function deployed successfully"
        
        # Get function URL
        local function_url
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$region" \
            --format="value(serviceConfig.uri)" 2>/dev/null)
        
        if [ -n "$function_url" ]; then
            log_success "Function URL: $function_url"
            echo "$function_url" > "${SCRIPT_DIR}/../function_url.txt"
            log_info "Function URL saved to: ${SCRIPT_DIR}/../function_url.txt"
        fi
    else
        log_error "Failed to deploy Cloud Function"
        exit 1
    fi
}

# Test the deployed function
test_function() {
    log_info "Testing the deployed function..."
    
    local function_url
    if [ -f "${SCRIPT_DIR}/../function_url.txt" ]; then
        function_url=$(cat "${SCRIPT_DIR}/../function_url.txt")
    else
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(serviceConfig.uri)" 2>/dev/null)
    fi
    
    if [ -z "$function_url" ]; then
        log_warning "Could not retrieve function URL for testing"
        return
    fi
    
    log_info "Testing function at: $function_url"
    
    # Test with curl if available
    if command -v curl &> /dev/null; then
        log_info "Sending test request..."
        
        local response
        if response=$(curl -s -w "\n%{http_code}" "$function_url" 2>/dev/null); then
            local body=$(echo "$response" | head -n -1)
            local status_code=$(echo "$response" | tail -n 1)
            
            if [ "$status_code" = "200" ]; then
                log_success "Function test successful!"
                if command -v jq &> /dev/null && echo "$body" | jq . &>/dev/null; then
                    echo "$body" | jq .
                else
                    echo "Response: $body"
                fi
            else
                log_warning "Function returned status code: $status_code"
                echo "Response: $body"
            fi
        else
            log_warning "Could not test function automatically"
        fi
    else
        log_warning "curl not available for automatic testing"
        log_info "You can manually test the function at: $function_url"
    fi
}

# Generate usage instructions
generate_instructions() {
    local function_url
    if [ -f "${SCRIPT_DIR}/../function_url.txt" ]; then
        function_url=$(cat "${SCRIPT_DIR}/../function_url.txt")
    fi
    
    cat << EOF

${GREEN}Deployment Successful!${NC}

Your visitor counter is now deployed and ready to use.

${BLUE}Function Details:${NC}
- Function Name: $FUNCTION_NAME
- Region: $REGION
- Runtime: Node.js 20
- URL: ${function_url:-"Use 'gcloud functions describe $FUNCTION_NAME --region=$REGION' to get URL"}

${BLUE}Usage Examples:${NC}
1. Basic visitor count (default page):
   curl "$function_url"

2. Count visits for specific page:
   curl "$function_url?page=home"

3. POST request with JSON:
   curl -X POST "$function_url" \\
        -H "Content-Type: application/json" \\
        -d '{"page": "about"}'

${BLUE}JavaScript Example:${NC}
<script>
fetch('$function_url?page=home')
  .then(response => response.json())
  .then(data => {
    console.log('Visits:', data.visits);
    document.getElementById('counter').textContent = data.visits;
  });
</script>

${BLUE}Firestore Data:${NC}
Visit counts are stored in the 'counters' collection in Firestore.
You can view them in the Firebase Console or using the gcloud CLI.

${BLUE}Cost Information:${NC}
- Cloud Functions: First 2 million invocations per month are free
- Firestore: First 20,000 document writes per day are free
- Typical monthly cost for low traffic: $0.00 - $0.50

${BLUE}Next Steps:${NC}
1. Integrate the function URL into your website or application
2. Monitor usage in the Google Cloud Console
3. Set up alerts for usage thresholds if needed
4. Run './destroy.sh' when you want to clean up resources

${YELLOW}Important:${NC} Save the function URL if you need to reference it later!

EOF
}

# Main deployment function
main() {
    local project_id="$1"
    local region="${2:-$DEFAULT_REGION}"
    
    # Show help if requested
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_help
        exit 0
    fi
    
    echo "=============================================="
    echo "  Visitor Counter Deployment Script"
    echo "=============================================="
    echo
    
    # Run deployment steps
    check_prerequisites
    setup_project "$project_id"
    
    export REGION="$region"
    log_info "Using region: $REGION"
    
    enable_apis
    initialize_firestore "$region"
    create_function_code
    deploy_function "$region"
    test_function
    
    echo
    echo "=============================================="
    generate_instructions
    echo "=============================================="
    
    log_success "Deployment completed successfully!"
}

# Run main function with all arguments
main "$@"