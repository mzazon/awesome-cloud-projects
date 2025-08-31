#!/bin/bash

# Deploy script for GCP App Engine Web Application
# Recipe: Web Application Deployment with App Engine
# Version: 1.1
# Last Updated: 2025-01-12

set -euo pipefail

# Colors for output
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

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy a Flask web application to Google App Engine.

OPTIONS:
    -p, --project-id PROJECT_ID     Specify GCP project ID (optional, will generate if not provided)
    -r, --region REGION            Specify GCP region (default: us-central1)
    -n, --app-name NAME            Specify application name prefix (default: webapp)
    -s, --skip-tests               Skip local testing
    -q, --quiet                    Suppress verbose output
    -h, --help                     Show this help message
    --dry-run                      Show what would be done without executing

EXAMPLES:
    $0                                          # Deploy with default settings
    $0 --project-id my-project-123              # Deploy to specific project
    $0 --region europe-west1 --app-name myapp  # Custom region and app name
    $0 --dry-run                               # Preview deployment

EOF
}

# Parse command line arguments
CUSTOM_PROJECT_ID=""
REGION="us-central1"
APP_NAME="webapp"
SKIP_TESTS=false
QUIET=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--project-id)
            CUSTOM_PROJECT_ID="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -n|--app-name)
            APP_NAME="$2"
            shift 2
            ;;
        -s|--skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
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
            log_error "Unknown option: $1"
            echo
            show_help
            exit 1
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed"
        log_info "Please install from: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if python3 is installed
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed"
        exit 1
    fi
    
    # Check if pip is installed
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        log_error "pip is not installed"
        exit 1
    fi
    
    # Check if curl is installed (for testing)
    if ! command -v curl &> /dev/null && [ "$SKIP_TESTS" = false ]; then
        log_warning "curl is not installed. Skipping HTTP tests."
        SKIP_TESTS=true
    fi
    
    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 > /dev/null; then
        log_error "No active gcloud authentication found"
        log_info "Please run: gcloud auth login"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Set up project and environment
setup_project() {
    log_info "Setting up GCP project and environment..."
    
    # Generate or use provided project ID
    if [ -z "$CUSTOM_PROJECT_ID" ]; then
        export PROJECT_ID="${APP_NAME}-demo-$(date +%s)"
        log_info "Generated project ID: $PROJECT_ID"
    else
        export PROJECT_ID="$CUSTOM_PROJECT_ID"
        log_info "Using provided project ID: $PROJECT_ID"
    fi
    
    export SERVICE_NAME="default"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo $(date +%s | tail -c 6))
    export RANDOM_SUFFIX
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create project: $PROJECT_ID"
        log_info "[DRY RUN] Would set region: $REGION"
        return 0
    fi
    
    # Create and configure project (only if custom project not provided)
    if [ -z "$CUSTOM_PROJECT_ID" ]; then
        log_info "Creating new GCP project..."
        if ! gcloud projects create "$PROJECT_ID" --name="${APP_NAME} Demo Project" --quiet; then
            log_error "Failed to create project. Project ID might already exist."
            exit 1
        fi
        log_success "Project created: $PROJECT_ID"
    else
        log_info "Using existing project: $PROJECT_ID"
    fi
    
    # Set active project
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    
    log_success "Project and environment configured"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would enable App Engine and Cloud Build APIs"
        return 0
    fi
    
    local apis=(
        "appengine.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if ! gcloud services enable "$api" --quiet; then
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_success "Required APIs enabled"
}

# Initialize App Engine
initialize_app_engine() {
    log_info "Initializing App Engine application..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would initialize App Engine in region: $REGION"
        return 0
    fi
    
    # Check if App Engine is already initialized
    if gcloud app describe --quiet &> /dev/null; then
        log_info "App Engine already initialized"
    else
        log_info "Creating App Engine application..."
        if ! gcloud app create --region="$REGION" --quiet; then
            log_error "Failed to initialize App Engine"
            exit 1
        fi
        log_success "App Engine initialized in region: $REGION"
    fi
}

