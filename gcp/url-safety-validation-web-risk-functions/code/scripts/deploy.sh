#!/bin/bash

# URL Safety Validation with Web Risk API - Deployment Script
# This script deploys a complete URL safety validation system using GCP services
# 
# Services deployed:
# - Cloud Functions (URL validation endpoint)
# - Web Risk API (threat detection)
# - Cloud Storage (audit logs and caching)
# - IAM (service account permissions)

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$ERROR_LOG"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Cleanup function for failed deployments
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    if [[ -n "${FUNCTION_NAME:-}" ]]; then
        gcloud functions delete "${FUNCTION_NAME}" --region="${REGION}" --quiet 2>/dev/null || true
    fi
    if [[ -n "${BUCKET_NAME:-}" ]]; then
        gsutil -m rm -r "gs://${BUCKET_NAME}" 2>/dev/null || true
    fi
    if [[ -n "${CACHE_BUCKET:-}" ]]; then
        gsutil -m rm -r "gs://${CACHE_BUCKET}" 2>/dev/null || true
    fi
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
URL Safety Validation Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -n, --function-name NAME      Function name (default: auto-generated)
    -d, --dry-run                 Show what would be deployed without executing
    -f, --force                   Skip confirmation prompts
    -h, --help                    Show this help message

EXAMPLES:
    $0 --project-id my-project
    $0 --project-id my-project --region us-east1 --function-name my-validator
    $0 --project-id my-project --dry-run

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT          Alternative way to specify project ID
    GCP_REGION                    Alternative way to specify region

PREREQUISITES:
    - gcloud CLI installed and authenticated
    - Billing enabled on the project
    - Required APIs enabled (or script will enable them)
    - Appropriate IAM permissions

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
            -n|--function-name)
                FUNCTION_NAME_OVERRIDE="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Initialize variables with defaults
init_variables() {
    # Set defaults
    PROJECT_ID="${PROJECT_ID:-${GOOGLE_CLOUD_PROJECT:-}}"
    REGION="${REGION:-${GCP_REGION:-us-central1}}"
    ZONE="${REGION}-a"
    DRY_RUN="${DRY_RUN:-false}"
    FORCE="${FORCE:-false}"
    
    # Generate unique identifiers
    TIMESTAMP=$(date +%s)
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Resource names
    if [[ -n "${FUNCTION_NAME_OVERRIDE:-}" ]]; then
        FUNCTION_NAME="${FUNCTION_NAME_OVERRIDE}"
    else
        FUNCTION_NAME="url-validator-${RANDOM_SUFFIX}"
    fi
    
    BUCKET_NAME="url-validation-logs-${PROJECT_ID}-${RANDOM_SUFFIX}"
    CACHE_BUCKET="url-validation-cache-${PROJECT_ID}-${RANDOM_SUFFIX}"
    
    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
        show_help
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        error "Project $PROJECT_ID does not exist or you don't have access."
        exit 1
    fi
    
    # Check billing
    if ! gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingEnabled)" | grep -q "True"; then
        warn "Billing may not be enabled for project $PROJECT_ID. Some services may not work."
    fi
    
    success "Prerequisites check completed"
}

# Show deployment plan
show_deployment_plan() {
    cat << EOF

${BLUE}═══════════════════════════════════════════════════════════════${NC}
${BLUE}                    DEPLOYMENT PLAN                           ${NC}
${BLUE}═══════════════════════════════════════════════════════════════${NC}

Project ID:           ${PROJECT_ID}
Region:               ${REGION}
Zone:                 ${ZONE}

Resources to be created:
${GREEN}✓${NC} Cloud Function:      ${FUNCTION_NAME}
${GREEN}✓${NC} Audit Bucket:       ${BUCKET_NAME}
${GREEN}✓${NC} Cache Bucket:       ${CACHE_BUCKET}
${GREEN}✓${NC} IAM Permissions:    Web Risk API & Storage access

APIs to be enabled:
${GREEN}✓${NC} Cloud Functions API
${GREEN}✓${NC} Web Risk API  
${GREEN}✓${NC} Cloud Storage API
${GREEN}✓${NC} Cloud Build API

Estimated costs:
${GREEN}✓${NC} Cloud Functions:    $0.40 per 1M requests
${GREEN}✓${NC} Web Risk API:       $1.00 per 1K requests
${GREEN}✓${NC} Cloud Storage:      $0.020 per GB/month
${GREEN}✓${NC} Cloud Build:        $0.003 per build minute

${BLUE}═══════════════════════════════════════════════════════════════${NC}

EOF
}

