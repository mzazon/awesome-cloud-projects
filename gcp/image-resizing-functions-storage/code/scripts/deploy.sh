#!/bin/bash

# Automatic Image Resizing with Cloud Functions and Storage - Deployment Script
# This script deploys the complete image resizing infrastructure on Google Cloud Platform

set -euo pipefail

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

# Check if running in interactive mode
check_interactive() {
    if [[ -t 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Confirmation prompt
confirm() {
    if check_interactive; then
        echo -e "${YELLOW}$1${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    else
        log_info "Running in non-interactive mode, proceeding with deployment"
    fi
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partial resources..."
    
    # Remove function if it exists
    if gcloud functions describe "${FUNCTION_NAME}" --gen2 --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
        log_info "Removing Cloud Function..."
        gcloud functions delete "${FUNCTION_NAME}" --gen2 --region="${REGION}" --project="${PROJECT_ID}" --quiet || true
    fi
    
    # Remove buckets if they exist
    if gsutil ls -p "${PROJECT_ID}" "gs://${ORIGINAL_BUCKET}" >/dev/null 2>&1; then
        log_info "Removing original images bucket..."
        gsutil -m rm -r "gs://${ORIGINAL_BUCKET}" || true
    fi
    
    if gsutil ls -p "${PROJECT_ID}" "gs://${RESIZED_BUCKET}" >/dev/null 2>&1; then
        log_info "Removing resized images bucket..."
        gsutil -m rm -r "gs://${RESIZED_BUCKET}" || true
    fi
    
    # Clean up local files
    if [[ -d "cloud-function-resize" ]]; then
        rm -rf cloud-function-resize
    fi
    
    log_error "Cleanup completed. Please check the logs above for the specific error."
    exit 1
}

# Set error trap
trap cleanup_on_error ERR

# Print banner
echo "=================================================="
echo "  GCP Image Resizing Infrastructure Deployment"
echo "=================================================="
echo

# Check prerequisites
log_info "Checking prerequisites..."

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    log_error "Google Cloud CLI (gcloud) is not installed or not in PATH"
    log_error "Please install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if gsutil is available
if ! command -v gsutil &> /dev/null; then
    log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
    exit 1
fi

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    log_error "Python 3 is not installed or not in PATH"
    exit 1
fi

log_success "Prerequisites check completed"

# Set environment variables with defaults
export PROJECT_ID="${PROJECT_ID:-image-resize-$(date +%s)}"
export REGION="${REGION:-us-central1}"
export ZONE="${ZONE:-us-central1-a}"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(3))")

# Set resource names
export ORIGINAL_BUCKET="${ORIGINAL_BUCKET:-original-images-${RANDOM_SUFFIX}}"
export RESIZED_BUCKET="${RESIZED_BUCKET:-resized-images-${RANDOM_SUFFIX}}"
export FUNCTION_NAME="${FUNCTION_NAME:-resize-image-function}"

# Display configuration
echo "Deployment Configuration:"
echo "========================="
echo "Project ID: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Zone: ${ZONE}"
echo "Original Bucket: ${ORIGINAL_BUCKET}"
echo "Resized Bucket: ${RESIZED_BUCKET}"
echo "Function Name: ${FUNCTION_NAME}"
echo

# Check if project exists
log_info "Verifying project access..."
if ! gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
    log_error "Cannot access project '${PROJECT_ID}'. Please check:"
    log_error "1. Project ID is correct"
    log_error "2. You have appropriate permissions"
    log_error "3. You are authenticated (run 'gcloud auth login')"
    exit 1
fi

log_success "Project access verified"

# Confirm deployment
confirm "This will create resources in project '${PROJECT_ID}' that may incur charges."

# Set default project and region
log_info "Configuring gcloud settings..."
gcloud config set project "${PROJECT_ID}"
gcloud config set compute/region "${REGION}"
gcloud config set functions/region "${REGION}"

# Enable required APIs
log_info "Enabling required APIs..."
log_info "This may take a few minutes..."

apis=(
    "cloudfunctions.googleapis.com"
    "storage.googleapis.com"
    "eventarc.googleapis.com"
    "cloudbuild.googleapis.com"
    "run.googleapis.com"
)

for api in "${apis[@]}"; do
    log_info "Enabling ${api}..."
    gcloud services enable "${api}" --project="${PROJECT_ID}"
done

log_success "APIs enabled successfully"

# Wait for API enablement to propagate
log_info "Waiting for API enablement to propagate..."
sleep 10

# Create Cloud Storage Buckets
log_info "Creating Cloud Storage buckets..."

# Check if buckets already exist
if gsutil ls -p "${PROJECT_ID}" "gs://${ORIGINAL_BUCKET}" >/dev/null 2>&1; then
    log_warning "Original bucket gs://${ORIGINAL_BUCKET} already exists"
else
    log_info "Creating original images bucket..."
    gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${ORIGINAL_BUCKET}"
    gsutil uniformbucketlevelaccess set on "gs://${ORIGINAL_BUCKET}"
    log_success "Original images bucket created"
fi

if gsutil ls -p "${PROJECT_ID}" "gs://${RESIZED_BUCKET}" >/dev/null 2>&1; then
    log_warning "Resized bucket gs://${RESIZED_BUCKET} already exists"
else
    log_info "Creating resized images bucket..."
    gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${RESIZED_BUCKET}"
    gsutil uniformbucketlevelaccess set on "gs://${RESIZED_BUCKET}"
    log_success "Resized images bucket created"
fi

# Create function directory and dependencies
log_info "Setting up Cloud Function code..."

# Clean up any existing directory
if [[ -d "cloud-function-resize" ]]; then
    rm -rf cloud-function-resize
fi

mkdir -p cloud-function-resize
cd cloud-function-resize

# Create requirements.txt
cat > requirements.txt << 'EOF'
Pillow>=10.0.0
google-cloud-storage>=2.10.0
functions-framework>=3.4.0
EOF

# Create main function file
cat > main.py << 'EOF'
import os
import tempfile
from PIL import Image
from google.cloud import storage
import functions_framework

# Initialize Cloud Storage client
storage_client = storage.Client()

# Define thumbnail sizes (width, height)
THUMBNAIL_SIZES = [
    (150, 150),   # Small thumbnail
    (300, 300),   # Medium thumbnail
    (600, 600),   # Large thumbnail
]

@functions_framework.cloud_event
def resize_image(cloud_event):
    """
    Triggered by Cloud Storage object finalization.
    Resizes uploaded images and saves thumbnails.
    """
    # Parse event data
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    print(f"Processing image: {file_name} from bucket: {bucket_name}")
    
    # Skip if file is not an image
    if not file_name.lower().endswith(('.jpg', '.jpeg', '.png', '.bmp', '.tiff')):
        print(f"Skipping non-image file: {file_name}")
        return
    
    # Skip if already a resized image (prevent recursion)
    if 'resized' in file_name.lower():
        print(f"Skipping already resized image: {file_name}")
        return
    
    try:
        # Download image from source bucket
        source_bucket = storage_client.bucket(bucket_name)
        source_blob = source_bucket.blob(file_name)
        
        # Create temporary file
        with tempfile.NamedTemporaryFile() as temp_file:
            source_blob.download_to_filename(temp_file.name)
            
            # Open and process image
            with Image.open(temp_file.name) as image:
                # Convert to RGB if necessary (for PNG with transparency)
                if image.mode in ('RGBA', 'LA', 'P'):
                    image = image.convert('RGB')
                
                # Get resized images bucket
                resized_bucket_name = os.environ.get('RESIZED_BUCKET')
                if not resized_bucket_name:
                    print("RESIZED_BUCKET environment variable not set")
                    return
                
                resized_bucket = storage_client.bucket(resized_bucket_name)
                
                # Create thumbnails in different sizes
                for width, height in THUMBNAIL_SIZES:
                    # Calculate resize dimensions maintaining aspect ratio
                    image_ratio = image.width / image.height
                    target_ratio = width / height
                    
                    if image_ratio > target_ratio:
                        # Image is wider, fit to width
                        new_width = width
                        new_height = int(width / image_ratio)
                    else:
                        # Image is taller, fit to height
                        new_height = height
                        new_width = int(height * image_ratio)
                    
                    # Resize image with high-quality resampling
                    resized_image = image.resize(
                        (new_width, new_height), 
                        Image.Resampling.LANCZOS
                    )
                    
                    # Generate output filename
                    name_parts = os.path.splitext(file_name)
                    output_name = f"{name_parts[0]}_resized_{width}x{height}{name_parts[1]}"
                    
                    # Save to temporary file
                    with tempfile.NamedTemporaryFile(suffix='.jpg') as output_temp:
                        resized_image.save(
                            output_temp.name, 
                            'JPEG', 
                            quality=85, 
                            optimize=True
                        )
                        
                        # Upload to resized bucket
                        output_blob = resized_bucket.blob(output_name)
                        output_blob.upload_from_filename(
                            output_temp.name,
                            content_type='image/jpeg'
                        )
                        
                        print(f"Created thumbnail: {output_name} ({width}x{height})")
                
                print(f"Successfully processed {file_name}")
    
    except Exception as e:
        print(f"Error processing {file_name}: {str(e)}")
        raise
EOF

log_success "Cloud Function code created"

# Deploy Cloud Function
log_info "Deploying Cloud Function with Storage trigger..."
log_info "This may take several minutes..."

# Set environment variable for the function
export RESIZED_BUCKET_ENV="RESIZED_BUCKET=${RESIZED_BUCKET}"

# Deploy function
gcloud functions deploy "${FUNCTION_NAME}" \
    --gen2 \
    --runtime=python311 \
    --region="${REGION}" \
    --source=. \
    --entry-point=resize_image \
    --trigger-event-type="google.cloud.storage.object.v1.finalized" \
    --trigger-event-filters="bucket=${ORIGINAL_BUCKET}" \
    --set-env-vars="${RESIZED_BUCKET_ENV}" \
    --memory=512MB \
    --timeout=120s \
    --max-instances=10

log_success "Cloud Function deployed successfully"

# Configure IAM permissions
log_info "Configuring IAM permissions..."

# Get project number for service account
PROJECT_NUMBER=$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

# Grant storage permissions
log_info "Granting storage permissions to service account..."
gsutil iam ch "serviceAccount:${SERVICE_ACCOUNT}:objectViewer" "gs://${ORIGINAL_BUCKET}"
gsutil iam ch "serviceAccount:${SERVICE_ACCOUNT}:objectAdmin" "gs://${RESIZED_BUCKET}"

log_success "IAM permissions configured"

# Create test image and test the function
log_info "Creating test image for validation..."

python3 -c "
from PIL import Image
import os

# Create a test image
img = Image.new('RGB', (1200, 800), color='red')
img.save('test-image.jpg', 'JPEG')
print('Test image created: test-image.jpg')
"

log_info "Uploading test image to trigger function..."
gsutil cp test-image.jpg "gs://${ORIGINAL_BUCKET}/"

log_info "Waiting for function processing to complete..."
sleep 30

# Validate deployment
log_info "Validating deployment..."

# Check if resized images were created
RESIZED_COUNT=$(gsutil ls "gs://${RESIZED_BUCKET}/" 2>/dev/null | wc -l || echo "0")
if [[ ${RESIZED_COUNT} -ge 3 ]]; then
    log_success "Validation successful: ${RESIZED_COUNT} resized images created"
else
    log_warning "Validation incomplete: Only ${RESIZED_COUNT} resized images found"
    log_info "This may be normal if processing is still in progress"
fi

# Clean up local files
cd ..
rm -rf cloud-function-resize

# Print deployment summary
echo
echo "=================================================="
echo "         Deployment Summary"
echo "=================================================="
echo -e "Status: ${GREEN}SUCCESS${NC}"
echo "Project ID: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Original Images Bucket: gs://${ORIGINAL_BUCKET}"
echo "Resized Images Bucket: gs://${RESIZED_BUCKET}"
echo "Cloud Function: ${FUNCTION_NAME}"
echo
echo "Next Steps:"
echo "1. Upload images to gs://${ORIGINAL_BUCKET} to test the resizing function"
echo "2. Check gs://${RESIZED_BUCKET} for automatically generated thumbnails"
echo "3. Monitor function logs with:"
echo "   gcloud functions logs read ${FUNCTION_NAME} --gen2 --region=${REGION}"
echo
echo "To clean up resources, run:"
echo "   ./destroy.sh"
echo "=================================================="

log_success "Deployment completed successfully!"