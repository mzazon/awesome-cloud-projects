#!/bin/bash

# =============================================================================
# Weather API with Cloud Functions and Storage - Deployment Script
# =============================================================================
# This script deploys the Weather API infrastructure using Google Cloud CLI
# Based on the recipe: Weather API with Cloud Functions and Storage
# =============================================================================

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly FUNCTION_SOURCE_DIR="$PROJECT_ROOT/terraform/function-source"

# Default configuration
DEFAULT_REGION="us-central1"
DEFAULT_FUNCTION_NAME="weather-api"
DEFAULT_WEATHER_API_KEY="demo_key"

# Global variables
PROJECT_ID=""
REGION=""
FUNCTION_NAME=""
BUCKET_NAME=""
WEATHER_API_KEY=""
DRY_RUN=false
SKIP_APIS=false

# =============================================================================
# Utility Functions
# =============================================================================

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

print_banner() {
    echo -e "${BLUE}"
    echo "============================================================================="
    echo "           Weather API with Cloud Functions and Storage"
    echo "                        Deployment Script"
    echo "============================================================================="
    echo -e "${NC}"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Weather API infrastructure to Google Cloud Platform

OPTIONS:
    -p, --project-id PROJECT_ID     GCP Project ID (required)
    -r, --region REGION             GCP Region (default: $DEFAULT_REGION)
    -f, --function-name NAME        Cloud Function name (default: $DEFAULT_FUNCTION_NAME)
    -k, --weather-key KEY           Weather API key (default: $DEFAULT_WEATHER_API_KEY)
    -d, --dry-run                   Show what would be deployed without executing
    -s, --skip-apis                 Skip enabling APIs (assumes already enabled)
    -h, --help                      Show this help message

EXAMPLES:
    $0 --project-id my-weather-project
    $0 -p my-weather-project -r europe-west1 -k YOUR_WEATHER_API_KEY
    $0 --project-id my-project --dry-run

NOTES:
    - Requires gcloud CLI to be installed and authenticated
    - Weather API key can be obtained from OpenWeatherMap (free tier available)
    - Default configuration uses demo key for testing purposes
    - Estimated deployment time: 3-5 minutes
    - Estimated cost: $0.01-$0.10 for testing (covered by free tier)

EOF
}

# =============================================================================
# Prerequisites and Validation Functions
# =============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI not found. Please install Google Cloud SDK."
        log_info "Install instructions: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi

    # Check if gcloud is authenticated
    if ! gcloud auth list --filter="status:ACTIVE" --format="value(account)" | head -n 1 &> /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi

    # Check if function source files exist
    if [[ ! -f "$FUNCTION_SOURCE_DIR/main.py" ]]; then
        log_error "Function source file not found: $FUNCTION_SOURCE_DIR/main.py"
        exit 1
    fi

    if [[ ! -f "$FUNCTION_SOURCE_DIR/requirements.txt" ]]; then
        log_error "Requirements file not found: $FUNCTION_SOURCE_DIR/requirements.txt"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

validate_project() {
    log_info "Validating project: $PROJECT_ID"

    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible"
        log_info "Available projects:"
        gcloud projects list --format="table(projectId,name,projectNumber)"
        exit 1
    fi

    # Set the project as active
    gcloud config set project "$PROJECT_ID"
    log_success "Project validated and set as active: $PROJECT_ID"
}

validate_region() {
    log_info "Validating region: $REGION"

    if ! gcloud compute regions describe "$REGION" &> /dev/null; then
        log_error "Region '$REGION' is not valid"
        log_info "Available regions:"
        gcloud compute regions list --format="value(name)" | head -10
        exit 1
    fi

    gcloud config set compute/region "$REGION"
    log_success "Region validated and set: $REGION"
}