# Confirm deployment
confirm_deployment() {
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo -n "Do you want to proceed with the deployment? (y/N): "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        info "Deployment cancelled by user"
        exit 0
    fi
}

# Set gcloud configuration
configure_gcloud() {
    log "Configuring gcloud settings..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set compute/region "$REGION"
        gcloud config set compute/zone "$ZONE"
    fi
    
    success "gcloud configuration updated"
}

# Enable required APIs
enable_apis() {
    log "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "webrisk.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if [[ "$DRY_RUN" == "false" ]]; then
            log "Enabling $api..."
            if gcloud services enable "$api" --project="$PROJECT_ID"; then
                success "Enabled $api"
            else
                error "Failed to enable $api"
                exit 1
            fi
        else
            info "Would enable $api"
        fi
    done
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    success "All required APIs enabled"
}

# Create Cloud Storage buckets
create_storage_buckets() {
    log "Creating Cloud Storage buckets..."
    
    # Create audit logs bucket
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Creating audit logs bucket: $BUCKET_NAME"
        if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME"; then
            gsutil versioning set on "gs://$BUCKET_NAME"
            success "Created audit logs bucket with versioning enabled"
        else
            error "Failed to create audit logs bucket"
            exit 1
        fi
    else
        info "Would create audit logs bucket: $BUCKET_NAME"
    fi
    
    # Create cache bucket
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Creating cache bucket: $CACHE_BUCKET"
        if gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$CACHE_BUCKET"; then
            # Set lifecycle policy for cache bucket
            cat > /tmp/lifecycle.json << 'EOF'
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
            gsutil lifecycle set /tmp/lifecycle.json "gs://$CACHE_BUCKET"
            rm /tmp/lifecycle.json
            success "Created cache bucket with 30-day lifecycle policy"
        else
            error "Failed to create cache bucket"
            exit 1
        fi
    else
        info "Would create cache bucket: $CACHE_BUCKET"
    fi
    
    success "Storage buckets created successfully"
}

