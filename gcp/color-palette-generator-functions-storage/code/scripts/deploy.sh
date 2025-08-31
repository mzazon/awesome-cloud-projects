#!/bin/bash

# Color Palette Generator with Cloud Functions and Storage - Deployment Script
# This script deploys a serverless color palette generation API using GCP Cloud Functions and Storage
# Version: 1.0
# Compatible with: Google Cloud SDK (gcloud CLI)

set -euo pipefail

# Colors for output formatting
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

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud CLI is installed
    if ! command_exists gcloud; then
        error_exit "Google Cloud CLI (gcloud) is not installed. Please install it first."
    fi
    
    # Check if gsutil is available
    if ! command_exists gsutil; then
        error_exit "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
    fi
    
    # Check if curl is available for testing
    if ! command_exists curl; then
        error_exit "curl is required for API testing but not found."
    fi
    
    # Check if Python 3 is available for JSON formatting
    if ! command_exists python3; then
        log_warning "Python 3 not found. JSON output formatting may not work during testing."
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null 2>&1; then
        error_exit "Not authenticated with Google Cloud. Please run 'gcloud auth login' first."
    fi
    
    log_success "Prerequisites validated successfully"
}

# Set environment variables with validation
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Allow user to override default values
    export PROJECT_ID="${PROJECT_ID:-color-palette-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export FUNCTION_NAME="${FUNCTION_NAME:-generate-color-palette}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c 6)")
    export BUCKET_NAME="${BUCKET_NAME:-color-palettes-${RANDOM_SUFFIX}}"
    
    # Validate region format
    if [[ ! "$REGION" =~ ^[a-z]+-[a-z]+[0-9]+$ ]]; then
        error_exit "Invalid region format: $REGION. Use format like 'us-central1'"
    fi
    
    # Validate function name
    if [[ ! "$FUNCTION_NAME" =~ ^[a-z][a-z0-9-]*[a-z0-9]$ ]]; then
        error_exit "Invalid function name: $FUNCTION_NAME. Use lowercase letters, numbers, and hyphens only."
    fi
    
    log_success "Environment configured:"
    log_info "  Project ID: $PROJECT_ID"
    log_info "  Region: $REGION"
    log_info "  Function Name: $FUNCTION_NAME"
    log_info "  Storage Bucket: $BUCKET_NAME"
}

# Create and configure Google Cloud project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project already exists
    if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
        log_warning "Project $PROJECT_ID already exists. Using existing project."
    else
        log_info "Creating new project: $PROJECT_ID"
        gcloud projects create "$PROJECT_ID" --quiet || error_exit "Failed to create project"
    fi
    
    # Set project configuration
    gcloud config set project "$PROJECT_ID" || error_exit "Failed to set project"
    gcloud config set compute/region "$REGION" || error_exit "Failed to set region"
    
    log_success "Project configured: $PROJECT_ID"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "storage.googleapis.com"
        "cloudbuild.googleapis.com"
        "artifactregistry.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if gcloud services enable "$api" --quiet; then
            log_success "Enabled $api"
        else
            error_exit "Failed to enable $api"
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled successfully"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket..."
    
    # Check if bucket already exists
    if gsutil ls -b "gs://$BUCKET_NAME" >/dev/null 2>&1; then
        log_warning "Bucket gs://$BUCKET_NAME already exists. Skipping creation."
    else
        log_info "Creating bucket: gs://$BUCKET_NAME"
        gsutil mb -p "$PROJECT_ID" \
            -c STANDARD \
            -l "$REGION" \
            "gs://$BUCKET_NAME" || error_exit "Failed to create storage bucket"
        
        log_success "Storage bucket created: gs://$BUCKET_NAME"
    fi
    
    # Configure bucket for public read access
    log_info "Configuring bucket permissions for public read access..."
    gsutil iam ch allUsers:objectViewer "gs://$BUCKET_NAME" || error_exit "Failed to configure bucket permissions"
    
    log_success "Bucket permissions configured successfully"
}

# Create function source code
create_function_code() {
    log_info "Creating Cloud Function source code..."
    
    local function_dir="palette-function"
    
    # Create function directory
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-storage==2.19.0
functions-framework==3.*
EOF
    
    # Create main.py with function code
    cat > main.py << EOF
import json
import colorsys
import hashlib
from datetime import datetime
from google.cloud import storage
import functions_framework

def hex_to_hsl(hex_color):
    """Convert hex color to HSL values"""
    hex_color = hex_color.lstrip('#')
    r, g, b = tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))
    r, g, b = r/255.0, g/255.0, b/255.0
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h * 360, s * 100, l * 100

