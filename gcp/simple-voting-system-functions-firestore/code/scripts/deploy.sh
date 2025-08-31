#!/bin/bash

# Simple Voting System with Cloud Functions and Firestore - Deployment Script
# This script deploys a complete serverless voting system on Google Cloud Platform

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Banner
echo -e "${BLUE}"
echo "========================================================"
echo "  Simple Voting System - Deployment Script"
echo "  Cloud Functions + Firestore on Google Cloud"
echo "========================================================"
echo -e "${NC}"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
        log_error "Google Cloud CLI is not authenticated"
        log_info "Run: gcloud auth login"
        exit 1
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log_error "Node.js is not installed"
        log_info "Install from: https://nodejs.org/"
        exit 1
    fi
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        log_error "npm is not installed"
        log_info "npm should be included with Node.js installation"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Allow user to override project ID
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="voting-system-$(date +%s)"
        log_info "Generated PROJECT_ID: ${PROJECT_ID}"
    else
        log_info "Using provided PROJECT_ID: ${PROJECT_ID}"
    fi
    
    # Allow user to override region
    if [[ -z "${REGION:-}" ]]; then
        export REGION="us-central1"
    fi
    log_info "Using REGION: ${REGION}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="vote-handler-${RANDOM_SUFFIX}"
    log_info "Generated FUNCTION_NAME: ${FUNCTION_NAME}"
    
    # Create deployment state directory
    export STATE_DIR="${HOME}/.voting-system-state"
    mkdir -p "${STATE_DIR}"
    
    # Save deployment state
    cat > "${STATE_DIR}/deployment.env" << EOF
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
FUNCTION_NAME="${FUNCTION_NAME}"
RANDOM_SUFFIX="${RANDOM_SUFFIX}"
DEPLOYMENT_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Environment variables configured"
}

# Create and configure Google Cloud project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Project ${PROJECT_ID} already exists"
    else
        log_info "Creating project: ${PROJECT_ID}"
        if ! gcloud projects create "${PROJECT_ID}"; then
            log_error "Failed to create project. You may need billing enabled or different project ID"
            exit 1
        fi
        log_success "Project created: ${PROJECT_ID}"
    fi
    
    # Set current project
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    
    # Check if billing is enabled
    if ! gcloud billing projects describe "${PROJECT_ID}" &> /dev/null; then
        log_warning "Billing may not be enabled for project ${PROJECT_ID}"
        log_info "You may need to enable billing in the Google Cloud Console"
        log_info "Visit: https://console.cloud.google.com/billing/linkedaccount?project=${PROJECT_ID}"
    fi
    
    log_success "Project configuration complete"
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
        log_info "Enabling ${api}..."
        if gcloud services enable "${api}"; then
            log_success "Enabled ${api}"
        else
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Initialize Firestore database
setup_firestore() {
    log_info "Setting up Firestore database..."
    
    # Check if Firestore database already exists
    if gcloud firestore databases list --format="value(name)" 2>/dev/null | grep -q "(default)"; then
        log_warning "Firestore database already exists"
    else
        log_info "Creating Firestore database in Native mode..."
        if gcloud firestore databases create --region="${REGION}" --type=firestore-native; then
            log_success "Firestore database created in ${REGION}"
        else
            log_error "Failed to create Firestore database"
            exit 1
        fi
    fi
    
    log_success "Firestore setup complete"
}

# Create function source code
create_function_code() {
    log_info "Creating function source code..."
    
    # Create temporary directory for function code
    export FUNCTION_DIR=$(mktemp -d)
    cd "${FUNCTION_DIR}"
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "voting-system-functions",
  "version": "1.0.0",
  "description": "Serverless voting system using Cloud Functions and Firestore",
  "main": "index.js",
  "scripts": {
    "start": "functions-framework --target=submitVote"
  },
  "dependencies": {
    "@google-cloud/firestore": "^7.9.0",
    "@google-cloud/functions-framework": "^3.4.0"
  },
  "engines": {
    "node": "20"
  }
}
EOF
    
    # Create the main function file
    cat > index.js << 'EOF'
