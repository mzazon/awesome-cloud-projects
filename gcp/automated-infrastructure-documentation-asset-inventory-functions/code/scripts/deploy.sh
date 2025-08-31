#!/bin/bash

# Deploy script for Automated Infrastructure Documentation using Asset Inventory and Cloud Functions
# Recipe: automated-infrastructure-documentation-asset-inventory-functions
# Provider: GCP

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Error handling
handle_error() {
    log_error "Deployment failed at line $1. Exiting..."
    exit 1
}

trap 'handle_error $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Automated Infrastructure Documentation using Asset Inventory and Cloud Functions

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP Region (default: us-central1)
    -h, --help                    Show this help message
    --dry-run                     Show what would be deployed without executing
    --skip-apis                   Skip API enablement (useful for repeated deployments)

ENVIRONMENT VARIABLES:
    GOOGLE_CLOUD_PROJECT          Alternative way to set project ID
    GOOGLE_CLOUD_REGION          Alternative way to set region

EXAMPLES:
    $0 --project-id my-project-123
    $0 --project-id my-project-123 --region us-west1
    $0 --project-id my-project-123 --dry-run

EOF
}

# Default values
REGION="us-central1"
ZONE="us-central1-a"
DRY_RUN=false
SKIP_APIS=false
PROJECT_ID=""

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
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-apis)
            SKIP_APIS=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set project ID from environment if not provided
if [[ -z "$PROJECT_ID" ]]; then
    if [[ -n "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
        PROJECT_ID="$GOOGLE_CLOUD_PROJECT"
    else
        log_error "Project ID is required. Use --project-id or set GOOGLE_CLOUD_PROJECT environment variable."
        show_help
        exit 1
    fi
fi

# Set region from environment if not provided via command line
if [[ -n "${GOOGLE_CLOUD_REGION:-}" && "$REGION" == "us-central1" ]]; then
    REGION="$GOOGLE_CLOUD_REGION"
fi

# Set zone based on region
ZONE="${REGION}-a"

log "Starting deployment for Automated Infrastructure Documentation"
log "Project ID: $PROJECT_ID"
log "Region: $REGION"
log "Zone: $ZONE"
log "Dry Run: $DRY_RUN"

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Cannot access project '$PROJECT_ID'. Check project ID and permissions."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please ensure Google Cloud SDK is properly installed."
        exit 1
    fi
    
    # Check if Python 3 is available (needed for function development)
    if ! command -v python3 &> /dev/null; then
        log_warning "Python 3 is not available. This may be needed for local function development."
    fi
    
    log_success "Prerequisites check completed"
}

# Execute command with dry run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would execute: $cmd"
        log "[DRY RUN] Description: $description"
    else
        log "Executing: $description"
        eval "$cmd"
    fi
}

# Generate unique suffix for resources
generate_unique_suffix() {
    if command -v openssl &> /dev/null; then
        openssl rand -hex 3
    else
        # Fallback using date and random
        echo "$(date +%s | tail -c 6)$(printf '%02x' $((RANDOM % 256)))"
    fi
}