def hsl_to_hex(h, s, l):
    """Convert HSL values to hex color"""
    h, s, l = h/360.0, s/100.0, l/100.0
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return '#{:02x}{:02x}{:02x}'.format(int(r*255), int(g*255), int(b*255))

def generate_palette(base_color):
    """Generate harmonious color palette from base color"""
    h, s, l = hex_to_hsl(base_color)
    
    # Generate complementary and analogous colors
    palette = {
        'base': base_color,
        'complementary': hsl_to_hex((h + 180) % 360, s, l),
        'analogous_1': hsl_to_hex((h + 30) % 360, s, l),
        'analogous_2': hsl_to_hex((h - 30) % 360, s, l),
        'triadic_1': hsl_to_hex((h + 120) % 360, s, l),
        'triadic_2': hsl_to_hex((h + 240) % 360, s, l),
        'light_variant': hsl_to_hex(h, s, min(100, l + 20)),
        'dark_variant': hsl_to_hex(h, s, max(0, l - 20))
    }
    
    return palette

@functions_framework.http
def generate_color_palette(request):
    """HTTP Cloud Function for color palette generation"""
    
    # Handle CORS for web applications
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST',
            'Access-Control-Allow-Headers': 'Content-Type',
        }
        return ('', 204, headers)
    
    headers = {'Access-Control-Allow-Origin': '*'}
    
    try:
        # Parse request data
        request_json = request.get_json(silent=True)
        if not request_json or 'base_color' not in request_json:
            return (json.dumps({"error": "Missing base_color parameter"}), 400, headers)
        
        base_color = request_json['base_color']
        
        # Validate hex color format
        if not base_color.startswith('#') or len(base_color) != 7:
            return (json.dumps({"error": "Invalid hex color format. Use #RRGGBB"}), 400, headers)
        
        # Validate hex characters
        try:
            int(base_color[1:], 16)
        except ValueError:
            return (json.dumps({"error": "Invalid hex color format. Use #RRGGBB"}), 400, headers)
        
        # Generate color palette
        palette = generate_palette(base_color)
        
        # Create palette metadata
        palette_id = hashlib.md5(base_color.encode()).hexdigest()[:8]
        palette_data = {
            'id': palette_id,
            'base_color': base_color,
            'colors': palette,
            'created_at': datetime.utcnow().isoformat(),
            'palette_type': 'harmonious'
        }
        
        # Store palette in Cloud Storage
        storage_client = storage.Client()
        bucket = storage_client.bucket('$BUCKET_NAME')
        blob = bucket.blob(f'palettes/{palette_id}.json')
        blob.upload_from_string(
            json.dumps(palette_data, indent=2),
            content_type='application/json'
        )
        
        # Return response with palette and storage URL
        response_data = {
            'success': True,
            'palette': palette_data,
            'storage_url': f'https://storage.googleapis.com/{bucket.name}/{blob.name}'
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except Exception as e:
        error_response = {'error': f'Internal server error: {str(e)}'}
        return (json.dumps(error_response), 500, headers)
EOF
    
    cd ..
    log_success "Function source code created in directory: $function_dir"
}

# Deploy Cloud Function
deploy_function() {
    log_info "Deploying Cloud Function..."
    
    cd palette-function
    
    # Check if function already exists
    if gcloud functions describe "$FUNCTION_NAME" --region="$REGION" >/dev/null 2>&1; then
        log_warning "Function $FUNCTION_NAME already exists. Updating existing function."
    fi
    
    # Deploy function with retry logic
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Deployment attempt $attempt of $max_attempts..."
        
        if gcloud functions deploy "$FUNCTION_NAME" \
            --runtime python312 \
            --trigger-http \
            --allow-unauthenticated \
            --source . \
            --entry-point generate_color_palette \
            --memory 256MB \
            --timeout 60s \
            --region "$REGION" \
            --quiet; then
            
            log_success "Cloud Function deployed successfully on attempt $attempt"
            break
        else
            if [ $attempt -eq $max_attempts ]; then
                error_exit "Failed to deploy Cloud Function after $max_attempts attempts"
            else
                log_warning "Deployment attempt $attempt failed. Retrying in 30 seconds..."
                sleep 30
            fi
        fi
        
        ((attempt++))
    done
    
    cd ..
}