const { Firestore } = require('@google-cloud/firestore');
const functions = require('@google-cloud/functions-framework');

const firestore = new Firestore();

// Vote submission endpoint
functions.http('submitVote', async (req, res) => {
  // Enable CORS
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
  
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  try {
    const { topicId, option, userId } = req.body;
    
    if (!topicId || !option || !userId) {
      res.status(400).json({ error: 'Missing required fields' });
      return;
    }
    
    // Check if user already voted
    const userVoteRef = firestore
      .collection('votes')
      .doc(`${topicId}_${userId}`);
    
    const userVoteDoc = await userVoteRef.get();
    
    if (userVoteDoc.exists) {
      res.status(409).json({ error: 'User already voted on this topic' });
      return;
    }
    
    // Use transaction to ensure atomicity
    await firestore.runTransaction(async (transaction) => {
      // Record the vote
      transaction.set(userVoteRef, {
        topicId,
        option,
        userId,
        timestamp: Firestore.Timestamp.now()
      });
      
      // Update vote count
      const countRef = firestore
        .collection('voteCounts')
        .doc(`${topicId}_${option}`);
      
      const countDoc = await transaction.get(countRef);
      const currentCount = countDoc.exists ? countDoc.data().count : 0;
      
      transaction.set(countRef, {
        topicId,
        option,
        count: currentCount + 1,
        lastUpdated: Firestore.Timestamp.now()
      });
    });
    
    res.status(200).json({ success: true, message: 'Vote recorded' });
  } catch (error) {
    console.error('Error processing vote:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Get results endpoint
functions.http('getResults', async (req, res) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }
  
  try {
    const { topicId } = req.query;
    
    if (!topicId) {
      res.status(400).json({ error: 'Missing topicId parameter' });
      return;
    }
    
    const countsSnapshot = await firestore
      .collection('voteCounts')
      .where('topicId', '==', topicId)
      .get();
    
    const results = {};
    countsSnapshot.forEach(doc => {
      const data = doc.data();
      results[data.option] = data.count;
    });
    
    res.status(200).json({ topicId, results });
  } catch (error) {
    console.error('Error getting results:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});
EOF
    
    # Install dependencies
    log_info "Installing Node.js dependencies..."
    if npm install; then
        log_success "Dependencies installed successfully"
    else
        log_error "Failed to install dependencies"
        exit 1
    fi
    
    log_success "Function source code created in ${FUNCTION_DIR}"
}

# Deploy Cloud Functions
deploy_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Deploy vote submission function
    log_info "Deploying vote submission function..."
    if gcloud functions deploy "${FUNCTION_NAME}-submit" \
        --gen2 \
        --runtime=nodejs20 \
        --region="${REGION}" \
        --source=. \
        --entry-point=submitVote \
        --trigger-http \
        --allow-unauthenticated \
        --memory=256MB \
        --timeout=60s; then
        log_success "Vote submission function deployed"
    else
        log_error "Failed to deploy vote submission function"
        exit 1
    fi
    
    # Get the function URL
    SUBMIT_URL=$(gcloud functions describe "${FUNCTION_NAME}-submit" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    if [[ -z "${SUBMIT_URL}" ]]; then
        log_error "Failed to get vote submission function URL"
        exit 1
    fi
    
    log_success "Vote submission function URL: ${SUBMIT_URL}"
    
    # Deploy results function
    log_info "Deploying results retrieval function..."
    if gcloud functions deploy "${FUNCTION_NAME}-results" \
        --gen2 \
        --runtime=nodejs20 \
        --region="${REGION}" \
        --source=. \
        --entry-point=getResults \
        --trigger-http \
        --allow-unauthenticated \
        --memory=256MB \
        --timeout=60s; then
        log_success "Results function deployed"
    else
        log_error "Failed to deploy results function"
        exit 1
    fi
    
    # Get the results function URL
    RESULTS_URL=$(gcloud functions describe "${FUNCTION_NAME}-results" \
        --region="${REGION}" \
        --format="value(serviceConfig.uri)")
    
    if [[ -z "${RESULTS_URL}" ]]; then
        log_error "Failed to get results function URL"
        exit 1
    fi
    
    log_success "Results function URL: ${RESULTS_URL}"
    
    # Save URLs to state
    echo "SUBMIT_URL=\"${SUBMIT_URL}\"" >> "${STATE_DIR}/deployment.env"
    echo "RESULTS_URL=\"${RESULTS_URL}\"" >> "${STATE_DIR}/deployment.env"
    echo "FUNCTION_DIR=\"${FUNCTION_DIR}\"" >> "${STATE_DIR}/deployment.env"
    
    log_success "Both functions deployed successfully"
}

# Create web interface
create_web_interface() {
    log_info "Creating web interface..."
    
    # Source the URLs from state
    source "${STATE_DIR}/deployment.env"
    
    # Create web interface in current directory
    cat > voting-interface.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Simple Voting System</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 600px; margin: 50px auto; padding: 20px; }
        .vote-option { margin: 10px 0; }
        button { background: #4285F4; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; }
        button:hover { background: #3367D6; }
        .results { margin-top: 30px; padding: 20px; background: #f0f0f0; border-radius: 4px; }
        .header { text-align: center; margin-bottom: 30px; }
        .status { margin: 10px 0; padding: 10px; border-radius: 4px; }
        .success { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Simple Voting System</h1>
        <p>Powered by Google Cloud Functions and Firestore</p>
    </div>
    
    <div>
        <h3>Vote on: What's your favorite cloud service?</h3>
        <div class="vote-option">
            <button onclick="submitVote('cloud-services', 'compute-engine')">Compute Engine</button>
        </div>
        <div class="vote-option">
            <button onclick="submitVote('cloud-services', 'cloud-functions')">Cloud Functions</button>
        </div>
        <div class="vote-option">
            <button onclick="submitVote('cloud-services', 'cloud-storage')">Cloud Storage</button>
        </div>
        <div class="vote-option">
            <button onclick="submitVote('cloud-services', 'firestore')">Firestore</button>
        </div>
    </div>
    
    <button onclick="getResults('cloud-services')" style="margin-top: 20px;">View Results</button>
    
    <div id="status"></div>
    
    <div id="results" class="results" style="display: none;">
        <h3>Current Results:</h3>
        <div id="results-content"></div>
    </div>

    <script>
        const SUBMIT_URL = '${SUBMIT_URL}';
        const RESULTS_URL = '${RESULTS_URL}';
        const USER_ID = 'user-' + Math.random().toString(36).substr(2, 9);
        
        function showStatus(message, isError = false) {
            const statusDiv = document.getElementById('status');
            statusDiv.innerHTML = '<div class="status ' + (isError ? 'error' : 'success') + '">' + message + '</div>';
            setTimeout(() => statusDiv.innerHTML = '', 5000);
        }
        
        async function submitVote(topicId, option) {
            try {
                showStatus('Submitting vote...');
                const response = await fetch(SUBMIT_URL, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ topicId, option, userId: USER_ID })
                });
                
                const result = await response.json();
                
                if (response.ok) {
                    showStatus('Vote submitted successfully!');
                    getResults(topicId);
                } else {
                    showStatus('Error: ' + result.error, true);
                }
            } catch (error) {
                showStatus('Network error: ' + error.message, true);
            }
        }
        
        async function getResults(topicId) {
            try {
                const response = await fetch(RESULTS_URL + '?topicId=' + topicId);
                const data = await response.json();
                
                if (response.ok) {
                    displayResults(data.results);
                } else {
                    showStatus('Error getting results: ' + data.error, true);
                }
            } catch (error) {
                showStatus('Network error: ' + error.message, true);
            }
        }
        
        function displayResults(results) {
            const resultsDiv = document.getElementById('results');
            const contentDiv = document.getElementById('results-content');
            
            let html = '';
            let total = 0;
            
            for (const [option, count] of Object.entries(results)) {
                total += count;
            }
            
            for (const [option, count] of Object.entries(results)) {
                const percentage = total > 0 ? Math.round((count / total) * 100) : 0;
                html += '<p><strong>' + option.replace(/-/g, ' ').toUpperCase() + 
                       ':</strong> ' + count + ' votes (' + percentage + '%)</p>';
            }
            
            contentDiv.innerHTML = html || '<p>No votes yet!</p>';
            resultsDiv.style.display = 'block';
        }
        
        // Load initial results
        getResults('cloud-services');
    </script>
</body>
</html>
EOF
    
    log_success "Web interface created: voting-interface.html"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Source the deployment state
    source "${STATE_DIR}/deployment.env"
    
    # Check functions status
    log_info "Checking function deployment status..."
    local submit_status=$(gcloud functions describe "${FUNCTION_NAME}-submit" \
        --region="${REGION}" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    local results_status=$(gcloud functions describe "${FUNCTION_NAME}-results" \
        --region="${REGION}" \
        --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "${submit_status}" == "ACTIVE" && "${results_status}" == "ACTIVE" ]]; then
        log_success "Both functions are active and ready"
    else
        log_error "Functions are not active. Submit: ${submit_status}, Results: ${results_status}"
        exit 1
    fi
    
    # Test basic functionality
    log_info "Testing vote submission..."
    local test_response=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${SUBMIT_URL}" \
        -H "Content-Type: application/json" \
        -d '{
          "topicId": "deployment-test",
          "option": "test-option",
          "userId": "test-user-deployment"
        }' 2>/dev/null || echo "000")
    
    if [[ "${test_response}" == "200" ]]; then
        log_success "Vote submission test passed"
    else
        log_warning "Vote submission test returned HTTP ${test_response} (this may be normal for first deployment)"
    fi
    
    log_success "Deployment validation complete"
}

# Print deployment summary
print_summary() {
    log_info "Deployment Summary"
    echo "===================="
    
    # Source the deployment state
    source "${STATE_DIR}/deployment.env"
    
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Function Name Prefix: ${FUNCTION_NAME}"
    echo "Deployment Time: ${DEPLOYMENT_TIME}"
    echo ""
    echo "Deployed Functions:"
    echo "- Vote Submission: ${SUBMIT_URL}"
    echo "- Results Retrieval: ${RESULTS_URL}"
    echo ""
    echo "Resources Created:"
    echo "- Cloud Functions (2): ${FUNCTION_NAME}-submit, ${FUNCTION_NAME}-results"
    echo "- Firestore Database: (default)"
    echo "- Web Interface: voting-interface.html"
    echo ""
    echo "Next Steps:"
    echo "1. Open voting-interface.html in your browser to test the system"
    echo "2. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME}-submit --region=${REGION}"
    echo "3. View Firestore data: https://console.cloud.google.com/firestore/databases/-default-/data/panel?project=${PROJECT_ID}"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo ""
    
    log_success "Deployment completed successfully!"
}

# Main execution flow
main() {
    local start_time=$(date +%s)
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    setup_firestore
    create_function_code
    deploy_functions
    create_web_interface
    validate_deployment
    print_summary
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    log_success "Total deployment time: ${duration} seconds"
    log_info "Deployment state saved to: ${STATE_DIR}/deployment.env"
}

# Handle script interruption
cleanup_on_exit() {
    if [[ -n "${FUNCTION_DIR:-}" && -d "${FUNCTION_DIR}" ]]; then
        log_info "Cleaning up temporary function directory..."
        rm -rf "${FUNCTION_DIR}"
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"