# Create Cloud Function
create_cloud_function() {
    log "Creating Cloud Function..."
    
    # Create function directory
    local function_dir="/tmp/url-validator-${RANDOM_SUFFIX}"
    mkdir -p "$function_dir"
    
    # Create requirements.txt
    cat > "$function_dir/requirements.txt" << 'EOF'
google-cloud-webrisk==1.15.0
google-cloud-storage==2.16.0
functions-framework==3.6.0
requests==2.31.0
urllib3==2.2.1
EOF
    
    # Create main.py
    cat > "$function_dir/main.py" << 'EOF'
import functions_framework
from google.cloud import webrisk_v1
from google.cloud import storage
import json
import hashlib
import urllib.parse
from datetime import datetime, timezone
import logging
import os

# Initialize clients
webrisk_client = webrisk_v1.WebRiskServiceClient()
storage_client = storage.Client()

def get_url_hash(url):
    """Generate SHA256 hash for URL caching"""
    return hashlib.sha256(url.encode('utf-8')).hexdigest()

def check_cache(url_hash, cache_bucket):
    """Check if URL validation result exists in cache"""
    try:
        bucket = storage_client.bucket(cache_bucket)
        blob = bucket.blob(f"cache/{url_hash}.json")
        if blob.exists():
            cache_data = json.loads(blob.download_as_text())
            # Check if cache is still valid (24 hours)
            cache_time = datetime.fromisoformat(
                cache_data['timestamp'].replace('Z', '+00:00')
            )
            now = datetime.now(timezone.utc)
            if (now - cache_time).total_seconds() < 86400:  # 24 hours
                return cache_data['result']
    except Exception as e:
        logging.warning(f"Cache check failed: {e}")
    return None

def store_cache(url_hash, result, cache_bucket):
    """Store validation result in cache"""
    try:
        bucket = storage_client.bucket(cache_bucket)
        blob = bucket.blob(f"cache/{url_hash}.json")
        cache_data = {
            'result': result,
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        blob.upload_from_string(json.dumps(cache_data))
    except Exception as e:
        logging.error(f"Cache storage failed: {e}")

def log_validation(url, result, audit_bucket):
    """Log validation result for audit purposes"""
    try:
        bucket = storage_client.bucket(audit_bucket)
        timestamp = datetime.now(timezone.utc).isoformat()
        filename = f"audit/{datetime.now().strftime('%Y/%m/%d')}/{timestamp}-{get_url_hash(url)[:8]}.json"
        blob = bucket.blob(filename)
        
        audit_data = {
            'timestamp': timestamp,
            'url': url,
            'result': result,
            'source_ip': 'cloud-function',
            'user_agent': 'url-validator-function'
        }
        blob.upload_from_string(json.dumps(audit_data, indent=2))
    except Exception as e:
        logging.error(f"Audit logging failed: {e}")

@functions_framework.http
def validate_url(request):
    """Main Cloud Function entry point for URL validation"""
    
    # Handle CORS for web clients
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    if request.method != 'POST':
        return ({'error': 'Only POST method supported'}, 405, headers)
    
    try:
        # Parse request data
        request_json = request.get_json()
        if not request_json or 'url' not in request_json:
            return ({'error': 'URL parameter required'}, 400, headers)
        
        url = request_json['url']
        cache_enabled = request_json.get('cache', True)
        
        # Validate URL format
        try:
            parsed = urllib.parse.urlparse(url)
            if not parsed.scheme or not parsed.netloc:
                return ({'error': 'Invalid URL format'}, 400, headers)
        except Exception:
            return ({'error': 'Invalid URL format'}, 400, headers)
        
        url_hash = get_url_hash(url)
        project_id = os.environ.get('GOOGLE_CLOUD_PROJECT')
        cache_bucket = f"url-validation-cache-{project_id}-{os.environ.get('CACHE_SUFFIX', '')}"
        audit_bucket = f"url-validation-logs-{project_id}-{os.environ.get('CACHE_SUFFIX', '')}"
        
        # Check cache first if enabled
        if cache_enabled:
            cached_result = check_cache(url_hash, cache_bucket)
            if cached_result:
                log_validation(url, {**cached_result, 'cached': True}, audit_bucket)
                return (cached_result, 200, headers)
        
        # Define threat types to check
        threat_types = [
            webrisk_v1.ThreatType.MALWARE,
            webrisk_v1.ThreatType.SOCIAL_ENGINEERING,
            webrisk_v1.ThreatType.UNWANTED_SOFTWARE
        ]
        
        # Check URL against Web Risk API
        request_obj = webrisk_v1.SearchUrisRequest(
            uri=url,
            threat_types=threat_types
        )
        
        response = webrisk_client.search_uris(request=request_obj)
        
        # Process results
        result = {
            'url': url,
            'safe': True,
            'threats': [],
            'checked_at': datetime.now(timezone.utc).isoformat(),
            'cached': False
        }
        
        if response.threat:
            result['safe'] = False
            for threat_type in response.threat.threat_types:
                result['threats'].append({
                    'type': threat_type.name,
                    'expires_at': response.threat.expire_time.isoformat() if response.threat.expire_time else None
                })
        
        # Store in cache and log
        if cache_enabled:
            store_cache(url_hash, result, cache_bucket)
        log_validation(url, result, audit_bucket)
        
        return (result, 200, headers)
        
    except Exception as e:
        logging.error(f"Validation error: {e}")
        error_result = {
            'error': 'Internal validation error',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
        return (error_result, 500, headers)
EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Deploying Cloud Function: $FUNCTION_NAME"
        cd "$function_dir"
        
        if gcloud functions deploy "$FUNCTION_NAME" \
            --runtime python311 \
            --trigger-http \
            --allow-unauthenticated \
            --source . \
            --entry-point validate_url \
            --memory 256MB \
            --timeout 60s \
            --max-instances 100 \
            --region="$REGION" \
            --set-env-vars "GOOGLE_CLOUD_PROJECT=$PROJECT_ID,CACHE_SUFFIX=$RANDOM_SUFFIX"; then
            
            # Get function URL
            FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
                --region="$REGION" \
                --format="value(httpsTrigger.url)")
            
            success "Cloud Function deployed successfully"
            info "Function URL: $FUNCTION_URL"
        else
            error "Failed to deploy Cloud Function"
            exit 1
        fi
        
        cd - > /dev/null
        rm -rf "$function_dir"
    else
        info "Would deploy Cloud Function: $FUNCTION_NAME"
        rm -rf "$function_dir"
    fi
    
    success "Cloud Function creation completed"
}

# Configure IAM permissions
configure_iam() {
    log "Configuring IAM permissions..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get the Cloud Function service account
        local function_sa
        function_sa=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(serviceAccountEmail)")
        
        if [[ -n "$function_sa" ]]; then
            log "Granting Web Risk API access to service account: $function_sa"
            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$function_sa" \
                --role="roles/webrisk.user"
            
            log "Granting Storage access to service account: $function_sa"
            gcloud projects add-iam-policy-binding "$PROJECT_ID" \
                --member="serviceAccount:$function_sa" \
                --role="roles/storage.objectAdmin"
            
            success "IAM permissions configured successfully"
        else
            error "Could not retrieve function service account"
            exit 1
        fi
    else
        info "Would configure IAM permissions for Cloud Function service account"
    fi
    
    success "IAM configuration completed"
}

# Create test script
create_test_script() {
    log "Creating test script..."
    
    local test_script="${SCRIPT_DIR}/test_validation.py"
    
    cat > "$test_script" << 'EOF'
#!/usr/bin/env python3
import requests
import json
import sys
import time

def test_url_validation(function_url, test_urls):
    """Test URL validation function with various URLs"""
    
    headers = {'Content-Type': 'application/json'}
    
    print(f"Testing URL validation function: {function_url}\n")
    
    for i, url in enumerate(test_urls, 1):
        print(f"Test {i}/{len(test_urls)}: {url}")
        
        payload = {
            'url': url,
            'cache': True
        }
        
        try:
            start_time = time.time()
            response = requests.post(function_url, 
                                   json=payload, 
                                   headers=headers, 
                                   timeout=30)
            end_time = time.time()
            
            response_time = round((end_time - start_time) * 1000, 2)
            
            if response.status_code == 200:
                result = response.json()
                status = "🔴 UNSAFE" if not result['safe'] else "🟢 SAFE"
                print(f"  Status: {status}")
                print(f"  Response time: {response_time}ms")
                
                if not result['safe']:
                    print("  Threats detected:")
                    for threat in result['threats']:
                        print(f"    - {threat['type']}")
                
                print(f"  Cached: {result.get('cached', False)}")
            else:
                print(f"  ❌ Error: {response.status_code} - {response.text}")
                
        except Exception as e:
            print(f"  ❌ Request failed: {e}")
        
        print()  # Empty line between tests

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 test_validation.py <FUNCTION_URL>")
        sys.exit(1)
    
    function_url = sys.argv[1]
    
    # Test URLs including known malware test sites
    test_urls = [
        "https://www.google.com",
        "https://testsafebrowsing.appspot.com/s/malware.html",
        "https://testsafebrowsing.appspot.com/s/phishing.html",
        "https://example.com",
        "https://github.com"
    ]
    
    test_url_validation(function_url, test_urls)
    
    print("🎉 Testing completed!")
    print("Note: The malware and phishing test URLs should be flagged as unsafe.")
EOF
    
    chmod +x "$test_script"
    success "Test script created: $test_script"
}

# Run validation tests
run_validation_tests() {
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Would run validation tests"
        return 0
    fi
    
    log "Running validation tests..."
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)")
    
    if [[ -n "$function_url" ]]; then
        info "Testing basic function accessibility..."
        
        # Simple test
        if curl -s -X POST "$function_url" \
            -H "Content-Type: application/json" \
            -d '{"url": "https://www.google.com"}' \
            --max-time 30 > /dev/null; then
            success "Basic connectivity test passed"
        else
            warn "Basic connectivity test failed - function may still be initializing"
        fi
        
        # Run comprehensive tests if Python is available
        if command -v python3 &> /dev/null; then
            if [[ -f "${SCRIPT_DIR}/test_validation.py" ]]; then
                log "Running comprehensive validation tests..."
                python3 "${SCRIPT_DIR}/test_validation.py" "$function_url" || true
            fi
        else
            info "Python3 not available. Skipping comprehensive tests."
            info "You can test manually with: curl -X POST $function_url -H 'Content-Type: application/json' -d '{\"url\": \"https://example.com\"}'"
        fi
    else
        error "Could not retrieve function URL"
        exit 1
    fi
}

# Save deployment information
save_deployment_info() {
    local info_file="${SCRIPT_DIR}/deployment_info.json"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local function_url
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(httpsTrigger.url)" 2>/dev/null || echo "")
        
        cat > "$info_file" << EOF
{
  "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "function_name": "$FUNCTION_NAME",
  "function_url": "$function_url",
  "audit_bucket": "$BUCKET_NAME",
  "cache_bucket": "$CACHE_BUCKET",
  "random_suffix": "$RANDOM_SUFFIX"
}
EOF
        success "Deployment information saved to: $info_file"
    fi
}

# Display deployment summary
show_deployment_summary() {
    cat << EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}                   DEPLOYMENT COMPLETED                       ${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

Project:              ${PROJECT_ID}
Region:               ${REGION}

${GREEN}Resources Created:${NC}
EOF

    if [[ "$DRY_RUN" == "false" ]]; then
        local function_url
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")
        
        cat << EOF
✅ Cloud Function:      ${FUNCTION_NAME}
✅ Function URL:        ${function_url}
✅ Audit Bucket:       gs://${BUCKET_NAME}
✅ Cache Bucket:       gs://${CACHE_BUCKET}
✅ IAM Permissions:    Configured for Web Risk API and Storage

${GREEN}Next Steps:${NC}
1. Test the function:
   curl -X POST ${function_url} \\
     -H "Content-Type: application/json" \\
     -d '{"url": "https://example.com"}'

2. Run comprehensive tests:
   python3 ${SCRIPT_DIR}/test_validation.py ${function_url}

3. Monitor logs:
   gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}

4. View audit logs:
   gsutil ls -r gs://${BUCKET_NAME}/audit/

${GREEN}Cost Management:${NC}
- Monitor usage in the GCP Console
- Set up billing alerts for unexpected costs
- Use the destroy.sh script to clean up when done

${GREEN}Documentation:${NC}
- Deployment info: ${SCRIPT_DIR}/deployment_info.json
- Deployment log: ${LOG_FILE}
- Error log: ${ERROR_LOG}
EOF
    else
        cat << EOF
${YELLOW}DRY RUN COMPLETED${NC}
No resources were actually created.
Run without --dry-run to perform the actual deployment.
EOF
    fi

    cat << EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}

EOF
}

# Main deployment function
main() {
    # Initialize log files
    echo "URL Safety Validation Deployment Log - $(date)" > "$LOG_FILE"
    echo "URL Safety Validation Deployment Errors - $(date)" > "$ERROR_LOG"
    
    log "Starting URL Safety Validation deployment..."
    
    # Parse arguments and initialize
    parse_args "$@"
    init_variables
    
    # Show deployment plan
    show_deployment_plan
    
    # Confirm deployment unless forced or dry run
    if [[ "$DRY_RUN" == "false" ]]; then
        confirm_deployment
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Execute deployment steps
    configure_gcloud
    enable_apis
    create_storage_buckets
    create_cloud_function
    configure_iam
    create_test_script
    
    # Save deployment information
    save_deployment_info
    
    # Run validation tests
    run_validation_tests
    
    # Show summary
    show_deployment_summary
    
    success "URL Safety Validation deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        info "Remember to run ./destroy.sh when you're done to avoid ongoing charges."
    fi
}

# Run main function with all arguments
main "$@"