generate_unique_names() {
    local timestamp=$(date +%s | tail -c 6)
    local random_suffix=$(openssl rand -hex 3 2>/dev/null || echo "$(shuf -i 100-999 -n 1)")
    
    BUCKET_NAME="weather-cache-${timestamp}-${random_suffix}"
    
    log_info "Generated unique resource names:"
    log_info "  Bucket: $BUCKET_NAME"
    log_info "  Function: $FUNCTION_NAME"
}

# =============================================================================
# Deployment Functions
# =============================================================================

enable_apis() {
    if [[ "$SKIP_APIS" == "true" ]]; then
        log_info "Skipping API enablement (--skip-apis flag provided)"
        return 0
    fi

    log_info "Enabling required Google Cloud APIs..."

    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "run.googleapis.com"
    )

    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if [[ "$DRY_RUN" == "false" ]]; then
            gcloud services enable "$api" || {
                log_warning "Failed to enable $api, continuing..."
            }
        else
            log_info "[DRY RUN] Would enable: $api"
        fi
    done

    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 10
    fi

    log_success "API enablement completed"
}

create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: $BUCKET_NAME"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create bucket: gs://$BUCKET_NAME in $REGION"
        return 0
    fi

    # Check if bucket already exists
    if gsutil ls -b "gs://$BUCKET_NAME" &> /dev/null; then
        log_warning "Bucket gs://$BUCKET_NAME already exists, skipping creation"
        return 0
    fi

    gsutil mb -p "$PROJECT_ID" -c STANDARD -l "$REGION" "gs://$BUCKET_NAME" || {
        log_error "Failed to create storage bucket"
        exit 1
    }

    # Set bucket lifecycle for cost optimization
    cat > /tmp/lifecycle.json << EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {
          "type": "Delete"
        },
        "condition": {
          "age": 7
        }
      }
    ]
  }
}
EOF

    gsutil lifecycle set /tmp/lifecycle.json "gs://$BUCKET_NAME"
    rm -f /tmp/lifecycle.json

    log_success "Storage bucket created: gs://$BUCKET_NAME"
}

deploy_cloud_function() {
    log_info "Deploying Cloud Function: $FUNCTION_NAME"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy function: $FUNCTION_NAME"
        log_info "[DRY RUN] Source: $FUNCTION_SOURCE_DIR"
        log_info "[DRY RUN] Environment variables:"
        log_info "[DRY RUN]   CACHE_BUCKET=$BUCKET_NAME"
        log_info "[DRY RUN]   WEATHER_API_KEY=$WEATHER_API_KEY"
        return 0
    fi

    # Deploy the function
    gcloud functions deploy "$FUNCTION_NAME" \
        --runtime python312 \
        --trigger-http \
        --allow-unauthenticated \
        --source "$FUNCTION_SOURCE_DIR" \
        --entry-point weather_api \
        --memory 256MB \
        --timeout 60s \
        --region "$REGION" \
        --set-env-vars "CACHE_BUCKET=$BUCKET_NAME,WEATHER_API_KEY=$WEATHER_API_KEY" || {
        log_error "Failed to deploy Cloud Function"
        exit 1
    }

    log_success "Cloud Function deployed: $FUNCTION_NAME"
}

configure_function_permissions() {
    log_info "Configuring function permissions..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure IAM permissions for function service account"
        return 0
    fi

    # Get function service account
    local function_sa
    function_sa=$(gcloud functions describe "$FUNCTION_NAME" \
        --region "$REGION" \
        --format="value(serviceAccountEmail)") || {
        log_warning "Could not retrieve function service account, skipping permission configuration"
        return 0
    }

    # Grant storage admin permissions to the function service account
    gsutil iam ch "serviceAccount:$function_sa:objectAdmin" "gs://$BUCKET_NAME" || {
        log_warning "Failed to set bucket permissions, function may not work properly"
    }

    log_success "Function permissions configured"
}

