#!/bin/bash

# Global Web Application Performance with Firebase App Hosting and Cloud CDN - Deployment Script
# This script deploys a complete web application performance optimization solution using
# Firebase App Hosting, Cloud CDN, Cloud Monitoring, and Cloud Functions

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
handle_error() {
    log_error "Deployment failed at line $1"
    log_error "Rolling back any created resources..."
    cleanup_on_error
    exit 1
}

trap 'handle_error $LINENO' ERR

# Configuration variables
PROJECT_ID=""
REGION="us-central1"
GITHUB_REPO=""
BUCKET_NAME=""
FUNCTION_NAME=""
GLOBAL_IP=""
DRY_RUN=false
SKIP_GITHUB=false

# Usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Global Web Application Performance solution with Firebase App Hosting and Cloud CDN

OPTIONS:
    -p, --project-id PROJECT_ID     Google Cloud Project ID (required)
    -r, --region REGION            Deployment region (default: us-central1)
    -g, --github-repo REPO         GitHub repository (format: username/repo)
    -b, --bucket-name NAME         Custom bucket name (optional)
    -f, --function-name NAME       Custom function name (optional)
    --dry-run                      Show what would be deployed without executing
    --skip-github                  Skip GitHub integration setup
    -h, --help                     Show this help message

EXAMPLES:
    $0 -p my-project -g myuser/webapp-repo
    $0 --project-id my-project --region europe-west1 --github-repo myuser/webapp
    $0 -p my-project --skip-github --dry-run

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
            -g|--github-repo)
                GITHUB_REPO="$2"
                shift 2
                ;;
            -b|--bucket-name)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-github)
                SKIP_GITHUB=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use -p or --project-id"
        show_usage
        exit 1
    fi

    if [[ "$SKIP_GITHUB" == false && -z "$GITHUB_REPO" ]]; then
        log_error "GitHub repository is required when GitHub integration is enabled."
        log_error "Use -g/--github-repo or --skip-github to skip GitHub integration."
        show_usage
        exit 1
    fi

    # Generate unique suffixes if not provided
    local random_suffix=$(openssl rand -hex 3)
    BUCKET_NAME="${BUCKET_NAME:-web-assets-${random_suffix}}"
    FUNCTION_NAME="${FUNCTION_NAME:-perf-optimizer-${random_suffix}}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check required tools
    local required_tools=("gcloud" "firebase" "npm" "curl" "openssl")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "$tool is required but not installed"
            exit 1
        fi
    done

    # Check gcloud authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "No active gcloud authentication found. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check Firebase CLI authentication
    if ! firebase list &> /dev/null; then
        log_error "Firebase CLI not authenticated. Please run 'firebase login'"
        exit 1
    fi

    # Check Node.js version
    local node_version=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ $node_version -lt 18 ]]; then
        log_error "Node.js 18+ is required. Current version: $(node --version)"
        exit 1
    fi

    # Validate project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project $PROJECT_ID does not exist or is not accessible"
        exit 1
    fi

    log_success "Prerequisites check completed"
}

# Setup project configuration
setup_project() {
    log_info "Setting up project configuration..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would configure project: $PROJECT_ID"
        log_info "[DRY RUN] Would set region: $REGION"
        return 0
    fi

    # Set active project and region
    gcloud config set project "$PROJECT_ID"
    gcloud config set compute/region "$REGION"

    # Enable required APIs with progress tracking
    local apis=(
        "firebase.googleapis.com"
        "firebasehosting.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
        "compute.googleapis.com"
        "monitoring.googleapis.com"
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
    )

    log_info "Enabling required APIs..."
    for api in "${apis[@]}"; do
        log_info "  Enabling $api..."
        gcloud services enable "$api" --quiet
    done

    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30

    log_success "Project configuration completed"
}

# Initialize Firebase project
setup_firebase() {
    log_info "Setting up Firebase project..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would initialize Firebase project: $PROJECT_ID"
        return 0
    fi

    # Set Firebase project
    firebase use --add "$PROJECT_ID" --alias default

    # Create firebase.json configuration
    cat > firebase.json << 'EOF'
{
  "hosting": {
    "public": "out",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ],
    "headers": [
      {
        "source": "**/*.@(js|css|png|jpg|jpeg|webp|avif|svg|ico|woff2)",
        "headers": [
          {
            "key": "Cache-Control",
            "value": "public, max-age=31536000, immutable"
          }
        ]
      }
    ]
  }
}
EOF

    log_success "Firebase project initialized"
}

