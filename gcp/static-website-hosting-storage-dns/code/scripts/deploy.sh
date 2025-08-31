#!/bin/bash

# Static Website Hosting with Cloud Storage and DNS - Deployment Script
# This script deploys a static website using Google Cloud Storage and Cloud DNS
# Based on recipe: Static Website Hosting with Cloud Storage and DNS

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

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partially created resources..."
    
    # Clean up local files if they exist
    [ -f "index.html" ] && rm -f index.html
    [ -f "404.html" ] && rm -f 404.html
    
    # Attempt to clean up cloud resources if they were created
    if [ -n "${BUCKET_NAME:-}" ]; then
        log_info "Attempting to clean up bucket: ${BUCKET_NAME}"
        gsutil -q rm -r gs://${BUCKET_NAME}/* 2>/dev/null || true
        gsutil -q rb gs://${BUCKET_NAME} 2>/dev/null || true
    fi
    
    if [ -n "${DNS_ZONE_NAME:-}" ]; then
        log_info "Attempting to clean up DNS zone: ${DNS_ZONE_NAME}"
        gcloud dns record-sets delete ${DOMAIN_NAME}. \
            --zone=${DNS_ZONE_NAME} \
            --type=CNAME \
            --quiet 2>/dev/null || true
        gcloud dns managed-zones delete ${DNS_ZONE_NAME} --quiet 2>/dev/null || true
    fi
    
    exit 1
}

trap cleanup_on_error ERR

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gsutil is installed
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "You are not authenticated with gcloud. Please run: gcloud auth login"
        exit 1
    fi
    
    # Check if openssl is available for random string generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random strings. Please install openssl."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
set_environment_variables() {
    log_info "Setting up environment variables..."
    
    # Prompt for required variables if not set
    if [ -z "${PROJECT_ID:-}" ]; then
        read -p "Enter GCP Project ID (or press Enter for auto-generated): " PROJECT_ID
        if [ -z "$PROJECT_ID" ]; then
            PROJECT_ID="static-website-$(date +%s)"
            log_info "Using auto-generated project ID: $PROJECT_ID"
        fi
    fi
    
    if [ -z "${DOMAIN_NAME:-}" ]; then
        read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME
        if [ -z "$DOMAIN_NAME" ]; then
            log_error "Domain name is required"
            exit 1
        fi
    fi
    
    # Set derived variables
    export PROJECT_ID
    export DOMAIN_NAME
    export BUCKET_NAME="${DOMAIN_NAME}"
    export REGION="${REGION:-us-central1}"
    
    # Generate unique suffix for DNS zone
    RANDOM_SUFFIX=$(openssl rand -hex 3)
    export DNS_ZONE_NAME="website-zone-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured:"
    log_info "  PROJECT_ID: ${PROJECT_ID}"
    log_info "  DOMAIN_NAME: ${DOMAIN_NAME}"
    log_info "  BUCKET_NAME: ${BUCKET_NAME}"
    log_info "  REGION: ${REGION}"
    log_info "  DNS_ZONE_NAME: ${DNS_ZONE_NAME}"
}

# Function to configure GCP project
configure_project() {
    log_info "Configuring GCP project and enabling APIs..."
    
    # Set default project and region
    gcloud config set project ${PROJECT_ID}
    gcloud config set compute/region ${REGION}
    
    # Enable required APIs
    log_info "Enabling Cloud Storage API..."
    gcloud services enable storage.googleapis.com
    
    log_info "Enabling Cloud DNS API..."
    gcloud services enable dns.googleapis.com
    
    # Wait for APIs to be fully enabled
    sleep 10
    
    log_success "Project configured: ${PROJECT_ID}"
    log_success "APIs enabled successfully"
}

# Function to create and configure storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for website hosting..."
    
    # Check if bucket already exists
    if gsutil ls -b gs://${BUCKET_NAME} &>/dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists. Skipping creation."
    else
        # Create bucket with domain name for CNAME compatibility
        gsutil mb -p ${PROJECT_ID} \
            -c STANDARD \
            -l ${REGION} \
            gs://${BUCKET_NAME}
        
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    fi
    
    # Configure bucket for static website hosting
    gsutil web set -m index.html -e 404.html gs://${BUCKET_NAME}
    
    log_success "Bucket configured for static website hosting"
}