# Get function URL and store in environment
get_function_url() {
    log_info "Retrieving function URL..."
    
    FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
        --region="$REGION" \
        --format="value(httpsTrigger.url)") || error_exit "Failed to get function URL"
    
    export FUNCTION_URL
    
    log_success "Function deployed and accessible at: $FUNCTION_URL"
}

# Test the deployed function
test_deployment() {
    log_info "Testing deployed function..."
    
    # Test with a sample color
    local test_color="#3498db"
    local response
    
    log_info "Testing palette generation with color: $test_color"
    
    if command_exists python3; then
        response=$(curl -s -X POST "$FUNCTION_URL" \
            -H "Content-Type: application/json" \
            -d "{\"base_color\": \"$test_color\"}")
        
        if echo "$response" | python3 -m json.tool >/dev/null 2>&1; then
            log_success "Function test passed - valid JSON response received"
            
            # Extract palette ID for verification
            local palette_id
            palette_id=$(echo "$response" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('palette', {}).get('id', 'unknown'))" 2>/dev/null || echo "unknown")
            
            if [ "$palette_id" != "unknown" ]; then
                log_success "Generated palette ID: $palette_id"
                
                # Verify palette was stored in bucket
                if gsutil ls "gs://$BUCKET_NAME/palettes/$palette_id.json" >/dev/null 2>&1; then
                    log_success "Palette successfully stored in Cloud Storage"
                else
                    log_warning "Palette may not have been stored in Cloud Storage"
                fi
            fi
        else
            log_warning "Function test completed but response format may be incorrect"
        fi
    else
        # Basic test without JSON parsing
        if curl -s -f -X POST "$FUNCTION_URL" \
            -H "Content-Type: application/json" \
            -d "{\"base_color\": \"$test_color\"}" >/dev/null; then
            log_success "Function test passed - HTTP request successful"
        else
            log_warning "Function test failed - HTTP request returned error"
        fi
    fi
    
    # Test error handling
    log_info "Testing error handling with invalid input..."
    local error_response
    error_response=$(curl -s -X POST "$FUNCTION_URL" \
        -H "Content-Type: application/json" \
        -d '{"base_color": "invalid"}')
    
    if echo "$error_response" | grep -q "error"; then
        log_success "Error handling test passed"
    else
        log_warning "Error handling may not be working correctly"
    fi
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="deployment-info.txt"
    
    cat > "$info_file" << EOF
Color Palette Generator Deployment Information
Generated on: $(date)

Project Configuration:
- Project ID: $PROJECT_ID
- Region: $REGION
- Function Name: $FUNCTION_NAME
- Storage Bucket: $BUCKET_NAME

Deployed Resources:
- Cloud Function URL: $FUNCTION_URL
- Storage Bucket: gs://$BUCKET_NAME
- Function Region: $REGION

Usage Examples:
# Test the API
curl -X POST $FUNCTION_URL \\
    -H "Content-Type: application/json" \\
    -d '{"base_color": "#3498db"}'

# List stored palettes
gsutil ls gs://$BUCKET_NAME/palettes/

# View a palette file
gsutil cat gs://$BUCKET_NAME/palettes/<palette-id>.json

Cleanup Command:
./destroy.sh
EOF
    
    log_success "Deployment information saved to: $info_file"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "Color Palette Generator Deployment Script"
    echo "=========================================="
    echo
    
    validate_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_storage_bucket
    create_function_code
    deploy_function
    get_function_url
    test_deployment
    save_deployment_info
    
    echo
    echo "=========================================="
    log_success "Deployment completed successfully!"
    echo "=========================================="
    echo
    log_info "Your color palette generator API is ready!"
    log_info "Function URL: $FUNCTION_URL"
    log_info "Storage Bucket: gs://$BUCKET_NAME"
    echo
    log_info "Test your API with:"
    echo "curl -X POST $FUNCTION_URL \\"
    echo "    -H \"Content-Type: application/json\" \\"
    echo "    -d '{\"base_color\": \"#3498db\"}'"
    echo
    log_info "View deployment details in: deployment-info.txt"
    log_info "To clean up resources, run: ./destroy.sh"
    echo
}

# Handle script interruption
cleanup_on_interrupt() {
    echo
    log_warning "Deployment interrupted by user"
    log_info "You may need to manually clean up partially created resources"
    log_info "Run ./destroy.sh to attempt cleanup"
    exit 130
}

# Set up signal handlers
trap cleanup_on_interrupt SIGINT SIGTERM

# Run main function
main "$@"