# Main deployment function
deploy_infrastructure() {
    log "Starting infrastructure deployment..."
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(generate_unique_suffix)
    
    # Set environment variables for resources
    export BUCKET_NAME="asset-docs-${RANDOM_SUFFIX}"
    export FUNCTION_NAME="asset-doc-generator"
    export TOPIC_NAME="asset-inventory-trigger"
    export SCHEDULER_JOB="daily-asset-docs"
    export FUNCTION_SOURCE_DIR="asset-doc-function"
    
    log "Resource names:"
    log "  Bucket: $BUCKET_NAME"
    log "  Function: $FUNCTION_NAME"
    log "  Topic: $TOPIC_NAME"
    log "  Scheduler: $SCHEDULER_JOB"
    
    # Set default project and region
    execute_command "gcloud config set project ${PROJECT_ID}" "Setting default project"
    execute_command "gcloud config set compute/region ${REGION}" "Setting default region"
    execute_command "gcloud config set compute/zone ${ZONE}" "Setting default zone"
    
    # Enable required APIs
    if [[ "$SKIP_APIS" == "false" ]]; then
        log "Enabling required APIs..."
        execute_command "gcloud services enable cloudasset.googleapis.com" "Enabling Cloud Asset Inventory API"
        execute_command "gcloud services enable cloudfunctions.googleapis.com" "Enabling Cloud Functions API"
        execute_command "gcloud services enable cloudscheduler.googleapis.com" "Enabling Cloud Scheduler API"
        execute_command "gcloud services enable pubsub.googleapis.com" "Enabling Pub/Sub API"
        execute_command "gcloud services enable storage.googleapis.com" "Enabling Cloud Storage API"
        
        if [[ "$DRY_RUN" == "false" ]]; then
            log "Waiting for APIs to be fully enabled..."
            sleep 30
        fi
        log_success "APIs enabled"
    else
        log_warning "Skipping API enablement"
    fi
    
    # Create Cloud Storage Bucket
    log "Creating Cloud Storage bucket..."
    execute_command "gsutil mb -p ${PROJECT_ID} -c STANDARD -l ${REGION} gs://${BUCKET_NAME}" "Creating storage bucket"
    execute_command "gsutil versioning set on gs://${BUCKET_NAME}" "Enabling bucket versioning"
    
    # Set up bucket structure
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "" | gsutil cp - gs://${BUCKET_NAME}/reports/.gitkeep
        echo "" | gsutil cp - gs://${BUCKET_NAME}/exports/.gitkeep
        echo "" | gsutil cp - gs://${BUCKET_NAME}/templates/.gitkeep
    fi
    log_success "Storage bucket created: gs://${BUCKET_NAME}"
    
    # Create Pub/Sub Topic
    log "Creating Pub/Sub topic..."
    execute_command "gcloud pubsub topics create ${TOPIC_NAME}" "Creating Pub/Sub topic"
    log_success "Pub/Sub topic created: ${TOPIC_NAME}"
    
    # Create function source directory and files
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Creating Cloud Function source code..."
        mkdir -p "$FUNCTION_SOURCE_DIR"
        cd "$FUNCTION_SOURCE_DIR"
        
        # Create main.py
        cat > main.py << 'EOF'
import json
import os
from datetime import datetime
from google.cloud import asset_v1
from google.cloud import storage
import functions_framework

@functions_framework.cloud_event
def generate_asset_documentation(cloud_event):
    """
    Triggered by Pub/Sub to generate infrastructure documentation
    from Cloud Asset Inventory data
    """
    
    project_id = os.environ.get('GCP_PROJECT')
    bucket_name = os.environ.get('STORAGE_BUCKET')
    
    # Initialize clients
    asset_client = asset_v1.AssetServiceClient()
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    
    try:
        # Query all assets in the project
        parent = f"projects/{project_id}"
        request = asset_v1.ListAssetsRequest(
            parent=parent,
            content_type=asset_v1.ContentType.RESOURCE,
            page_size=1000
        )
        assets = asset_client.list_assets(request=request)
        
        # Process and categorize assets
        asset_summary = categorize_assets(assets)
        
        # Generate HTML report
        html_content = generate_html_report(asset_summary)
        upload_to_storage(bucket, 'reports/infrastructure-report.html', html_content)
        
        # Generate markdown documentation
        markdown_content = generate_markdown_docs(asset_summary)
        upload_to_storage(bucket, 'reports/infrastructure-docs.md', markdown_content)
        
        # Export raw JSON data
        json_content = json.dumps(asset_summary, indent=2, default=str)
        upload_to_storage(bucket, 'exports/asset-inventory.json', json_content)
        
        print(f"✅ Documentation generated successfully at {datetime.now()}")
        return {'status': 'success', 'timestamp': datetime.now().isoformat()}
        
    except Exception as e:
        print(f"❌ Error generating documentation: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def categorize_assets(assets):
    """Categorize assets by type and extract key information"""
    categories = {
        'compute': [],
        'storage': [],
        'networking': [],
        'databases': [],
        'security': [],
        'other': []
    }
    
    for asset in assets:
        asset_info = {
            'name': asset.name,
            'asset_type': asset.asset_type,
            'create_time': asset.resource.discovery_document_uri if asset.resource else None,
            'location': asset.resource.location if asset.resource else 'global'
        }
        
        # Categorize by asset type
        if 'compute' in asset.asset_type.lower():
            categories['compute'].append(asset_info)
        elif 'storage' in asset.asset_type.lower():
            categories['storage'].append(asset_info)
        elif any(net in asset.asset_type.lower() for net in ['network', 'firewall', 'subnet']):
            categories['networking'].append(asset_info)
        elif any(db in asset.asset_type.lower() for db in ['sql', 'database', 'datastore']):
            categories['databases'].append(asset_info)
        elif any(sec in asset.asset_type.lower() for sec in ['iam', 'security', 'kms']):
            categories['security'].append(asset_info)
        else:
            categories['other'].append(asset_info)
    
    return categories

def generate_html_report(asset_summary):
    """Generate HTML infrastructure report"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Infrastructure Documentation Report</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; }}
            .header {{ background-color: #4285F4; color: white; padding: 20px; border-radius: 5px; }}
            .category {{ margin: 20px 0; }}
            .category h2 {{ color: #34A853; border-bottom: 2px solid #34A853; }}
            table {{ border-collapse: collapse; width: 100%; margin: 10px 0; }}
            th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
            th {{ background-color: #f2f2f2; }}
            .timestamp {{ color: #666; font-size: 0.9em; }}
        </style>
    </head>
    <body>
        <div class="header">
            <h1>Google Cloud Infrastructure Documentation</h1>
            <p class="timestamp">Generated: {timestamp}</p>
        </div>
    """
    
    for category, assets in asset_summary.items():
        if assets:
            html += f"""
            <div class="category">
                <h2>{category.title()} Resources ({len(assets)})</h2>
                <table>
                    <tr>
                        <th>Resource Name</th>
                        <th>Asset Type</th>
                        <th>Location</th>
                    </tr>
            """
            for asset in assets:
                html += f"""
                    <tr>
                        <td>{asset['name'].split('/')[-1]}</td>
                        <td>{asset['asset_type']}</td>
                        <td>{asset['location']}</td>
                    </tr>
                """
            html += "</table></div>"
    
    html += "</body></html>"
    return html

def generate_markdown_docs(asset_summary):
    """Generate markdown documentation"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    markdown = f"""# Google Cloud Infrastructure Documentation

Generated: {timestamp}

## Overview

This document provides an automated inventory of all Google Cloud resources in the current project.

"""
    
    for category, assets in asset_summary.items():
        if assets:
            markdown += f"""## {category.title()} Resources ({len(assets)})

| Resource Name | Asset Type | Location |
|---------------|------------|----------|
"""
            for asset in assets:
                name = asset['name'].split('/')[-1]
                markdown += f"| {name} | {asset['asset_type']} | {asset['location']} |\n"
            
            markdown += "\n"
    
    return markdown

def upload_to_storage(bucket, filename, content):
    """Upload content to Cloud Storage"""
    blob = bucket.blob(filename)
    blob.upload_from_string(content)
    print(f"Uploaded {filename} to bucket")
EOF
        
        # Create requirements.txt
        cat > requirements.txt << 'EOF'
google-cloud-asset>=3.20.0
google-cloud-storage>=2.10.0
functions-framework>=3.5.0
EOF
        
        # Create .env.yaml
        cat > .env.yaml << EOF
GCP_PROJECT: ${PROJECT_ID}
STORAGE_BUCKET: ${BUCKET_NAME}
EOF
        
        log_success "Cloud Function source code created"
    else
        log "[DRY RUN] Would create Cloud Function source code in ${FUNCTION_SOURCE_DIR}/"
    fi
    
    # Deploy Cloud Function
    log "Deploying Cloud Function..."
    if [[ "$DRY_RUN" == "false" ]]; then
        execute_command "gcloud functions deploy ${FUNCTION_NAME} \
            --gen2 \
            --runtime python313 \
            --trigger-topic ${TOPIC_NAME} \
            --source . \
            --entry-point generate_asset_documentation \
            --memory 512MB \
            --timeout 300s \
            --env-vars-file .env.yaml \
            --max-instances 10 \
            --region ${REGION}" "Deploying Cloud Function"
        cd ..
    else
        log "[DRY RUN] Would deploy Cloud Function: ${FUNCTION_NAME}"
    fi
    log_success "Cloud Function deployed: ${FUNCTION_NAME}"
    
    # Create Cloud Scheduler job
    log "Creating Cloud Scheduler job..."
    execute_command "gcloud scheduler jobs create pubsub ${SCHEDULER_JOB} \
        --schedule=\"0 9 * * *\" \
        --topic=${TOPIC_NAME} \
        --message-body='{\"trigger\": \"scheduled\"}' \
        --time-zone=\"UTC\" \
        --location=${REGION} \
        --description=\"Daily infrastructure documentation generation\"" "Creating Cloud Scheduler job"
    log_success "Cloud Scheduler job created: ${SCHEDULER_JOB}"
    
    # Configure IAM permissions
    log "Configuring IAM permissions..."
    if [[ "$DRY_RUN" == "false" ]]; then
        # Get the Cloud Function service account
        FUNCTION_SA=$(gcloud functions describe ${FUNCTION_NAME} \
            --region=${REGION} \
            --format="value(serviceConfig.serviceAccountEmail)")
        
        # Grant Asset Inventory access
        execute_command "gcloud projects add-iam-policy-binding ${PROJECT_ID} \
            --member=\"serviceAccount:${FUNCTION_SA}\" \
            --role=\"roles/cloudasset.viewer\"" "Granting Asset Inventory access"
        
        # Grant Storage access
        execute_command "gcloud projects add-iam-policy-binding ${PROJECT_ID} \
            --member=\"serviceAccount:${FUNCTION_SA}\" \
            --role=\"roles/storage.objectAdmin\"" "Granting Storage access"
        
        log_success "IAM permissions configured for service account: ${FUNCTION_SA}"
    else
        log "[DRY RUN] Would configure IAM permissions for Cloud Function service account"
    fi
    
    # Test deployment with manual trigger
    log "Testing deployment with manual trigger..."
    execute_command "gcloud pubsub topics publish ${TOPIC_NAME} \
        --message='{\"trigger\": \"deployment_test\"}'" "Publishing test message"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "Waiting for function execution..."
        sleep 30
        
        # Check function logs
        log "Recent function logs:"
        gcloud functions logs read ${FUNCTION_NAME} \
            --region=${REGION} \
            --limit=5 \
            --format="value(timestamp,textPayload)" || true
    fi
    
    log_success "Deployment test completed"
}

# Save deployment configuration
save_deployment_config() {
    if [[ "$DRY_RUN" == "false" ]]; then
        cat > deployment-config.env << EOF
# Deployment configuration for Automated Infrastructure Documentation
# Generated on $(date)

PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
FUNCTION_NAME=${FUNCTION_NAME}
TOPIC_NAME=${TOPIC_NAME}
SCHEDULER_JOB=${SCHEDULER_JOB}
DEPLOYMENT_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
        log_success "Deployment configuration saved to deployment-config.env"
    fi
}

# Display deployment summary
show_deployment_summary() {
    log_success "Deployment completed successfully!"
    echo
    echo "======================================"
    echo "DEPLOYMENT SUMMARY"
    echo "======================================"
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "Storage Bucket: gs://$BUCKET_NAME"
    echo "Cloud Function: $FUNCTION_NAME"
    echo "Pub/Sub Topic: $TOPIC_NAME"
    echo "Scheduler Job: $SCHEDULER_JOB"
    echo
    echo "NEXT STEPS:"
    echo "1. Check function logs: gcloud functions logs read $FUNCTION_NAME --region=$REGION"
    echo "2. View generated reports: gsutil ls gs://$BUCKET_NAME/reports/"
    echo "3. Monitor scheduler: gcloud scheduler jobs describe $SCHEDULER_JOB --location=$REGION"
    echo "4. Access documentation: gsutil cp gs://$BUCKET_NAME/reports/infrastructure-report.html ./"
    echo
    echo "ESTIMATED MONTHLY COST: \$5-15 (based on organization size)"
    echo
    echo "To cleanup resources, run: ./destroy.sh --project-id $PROJECT_ID"
    echo "======================================"
}

# Main execution
main() {
    log "Automated Infrastructure Documentation Deployment Script"
    log "======================================================"
    
    check_prerequisites
    deploy_infrastructure
    save_deployment_config
    show_deployment_summary
}

# Run main function
main "$@"