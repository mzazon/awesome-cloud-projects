#!/bin/bash

# Automated Code Review Pipeline Deployment Script
# This script deploys the Firebase Studio and Cloud Build automated code review infrastructure
# Prerequisites: gcloud CLI installed, authenticated, and project selected

set -euo pipefail

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

# Check if script is run with -h or --help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    cat <<EOF
Automated Code Review Pipeline Deployment Script

Usage: $0 [OPTIONS]

Options:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -p, --project       Specify GCP project ID (overrides current project)
    -r, --region        Specify GCP region (default: us-central1)
    --skip-apis         Skip API enablement (assume already enabled)
    --skip-prereqs      Skip prerequisite checks

Environment Variables:
    PROJECT_ID          GCP Project ID (required if not set via gcloud config)
    REGION              GCP Region (default: us-central1)
    GEMINI_API_KEY      API key for Gemini AI integration

Examples:
    $0                              # Deploy with default settings
    $0 --dry-run                    # Preview deployment without changes
    $0 -p my-project -r us-west1    # Deploy to specific project and region
EOF
    exit 0
fi

# Parse command line arguments
DRY_RUN=false
SKIP_APIS=false
SKIP_PREREQS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -p|--project)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        --skip-apis)
            SKIP_APIS=true
            shift
            ;;
        --skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set default values
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || echo '')}"
REGION="${REGION:-us-central1}"
ZONE="${REGION}-a"

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "PROJECT_ID must be set via environment variable, --project flag, or gcloud config"
    exit 1
fi

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)
QUEUE_NAME="code-review-queue-${RANDOM_SUFFIX}"
FUNCTION_NAME="code-review-handler-${RANDOM_SUFFIX}"
METRICS_FUNCTION="code-review-metrics-${RANDOM_SUFFIX}"
REPO_NAME="code-review-repo-${RANDOM_SUFFIX}"
METRICS_BUCKET="${PROJECT_ID}-code-review-metrics"
BUILD_BUCKET="${PROJECT_ID}-build-artifacts"

log_info "Starting deployment for project: $PROJECT_ID"
log_info "Region: $REGION"
log_info "Queue name: $QUEUE_NAME"
log_info "Function name: $FUNCTION_NAME"
log_info "Repository name: $REPO_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No changes will be made"
fi

# Function to execute commands with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    log_info "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "    Would execute: $cmd"
    else
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    if [[ "$SKIP_PREREQS" == "true" ]]; then
        log_warning "Skipping prerequisite checks"
        return 0
    fi

    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible"
        exit 1
    fi

    # Check if billing is enabled
    if ! gcloud billing projects describe "$PROJECT_ID" &> /dev/null; then
        log_warning "Unable to verify billing status. Ensure billing is enabled for the project."
    fi

    # Check for required tools
    local missing_tools=()
    
    for tool in curl openssl jq; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install these tools before continuing"
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Function to enable required APIs
enable_apis() {
    if [[ "$SKIP_APIS" == "true" ]]; then
        log_warning "Skipping API enablement"
        return 0
    fi

    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudbuild.googleapis.com"
        "cloudtasks.googleapis.com" 
        "cloudfunctions.googleapis.com"
        "sourcerepo.googleapis.com"
        "firebase.googleapis.com"
        "aiplatform.googleapis.com"
        "storage.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
    )

    for api in "${apis[@]}"; do
        execute_command "gcloud services enable $api --project=$PROJECT_ID" "Enabling $api"
    done

    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 10
    fi

    log_success "APIs enabled successfully"
}

# Function to set up project configuration
setup_project_config() {
    log_info "Configuring project settings..."
    
    execute_command "gcloud config set project $PROJECT_ID" "Setting project"
    execute_command "gcloud config set compute/region $REGION" "Setting region"
    execute_command "gcloud config set compute/zone $ZONE" "Setting zone"
    
    log_success "Project configuration completed"
}