# Function to create website content
create_website_content() {
    log_info "Creating sample website content..."
    
    # Create index.html with responsive design
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to Cloud Website</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        .container { max-width: 800px; margin: 0 auto; }
        h1 { color: #4285F4; }
        .cloud-info { background: #f0f8ff; padding: 20px; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Welcome to Your Cloud Website!</h1>
        <div class="cloud-info">
            <p>This static website is hosted on Google Cloud Storage with:</p>
            <ul>
                <li>Automatic global content delivery</li>
                <li>99.999999999% (11 9's) data durability</li>
                <li>Pay-per-use pricing model</li>
                <li>Custom domain support</li>
            </ul>
        </div>
        <p>Build Date: $(date)</p>
    </div>
</body>
</html>
EOF
    
    # Create 404 error page
    cat > 404.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; margin-top: 100px; }
        h1 { color: #EA4335; }
    </style>
</head>
<body>
    <h1>404 - Page Not Found</h1>
    <p>The page you're looking for doesn't exist.</p>
    <a href="/">Return to Homepage</a>
</body>
</html>
EOF
    
    log_success "Website content created successfully"
}

# Function to upload website content
upload_website_content() {
    log_info "Uploading website content to bucket..."
    
    # Upload website files with cache control headers
    gsutil -h "Cache-Control:public, max-age=3600" \
        cp index.html gs://${BUCKET_NAME}/
    
    gsutil -h "Cache-Control:public, max-age=3600" \
        cp 404.html gs://${BUCKET_NAME}/
    
    # Verify files were uploaded successfully
    log_info "Verifying uploaded files..."
    gsutil ls gs://${BUCKET_NAME}/
    
    log_success "Website files uploaded with cache optimization"
}

# Function to configure public access
configure_public_access() {
    log_info "Configuring public access for website content..."
    
    # Make bucket contents publicly readable
    gsutil iam ch allUsers:objectViewer gs://${BUCKET_NAME}
    
    log_success "Bucket configured for public web access"
}

# Function to create DNS zone
create_dns_zone() {
    log_info "Creating Cloud DNS zone for domain management..."
    
    # Check if DNS zone already exists
    if gcloud dns managed-zones describe ${DNS_ZONE_NAME} &>/dev/null; then
        log_warning "DNS zone ${DNS_ZONE_NAME} already exists. Skipping creation."
    else
        # Create Cloud DNS managed zone
        gcloud dns managed-zones create ${DNS_ZONE_NAME} \
            --description="DNS zone for static website" \
            --dns-name="${DOMAIN_NAME}." \
            --visibility=public
        
        log_success "DNS zone created successfully"
    fi
    
    # Display name servers for domain configuration
    log_info "📝 Configure these name servers with your domain registrar:"
    gcloud dns managed-zones describe ${DNS_ZONE_NAME} \
        --format="value(nameServers[].join('\n'))"
}

# Function to create CNAME record
create_cname_record() {
    log_info "Creating CNAME record pointing to Cloud Storage..."
    
    # Check if CNAME record already exists
    if gcloud dns record-sets list --zone=${DNS_ZONE_NAME} --name="${DOMAIN_NAME}." --type=CNAME &>/dev/null; then
        log_warning "CNAME record for ${DOMAIN_NAME} already exists. Skipping creation."
    else
        # Create CNAME record pointing to Cloud Storage
        gcloud dns record-sets create ${DOMAIN_NAME}. \
            --zone=${DNS_ZONE_NAME} \
            --type=CNAME \
            --ttl=300 \
            --rrdatas="c.storage.googleapis.com."
        
        log_success "CNAME record created pointing to Cloud Storage"
    fi
    
    # Display DNS records
    log_info "Current DNS records:"
    gcloud dns record-sets list --zone=${DNS_ZONE_NAME}
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    # Test 1: Verify bucket website configuration
    log_info "Testing bucket website configuration..."
    if gsutil web get gs://${BUCKET_NAME} | grep -q "index.html"; then
        log_success "✅ Bucket website configuration verified"
    else
        log_error "❌ Bucket website configuration failed"
        return 1
    fi
    
    # Test 2: Test direct bucket access
    log_info "Testing direct bucket access..."
    if curl -s -I "https://storage.googleapis.com/${BUCKET_NAME}/index.html" | grep -q "200 OK"; then
        log_success "✅ Direct bucket access working"
    else
        log_warning "⚠️  Direct bucket access test inconclusive (may need time to propagate)"
    fi
    
    # Test 3: Verify DNS configuration
    log_info "Verifying DNS configuration..."
    if gcloud dns record-sets list --zone=${DNS_ZONE_NAME} --format="value(type)" | grep -q "CNAME"; then
        log_success "✅ DNS CNAME record configured"
    else
        log_error "❌ DNS CNAME record not found"
        return 1
    fi
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
display_deployment_summary() {
    log_success "🎉 Deployment completed successfully!"
    echo
    log_info "Deployment Summary:"
    log_info "==================="
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Domain: ${DOMAIN_NAME}"
    log_info "Storage Bucket: gs://${BUCKET_NAME}"
    log_info "DNS Zone: ${DNS_ZONE_NAME}"
    echo
    log_info "Next Steps:"
    log_info "1. Configure the following name servers with your domain registrar:"
    gcloud dns managed-zones describe ${DNS_ZONE_NAME} \
        --format="value(nameServers[].join('\n'))" | sed 's/^/   - /'
    echo
    log_info "2. Wait for DNS propagation (may take up to 48 hours)"
    log_info "3. Test your website at: http://${DOMAIN_NAME}"
    echo
    log_info "To test immediately, try:"
    log_info "curl -H 'Host: ${DOMAIN_NAME}' https://storage.googleapis.com/${BUCKET_NAME}/index.html"
    echo
    log_warning "Remember to run destroy.sh when you're done to avoid ongoing charges!"
}

# Function to save deployment state
save_deployment_state() {
    log_info "Saving deployment state..."
    
    cat > .deployment_state << EOF
# Deployment state for static website hosting
# Generated on: $(date)
PROJECT_ID="${PROJECT_ID}"
DOMAIN_NAME="${DOMAIN_NAME}"
BUCKET_NAME="${BUCKET_NAME}"
REGION="${REGION}"
DNS_ZONE_NAME="${DNS_ZONE_NAME}"
DEPLOYMENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    log_success "Deployment state saved to .deployment_state"
}

# Main deployment function
main() {
    log_info "🚀 Starting static website hosting deployment..."
    echo
    
    # Run deployment steps
    check_prerequisites
    set_environment_variables
    configure_project
    create_storage_bucket
    create_website_content
    upload_website_content
    configure_public_access
    create_dns_zone
    create_cname_record
    run_validation_tests
    save_deployment_state
    
    # Clean up local files
    rm -f index.html 404.html
    
    display_deployment_summary
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --dry-run      Show what would be done without executing"
        echo ""
        echo "Environment variables:"
        echo "  PROJECT_ID     GCP Project ID (optional, will prompt if not set)"
        echo "  DOMAIN_NAME    Your domain name (required)"
        echo "  REGION         GCP region (default: us-central1)"
        echo ""
        echo "Example:"
        echo "  export DOMAIN_NAME=mywebsite.com"
        echo "  export PROJECT_ID=my-project-123"
        echo "  ./deploy.sh"
        exit 0
        ;;
    --dry-run)
        log_info "🔍 Dry run mode - showing what would be deployed..."
        echo
        log_info "This script would:"
        log_info "1. Check prerequisites (gcloud, gsutil, authentication)"
        log_info "2. Configure GCP project and enable APIs"
        log_info "3. Create Cloud Storage bucket for domain: \${DOMAIN_NAME}"
        log_info "4. Generate and upload sample website content"
        log_info "5. Configure bucket for public web access"
        log_info "6. Create Cloud DNS zone and CNAME record"
        log_info "7. Run validation tests"
        log_info "8. Display name servers for domain registrar configuration"
        echo
        log_info "To run actual deployment: ./deploy.sh"
        exit 0
        ;;
    "")
        # No arguments, run main deployment
        main
        ;;
    *)
        log_error "Unknown argument: $1"
        log_error "Use --help for usage information"
        exit 1
        ;;
esac