# Create sample web application
create_web_application() {
    log_info "Creating optimized web application..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create Next.js application with performance optimizations"
        return 0
    fi

    # Create web application directory
    mkdir -p web-app
    cd web-app

    # Create Next.js application
    log_info "Creating Next.js application..."
    npx create-next-app@latest . --typescript --tailwind --eslint --app --yes

    # Install performance optimization dependencies
    log_info "Installing performance optimization packages..."
    npm install --save @vercel/analytics @next/bundle-analyzer

    # Create optimized Next.js configuration
    cat > next.config.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  output: 'standalone',
  experimental: {
    optimizeCss: true,
    optimizePackageImports: ['@/components']
  },
  images: {
    formats: ['image/webp', 'image/avif'],
    deviceSizes: [640, 750, 828, 1080, 1200, 1920, 2048, 3840],
    imageSizes: [16, 32, 48, 64, 96, 128, 256, 384]
  }
};

module.exports = nextConfig;
EOF

    # Build the application
    log_info "Building optimized application..."
    npm run build

    cd ..
    log_success "Web application created and built"
}

# Setup Cloud Storage
setup_cloud_storage() {
    log_info "Setting up Cloud Storage for static assets..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create bucket: $BUCKET_NAME"
        log_info "[DRY RUN] Would configure CORS and public access"
        return 0
    fi

    # Create Cloud Storage bucket
    gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"

    # Enable versioning
    gsutil versioning set on "gs://$BUCKET_NAME"

    # Configure CORS
    cat > cors.json << 'EOF'
[
  {
    "origin": ["*"],
    "method": ["GET", "HEAD"],
    "responseHeader": ["Content-Type", "Cache-Control"],
    "maxAgeSeconds": 3600
  }
]
EOF

    gsutil cors set cors.json "gs://$BUCKET_NAME"
    rm cors.json

    # Set public read permissions
    gsutil iam ch allUsers:objectViewer "gs://$BUCKET_NAME"

    log_success "Cloud Storage bucket configured: $BUCKET_NAME"
}

# Setup Firebase App Hosting
setup_app_hosting() {
    log_info "Setting up Firebase App Hosting..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create Firebase App Hosting backend"
        if [[ "$SKIP_GITHUB" == false ]]; then
            log_info "[DRY RUN] Would connect to GitHub repository: $GITHUB_REPO"
        fi
        return 0
    fi

    if [[ "$SKIP_GITHUB" == false ]]; then
        # Create Firebase App Hosting backend with GitHub integration
        log_info "Creating App Hosting backend with GitHub integration..."
        firebase apphosting:backends:create \
            --project="$PROJECT_ID" \
            --location="$REGION" \
            --service-id=web-app-backend \
            --github-repo="$GITHUB_REPO" \
            --non-interactive
    else
        log_warning "Skipping GitHub integration. Manual deployment will be required."
    fi

    log_success "Firebase App Hosting configured"
}