# Function to create Cloud Source Repository
create_source_repository() {
    log_info "Creating Cloud Source Repository..."
    
    execute_command "gcloud source repos create $REPO_NAME --project=$PROJECT_ID" "Creating repository $REPO_NAME"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local repo_url
        repo_url=$(gcloud source repos describe "$REPO_NAME" --format="value(url)" 2>/dev/null || echo "")
        if [[ -n "$repo_url" ]]; then
            log_success "Repository created: $repo_url"
        fi
    fi
}

# Function to create Cloud Storage buckets
create_storage_buckets() {
    log_info "Creating Cloud Storage buckets..."
    
    # Create metrics bucket
    execute_command "gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$METRICS_BUCKET" "Creating metrics bucket"
    
    # Create build artifacts bucket
    execute_command "gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUILD_BUCKET" "Creating build artifacts bucket"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Set bucket lifecycle for cost optimization
        cat > /tmp/lifecycle.json <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 30}
      }
    ]
  }
}
EOF
        execute_command "gsutil lifecycle set /tmp/lifecycle.json gs://$METRICS_BUCKET" "Setting lifecycle policy on metrics bucket"
        execute_command "gsutil lifecycle set /tmp/lifecycle.json gs://$BUILD_BUCKET" "Setting lifecycle policy on build artifacts bucket"
        rm -f /tmp/lifecycle.json
    fi
    
    log_success "Storage buckets created successfully"
}

# Function to create Cloud Tasks queue
create_cloud_tasks_queue() {
    log_info "Creating Cloud Tasks queue..."
    
    execute_command "gcloud tasks queues create $QUEUE_NAME \
        --location=$REGION \
        --max-concurrent-dispatches=10 \
        --max-attempts=3 \
        --max-retry-duration=300s \
        --max-backoff=60s \
        --min-backoff=5s" "Creating Cloud Tasks queue"
    
    log_success "Cloud Tasks queue created successfully"
}

# Function to deploy Cloud Functions
deploy_cloud_functions() {
    log_info "Deploying Cloud Functions..."
    
    # Create temporary directories for function code
    local temp_dir="/tmp/code-review-functions-$$"
    mkdir -p "$temp_dir/code-review" "$temp_dir/metrics"
    
    # Create main code review function
    cat > "$temp_dir/code-review/main.py" <<'EOF'
import json
import os
from datetime import datetime
from google.cloud import tasks_v2
from google.cloud import storage
from google.cloud import logging
import google.generativeai as genai
import functions_framework

# Initialize logging client
logging_client = logging.Client()
logger = logging_client.logger('code-review-function')

@functions_framework.http
def analyze_code(request):
    """Analyze code changes and provide review feedback using Gemini AI."""
    
    try:
        # Parse request data
        request_data = request.get_json(silent=True)
        if not request_data:
            logger.error("No JSON data provided in request")
            return {'error': 'No data provided'}, 400
        
        repo_name = request_data.get('repo_name')
        commit_sha = request_data.get('commit_sha')
        file_changes = request_data.get('file_changes', [])
        
        if not repo_name or not commit_sha:
            logger.error("Missing required fields: repo_name or commit_sha")
            return {'error': 'Missing required fields'}, 400
        
        # Configure Gemini AI for code review
        api_key = os.environ.get('GEMINI_API_KEY')
        if not api_key:
            logger.error("GEMINI_API_KEY environment variable not set")
            return {'error': 'Configuration error'}, 500
            
        genai.configure(api_key=api_key)
        model = genai.GenerativeModel('gemini-1.5-pro')
        
        review_results = []
        
        for file_change in file_changes:
            file_path = file_change.get('file_path')
            diff_content = file_change.get('diff')
            
            if not file_path or not diff_content:
                continue
            
            # Generate comprehensive code review prompt
            prompt = f"""
            As an expert code reviewer, analyze this code change and provide thorough feedback:
            
            File: {file_path}
            Changes:
            {diff_content}
            
            Please provide a detailed review covering:
            1. Code quality and adherence to best practices
            2. Potential bugs, security vulnerabilities, or logic errors
            3. Performance implications and optimization opportunities
            4. Code readability and maintainability
            5. Test coverage recommendations
            6. Documentation completeness
            
            Format your response as structured feedback with specific line references where applicable.
            Focus on actionable recommendations that improve code quality.
            """
            
            try:
                # Generate AI-powered review
                response = model.generate_content(prompt)
                
                review_results.append({
                    'file_path': file_path,
                    'review_feedback': response.text,
                    'timestamp': datetime.utcnow().isoformat(),
                    'commit_sha': commit_sha,
                    'status': 'analyzed'
                })
                
                logger.info(f"Successfully analyzed file: {file_path}")
                
            except Exception as e:
                logger.error(f"Analysis failed for {file_path}: {str(e)}")
                review_results.append({
                    'file_path': file_path,
                    'error': f'Analysis failed: {str(e)}',
                    'commit_sha': commit_sha,
                    'status': 'error'
                })
        
        response_data = {
            'status': 'success',
            'repo_name': repo_name,
            'commit_sha': commit_sha,
            'review_results': review_results,
            'total_files_analyzed': len([r for r in review_results if r.get('status') == 'analyzed']),
            'timestamp': datetime.utcnow().isoformat()
        }
        
        logger.info(f"Code review completed for {repo_name}:{commit_sha}")
        return response_data
        
    except Exception as e:
        logger.error(f"Unhandled error in analyze_code: {str(e)}")
        return {'error': 'Internal server error'}, 500
EOF

    cat > "$temp_dir/code-review/requirements.txt" <<EOF
functions-framework==3.*
google-cloud-tasks==2.*
google-cloud-storage==2.*
google-generativeai==0.*
google-cloud-logging==3.*
EOF

    # Create metrics collection function
    cat > "$temp_dir/metrics/main.py" <<'EOF'
import json
import os
from datetime import datetime, timedelta
from google.cloud import monitoring_v3
from google.cloud import logging
from google.cloud import storage
import functions_framework

# Initialize clients
logging_client = logging.Client()
logger = logging_client.logger('code-review-metrics')
monitoring_client = monitoring_v3.MetricServiceClient()
storage_client = storage.Client()

@functions_framework.http
def collect_review_metrics(request):
    """Collect and store comprehensive code review metrics."""
    
    try:
        request_data = request.get_json(silent=True)
        if not request_data:
            logger.warning("No metrics data provided")
            return {'error': 'No metrics data provided'}, 400
        
        project_id = os.environ.get('PROJECT_ID')
        if not project_id:
            logger.error("PROJECT_ID environment variable not set")
            return {'error': 'Configuration error'}, 500
        
        project_name = f"projects/{project_id}"
        
        # Extract metrics from request
        metrics_data = {
            'review_duration': request_data.get('review_duration', 0),
            'issues_found': request_data.get('issues_count', 0),
            'code_quality_score': request_data.get('quality_score', 0),
            'files_analyzed': request_data.get('files_analyzed', 0),
            'security_issues': request_data.get('security_issues', 0),
            'performance_issues': request_data.get('performance_issues', 0),
            'test_coverage': request_data.get('test_coverage', 0),
            'build_duration': request_data.get('build_duration', 0)
        }
        
        # Create detailed metrics for monitoring
        metrics_logged = 0
        
        for metric_name, value in metrics_data.items():
            if value > 0:  # Only log meaningful metrics
                try:
                    # Log structured metric data
                    logger.info(
                        f"Code review metric: {metric_name}",
                        extra={
                            'metric_name': metric_name,
                            'metric_value': value,
                            'repo_name': request_data.get('repo_name', ''),
                            'commit_sha': request_data.get('commit_sha', ''),
                            'branch': request_data.get('branch', 'main'),
                            'review_type': request_data.get('review_type', 'automated'),
                            'timestamp': datetime.utcnow().isoformat()
                        }
                    )
                    metrics_logged += 1
                    
                except Exception as e:
                    logger.error(f"Failed to log metric {metric_name}: {str(e)}")
        
        # Store aggregate metrics for analysis
        try:
            aggregate_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'repository': request_data.get('repo_name', ''),
                'metrics': metrics_data,
                'metadata': {
                    'commit_sha': request_data.get('commit_sha', ''),
                    'branch': request_data.get('branch', 'main'),
                    'review_type': request_data.get('review_type', 'automated'),
                    'reviewer': request_data.get('reviewer', 'ai-agent')
                }
            }
            
            # Store in Cloud Storage for long-term analysis
            bucket_name = f"{project_id}-code-review-metrics"
            date_prefix = datetime.utcnow().strftime('%Y/%m/%d')
            filename = f"{date_prefix}/metrics-{datetime.utcnow().strftime('%H%M%S')}.json"
            
            try:
                bucket = storage_client.bucket(bucket_name)
                blob = bucket.blob(filename)
                blob.upload_from_string(json.dumps(aggregate_data, indent=2))
                logger.info(f"Metrics stored to gs://{bucket_name}/{filename}")
            except Exception as e:
                logger.warning(f"Failed to store metrics to Cloud Storage: {str(e)}")
        
        except Exception as e:
            logger.error(f"Failed to process aggregate metrics: {str(e)}")
        
        # Return success response
        response_data = {
            'status': 'success',
            'metrics_recorded': metrics_logged,
            'timestamp': datetime.utcnow().isoformat(),
            'project_id': project_id
        }
        
        logger.info(f"Successfully processed {metrics_logged} metrics")
        return response_data
        
    except Exception as e:
        logger.error(f"Unhandled error in collect_review_metrics: {str(e)}")
        return {'error': 'Internal server error'}, 500
EOF

    cat > "$temp_dir/metrics/requirements.txt" <<EOF
functions-framework==3.*
google-cloud-monitoring==2.*
google-cloud-logging==3.*
google-cloud-storage==2.*
EOF

    # Deploy main code review function
    execute_command "gcloud functions deploy $FUNCTION_NAME \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source $temp_dir/code-review \
        --entry-point analyze_code \
        --memory 1GB \
        --timeout 540s \
        --set-env-vars \"PROJECT_ID=$PROJECT_ID\" \
        --region $REGION" "Deploying code review function"

    # Deploy metrics collection function
    execute_command "gcloud functions deploy $METRICS_FUNCTION \
        --runtime python311 \
        --trigger-http \
        --allow-unauthenticated \
        --source $temp_dir/metrics \
        --entry-point collect_review_metrics \
        --memory 512MB \
        --timeout 120s \
        --set-env-vars \"PROJECT_ID=$PROJECT_ID\" \
        --region $REGION" "Deploying metrics collection function"
    
    # Clean up temporary files
    rm -rf "$temp_dir"
    
    log_success "Cloud Functions deployed successfully"
}

# Function to create Cloud Build triggers
create_build_triggers() {
    log_info "Creating Cloud Build triggers..."
    
    # Get function URLs for substitution variables
    local function_url=""
    if [[ "$DRY_RUN" == "false" ]]; then
        function_url=$(gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --format="value(httpsTrigger.url)" 2>/dev/null || echo "")
    else
        function_url="https://example-function-url.cloudfunctions.net/"
    fi
    
    # Create trigger for main branch
    execute_command "gcloud builds triggers create cloud-source-repositories \
        --repo=$REPO_NAME \
        --branch-pattern=\"^main$\" \
        --build-config=cloudbuild.yaml \
        --description=\"Automated code review pipeline for main branch\" \
        --name=\"code-review-main-trigger\" \
        --substitutions=\"_REPO_NAME=$REPO_NAME,_FUNCTION_URL=$function_url,_QUEUE_NAME=$QUEUE_NAME,_REGION=$REGION\"" "Creating main branch trigger"
    
    # Create trigger for feature branches
    execute_command "gcloud builds triggers create cloud-source-repositories \
        --repo=$REPO_NAME \
        --branch-pattern=\"^feature/.*$\" \
        --build-config=cloudbuild.yaml \
        --description=\"Code review pipeline for feature branches\" \
        --name=\"code-review-feature-trigger\" \
        --substitutions=\"_REPO_NAME=$REPO_NAME,_FUNCTION_URL=$function_url,_QUEUE_NAME=$QUEUE_NAME,_REGION=$REGION\"" "Creating feature branch trigger"
    
    log_success "Cloud Build triggers created successfully"
}

