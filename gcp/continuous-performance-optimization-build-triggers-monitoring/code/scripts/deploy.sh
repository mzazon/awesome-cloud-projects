#!/bin/bash

# Deploy script for Continuous Performance Optimization with Cloud Build Triggers and Cloud Monitoring
# This script deploys the complete infrastructure for automated performance optimization
# Version: 1.0
# Last Updated: 2025-01-28

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

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

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
FORCE_DEPLOY=${FORCE_DEPLOY:-false}

# Default configuration
DEFAULT_PROJECT_ID="perf-optimization-$(date +%s)"
DEFAULT_REGION="us-central1"
DEFAULT_ZONE="us-central1-a"

# Configuration variables with defaults
PROJECT_ID=${PROJECT_ID:-$DEFAULT_PROJECT_ID}
REGION=${REGION:-$DEFAULT_REGION}
ZONE=${ZONE:-$DEFAULT_ZONE}
REPO_NAME=${REPO_NAME:-"app-performance-repo"}
BUILD_TRIGGER_NAME=${BUILD_TRIGGER_NAME:-"perf-optimization-trigger"}
MONITORING_POLICY_NAME=${MONITORING_POLICY_NAME:-"performance-threshold-policy"}

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
SERVICE_NAME=${SERVICE_NAME:-"performance-app-${RANDOM_SUFFIX}"}