# Create application files
create_application_files() {
    log_info "Creating Flask application files..."
    
    # Create project directory
    APP_DIR="${APP_NAME}-${RANDOM_SUFFIX}"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create application directory: $APP_DIR"
        log_info "[DRY RUN] Would create Flask application files"
        return 0
    fi
    
    mkdir -p "$APP_DIR"/{templates,static}
    cd "$APP_DIR"
    
    # Create main.py
    cat > main.py << 'EOF'
from flask import Flask, render_template
import datetime
import os

app = Flask(__name__)

@app.route('/')
def home():
    return render_template('index.html', 
                         current_time=datetime.datetime.now(),
                         version=os.environ.get('GAE_VERSION', 'local'))

@app.route('/health')
def health_check():
    return {'status': 'healthy', 'timestamp': str(datetime.datetime.now())}

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080, debug=True)
EOF

    # Create HTML template
    cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>My App Engine Web App</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">
</head>
<body>
    <div class="container">
        <h1>Welcome to App Engine!</h1>
        <p>Your web application is running successfully.</p>
        <div class="info">
            <p><strong>Current Time:</strong> {{ current_time }}</p>
            <p><strong>App Version:</strong> {{ version }}</p>
        </div>
        <button onclick="checkHealth()">Check Application Health</button>
        <div id="health-status"></div>
    </div>
    <script src="{{ url_for('static', filename='script.js') }}"></script>
</body>
</html>
EOF

    # Create CSS file
    cat > static/style.css << 'EOF'
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    margin: 0;
    padding: 20px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
}

.container {
    max-width: 600px;
    margin: 0 auto;
    text-align: center;
    background: rgba(255, 255, 255, 0.1);
    padding: 40px;
    border-radius: 15px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
}

.info {
    background: rgba(255, 255, 255, 0.2);
    padding: 20px;
    border-radius: 10px;
    margin: 20px 0;
}

button {
    background: #4285f4;
    color: white;
    border: none;
    padding: 10px 20px;
    border-radius: 5px;
    cursor: pointer;
    font-size: 16px;
}

button:hover {
    background: #3367d6;
}
EOF

    # Create JavaScript file
    cat > static/script.js << 'EOF'
async function checkHealth() {
    try {
        const response = await fetch('/health');
        const data = await response.json();
        document.getElementById('health-status').innerHTML = 
            `<p style="color: #34a853;">✅ ${data.status} - ${data.timestamp}</p>`;
    } catch (error) {
        document.getElementById('health-status').innerHTML = 
            `<p style="color: #ea4335;">❌ Health check failed</p>`;
    }
}
EOF

    # Create requirements.txt
    cat > requirements.txt << 'EOF'
Flask==3.0.0
Werkzeug==3.0.1
EOF

    # Create app.yaml
    cat > app.yaml << 'EOF'
runtime: python312

# Automatic scaling configuration
automatic_scaling:
  min_instances: 0
  max_instances: 10
  target_cpu_utilization: 0.6

# Static file handlers
handlers:
- url: /static
  static_dir: static

- url: /.*
  script: auto

# Environment variables
env_variables:
  FLASK_ENV: production
EOF

    log_success "Application files created"
}

# Test application locally
test_locally() {
    if [ "$SKIP_TESTS" = true ]; then
        log_info "Skipping local tests as requested"
        return 0
    fi
    
    log_info "Testing application locally..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would test application locally"
        return 0
    fi
    
    # Set up virtual environment
    log_info "Setting up Python virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    
    # Install dependencies
    pip install -r requirements.txt --quiet
    
    # Start local server in background
    log_info "Starting local development server..."
    python main.py &
    LOCAL_PID=$!
    
    # Wait for server to start
    sleep 5
    
    # Test endpoints
    local test_passed=true
    
    if curl -s http://localhost:8080/ | grep -q "Welcome to App Engine"; then
        log_success "Home page test passed"
    else
        log_error "Home page test failed"
        test_passed=false
    fi
    
    if curl -s http://localhost:8080/health | grep -q "healthy"; then
        log_success "Health check test passed"
    else
        log_error "Health check test failed"
        test_passed=false
    fi
    
    # Stop local server
    kill $LOCAL_PID 2>/dev/null || true
    wait $LOCAL_PID 2>/dev/null || true
    
    # Deactivate virtual environment
    deactivate
    
    if [ "$test_passed" = false ]; then
        log_error "Local tests failed"
        exit 1
    fi
    
    log_success "Local testing completed successfully"
}