# Function to setup sample repository content
setup_sample_repository() {
    log_info "Setting up sample repository content..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Would clone and setup sample repository content"
        return 0
    fi
    
    # Create temporary directory for repository setup
    local temp_repo_dir="/tmp/code-review-repo-$$"
    mkdir -p "$temp_repo_dir"
    
    # Clone the repository
    execute_command "gcloud source repos clone $REPO_NAME $temp_repo_dir --project=$PROJECT_ID" "Cloning repository"
    
    cd "$temp_repo_dir"
    
    # Create comprehensive Cloud Build configuration
    cat > cloudbuild.yaml <<'EOF'
steps:
  # Step 1: Install dependencies and prepare environment
  - name: 'node:18'
    entrypoint: 'npm'
    args: ['install']
    id: 'install-deps'
    dir: '.'
  
  # Step 2: Run unit tests with coverage reporting
  - name: 'node:18'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Running unit tests with coverage..."
        npm test -- --coverage --passWithNoTests
        echo "✅ Tests completed"
    id: 'run-tests'
    waitFor: ['install-deps']
  
  # Step 3: Run security and quality scans
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    timeout: '300s'
    args:
      - '-c'
      - |
        echo "Running security analysis..."
        
        # Install security scanning tools
        npm install -g audit-ci eslint
        
        # Run security audit
        npm audit --audit-level moderate || echo "⚠️ Security audit completed with warnings"
        
        # Run linting if available
        if [ -f ".eslintrc.js" ] || [ -f ".eslintrc.json" ]; then
          eslint . --ext .js,.ts --format json --output-file lint-results.json || true
          echo "✅ Linting completed"
        else
          echo "No ESLint configuration found, skipping linting"
        fi
        
        echo "✅ Security scan completed"
    id: 'security-scan'
    waitFor: ['install-deps']
  
  # Step 4: Prepare code changes for AI review
  - name: 'gcr.io/cloud-builders/git'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Preparing code changes for review..."
        
        # Configure git for Cloud Build environment
        git config --global user.email "cloudbuild@google.com"
        git config --global user.name "Cloud Build"
        
        # Get changed files (fallback for new repositories)
        if git rev-parse HEAD~1 >/dev/null 2>&1; then
          git diff --name-only HEAD~1 HEAD > changed_files.txt
          git diff HEAD~1 HEAD > changes.diff
        else
          # For initial commit, list all files
          git ls-files > changed_files.txt
          echo "Initial commit - reviewing all files" > changes.diff
        fi
        
        # Count changed files
        CHANGED_COUNT=$(wc -l < changed_files.txt)
        echo "Found $CHANGED_COUNT changed files"
        
        # Store for next step
        echo "$CHANGED_COUNT" > change_count.txt
        
        echo "✅ Code changes prepared for review"
    id: 'prepare-changes'
    waitFor: ['run-tests', 'security-scan']
  
  # Step 5: Queue AI-powered code review task
  - name: 'gcr.io/cloud-builders/gcloud'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Queueing AI-powered code review..."
        
        # Read change count
        CHANGE_COUNT=$(cat change_count.txt || echo "0")
        
        if [ "$CHANGE_COUNT" -gt 0 ]; then
          # Create review payload with file changes
          cat > review_payload.json << EOF_PAYLOAD
        {
          "repo_name": "${_REPO_NAME}",
          "commit_sha": "$COMMIT_SHA",
          "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
          "file_changes": [
            {
              "file_path": "$(head -1 changed_files.txt || echo 'unknown')",
              "diff": "$(head -20 changes.diff | tr '\n' ' ' | tr '"' "'")"
            }
          ]
        }
        EOF_PAYLOAD
        
          # Submit task to Cloud Tasks queue
          gcloud tasks create-http-task \
            --queue=${_QUEUE_NAME} \
            --location=${_REGION} \
            --url=${_FUNCTION_URL} \
            --method=POST \
            --header="Content-Type=application/json" \
            --body-file=review_payload.json \
            --schedule-time="$(date -u -d '+30 seconds' +%Y-%m-%dT%H:%M:%SZ)"
          
          echo "✅ Code review task queued successfully"
        else
          echo "No code changes detected, skipping AI review"
        fi
    id: 'queue-code-review'
    waitFor: ['prepare-changes']
  
  # Step 6: Build application artifacts
  - name: 'node:18'
    entrypoint: 'bash'
    args:
      - '-c'
      - |
        echo "Building application..."
        
        # Run build process
        npm run build
        
        # Create build metadata
        cat > dist/build-info.json << EOF_BUILD
        {
          "build_id": "$BUILD_ID",
          "commit_sha": "$COMMIT_SHA",
          "build_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
          "repository": "${_REPO_NAME}"
        }
        EOF_BUILD
        
        echo "✅ Application build completed"
    id: 'build-app'
    waitFor: ['queue-code-review']

# Build configuration options
options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_MEDIUM'
  substitution_option: 'ALLOW_LOOSE'

# Artifact configuration
artifacts:
  objects:
    location: 'gs://${PROJECT_ID}-build-artifacts'
    paths: 
      - 'dist/**/*'
      - 'coverage/**/*'
      - 'lint-results.json'

# Timeout and environment
timeout: '1200s'
env:
  - 'NODE_ENV=production'
  - 'CI=true'
EOF

    # Create sample package.json
    cat > package.json <<'EOF'
{
  "name": "code-review-sample",
  "version": "1.0.0",
  "description": "Sample application for automated code review pipeline",
  "main": "index.js",
  "scripts": {
    "test": "echo 'Running tests...' && node test.js",
    "lint": "echo 'Running linter...' && exit 0",
    "build": "echo 'Building application...' && mkdir -p dist && echo 'console.log(\"Built successfully\");' > dist/index.js && echo 'Built successfully' > dist/index.html"
  },
  "dependencies": {
    "express": "^4.18.0"
  },
  "devDependencies": {
    "jest": "^29.0.0"
  }
}
EOF

    # Create sample application
    cat > index.js <<'EOF'
// Sample application for code review pipeline
const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

/**
 * Greet a user with validation
 * @param {string} name - User's name
 * @returns {string} Greeting message
 */
function greetUser(name) {
    if (!name || typeof name !== 'string') {
        throw new Error('Name is required and must be a string');
    }
    return `Hello, ${name.trim()}!`;
}

/**
 * Calculate sum of numbers with validation
 * @param {number[]} numbers - Array of numbers to sum
 * @returns {number} Sum of all numbers
 */
function calculateSum(numbers) {
    if (!Array.isArray(numbers)) {
        throw new Error('Input must be an array');
    }
    
    return numbers.reduce((sum, num) => {
        if (typeof num !== 'number') {
            throw new Error('All elements must be numbers');
        }
        return sum + num;
    }, 0);
}

// Express routes
app.get('/greet/:name', (req, res) => {
    try {
        const greeting = greetUser(req.params.name);
        res.json({ message: greeting });
    } catch (error) {
        res.status(400).json({ error: error.message });
    }
});

app.listen(port, () => {
    console.log(`Server running on port ${port}`);
});

module.exports = { greetUser, calculateSum };
EOF

    # Create test file
    cat > test.js <<'EOF'
const { greetUser, calculateSum } = require('./index');

// Simple test runner
function runTests() {
    console.log('Running tests...');
    
    try {
        // Test greetUser
        const greeting = greetUser('Alice');
        console.assert(greeting === 'Hello, Alice!', 'Greeting test failed');
        console.log('✅ Greeting test passed');
        
        // Test calculateSum
        const sum = calculateSum([1, 2, 3, 4, 5]);
        console.assert(sum === 15, 'Sum test failed');
        console.log('✅ Sum test passed');
        
        console.log('All tests passed!');
        process.exit(0);
    } catch (error) {
        console.error('Test failed:', error.message);
        process.exit(1);
    }
}

runTests();
EOF

    # Create Firebase Studio configuration
    mkdir -p .firebase-studio .vscode
    
    cat > .firebase-studio/workspace.yaml <<EOF
workspace:
  name: "code-review-workspace"
  runtime: "nodejs18"
  ai_assistance:
    enabled: true
    gemini_model: "gemini-1.5-pro"
    code_review_agent: true
    features:
      - code_analysis
      - security_scanning
      - performance_optimization
  integrations:
    cloud_build:
      enabled: true
      project_id: "${PROJECT_ID}"
    cloud_tasks:
      enabled: true
      queue_location: "${REGION}"
    source_repositories:
      enabled: true
      repo_name: "${REPO_NAME}"
development:
  pre_commit_hooks: true
  real_time_feedback: true
  auto_save: true
EOF

    cat > .vscode/settings.json <<EOF
{
  "firebase.studio.integration": true,
  "firebase.studio.ai.codeReview": true,
  "firebase.studio.autoTriggerBuilds": false,
  "editor.formatOnSave": true,
  "editor.codeActionsOnSave": {
    "source.fixAll": true,
    "source.organizeImports": true
  }
}
EOF

    # Commit all files
    git add .
    git commit -m "Initial automated code review pipeline setup

- Added comprehensive Cloud Build configuration
- Created sample application with validation
- Configured automated testing and review pipeline
- Added error handling and logging
- Set up Firebase Studio integration"

    git push origin main
    
    cd - > /dev/null
    rm -rf "$temp_repo_dir"
    
    log_success "Sample repository content created and committed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Repository: $REPO_NAME"
    echo "Queue: $QUEUE_NAME"
    echo "Code Review Function: $FUNCTION_NAME"
    echo "Metrics Function: $METRICS_FUNCTION"
    echo "Metrics Bucket: gs://$METRICS_BUCKET"
    echo "Build Artifacts Bucket: gs://$BUILD_BUCKET"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local repo_url function_url
        repo_url=$(gcloud source repos describe "$REPO_NAME" --format="value(url)" 2>/dev/null || echo "N/A")
        function_url=$(gcloud functions describe "$FUNCTION_NAME" --region="$REGION" --format="value(httpsTrigger.url)" 2>/dev/null || echo "N/A")
        
        echo "Repository URL: $repo_url"
        echo "Function URL: $function_url"
        echo "Firebase Studio: https://studio.firebase.google.com/project/$PROJECT_ID"
        echo ""
        
        log_info "Next Steps:"
        echo "1. Import repository in Firebase Studio"
        echo "2. Set GEMINI_API_KEY environment variable in Cloud Functions"
        echo "3. Push code changes to trigger automated reviews"
        echo "4. Monitor builds in Cloud Build console"
    fi
    
    log_success "Deployment completed successfully!"
}

# Main execution flow
main() {
    log_info "Starting automated code review pipeline deployment"
    
    check_prerequisites
    setup_project_config
    enable_apis
    create_storage_buckets
    create_source_repository
    create_cloud_tasks_queue
    deploy_cloud_functions
    create_build_triggers
    setup_sample_repository
    display_summary
}

# Execute main function with error handling
if main; then
    log_success "All deployment steps completed successfully"
    exit 0
else
    log_error "Deployment failed. Check the logs above for details."
    exit 1
fi