# Setup Cloud CDN and Load Balancer
setup_cdn_load_balancer() {
    log_info "Setting up Cloud CDN and Load Balancer..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create global IP address"
        log_info "[DRY RUN] Would create backend bucket for: $BUCKET_NAME"
        log_info "[DRY RUN] Would create URL map and load balancer"
        return 0
    fi

    # Create global IP address
    log_info "Creating global IP address..."
    gcloud compute addresses create web-app-ip --global --project="$PROJECT_ID"

    # Get the allocated IP address
    GLOBAL_IP=$(gcloud compute addresses describe web-app-ip --global --format="get(address)")
    log_info "Global IP allocated: $GLOBAL_IP"

    # Create backend bucket for static assets
    log_info "Creating backend bucket..."
    gcloud compute backend-buckets create web-assets-backend \
        --gcs-bucket-name="$BUCKET_NAME" \
        --enable-cdn \
        --cache-mode=CACHE_ALL_STATIC \
        --default-ttl=3600 \
        --max-ttl=86400 \
        --project="$PROJECT_ID"

    # Create URL map for traffic routing
    log_info "Creating URL map..."
    gcloud compute url-maps create web-app-urlmap \
        --default-backend-bucket=web-assets-backend \
        --project="$PROJECT_ID"

    # Create SSL certificate (self-managed for demo)
    log_info "Creating SSL certificate..."
    gcloud compute ssl-certificates create web-app-ssl-cert \
        --domains="$GLOBAL_IP.nip.io" \
        --global \
        --project="$PROJECT_ID"

    # Create target HTTPS proxy
    log_info "Creating HTTPS proxy..."
    gcloud compute target-https-proxies create web-app-proxy \
        --url-map=web-app-urlmap \
        --ssl-certificates=web-app-ssl-cert \
        --project="$PROJECT_ID"

    # Create forwarding rule
    log_info "Creating forwarding rule..."
    gcloud compute forwarding-rules create web-app-forwarding-rule \
        --address="$GLOBAL_IP" \
        --global \
        --target-https-proxy=web-app-proxy \
        --ports=443 \
        --project="$PROJECT_ID"

    log_success "Cloud CDN and Load Balancer configured"
}

