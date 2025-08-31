#!/bin/bash

# Random Quote API with Cloud Functions and Firestore - Deployment Script
# This script deploys a serverless REST API using Cloud Functions and Firestore
# Based on: random-quote-api-functions-firestore recipe

set -euo pipefail

# Color codes for output formatting
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

# Configuration variables with defaults
PROJECT_PREFIX="${PROJECT_PREFIX:-quote-api}"
REGION="${REGION:-us-central1}"
FUNCTION_NAME="${FUNCTION_NAME:-random-quote-api}"
DATABASE_ID="${DATABASE_ID:-quotes-db}"
DRY_RUN="${DRY_RUN:-false}"

# Generate unique project ID
PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"

# Cleanup function for error handling
cleanup_on_error() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code $exit_code"
        log_warning "You may need to manually clean up resources in project: $PROJECT_ID"
    fi
    exit $exit_code
}

trap cleanup_on_error EXIT

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 &> /dev/null; then
        log_error "No active Google Cloud authentication found"
        log_error "Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if npm is installed for function dependencies
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed"
        log_error "Please install Node.js and npm from: https://nodejs.org/"
        exit 1
    fi
    
    # Check if node is installed
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed"
        log_error "Please install Node.js from: https://nodejs.org/"
        exit 1
    fi
    
    log_success "All prerequisites satisfied"
}

# Create and configure Google Cloud Project
setup_project() {
    log_info "Setting up Google Cloud project: $PROJECT_ID"
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Project $PROJECT_ID already exists, using existing project"
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create project: $PROJECT_ID"
        else
            gcloud projects create "$PROJECT_ID" \
                --name="Random Quote API Demo" \
                --quiet
            log_success "Created project: $PROJECT_ID"
        fi
    fi
    
    # Set the project as default
    if [[ "$DRY_RUN" != "true" ]]; then
        gcloud config set project "$PROJECT_ID" --quiet
        gcloud config set functions/region "$REGION" --quiet
        log_success "Configured project settings"
    fi
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "firestore.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would enable API: $api"
        else
            log_info "Enabling $api..."
            gcloud services enable "$api" --quiet
        fi
    done
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Wait a moment for APIs to be fully enabled
        sleep 10
        log_success "APIs enabled successfully"
    fi
}

# Create Firestore database
create_firestore_database() {
    log_info "Creating Firestore database: $DATABASE_ID"
    
    # Check if database already exists
    if gcloud firestore databases describe "$DATABASE_ID" &>/dev/null; then
        log_warning "Firestore database $DATABASE_ID already exists"
        return 0
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create Firestore database: $DATABASE_ID"
    else
        gcloud firestore databases create \
            --database="$DATABASE_ID" \
            --location="$REGION" \
            --type=firestore-native \
            --quiet
        
        log_success "Firestore database created: $DATABASE_ID"
    fi
}

# Create and populate function source code
setup_function_code() {
    log_info "Setting up Cloud Function code..."
    
    local temp_dir="/tmp/quote-function-$$"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create function code in: $temp_dir"
        return 0
    fi
    
    # Create temporary directory for function code
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "random-quote-api",
  "version": "1.0.0",
  "main": "index.js",
  "dependencies": {
    "@google-cloud/firestore": "^7.1.0",
    "@google-cloud/functions-framework": "^3.3.0"
  }
}
EOF
    
    # Create the main function implementation
    cat > index.js << 'EOF'
const { Firestore } = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

// Initialize Firestore client with automatic project detection
const firestore = new Firestore({
  databaseId: process.env.DATABASE_ID || 'quotes-db'
});

// HTTP Cloud Function that responds to GET requests
functions.http('randomQuote', async (req, res) => {
  // Set CORS headers for web browser compatibility
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET');
  
  try {
    // Query all documents from the 'quotes' collection
    const quotesRef = firestore.collection('quotes');
    const snapshot = await quotesRef.get();
    
    if (snapshot.empty) {
      return res.status(404).json({ 
        error: 'No quotes found in database' 
      });
    }
    
    // Select a random document from the collection
    const quotes = snapshot.docs;
    const randomIndex = Math.floor(Math.random() * quotes.length);
    const randomQuote = quotes[randomIndex];
    
    // Return the quote data with metadata
    const quoteData = randomQuote.data();
    res.status(200).json({
      id: randomQuote.id,
      quote: quoteData.text,
      author: quoteData.author,
      category: quoteData.category || 'general',
      timestamp: new Date().toISOString()
    });
    
  } catch (error) {
    console.error('Error fetching quote:', error);
    res.status(500).json({ 
      error: 'Internal server error' 
    });
  }
});
EOF
    
    # Create sample data population script
    cat > populate-quotes.js << 'EOF'
const { Firestore } = require('@google-cloud/firestore');

const firestore = new Firestore({
  databaseId: process.env.DATABASE_ID || 'quotes-db'
});

const sampleQuotes = [
  {
    text: "The only way to do great work is to love what you do.",
    author: "Steve Jobs",
    category: "motivation"
  },
  {
    text: "Innovation distinguishes between a leader and a follower.",
    author: "Steve Jobs", 
    category: "innovation"
  },
  {
    text: "Life is what happens to you while you're busy making other plans.",
    author: "John Lennon",
    category: "life"
  },
  {
    text: "The future belongs to those who believe in the beauty of their dreams.",
    author: "Eleanor Roosevelt",
    category: "inspiration"
  },
  {
    text: "Success is not final, failure is not fatal: it is the courage to continue that counts.",
    author: "Winston Churchill",
    category: "perseverance"
  }
];

