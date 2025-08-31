#!/bin/bash

# Website Screenshot API Deployment Script
# This script deploys a serverless screenshot API using Google Cloud Functions and Storage
# Based on the website-screenshot-api-functions-storage recipe

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    log_info "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
    else
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        log_info "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1 &> /dev/null; then
        log_error "Not authenticated with Google Cloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some validation steps may be limited."
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Required for generating unique resource names."
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values or use existing environment variables
    export PROJECT_ID="${PROJECT_ID:-screenshot-api-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-screenshot-generator}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export BUCKET_NAME="${BUCKET_NAME:-screenshots-${RANDOM_SUFFIX}}"
    
    log_info "Environment variables set:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  REGION: ${REGION}"
    log_info "  FUNCTION_NAME: ${FUNCTION_NAME}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
}

# Function to create and configure GCP project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_info "Project ${PROJECT_ID} already exists. Using existing project."
    else
        execute_command "gcloud projects create ${PROJECT_ID} --name='Screenshot API Project'" \
            "Creating new project: ${PROJECT_ID}"
    fi
    
    # Set default project and region
    execute_command "gcloud config set project ${PROJECT_ID}" \
        "Setting default project"
    
    execute_command "gcloud config set functions/region ${REGION}" \
        "Setting default functions region"
    
    # Check if billing is enabled
    if [[ "$DRY_RUN" != "true" ]]; then
        if ! gcloud billing projects list --filter="PROJECT_ID:${PROJECT_ID}" --format="value(BILLING_ENABLED)" | grep -q "True"; then
            log_warning "Billing is not enabled for project ${PROJECT_ID}"
            log_warning "Please enable billing to continue with resource creation"
            log_info "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
            
            read -p "Press Enter after enabling billing, or Ctrl+C to exit..."
        fi
    fi
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_command "gcloud services enable ${api}" \
            "Enabling ${api}"
    done
    
    # Wait for APIs to be fully enabled
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 10
    fi
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for screenshots..."
    
    # Check if bucket already exists
    if [[ "$DRY_RUN" != "true" ]] && gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
        log_info "Bucket gs://${BUCKET_NAME} already exists. Using existing bucket."
    else
        execute_command "gcloud storage buckets create gs://${BUCKET_NAME} --location=${REGION} --storage-class=STANDARD --uniform-bucket-level-access" \
            "Creating storage bucket"
    fi
    
    # Configure public read access for screenshot URLs
    execute_command "gcloud storage buckets add-iam-policy-binding gs://${BUCKET_NAME} --member='allUsers' --role='roles/storage.objectViewer'" \
        "Configuring public read access for screenshots"
    
    log_success "Storage bucket created and configured"
}

# Function to create function source code
create_function_code() {
    log_info "Creating Cloud Function source code..."
    
    local function_dir="screenshot-function"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create function directory
        mkdir -p "${function_dir}"
        cd "${function_dir}"
        
        # Create package.json
        cat > package.json << 'EOF'
{
  "name": "screenshot-api",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "gcp-build": "node node_modules/puppeteer/install.mjs"
  },
  "dependencies": {
    "@google-cloud/functions-framework": "^4.0.0",
    "@google-cloud/storage": "^7.16.0",
    "puppeteer": "^24.15.0"
  }
}
EOF
        
        # Create Puppeteer configuration
        cat > .puppeteerrc.cjs << 'EOF'
const {join} = require('path');

/**
 * @type {import("puppeteer").Configuration}
 */
module.exports = {
  // Changes the cache location for Puppeteer
  cacheDirectory: join(__dirname, '.cache', 'puppeteer'),
};
EOF
        
        # Create main function file
        cat > index.js << 'EOF'
const functions = require('@google-cloud/functions-framework');
const puppeteer = require('puppeteer');
const {Storage} = require('@google-cloud/storage');

// Initialize Cloud Storage client
const storage = new Storage();
const bucketName = process.env.BUCKET_NAME;

functions.http('generateScreenshot', async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(204).send('');
  }

  try {
    // Extract URL from request
    const targetUrl = req.query.url || req.body?.url;
    
    if (!targetUrl) {
      return res.status(400).json({
        error: 'URL parameter is required'
      });
    }

    // Validate URL format
    try {
      new URL(targetUrl);
    } catch (urlError) {
      return res.status(400).json({
        error: 'Invalid URL format'
      });
    }

    console.log(`Taking screenshot of: ${targetUrl}`);

    // Launch browser with optimized settings
    const browser = await puppeteer.launch({
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--disable-gpu'
      ],
      headless: 'new'
    });

    const page = await browser.newPage();
    
    // Set viewport for consistent screenshots
    await page.setViewport({
      width: 1200,
      height: 800,
      deviceScaleFactor: 1
    });

    // Navigate and take screenshot
    await page.goto(targetUrl, {
      waitUntil: 'networkidle2',
      timeout: 30000
    });

    const screenshot = await page.screenshot({
      type: 'png',
      fullPage: false
    });

    await browser.close();

    // Generate unique filename
    const timestamp = Date.now();
    const filename = `screenshot-${timestamp}.png`;

    // Upload to Cloud Storage
    const file = storage.bucket(bucketName).file(filename);
    
    await file.save(screenshot, {
      metadata: {
        contentType: 'image/png',
        metadata: {
          sourceUrl: targetUrl,
          generatedAt: new Date().toISOString()
        }
      }
    });

    // Return screenshot URL
    const publicUrl = `https://storage.googleapis.com/${bucketName}/${filename}`;
    
    res.json({
      success: true,
      screenshotUrl: publicUrl,
      filename: filename,
      sourceUrl: targetUrl
    });

  } catch (error) {
    console.error('Screenshot generation failed:', error);
    res.status(500).json({
      error: 'Screenshot generation failed',
      details: error.message
    });
  }
});
EOF
        
        cd ..
        log_success "Function source code created"
    else
        log_info "DRY-RUN: Would create function source code in ${function_dir}/"
    fi
}

# Function to deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cd screenshot-function
    fi
    
    execute_command "gcloud functions deploy ${FUNCTION_NAME} --gen2 --runtime=nodejs20 --trigger-http --allow-unauthenticated --memory=1024MB --timeout=540s --set-env-vars BUCKET_NAME=${BUCKET_NAME} --source=." \
        "Deploying screenshot generation function"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cd ..
        
        # Get function URL
        FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" --format="value(serviceConfig.uri)")
        echo "FUNCTION_URL=${FUNCTION_URL}" > .deployment_vars
        
        log_success "Function deployed successfully"
        log_info "Function URL: ${FUNCTION_URL}"
    else
        log_info "DRY-RUN: Would deploy function and save URL to .deployment_vars"
    fi
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY-RUN: Would validate function deployment and storage bucket"
        return
    fi
    
    # Check function status
    local function_status=$(gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" --format="value(state)")
    if [[ "$function_status" == "ACTIVE" ]]; then
        log_success "Function is active and ready"
    else
        log_error "Function deployment failed. Status: ${function_status}"
        return 1
    fi
    
    # Check storage bucket
    if gcloud storage buckets describe "gs://${BUCKET_NAME}" &> /dev/null; then
        log_success "Storage bucket is accessible"
    else
        log_error "Storage bucket is not accessible"
        return 1
    fi
    
    # Test function with a simple request if possible
    if [[ -f ".deployment_vars" ]]; then
        source .deployment_vars
        log_info "Testing function with Google homepage..."
        
        if command -v curl &> /dev/null; then
            local test_response
            test_response=$(curl -s -X POST "${FUNCTION_URL}" \
                -H "Content-Type: application/json" \
                -d '{"url": "https://www.google.com"}' \
                --max-time 60)
            
            if echo "$test_response" | grep -q "success.*true"; then
                log_success "Function test completed successfully"
                if command -v jq &> /dev/null; then
                    local screenshot_url
                    screenshot_url=$(echo "$test_response" | jq -r '.screenshotUrl // empty')
                    if [[ -n "$screenshot_url" ]]; then
                        log_info "Test screenshot URL: ${screenshot_url}"
                    fi
                fi
            else
                log_warning "Function test did not return expected success response"
                log_info "Response: ${test_response}"
            fi
        else
            log_warning "curl not available, skipping function test"
        fi
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "===================="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Function Name: ${FUNCTION_NAME}"
    echo "Storage Bucket: gs://${BUCKET_NAME}"
    
    if [[ "$DRY_RUN" != "true" ]] && [[ -f ".deployment_vars" ]]; then
        source .deployment_vars
        echo "Function URL: ${FUNCTION_URL}"
        echo ""
        echo "Test your API:"
        echo "curl '${FUNCTION_URL}?url=https://www.example.com'"
        echo ""
        echo "Or with POST:"
        echo "curl -X POST '${FUNCTION_URL}' -H 'Content-Type: application/json' -d '{\"url\": \"https://www.example.com\"}'"
    fi
    
    echo ""
    log_info "Estimated monthly cost for light usage: \$0.01 - \$0.10"
    log_warning "Remember to clean up resources when no longer needed to avoid charges"
    log_info "Run './destroy.sh' to clean up all resources"
}

# Function to handle errors
handle_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code ${exit_code}"
    log_info "Check the logs above for details"
    log_info "You can run './destroy.sh' to clean up any partially created resources"
    exit $exit_code
}

# Main deployment function
main() {
    log_info "Starting Website Screenshot API deployment..."
    
    # Set up error handling
    trap handle_error ERR
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_function_code
    deploy_function
    validate_deployment
    display_summary
    
    log_success "Deployment completed successfully!"
}

# Handle command line arguments
case "${1:-}" in
    --dry-run)
        export DRY_RUN=true
        log_info "Dry-run mode enabled"
        ;;
    --help|-h)
        echo "Website Screenshot API Deployment Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --dry-run    Show what would be deployed without creating resources"
        echo "  --help, -h   Show this help message"
        echo ""
        echo "Environment Variables:"
        echo "  PROJECT_ID    GCP project ID (default: screenshot-api-<timestamp>)"
        echo "  REGION        GCP region (default: us-central1)"
        echo "  FUNCTION_NAME Function name (default: screenshot-generator)"
        echo "  BUCKET_NAME   Storage bucket name (default: screenshots-<random>)"
        echo ""
        echo "Examples:"
        echo "  $0                    # Deploy with default settings"
        echo "  $0 --dry-run          # Preview deployment"
        echo "  PROJECT_ID=my-proj $0 # Deploy to specific project"
        exit 0
        ;;
    "")
        # No arguments, proceed with deployment
        ;;
    *)
        log_error "Unknown argument: $1"
        log_info "Use --help for usage information"
        exit 1
        ;;
esac

# Run main function
main