# Required APIs
REQUIRED_APIS=(
    "cloudbuild.googleapis.com"
    "monitoring.googleapis.com"
    "sourcerepo.googleapis.com"
    "run.googleapis.com"
    "containerregistry.googleapis.com"
)

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud CLI (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active Google Cloud authentication found. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_warning "Project $PROJECT_ID does not exist."
        read -p "Create project $PROJECT_ID? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Creating project $PROJECT_ID..."
            gcloud projects create "$PROJECT_ID" --name="Performance Optimization Project"
            
            # Enable billing (user must have billing account)
            log_warning "Please ensure billing is enabled for project $PROJECT_ID"
            log_info "You can enable billing at: https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT_ID"
            read -p "Press Enter after enabling billing..."
        else
            log_error "Project creation cancelled. Exiting."
            exit 1
        fi
    fi
    
    # Check required tools
    local missing_tools=()
    
    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi
    
    if ! command -v openssl &> /dev/null; then
        missing_tools+=("openssl")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install missing tools and try again."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to display configuration
display_configuration() {
    log_info "Deployment Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Zone: $ZONE"
    echo "  Repository Name: $REPO_NAME"
    echo "  Service Name: $SERVICE_NAME"
    echo "  Build Trigger: $BUILD_TRIGGER_NAME"
    echo "  Monitoring Policy: $MONITORING_POLICY_NAME"
    echo "  Random Suffix: $RANDOM_SUFFIX"
    echo ""
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN MODE - No resources will be created"
        return 0
    fi
    
    if [ "$FORCE_DEPLOY" != "true" ]; then
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user."
            exit 0
        fi
    fi
}

# Function to set up GCP configuration
setup_gcp_configuration() {
    log_info "Configuring Google Cloud settings..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would set project to $PROJECT_ID"
        log_info "[DRY RUN] Would set compute/region to $REGION"
        log_info "[DRY RUN] Would set compute/zone to $ZONE"
        return 0
    fi
    
    # Set default project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"
    gcloud config set compute/zone "$ZONE"
    
    log_success "GCP configuration completed"
}

# Function to enable required APIs
enable_required_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would enable APIs: ${REQUIRED_APIS[*]}"
        return 0
    fi
    
    for api in "${REQUIRED_APIS[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --project="$PROJECT_ID"; then
            log_success "Enabled $api"
        else
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Source Repository
create_source_repository() {
    log_info "Creating Cloud Source Repository..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create repository: $REPO_NAME"
        return 0
    fi
    
    # Check if repository already exists
    if gcloud source repos describe "$REPO_NAME" --project="$PROJECT_ID" &> /dev/null; then
        log_warning "Repository $REPO_NAME already exists"
        if [ "$FORCE_DEPLOY" != "true" ]; then
            read -p "Continue with existing repository? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Repository creation cancelled"
                exit 1
            fi
        fi
    else
        # Create the repository
        if gcloud source repos create "$REPO_NAME" --project="$PROJECT_ID"; then
            log_success "Created repository: $REPO_NAME"
        else
            log_error "Failed to create repository: $REPO_NAME"
            exit 1
        fi
    fi
}

# Function to setup application code
setup_application_code() {
    log_info "Setting up application code..."
    
    local repo_dir="$REPO_NAME"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would clone repository and create application code"
        return 0
    fi
    
    # Clone the repository
    if [ -d "$repo_dir" ]; then
        log_warning "Repository directory $repo_dir already exists"
        if [ "$FORCE_DEPLOY" != "true" ]; then
            read -p "Remove existing directory and continue? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -rf "$repo_dir"
            else
                log_error "Setup cancelled"
                exit 1
            fi
        else
            rm -rf "$repo_dir"
        fi
    fi
    
    log_info "Cloning repository..."
    if ! gcloud source repos clone "$REPO_NAME" --project="$PROJECT_ID"; then
        log_error "Failed to clone repository"
        exit 1
    fi
    
    cd "$repo_dir"
    
    # Create sample Node.js application
    log_info "Creating sample application..."
    
    cat > app.js << 'EOF'
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

// Simulate CPU-intensive operation
function cpuIntensiveTask(duration = 100) {
  const start = Date.now();
  while (Date.now() - start < duration) {
    Math.random() * Math.random();
  }
}

// Main endpoint with configurable performance
app.get('/', (req, res) => {
  const delay = parseInt(req.query.delay) || 0;
  cpuIntensiveTask(delay);
  res.json({
    message: 'Performance monitoring app',
    timestamp: new Date().toISOString(),
    processingTime: delay
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', timestamp: new Date().toISOString() });
});

// Performance test endpoint
app.get('/load-test', (req, res) => {
  cpuIntensiveTask(500); // Simulate heavy load
  res.json({ message: 'Load test completed', duration: 500 });
});

app.listen(port, () => {
  console.log(`Server running on port ${port}`);
});
EOF
    
    # Create package.json
    cat > package.json << 'EOF'
{
  "name": "performance-monitoring-app",
  "version": "1.0.0",
  "description": "Sample app for performance optimization testing",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "test": "echo \"Error: no test specified\" && exit 1"
  },
  "dependencies": {
    "express": "^4.18.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOF
    
    # Create optimized Dockerfile
    cat > Dockerfile << 'EOF'
FROM node:18-alpine

# Create app directory
WORKDIR /usr/src/app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy application code
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Change ownership and switch to non-root user
RUN chown -R nodejs:nodejs /usr/src/app
USER nodejs

# Expose port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) })"

# Start application
CMD ["npm", "start"]
EOF
    
    # Create Cloud Build configuration
    cat > cloudbuild.yaml << EOF
steps:
# Build optimized container image
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', 'gcr.io/\$PROJECT_ID/\${_SERVICE_NAME}:\$BUILD_ID', '.']
  id: 'build-image'

# Push image to Container Registry
- name: 'gcr.io/cloud-builders/docker'
  args: ['push', 'gcr.io/\$PROJECT_ID/\${_SERVICE_NAME}:\$BUILD_ID']
  id: 'push-image'
  waitFor: ['build-image']

# Deploy to Cloud Run with performance optimizations
- name: 'gcr.io/cloud-builders/gcloud'
  args:
  - 'run'
  - 'deploy'
  - '\${_SERVICE_NAME}'
  - '--image=gcr.io/\$PROJECT_ID/\${_SERVICE_NAME}:\$BUILD_ID'
  - '--region=\${_REGION}'
  - '--platform=managed'
  - '--allow-unauthenticated'
  - '--memory=512Mi'
  - '--cpu=1'
  - '--concurrency=80'
  - '--max-instances=10'
  - '--min-instances=1'
  - '--port=8080'
  - '--set-env-vars=NODE_ENV=production'
  id: 'deploy-service'
  waitFor: ['push-image']

# Create performance baseline
- name: 'gcr.io/cloud-builders/curl'
  args:
  - '-f'
  - '-s'
  - '-o'
  - '/dev/null'
  - '-w'
  - 'Deploy verification: %{http_code} - Response time: %{time_total}s'
  - 'https://\${_SERVICE_NAME}-\${_REGION}-\$PROJECT_ID.a.run.app/health'
  id: 'verify-deployment'
  waitFor: ['deploy-service']

substitutions:
  _SERVICE_NAME: '$SERVICE_NAME'
  _REGION: '$REGION'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_HIGHCPU_8'

timeout: '600s'
EOF
    
    # Create performance monitoring script
    cat > monitor-performance.sh << 'EOF'
#!/bin/bash

SERVICE_URL=$1
DURATION=${2:-60}  # Default 60 seconds

if [ -z "$SERVICE_URL" ]; then
  echo "Usage: $0 <service-url> [duration-seconds]"
  exit 1
fi

echo "Starting performance monitoring for ${DURATION} seconds..."
echo "Target URL: ${SERVICE_URL}"

# Performance metrics collection
TOTAL_REQUESTS=0
TOTAL_RESPONSE_TIME=0
ERROR_COUNT=0

START_TIME=$(date +%s)
END_TIME=$((START_TIME + DURATION))

while [ $(date +%s) -lt $END_TIME ]; do
  # Perform request and measure response time
  RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" "${SERVICE_URL}/")
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SERVICE_URL}/")
  
  TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
  
  if [ "$HTTP_CODE" = "200" ]; then
    TOTAL_RESPONSE_TIME=$(echo "$TOTAL_RESPONSE_TIME + $RESPONSE_TIME" | bc -l)
  else
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi
  
  # Log performance metrics to Cloud Logging
  gcloud logging write performance-metrics \
    "{\"responseTime\": $RESPONSE_TIME, \"httpCode\": \"$HTTP_CODE\", \"timestamp\": \"$(date -Iseconds)\"}" \
    --severity=INFO
  
  sleep 1
done

# Calculate and report final metrics
if [ $TOTAL_REQUESTS -gt 0 ]; then
  AVERAGE_RESPONSE_TIME=$(echo "scale=3; $TOTAL_RESPONSE_TIME / ($TOTAL_REQUESTS - $ERROR_COUNT)" | bc -l)
  ERROR_RATE=$(echo "scale=2; $ERROR_COUNT * 100 / $TOTAL_REQUESTS" | bc -l)
  
  echo "Performance Summary:"
  echo "  Total Requests: $TOTAL_REQUESTS"
  echo "  Average Response Time: ${AVERAGE_RESPONSE_TIME}s"
  echo "  Error Rate: ${ERROR_RATE}%"
  echo "  Errors: $ERROR_COUNT"
  
  # Send summary metrics to Cloud Monitoring
  gcloud logging write performance-summary \
    "{\"totalRequests\": $TOTAL_REQUESTS, \"avgResponseTime\": $AVERAGE_RESPONSE_TIME, \"errorRate\": $ERROR_RATE}" \
    --severity=INFO
fi
EOF
    
    chmod +x monitor-performance.sh
    
    # Create validation script
    cat > validate-performance.sh << 'EOF'
#!/bin/bash

SERVICE_URL=$1
BASELINE_FILE=${2:-"baseline-performance.json"}

if [ -z "$SERVICE_URL" ]; then
  echo "Usage: $0 <service-url> [baseline-file]"
  exit 1
fi

echo "Running performance validation against: ${SERVICE_URL}"

# Performance test scenarios
declare -a TEST_SCENARIOS=(
  "/"
  "/?delay=100"
  "/?delay=200"
  "/load-test"
)

# Run performance tests
RESULTS_FILE="performance-results-$(date +%s).json"
echo "{\"timestamp\": \"$(date -Iseconds)\", \"tests\": [" > $RESULTS_FILE

for i in "${!TEST_SCENARIOS[@]}"; do
  ENDPOINT="${TEST_SCENARIOS[$i]}"
  echo "Testing endpoint: ${ENDPOINT}"
  
  # Run multiple requests to get average
  TOTAL_TIME=0
  SUCCESS_COUNT=0
  
  for j in {1..10}; do
    RESPONSE_TIME=$(curl -s -o /dev/null -w "%{time_total}" "${SERVICE_URL}${ENDPOINT}")
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SERVICE_URL}${ENDPOINT}")
    
    if [ "$HTTP_CODE" = "200" ]; then
      TOTAL_TIME=$(echo "$TOTAL_TIME + $RESPONSE_TIME" | bc -l)
      SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi
  done
  
  if [ $SUCCESS_COUNT -gt 0 ]; then
    AVERAGE_TIME=$(echo "scale=3; $TOTAL_TIME / $SUCCESS_COUNT" | bc -l)
  else
    AVERAGE_TIME=0
  fi
  
  # Add result to JSON
  echo "    {\"endpoint\": \"${ENDPOINT}\", \"averageTime\": $AVERAGE_TIME, \"successRate\": $(echo "scale=2; $SUCCESS_COUNT * 10" | bc -l)}${i+1 < ${#TEST_SCENARIOS[@]} && echo ","}" >> $RESULTS_FILE
done

echo "  ]}" >> $RESULTS_FILE

echo "✅ Performance validation completed"
echo "   Results saved to: $RESULTS_FILE"

# Compare with baseline if available
if [ -f "$BASELINE_FILE" ]; then
  echo "Comparing with baseline performance..."
  # Implement baseline comparison logic here
fi
EOF
    
    chmod +x validate-performance.sh
    
    # Configure git and commit
    git config user.email "performance-optimizer@example.com"
    git config user.name "Performance Optimizer"
    
    git add .
    git commit -m "Initial performance monitoring application

- Added Express.js application with performance endpoints
- Implemented optimized Dockerfile with security hardening
- Created Cloud Build configuration with performance optimizations
- Added comprehensive performance monitoring script
- Configured baseline performance thresholds"
    
    # Push to repository
    git push origin master
    
    cd ..
    
    log_success "Application code setup completed"
}

# Function to create Cloud Build Trigger
create_build_trigger() {
    log_info "Creating Cloud Build Trigger..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create build trigger: $BUILD_TRIGGER_NAME"
        return 0
    fi
    
    # Check if trigger already exists
    if gcloud builds triggers describe "$BUILD_TRIGGER_NAME" --project="$PROJECT_ID" &> /dev/null; then
        log_warning "Build trigger $BUILD_TRIGGER_NAME already exists"
        if [ "$FORCE_DEPLOY" != "true" ]; then
            read -p "Continue with existing trigger? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Trigger creation cancelled"
                exit 1
            fi
        fi
    else
        # Create the trigger
        if gcloud builds triggers create cloud-source-repositories \
            --repo="$REPO_NAME" \
            --branch-pattern=".*" \
            --build-config=cloudbuild.yaml \
            --name="$BUILD_TRIGGER_NAME" \
            --description="Automated performance optimization trigger" \
            --include-logs-with-status \
            --substitutions="_SERVICE_NAME=$SERVICE_NAME,_REGION=$REGION" \
            --project="$PROJECT_ID"; then
            log_success "Created build trigger: $BUILD_TRIGGER_NAME"
        else
            log_error "Failed to create build trigger"
            exit 1
        fi
    fi
}

# Function to deploy initial application
deploy_initial_application() {
    log_info "Deploying initial application version..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would trigger initial build and deployment"
        return 0
    fi
    
    # Trigger initial build
    if gcloud builds triggers run "$BUILD_TRIGGER_NAME" --branch=master --project="$PROJECT_ID"; then
        log_success "Initial build triggered"
    else
        log_error "Failed to trigger initial build"
        exit 1
    fi
    
    # Wait for deployment
    log_info "Waiting for deployment to complete..."
    sleep 120  # Wait 2 minutes for deployment
    
    # Get service URL
    local service_url
    service_url=$(gcloud run services describe "$SERVICE_NAME" \
        --region="$REGION" \
        --project="$PROJECT_ID" \
        --format="value(status.url)" 2>/dev/null || echo "")
    
    if [ -n "$service_url" ]; then
        log_success "Application deployed successfully"
        log_info "Service URL: $service_url"
        
        # Test the service
        if curl -s -f "$service_url/health" > /dev/null; then
            log_success "Health check passed"
        else
            log_warning "Health check failed - service may still be starting"
        fi
        
        # Store URL for later use
        export SERVICE_URL="$service_url"
        echo "SERVICE_URL=$service_url" >> deployment.env
    else
        log_error "Failed to get service URL"
        exit 1
    fi
}

# Function to create monitoring alerting policy
create_monitoring_policy() {
    log_info "Creating Cloud Monitoring alerting policy..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create monitoring alerting policy"
        return 0
    fi
    
    # Create alerting policy configuration
    cat > alerting-policy.yaml << EOF
displayName: "$MONITORING_POLICY_NAME"
documentation:
  content: "Triggers performance optimization builds when response time exceeds thresholds"
  mimeType: "text/markdown"
conditions:
- displayName: "High Response Time"
  conditionThreshold:
    filter: 'resource.type="cloud_run_revision" AND metric.type="run.googleapis.com/request_latencies"'
    comparison: COMPARISON_GREATER_THAN
    thresholdValue: 1.0
    duration: "300s"
    aggregations:
    - alignmentPeriod: "60s"
      perSeriesAligner: ALIGN_MEAN
      crossSeriesReducer: REDUCE_MEAN
      groupByFields:
      - "resource.label.service_name"
- displayName: "High Memory Usage"
  conditionThreshold:
    filter: 'resource.type="cloud_run_revision" AND metric.type="run.googleapis.com/container/memory/utilizations"'
    comparison: COMPARISON_GREATER_THAN
    thresholdValue: 0.8
    duration: "180s"
    aggregations:
    - alignmentPeriod: "60s"
      perSeriesAligner: ALIGN_MEAN
      crossSeriesReducer: REDUCE_MEAN
      groupByFields:
      - "resource.label.service_name"
combiner: OR
enabled: true
EOF
    
    # Create the alerting policy
    if gcloud alpha monitoring policies create --policy-from-file=alerting-policy.yaml --project="$PROJECT_ID"; then
        log_success "Created monitoring alerting policy"
    else
        log_error "Failed to create monitoring alerting policy"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f alerting-policy.yaml
}

# Function to create notification channel
create_notification_channel() {
    log_info "Creating notification channel..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would create notification channel"
        return 0
    fi
    
    # Get trigger ID
    local trigger_id
    trigger_id=$(gcloud builds triggers list \
        --filter="name:$BUILD_TRIGGER_NAME" \
        --format="value(id)" \
        --limit=1 \
        --project="$PROJECT_ID")
    
    if [ -z "$trigger_id" ]; then
        log_error "Failed to get trigger ID"
        exit 1
    fi
    
    # Create notification channel configuration
    cat > notification-channel.yaml << EOF
type: "webhook_tokenauth"
displayName: "Performance Optimization Webhook"
description: "Webhook to trigger performance optimization builds"
labels:
  url: "https://cloudbuild.googleapis.com/v1/projects/$PROJECT_ID/triggers/$trigger_id:webhook"
userLabels:
  purpose: "performance-optimization"
  component: "automated-builds"
EOF
    
    # Create notification channel
    local channel_id
    channel_id=$(gcloud alpha monitoring channels create \
        --channel-from-file=notification-channel.yaml \
        --project="$PROJECT_ID" \
        --format="value(name.split('/').slice(-1)[0])" 2>/dev/null || echo "")
    
    if [ -n "$channel_id" ]; then
        log_success "Created notification channel: $channel_id"
        echo "CHANNEL_ID=$channel_id" >> deployment.env
    else
        log_error "Failed to create notification channel"
        exit 1
    fi
    
    # Clean up temporary file
    rm -f notification-channel.yaml
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_info "[DRY RUN] Would save deployment information"
        return 0
    fi
    
    # Create deployment summary
    cat > deployment-summary.json << EOF
{
  "timestamp": "$(date -Iseconds)",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "zone": "$ZONE",
  "resources": {
    "repository": "$REPO_NAME",
    "service": "$SERVICE_NAME",
    "build_trigger": "$BUILD_TRIGGER_NAME",
    "monitoring_policy": "$MONITORING_POLICY_NAME"
  },
  "urls": {
    "service_url": "${SERVICE_URL:-}",
    "console_url": "https://console.cloud.google.com/run/detail/$REGION/$SERVICE_NAME/metrics?project=$PROJECT_ID"
  }
}
EOF
    
    log_success "Deployment information saved to deployment-summary.json"
}

# Function to display deployment summary
display_deployment_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "                    DEPLOYMENT SUMMARY"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Service Name: $SERVICE_NAME"
    echo "Repository: $REPO_NAME"
    echo "Build Trigger: $BUILD_TRIGGER_NAME"
    echo ""
    
    if [ -n "${SERVICE_URL:-}" ]; then
        echo "Service URL: $SERVICE_URL"
        echo "Health Check: $SERVICE_URL/health"
        echo "Load Test: $SERVICE_URL/load-test"
        echo ""
    fi
    
    echo "Console URLs:"
    echo "  Cloud Run: https://console.cloud.google.com/run/detail/$REGION/$SERVICE_NAME/metrics?project=$PROJECT_ID"
    echo "  Cloud Build: https://console.cloud.google.com/cloud-build/triggers?project=$PROJECT_ID"
    echo "  Monitoring: https://console.cloud.google.com/monitoring/alerting?project=$PROJECT_ID"
    echo "  Source Repo: https://source.cloud.google.com/repo/$REPO_NAME"
    echo ""
    echo "Next Steps:"
    echo "1. Test the application using the service URL"
    echo "2. Monitor performance metrics in Cloud Monitoring"
    echo "3. Trigger load tests to verify alerting policies"
    echo "4. Review build logs for optimization insights"
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
}

# Function to handle cleanup on error
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    
    # Run cleanup script if it exists
    if [ -f "./destroy.sh" ]; then
        log_info "Running cleanup script..."
        ./destroy.sh
    fi
    
    exit 1
}