async function populateQuotes() {
  const quotesCollection = firestore.collection('quotes');
  
  for (const quote of sampleQuotes) {
    await quotesCollection.add(quote);
    console.log(`Added quote: "${quote.text.substring(0, 30)}..."`);
  }
  
  console.log('✅ Sample quotes added to Firestore');
}

populateQuotes().catch(console.error);
EOF
    
    log_success "Function code created in: $temp_dir"
    echo "$temp_dir" # Return temp directory path for later use
}

# Populate Firestore with sample data
populate_sample_data() {
    local temp_dir="$1"
    
    log_info "Populating Firestore with sample quotes..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would populate sample data"
        return 0
    fi
    
    cd "$temp_dir"
    
    # Install dependencies
    npm install --silent
    
    # Set environment variable and populate data
    export DATABASE_ID="$DATABASE_ID"
    node populate-quotes.js
    
    log_success "Sample quotes populated in Firestore"
}

# Deploy Cloud Function
deploy_function() {
    local temp_dir="$1"
    
    log_info "Deploying Cloud Function: $FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy function: $FUNCTION_NAME"
        return 0
    fi
    
    cd "$temp_dir"
    
    # Deploy the function with appropriate settings
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime=nodejs20 \
        --trigger-http \
        --entry-point=randomQuote \
        --memory=256MB \
        --timeout=60s \
        --set-env-vars="DATABASE_ID=$DATABASE_ID" \
        --allow-unauthenticated \
        --region="$REGION" \
        --quiet
    
    # Get the function's HTTP URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    log_success "Cloud Function deployed successfully"
    log_success "Function URL: $function_url"
    
    # Store deployment info for later reference
    cat > "/tmp/quote-api-deployment-info.txt" << EOF
Project ID: $PROJECT_ID
Function Name: $FUNCTION_NAME
Database ID: $DATABASE_ID
Region: $REGION
Function URL: $function_url
Deployed at: $(date)
EOF
    
    log_info "Deployment info saved to: /tmp/quote-api-deployment-info.txt"
}

# Test the deployed function
test_deployment() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test the deployment"
        return 0
    fi
    
    log_info "Testing the deployed API..."
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    # Test the API with curl if available
    if command -v curl &> /dev/null; then
        log_info "Making test request to: $function_url"
        
        local response
        if response=$(curl -s -w "\n%{http_code}" "$function_url"); then
            local body=$(echo "$response" | sed '$d')
            local status_code=$(echo "$response" | tail -n1)
            
            if [[ "$status_code" == "200" ]]; then
                log_success "API test successful!"
                log_info "Response: $body"
            else
                log_warning "API returned status code: $status_code"
                log_warning "Response: $body"
            fi
        else
            log_warning "Failed to test API endpoint"
        fi
    else
        log_warning "curl not available, skipping API test"
        log_info "You can test the API manually at: $function_url"
    fi
}

# Cleanup temporary files
cleanup_temp_files() {
    local temp_dir="$1"
    
    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"
        log_info "Cleaned up temporary files"
    fi
}

# Main deployment function
main() {
    log_info "Starting Random Quote API deployment..."
    log_info "Project ID: $PROJECT_ID"
    log_info "Region: $REGION"
    log_info "Function Name: $FUNCTION_NAME"
    log_info "Database ID: $DATABASE_ID"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_warning "DRY RUN MODE - No actual resources will be created"
    fi
    
    check_prerequisites
    setup_project
    enable_apis
    create_firestore_database
    
    local temp_dir
    temp_dir=$(setup_function_code)
    
    populate_sample_data "$temp_dir"
    deploy_function "$temp_dir"
    test_deployment
    
    cleanup_temp_files "$temp_dir"
    
    log_success "Deployment completed successfully!"
    log_info "Your Random Quote API is ready to use"
    
    if [[ -f "/tmp/quote-api-deployment-info.txt" ]]; then
        log_info "Deployment details:"
        cat "/tmp/quote-api-deployment-info.txt"
    fi
}

# Script usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy a Random Quote API using Google Cloud Functions and Firestore

OPTIONS:
    -p, --project-prefix    Project prefix (default: quote-api)
    -r, --region           GCP region (default: us-central1)
    -f, --function-name    Cloud Function name (default: random-quote-api)
    -d, --database-id      Firestore database ID (default: quotes-db)
    --dry-run              Show what would be done without making changes
    -h, --help             Show this help message

ENVIRONMENT VARIABLES:
    PROJECT_PREFIX         Override project prefix
    REGION                 Override region
    FUNCTION_NAME          Override function name
    DATABASE_ID            Override database ID
    DRY_RUN               Set to 'true' for dry run mode

EXAMPLES:
    $0                                          # Deploy with defaults
    $0 --dry-run                               # Preview changes
    $0 -p my-quotes -r us-west1               # Custom prefix and region
    PROJECT_PREFIX=company-api $0              # Use environment variable

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-prefix)
            PROJECT_PREFIX="$2"
            PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
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
        -d|--database-id)
            DATABASE_ID="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
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

# Run the main deployment
main "$@"