test_deployment() {
    log_info "Testing deployed infrastructure..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would test the deployed function"
        return 0
    fi

    # Get function URL
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" \
        --region "$REGION" \
        --format="value(httpsTrigger.url)") || {
        log_warning "Could not retrieve function URL for testing"
        return 0
    }

    log_info "Testing function at: $function_url"

    # Test the function with a simple request
    if command -v curl &> /dev/null; then
        local response
        response=$(curl -s -w "%{http_code}" -o /tmp/function_test_response "$function_url?city=London" || echo "000")
        local http_code="${response: -3}"
        
        if [[ "$http_code" == "200" ]]; then
            log_success "Function test passed (HTTP 200)"
            if [[ -f /tmp/function_test_response ]]; then
                log_info "Response preview:"
                head -c 200 /tmp/function_test_response | jq . 2>/dev/null || cat /tmp/function_test_response
            fi
        else
            log_warning "Function test returned HTTP $http_code"
        fi
        
        rm -f /tmp/function_test_response
    else
        log_warning "curl not available for testing, skipping function test"
    fi
}

display_deployment_summary() {
    echo -e "${GREEN}"
    echo "============================================================================="
    echo "                        DEPLOYMENT COMPLETED"
    echo "============================================================================="
    echo -e "${NC}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}DRY RUN MODE - No resources were actually created${NC}"
        echo ""
    fi

    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Function Name: $FUNCTION_NAME"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local function_url
        function_url=$(gcloud functions describe "$FUNCTION_NAME" \
            --region "$REGION" \
            --format="value(httpsTrigger.url)" 2>/dev/null || echo "Unable to retrieve")
        
        echo "Function URL: $function_url"
        echo ""
        echo "Test your API:"
        echo "  curl \"$function_url?city=London\""
        echo "  curl \"$function_url?city=Tokyo\""
        echo ""
    fi
    
    echo "To clean up resources, run:"
    echo "  ./destroy.sh --project-id $PROJECT_ID --region $REGION --function-name $FUNCTION_NAME --bucket-name $BUCKET_NAME"
    echo ""
    
    if [[ "$WEATHER_API_KEY" == "demo_key" ]]; then
        log_warning "Using demo API key. For production use, get a real API key from OpenWeatherMap"
        log_info "Sign up at: https://openweathermap.org/api"
    fi
}

# =============================================================================
# Main Execution Flow
# =============================================================================

parse_arguments() {
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
            -k|--weather-key)
                WEATHER_API_KEY="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-apis)
                SKIP_APIS=true
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

    # Set defaults for optional parameters
    REGION="${REGION:-$DEFAULT_REGION}"
    FUNCTION_NAME="${FUNCTION_NAME:-$DEFAULT_FUNCTION_NAME}"
    WEATHER_API_KEY="${WEATHER_API_KEY:-$DEFAULT_WEATHER_API_KEY}"

    # Validate required parameters
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "Project ID is required. Use --project-id or -p"
        show_usage
        exit 1
    fi
}

main() {
    print_banner

    # Parse command line arguments
    parse_arguments "$@"

    # Validate environment and inputs
    check_prerequisites
    validate_project
    validate_region
    generate_unique_names

    # Show deployment plan
    echo "Deployment Configuration:"
    echo "  Project ID: $PROJECT_ID"
    echo "  Region: $REGION"
    echo "  Function Name: $FUNCTION_NAME"
    echo "  Bucket Name: $BUCKET_NAME"
    echo "  Weather API Key: ${WEATHER_API_KEY:0:8}..."
    echo "  Dry Run: $DRY_RUN"
    echo ""

    if [[ "$DRY_RUN" == "false" ]]; then
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled"
            exit 0
        fi
    fi

    # Execute deployment steps
    log_info "Starting deployment..."
    
    enable_apis
    create_storage_bucket
    deploy_cloud_function
    configure_function_permissions
    test_deployment
    
    display_deployment_summary
    
    log_success "Weather API deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Deployment interrupted!"; exit 1' INT TERM

# Execute main function with all arguments
main "$@"