#!/bin/bash

# Website Status Monitor Cloud Function Deployment Script
# This script deploys a serverless website monitoring API using Google Cloud Functions
# Based on the GCP recipe: Website Status Monitor with Cloud Functions

set -euo pipefail

# Enable strict error handling
trap 'echo "❌ Error occurred at line $LINENO. Exit code: $?" >&2' ERR

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly FUNCTION_DIR="${SCRIPT_DIR}/../function"
readonly DEFAULT_PROJECT_ID="website-monitor-$(date +%s)"
readonly DEFAULT_REGION="us-central1"
readonly DEFAULT_FUNCTION_NAME="website-status-monitor"

# Runtime variables
PROJECT_ID="${PROJECT_ID:-${DEFAULT_PROJECT_ID}}"
REGION="${REGION:-${DEFAULT_REGION}}"
FUNCTION_NAME="${FUNCTION_NAME:-${DEFAULT_FUNCTION_NAME}}"
DRY_RUN="${DRY_RUN:-false}"

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print section headers
print_section() {
    local message=$1
    echo -e "\n${BLUE}================================================${NC}"
    echo -e "${BLUE} ${message}${NC}"
    echo -e "${BLUE}================================================${NC}\n"
}

# Function to check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        print_status "$RED" "❌ gcloud CLI is not installed. Please install it first:"
        print_status "$YELLOW" "   https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --format="value(account)" --filter="status=ACTIVE" | head -1 &> /dev/null; then
        print_status "$RED" "❌ Not authenticated with gcloud. Please run:"
        print_status "$YELLOW" "   gcloud auth login"
        exit 1
    fi
    
    # Check if jq is available for JSON parsing (optional but recommended)
    if ! command -v jq &> /dev/null; then
        print_status "$YELLOW" "⚠️  jq is not installed. JSON output will not be formatted."
    fi
    
    # Check if curl is available for testing
    if ! command -v curl &> /dev/null; then
        print_status "$YELLOW" "⚠️  curl is not installed. Function testing will be skipped."
    fi
    
    print_status "$GREEN" "✅ Prerequisites check completed"
}

# Function to validate project settings
validate_project() {
    print_section "Validating Project Configuration"
    
    # Check if project exists or needs to be created
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        print_status "$YELLOW" "⚠️  Project '$PROJECT_ID' does not exist."
        read -p "Do you want to create it? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if [ "$DRY_RUN" = "true" ]; then
                print_status "$BLUE" "[DRY RUN] Would create project: $PROJECT_ID"
            else
                gcloud projects create "$PROJECT_ID"
                print_status "$GREEN" "✅ Project '$PROJECT_ID' created successfully"
            fi
        else
            print_status "$RED" "❌ Deployment cancelled. Project is required."
            exit 1
        fi
    fi
    
    # Set the active project
    if [ "$DRY_RUN" = "false" ]; then
        gcloud config set project "$PROJECT_ID"
        gcloud config set functions/region "$REGION"
    else
        print_status "$BLUE" "[DRY RUN] Would set project to: $PROJECT_ID"
        print_status "$BLUE" "[DRY RUN] Would set region to: $REGION"
    fi
    
    print_status "$GREEN" "✅ Project configuration validated"
}

# Function to enable required APIs
enable_apis() {
    print_section "Enabling Required APIs"
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
        "cloudresourcemanager.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        if [ "$DRY_RUN" = "true" ]; then
            print_status "$BLUE" "[DRY RUN] Would enable API: $api"
        else
            print_status "$YELLOW" "Enabling $api..."
            if gcloud services enable "$api" --quiet; then
                print_status "$GREEN" "✅ $api enabled successfully"
            else
                print_status "$RED" "❌ Failed to enable $api"
                exit 1
            fi
        fi
    done
    
    # Wait for APIs to be fully enabled
    if [ "$DRY_RUN" = "false" ]; then
        print_status "$YELLOW" "Waiting for APIs to be fully enabled..."
        sleep 10
    fi
}