# Setup Cloud Monitoring
setup_monitoring() {
    log_info "Setting up Cloud Monitoring..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create monitoring dashboard and alerting policies"
        return 0
    fi

    # Create alerting policy for high latency
    cat > alerting-policy.json << EOF
{
  "displayName": "High Latency Alert",
  "conditions": [
    {
      "displayName": "High response time",
      "conditionThreshold": {
        "filter": "resource.type=\"gae_app\" AND metric.type=\"appengine.googleapis.com/http/server/response_latencies\"",
        "comparison": "COMPARISON_GT",
        "thresholdValue": 1000,
        "duration": "300s"
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "enabled": true
}
EOF

    # Create the alerting policy
    gcloud alpha monitoring policies create --policy-from-file=alerting-policy.json
    rm alerting-policy.json

    log_success "Cloud Monitoring configured"
}

# Deploy performance optimization function
deploy_optimization_function() {
    log_info "Deploying performance optimization Cloud Function..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would deploy Cloud Function: $FUNCTION_NAME"
        return 0
    fi

    # Create function directory
    mkdir -p performance-optimizer
    cd performance-optimizer

    # Create function code
    cat > main.py << 'EOF'
import json
import logging
import os
import time
from google.cloud import monitoring_v3
from google.cloud import compute_v1

def optimize_performance(request):
    """Analyze performance metrics and optimize CDN settings"""
    
    project_id = os.environ.get('GCP_PROJECT')
    if not project_id:
        return {'status': 'error', 'message': 'GCP_PROJECT environment variable not set'}
    
    # Initialize monitoring client
    client = monitoring_v3.MetricServiceClient()
    project_name = f"projects/{project_id}"
    
    # Query CDN performance metrics
    interval = monitoring_v3.TimeInterval({
        "end_time": {"seconds": int(time.time())},
        "start_time": {"seconds": int(time.time()) - 3600}
    })
    
    try:
        # Analyze cache hit rates and suggest optimizations
        results = client.list_time_series(
            name=project_name,
            filter='metric.type="loadbalancing.googleapis.com/https/request_count"',
            interval=interval
        )
        
        # Implement optimization logic based on metrics
        optimizations = []
        
        for result in results:
            cache_hit_rate = calculate_cache_hit_rate(result)
            if cache_hit_rate < 0.8:
                optimizations.append({
                    'action': 'increase_ttl',
                    'resource': result.resource.labels.get('backend_target_name', 'unknown'),
                    'recommendation': 'Increase cache TTL to improve hit rate'
                })
        
        return {
            'status': 'success',
            'optimizations': optimizations,
            'timestamp': int(time.time()),
            'analyzed_metrics': len(list(results))
        }
    
    except Exception as e:
        logging.error(f"Error optimizing performance: {str(e)}")
        return {
            'status': 'error',
            'message': str(e),
            'timestamp': int(time.time())
        }

def calculate_cache_hit_rate(metrics):
    """Calculate cache hit rate from monitoring data"""
    # Simplified calculation for demonstration
    # In production, this would analyze actual time series data
    return 0.85
EOF

    # Create requirements file
    cat > requirements.txt << 'EOF'
google-cloud-monitoring==2.14.1
google-cloud-compute==1.11.0
functions-framework==3.5.0
EOF

    # Create Pub/Sub topic for function trigger
    gcloud pubsub topics create performance-metrics --project="$PROJECT_ID" || true

    # Deploy the optimization function
    log_info "Deploying Cloud Function..."
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime=python39 \
        --trigger-topic=performance-metrics \
        --entry-point=optimize_performance \
        --memory=256MB \
        --timeout=60s \
        --set-env-vars="GCP_PROJECT=$PROJECT_ID" \
        --project="$PROJECT_ID" \
        --region="$REGION"

    cd ..
    log_success "Performance optimization function deployed: $FUNCTION_NAME"
}

# Cleanup on error
cleanup_on_error() {
    log_warning "Performing emergency cleanup..."
    
    # Note: This is a basic cleanup - full cleanup should use destroy.sh
    if [[ -n "$FUNCTION_NAME" ]]; then
        gcloud functions delete "$FUNCTION_NAME" --region="$REGION" --quiet || true
    fi
    
    if [[ -n "$BUCKET_NAME" ]]; then
        gsutil -m rm -rf "gs://$BUCKET_NAME" || true
    fi
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would verify all resources are deployed correctly"
        return 0
    fi

    local verification_passed=true

    # Check Cloud Storage bucket
    if gsutil ls "gs://$BUCKET_NAME" &> /dev/null; then
        log_success "✓ Cloud Storage bucket verified: $BUCKET_NAME"
    else
        log_error "✗ Cloud Storage bucket verification failed"
        verification_passed=false
    fi

    # Check global IP
    if gcloud compute addresses describe web-app-ip --global &> /dev/null; then
        log_success "✓ Global IP address verified: $GLOBAL_IP"
    else
        log_error "✗ Global IP address verification failed"
        verification_passed=false
    fi

    # Check Cloud Function
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" &> /dev/null; then
        log_success "✓ Cloud Function verified: $FUNCTION_NAME"
    else
        log_error "✗ Cloud Function verification failed"
        verification_passed=false
    fi

    # Check Firebase project
    if firebase projects:list | grep -q "$PROJECT_ID"; then
        log_success "✓ Firebase project verified: $PROJECT_ID"
    else
        log_error "✗ Firebase project verification failed"
        verification_passed=false
    fi

    if [[ "$verification_passed" == true ]]; then
        log_success "All resources verified successfully!"
    else
        log_error "Some resources failed verification. Check the logs above."
        return 1
    fi
}

# Display deployment summary
show_deployment_summary() {
    log_info "Deployment Summary"
    echo "==================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Bucket Name: $BUCKET_NAME"
    echo "Function Name: $FUNCTION_NAME"
    if [[ -n "$GLOBAL_IP" ]]; then
        echo "Global IP: $GLOBAL_IP"
        echo "Application URL: https://$GLOBAL_IP.nip.io"
    fi
    if [[ "$SKIP_GITHUB" == false && -n "$GITHUB_REPO" ]]; then
        echo "GitHub Repository: $GITHUB_REPO"
    fi
    echo ""
    log_success "Deployment completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "1. Upload static assets to Cloud Storage bucket: gs://$BUCKET_NAME"
    echo "2. Configure your domain DNS to point to: $GLOBAL_IP"
    echo "3. Monitor performance in Cloud Monitoring console"
    if [[ "$SKIP_GITHUB" == false ]]; then
        echo "4. Push code to GitHub repository to trigger automatic deployment"
    else
        echo "4. Manually deploy your application to Firebase App Hosting"
    fi
}

# Main deployment function
main() {
    log_info "Starting Global Web Application Performance deployment..."
    
    parse_args "$@"
    check_prerequisites
    setup_project
    setup_firebase
    create_web_application
    setup_cloud_storage
    setup_app_hosting
    setup_cdn_load_balancer
    setup_monitoring
    deploy_optimization_function
    verify_deployment
    show_deployment_summary
}

# Execute main function with all arguments
main "$@"