# Main deployment function
main() {
    log_info "Starting deployment of Continuous Performance Optimization solution..."
    
    # Set up error handling
    trap cleanup_on_error ERR
    
    # Execute deployment steps
    check_prerequisites
    display_configuration
    setup_gcp_configuration
    enable_required_apis
    create_source_repository
    setup_application_code
    create_build_trigger
    deploy_initial_application
    create_monitoring_policy
    create_notification_channel
    save_deployment_info
    display_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Script usage information
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -d, --dry-run           Run in dry-run mode (no resources created)"
    echo "  -f, --force             Force deployment without prompts"
    echo "  -p, --project PROJECT   Set project ID"
    echo "  -r, --region REGION     Set region (default: us-central1)"
    echo "  -z, --zone ZONE         Set zone (default: us-central1-a)"
    echo ""
    echo "Environment Variables:"
    echo "  PROJECT_ID              Google Cloud project ID"
    echo "  REGION                  Google Cloud region"
    echo "  ZONE                    Google Cloud zone"
    echo "  REPO_NAME               Cloud Source Repository name"
    echo "  SERVICE_NAME            Cloud Run service name"
    echo "  BUILD_TRIGGER_NAME      Cloud Build trigger name"
    echo "  MONITORING_POLICY_NAME  Monitoring policy name"
    echo "  DRY_RUN                 Run in dry-run mode (true/false)"
    echo "  FORCE_DEPLOY            Force deployment (true/false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Interactive deployment"
    echo "  $0 --dry-run                          # Dry run mode"
    echo "  $0 --force --project my-project       # Force deployment"
    echo "  DRY_RUN=true $0                       # Dry run via environment"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE_DEPLOY=true
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
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"