# Function to create function source code
create_function_code() {
    print_section "Creating Function Source Code"
    
    # Create function directory
    if [ "$DRY_RUN" = "true" ]; then
        print_status "$BLUE" "[DRY RUN] Would create function directory: $FUNCTION_DIR"
        return 0
    fi
    
    mkdir -p "$FUNCTION_DIR"
    cd "$FUNCTION_DIR"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
requests==2.32.4
functions-framework==3.8.3
EOF
    
    # Create main.py with the website monitoring function
    cat > main.py << 'EOF'
import functions_framework
import requests
import json
import time
from datetime import datetime, timezone
from urllib.parse import urlparse

@functions_framework.http
def website_status_monitor(request):
    """HTTP Cloud Function to monitor website status and performance."""
    
    # Set CORS headers for web requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        'Content-Type': 'application/json'
    }
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Parse request data
        if request.method == 'GET':
            url = request.args.get('url')
        else:
            request_json = request.get_json(silent=True)
            url = request_json.get('url') if request_json else None
        
        if not url:
            return (json.dumps({
                'error': 'URL parameter is required',
                'usage': 'GET /?url=https://example.com or POST with {"url": "https://example.com"}'
            }), 400, headers)
        
        # Validate URL format
        parsed_url = urlparse(url)
        if not parsed_url.scheme or not parsed_url.netloc:
            return (json.dumps({
                'error': 'Invalid URL format. Must include protocol (http:// or https://)'
            }), 400, headers)
        
        # Perform website health check
        start_time = time.time()
        
        try:
            response = requests.get(
                url,
                timeout=10,
                allow_redirects=True,
                headers={'User-Agent': 'GCP-Website-Monitor/1.0'}
            )
            
            end_time = time.time()
            response_time = round((end_time - start_time) * 1000, 2)  # Convert to milliseconds
            
            # Determine status
            is_healthy = 200 <= response.status_code < 400
            
            # Build response data
            result = {
                'url': url,
                'status': 'healthy' if is_healthy else 'unhealthy',
                'status_code': response.status_code,
                'response_time_ms': response_time,
                'content_length': len(response.content),
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'redirected': response.url != url,
                'final_url': response.url,
                'server': response.headers.get('server', 'Unknown'),
                'content_type': response.headers.get('content-type', 'Unknown')
            }
            
            print(f"Monitored {url}: {response.status_code} ({response_time}ms)")
            return (json.dumps(result), 200, headers)
            
        except requests.exceptions.Timeout:
            return (json.dumps({
                'url': url,
                'status': 'timeout',
                'error': 'Request timeout after 10 seconds',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }), 200, headers)
            
        except requests.exceptions.ConnectionError:
            return (json.dumps({
                'url': url,
                'status': 'connection_error',
                'error': 'Unable to connect to the website',
                'timestamp': datetime.now(timezone.utc).isoformat()
            }), 200, headers)
            
        except Exception as e:
            return (json.dumps({
                'url': url,
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.now(timezone.utc).isoformat()
            }), 200, headers)
    
    except Exception as e:
        print(f"Function error: {str(e)}")
        return (json.dumps({
            'error': 'Internal server error',
            'message': str(e)
        }), 500, headers)
EOF
    
    print_status "$GREEN" "✅ Function source code created successfully"
    print_status "$BLUE" "   - Created: $FUNCTION_DIR/main.py"
    print_status "$BLUE" "   - Created: $FUNCTION_DIR/requirements.txt"
}

# Function to deploy the Cloud Function
deploy_function() {
    print_section "Deploying Cloud Function"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_status "$BLUE" "[DRY RUN] Would deploy function: $FUNCTION_NAME"
        print_status "$BLUE" "[DRY RUN] Would use source: $FUNCTION_DIR"
        return 0
    fi
    
    cd "$FUNCTION_DIR"
    
    print_status "$YELLOW" "Deploying Cloud Function '$FUNCTION_NAME'..."
    print_status "$BLUE" "This may take several minutes..."
    
    # Deploy the function with comprehensive configuration
    if gcloud functions deploy "$FUNCTION_NAME" \
        --region="$REGION" \
        --runtime=python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source=. \
        --entry-point=website_status_monitor \
        --memory=256MB \
        --timeout=30s \
        --max-instances=100 \
        --set-env-vars="FUNCTION_TARGET=website_status_monitor" \
        --quiet; then
        
        print_status "$GREEN" "✅ Cloud Function deployed successfully"
        
        # Get function URL
        local function_url
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(httpsTrigger.url)")
        
        print_status "$GREEN" "🌐 Function URL: $function_url"
        
        # Store URL in environment file for easy access
        echo "FUNCTION_URL=$function_url" > "${SCRIPT_DIR}/.env"
        print_status "$BLUE" "   Function URL saved to: ${SCRIPT_DIR}/.env"
        
        return 0
    else
        print_status "$RED" "❌ Failed to deploy Cloud Function"
        return 1
    fi
}