# Deploy to App Engine
deploy_application() {
    log_info "Deploying application to App Engine..."
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would deploy application to App Engine"
        log_info "[DRY RUN] Would get application URL"
        return 0
    fi
    
    # Deploy the application
    if ! gcloud app deploy --quiet --promote; then
        log_error "Failed to deploy application"
        exit 1
    fi
    
    # Get application URL
    APP_URL=$(gcloud app browse --no-launch-browser 2>/dev/null || echo "https://${PROJECT_ID}.appspot.com")
    export APP_URL
    
    log_success "Application deployed successfully"
    log_success "Application URL: $APP_URL"
    
    # Save deployment info
    cat > deployment-info.txt << EOF
# Deployment Information
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
APP_URL=${APP_URL}
DEPLOYED_AT=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
APP_DIR=${APP_DIR}
EOF
    
    log_info "Deployment information saved to deployment-info.txt"
}

# Validate deployment
validate_deployment() {
    if [ "$SKIP_TESTS" = true ] || [ "$DRY_RUN" = true ]; then
        log_info "Skipping deployment validation"
        return 0
    fi
    
    log_info "Validating deployment..."
    
    # Wait for deployment to be fully ready
    log_info "Waiting for application to be ready..."
    sleep 10
    
    # Test deployed application
    local validation_passed=true
    
    if curl -s "$APP_URL" | grep -q "Welcome to App Engine"; then
        log_success "Deployed application home page accessible"
    else
        log_warning "Home page validation failed - application may still be starting"
        validation_passed=false
    fi
    
    if curl -s "$APP_URL/health" | grep -q "healthy"; then
        log_success "Health check endpoint working"
    else
        log_warning "Health check validation failed - application may still be starting"
        validation_passed=false
    fi
    
    if [ "$validation_passed" = false ]; then
        log_warning "Some validation tests failed. This may be normal if the application is still starting."
        log_info "Please check the application manually at: $APP_URL"
    else
        log_success "Deployment validation completed successfully"
    fi
}

# Main deployment function
main() {
    log_info "Starting GCP App Engine deployment..."
    log_info "================================================"
    
    # Store original directory
    ORIGINAL_DIR=$(pwd)
    
    # Trap to ensure cleanup on exit
    trap 'cd "$ORIGINAL_DIR" 2>/dev/null || true' EXIT
    
    # Run deployment steps
    check_prerequisites
    setup_project
    enable_apis
    initialize_app_engine
    create_application_files
    test_locally
    deploy_application
    validate_deployment
    
    # Return to original directory
    cd "$ORIGINAL_DIR"
    
    log_success "================================================"
    log_success "Deployment completed successfully!"
    
    if [ "$DRY_RUN" = false ]; then
        echo
        log_info "Deployment Summary:"
        log_info "  Project ID: $PROJECT_ID"
        log_info "  Region: $REGION"
        log_info "  Application URL: $APP_URL"
        log_info "  Application Directory: $APP_DIR"
        echo
        log_info "Next Steps:"
        log_info "  1. Visit your application: $APP_URL"
        log_info "  2. Check logs: gcloud app logs tail -s default"
        log_info "  3. Monitor: https://console.cloud.google.com/appengine?project=$PROJECT_ID"
        echo
        log_warning "Remember to run the cleanup script when done to avoid charges!"
    fi
}

# Run main function
main "$@"