# Function to test the deployed function
test_function() {
    print_section "Testing Deployed Function"
    
    if [ "$DRY_RUN" = "true" ]; then
        print_status "$BLUE" "[DRY RUN] Would test the deployed function"
        return 0
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        print_status "$YELLOW" "⚠️  curl not available. Skipping function testing."
        return 0
    fi
    
    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)" 2>/dev/null)
    
    if [ -z "$function_url" ]; then
        print_status "$RED" "❌ Could not retrieve function URL"
        return 1
    fi
    
    print_status "$YELLOW" "Testing function with sample requests..."
    
    # Test 1: Valid website
    print_status "$BLUE" "Test 1: Monitoring a healthy website"
    if command -v jq &> /dev/null; then
        curl -s -X POST "$function_url" \
            -H "Content-Type: application/json" \
            -d '{"url": "https://httpbin.org/status/200"}' | jq .
    else
        curl -s -X POST "$function_url" \
            -H "Content-Type: application/json" \
            -d '{"url": "https://httpbin.org/status/200"}'
    fi
    
    echo
    
    # Test 2: Error status
    print_status "$BLUE" "Test 2: Monitoring a website with error status"
    if command -v jq &> /dev/null; then
        curl -s -X POST "$function_url" \
            -H "Content-Type: application/json" \
            -d '{"url": "https://httpbin.org/status/500"}' | jq .
    else
        curl -s -X POST "$function_url" \
            -H "Content-Type: application/json" \
            -d '{"url": "https://httpbin.org/status/500"}'
    fi
    
    echo
    
    # Test 3: GET method
    print_status "$BLUE" "Test 3: Using GET method"
    if command -v jq &> /dev/null; then
        curl -s "${function_url}?url=https://www.google.com" | jq .
    else
        curl -s "${function_url}?url=https://www.google.com"
    fi
    
    echo
    print_status "$GREEN" "✅ Function testing completed successfully"
}

# Function to display deployment summary
display_summary() {
    print_section "Deployment Summary"
    
    print_status "$GREEN" "🎉 Website Status Monitor deployment completed successfully!"
    echo
    print_status "$BLUE" "Configuration:"
    print_status "$NC" "  Project ID: $PROJECT_ID"
    print_status "$NC" "  Region: $REGION"
    print_status "$NC" "  Function Name: $FUNCTION_NAME"
    echo
    
    if [ "$DRY_RUN" = "false" ]; then
        local function_url
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region="$REGION" \
            --format="value(httpsTrigger.url)" 2>/dev/null || echo "N/A")
        
        print_status "$BLUE" "Function Details:"
        print_status "$NC" "  Function URL: $function_url"
        print_status "$NC" "  Runtime: Python 3.12"
        print_status "$NC" "  Memory: 256MB"
        print_status "$NC" "  Timeout: 30s"
        echo
        
        print_status "$YELLOW" "Usage Examples:"
        print_status "$NC" "  # POST request"
        print_status "$NC" "  curl -X POST '$function_url' \\"
        print_status "$NC" "       -H 'Content-Type: application/json' \\"
        print_status "$NC" "       -d '{\"url\": \"https://example.com\"}'"
        echo
        print_status "$NC" "  # GET request"
        print_status "$NC" "  curl '$function_url?url=https://example.com'"
        echo
        
        print_status "$BLUE" "Next Steps:"
        print_status "$NC" "  • Test the function with your websites"
        print_status "$NC" "  • Set up monitoring and alerting in Cloud Monitoring"
        print_status "$NC" "  • Implement batch monitoring for multiple URLs"
        print_status "$NC" "  • Consider adding authentication for production use"
        echo
        
        print_status "$YELLOW" "To clean up resources, run:"
        print_status "$NC" "  ./destroy.sh"
    else
        print_status "$BLUE" "[DRY RUN] Deployment simulation completed"
    fi
}

# Function to show usage information
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Deploy a Website Status Monitor Cloud Function to Google Cloud Platform"
    echo
    echo "Options:"
    echo "  -p, --project-id    Project ID (default: website-monitor-<timestamp>)"
    echo "  -r, --region        Deployment region (default: us-central1)"
    echo "  -f, --function-name Function name (default: website-status-monitor)"
    echo "  -d, --dry-run       Simulate deployment without making changes"
    echo "  -h, --help          Show this help message"
    echo
    echo "Environment Variables:"
    echo "  PROJECT_ID          Override default project ID"
    echo "  REGION              Override default region"
    echo "  FUNCTION_NAME       Override default function name"
    echo "  DRY_RUN            Set to 'true' for dry run mode"
    echo
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  $0 -p my-project -r us-east1         # Deploy to specific project/region"
    echo "  $0 --dry-run                         # Simulate deployment"
    echo "  PROJECT_ID=my-project $0             # Use environment variable"
}

# Main deployment function
main() {
    print_section "Website Status Monitor - Cloud Function Deployment"
    print_status "$BLUE" "Starting deployment process..."
    
    # Parse command line arguments
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
            -f|--function-name)
                FUNCTION_NAME="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Show configuration
    print_status "$BLUE" "Deployment Configuration:"
    print_status "$NC" "  Project ID: $PROJECT_ID"
    print_status "$NC" "  Region: $REGION"
    print_status "$NC" "  Function Name: $FUNCTION_NAME"
    print_status "$NC" "  Dry Run: $DRY_RUN"
    echo
    
    # Confirm deployment unless in dry run mode
    if [ "$DRY_RUN" = "false" ]; then
        read -p "Proceed with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "$YELLOW" "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    # Execute deployment steps
    check_prerequisites
    validate_project
    enable_apis
    create_function_code
    deploy_function
    test_function
    display_summary
    
    print_status "$GREEN" "🚀 Deployment completed successfully!"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi