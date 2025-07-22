#!/bin/bash

# Immersive XR Content Delivery with Immersive Stream for XR and Cloud CDN - Deployment Script
# This script deploys the complete XR content delivery platform infrastructure

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="xr-deployment-$(date +%Y%m%d-%H%M%S).log"
readonly REQUIRED_APIS=(
    "compute.googleapis.com"
    "storage.googleapis.com"
    "stream.googleapis.com"
    "networkservices.googleapis.com"
    "certificatemanager.googleapis.com"
    "logging.googleapis.com"
    "monitoring.googleapis.com"
    "iam.googleapis.com"
)

# Global variables
PROJECT_ID=""
REGION="us-central1"
ZONE="us-central1-a"
BUCKET_NAME=""
CDN_NAME=""
STREAM_NAME=""
RANDOM_SUFFIX=""
DRY_RUN=false
SKIP_PREREQUISITES=false
CLEANUP_ON_FAILURE=true

# Usage function
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy Immersive XR Content Delivery Platform on Google Cloud Platform

OPTIONS:
    -p, --project-id PROJECT_ID    Google Cloud Project ID (required)
    -r, --region REGION           Deployment region (default: us-central1)
    -z, --zone ZONE              Deployment zone (default: us-central1-a)
    -s, --suffix SUFFIX          Custom resource name suffix
    --dry-run                    Show what would be deployed without executing
    --skip-prerequisites         Skip prerequisite checks
    --no-cleanup-on-failure      Don't clean up resources if deployment fails
    -h, --help                   Show this help message

EXAMPLES:
    $SCRIPT_NAME --project-id my-xr-project
    $SCRIPT_NAME --project-id my-project --region europe-west1 --zone europe-west1-b
    $SCRIPT_NAME --project-id my-project --dry-run

EOF
}

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    if [[ "$CLEANUP_ON_FAILURE" == "true" && "$DRY_RUN" == "false" ]]; then
        log_warning "Initiating cleanup due to deployment failure..."
        cleanup_resources
    fi
    exit 1
}

# Cleanup function for failed deployments
cleanup_resources() {
    log_info "Cleaning up partially deployed resources..."
    
    # Best effort cleanup - don't fail if resources don't exist
    set +e
    
    # Delete XR service if exists
    if [[ -n "$STREAM_NAME" ]]; then
        gcloud beta immersive-stream xr service-instances delete "$STREAM_NAME" \
            --location="$REGION" --quiet 2>/dev/null || true
    fi
    
    # Delete load balancer components
    if [[ -n "$CDN_NAME" ]]; then
        gcloud compute forwarding-rules delete "${CDN_NAME}-rule" --global --quiet 2>/dev/null || true
        gcloud compute target-http-proxies delete "${CDN_NAME}-proxy" --quiet 2>/dev/null || true
        gcloud compute url-maps delete "${CDN_NAME}-urlmap" --quiet 2>/dev/null || true
        gcloud compute backend-buckets delete "${CDN_NAME}-backend" --quiet 2>/dev/null || true
    fi
    
    # Delete storage bucket
    if [[ -n "$BUCKET_NAME" ]]; then
        gsutil -m rm -r "gs://$BUCKET_NAME" 2>/dev/null || true
    fi
    
    # Delete service account
    gcloud iam service-accounts delete "xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com" --quiet 2>/dev/null || true
    
    set -e
}

# Trap for cleanup on script exit
trap 'cleanup_resources' ERR

# Check if running in dry-run mode
check_dry_run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE: Command would execute: $*"
        return 0
    fi
    return 1
}

# Execute command with dry-run support
execute_command() {
    local command="$*"
    log_info "Executing: $command"
    
    if check_dry_run "$command"; then
        return 0
    fi
    
    eval "$command"
}

# Prerequisite checks
check_prerequisites() {
    if [[ "$SKIP_PREREQUISITES" == "true" ]]; then
        log_warning "Skipping prerequisite checks as requested"
        return 0
    fi

    log_info "Checking prerequisites..."

    # Check if gcloud is installed and authenticated
    if ! command -v gcloud &> /dev/null; then
        error_exit "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
    fi

    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        error_exit "gsutil is not available. Please ensure Google Cloud SDK is properly installed"
    fi

    # Check authentication
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        error_exit "No active gcloud authentication found. Please run 'gcloud auth login'"
    fi

    # Validate project
    if [[ -z "$PROJECT_ID" ]]; then
        error_exit "Project ID is required. Use --project-id option"
    fi

    # Check if project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        error_exit "Project '$PROJECT_ID' not found or not accessible"
    fi

    # Check if billing is enabled
    local billing_account
    billing_account=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null || echo "")
    if [[ -z "$billing_account" ]]; then
        error_exit "Billing is not enabled for project '$PROJECT_ID'. Please enable billing in the Google Cloud Console"
    fi

    # Check required APIs
    log_info "Checking required APIs..."
    local missing_apis=()
    for api in "${REQUIRED_APIS[@]}"; do
        if ! gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
            missing_apis+=("$api")
        fi
    done

    if [[ ${#missing_apis[@]} -gt 0 ]]; then
        log_warning "The following APIs need to be enabled: ${missing_apis[*]}"
        if [[ "$DRY_RUN" == "false" ]]; then
            log_info "Enabling required APIs..."
            for api in "${missing_apis[@]}"; do
                execute_command "gcloud services enable $api --project=$PROJECT_ID"
            done
            log_info "Waiting for APIs to be fully enabled..."
            sleep 30
        fi
    fi

    # Check quotas (basic check)
    log_info "Checking basic quotas..."
    local compute_quota
    compute_quota=$(gcloud compute project-info describe --format="value(quotas[?metric=='CPUS'].usage,quotas[?metric=='CPUS'].limit)" 2>/dev/null || echo "0,0")
    log_info "Current CPU quota usage: $compute_quota"

    log_success "Prerequisites check completed"
}

# Generate unique resource names
generate_resource_names() {
    if [[ -z "$RANDOM_SUFFIX" ]]; then
        RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    BUCKET_NAME="xr-assets-${RANDOM_SUFFIX}"
    CDN_NAME="xr-cdn-${RANDOM_SUFFIX}"
    STREAM_NAME="xr-stream-${RANDOM_SUFFIX}"
    
    log_info "Generated resource names with suffix: $RANDOM_SUFFIX"
    log_info "  Bucket: $BUCKET_NAME"
    log_info "  CDN: $CDN_NAME"
    log_info "  Stream: $STREAM_NAME"
}

# Configure gcloud settings
configure_gcloud() {
    log_info "Configuring gcloud settings..."
    
    execute_command "gcloud config set project $PROJECT_ID"
    execute_command "gcloud config set compute/region $REGION"
    execute_command "gcloud config set compute/zone $ZONE"
    
    log_success "gcloud configuration updated"
}

# Create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: $BUCKET_NAME"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://$BUCKET_NAME" &>/dev/null; then
        log_warning "Bucket gs://$BUCKET_NAME already exists"
        return 0
    fi
    
    execute_command "gsutil mb -p $PROJECT_ID -c STANDARD -l $REGION gs://$BUCKET_NAME"
    execute_command "gsutil uniformbucketlevelaccess set on gs://$BUCKET_NAME"
    execute_command "gsutil iam ch allUsers:objectViewer gs://$BUCKET_NAME"
    
    log_success "Storage bucket created: gs://$BUCKET_NAME"
}

# Upload sample XR assets
upload_sample_assets() {
    log_info "Creating and uploading sample XR assets..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create sample XR assets and upload to gs://$BUCKET_NAME"
        return 0
    fi
    
    # Create temporary directory for assets
    local temp_dir
    temp_dir=$(mktemp -d)
    local xr_assets_dir="$temp_dir/xr-assets"
    
    mkdir -p "$xr_assets_dir"/{models,textures,animations,configs,app}
    
    # Create sample configuration file
    cat > "$xr_assets_dir/configs/app-config.json" << 'EOF'
{
  "version": "1.0",
  "environment": "production",
  "rendering": {
    "quality": "high",
    "fps": 60,
    "resolution": "1920x1080"
  },
  "features": {
    "ar_enabled": true,
    "multi_user": false,
    "analytics": true
  }
}
EOF

    # Create sample HTML file
    cat > "$xr_assets_dir/app/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>XR Experience Platform</title>
    <style>
        body { margin: 0; padding: 0; font-family: Arial, sans-serif; }
        #xr-container { width: 100vw; height: 100vh; position: relative; background: linear-gradient(45deg, #1a1a2e, #16213e); }
        #loading { position: absolute; top: 50%; left: 50%; transform: translate(-50%, -50%); color: white; text-align: center; }
        #controls { position: absolute; bottom: 20px; left: 50%; transform: translateX(-50%); }
        button { padding: 12px 24px; margin: 0 8px; border: none; border-radius: 25px; cursor: pointer; background: #4285f4; color: white; font-size: 14px; transition: all 0.3s; }
        button:hover { background: #3367d6; transform: translateY(-2px); }
        .status { position: absolute; top: 20px; right: 20px; background: rgba(0,0,0,0.7); color: white; padding: 10px; border-radius: 5px; }
    </style>
</head>
<body>
    <div id="xr-container">
        <div id="loading">
            <h2>🥽 Loading XR Experience...</h2>
            <p>Preparing immersive content delivery platform</p>
        </div>
        <div class="status">
            <div>Status: <span id="status">Initializing</span></div>
            <div>Session: <span id="session">None</span></div>
        </div>
        <div id="controls">
            <button onclick="startXR()">🚀 Start XR</button>
            <button onclick="toggleAR()">📱 Toggle AR</button>
            <button onclick="resetView()">🔄 Reset View</button>
        </div>
    </div>
    <script src="xr-client.js"></script>
</body>
</html>
EOF

    # Create sample JavaScript client
    cat > "$xr_assets_dir/app/xr-client.js" << 'EOF'
class XRClient {
    constructor() {
        this.streamEndpoint = window.location.origin + '/stream/';
        this.sessionId = null;
        this.isARMode = false;
        this.status = 'Initializing';
        this.init();
    }
    
    init() {
        this.updateStatus('Ready');
        console.log('XR Client initialized');
    }
    
    async startXR() {
        try {
            this.updateStatus('Starting XR Session...');
            document.getElementById('loading').style.display = 'block';
            
            // Simulate XR session initialization
            const sessionData = {
                sessionId: 'xr-' + Math.random().toString(36).substr(2, 9),
                device: this.detectDevice(),
                timestamp: new Date().toISOString(),
                streamUrl: this.streamEndpoint + 'session'
            };
            
            this.sessionId = sessionData.sessionId;
            this.updateSession(this.sessionId);
            
            // Simulate connection delay
            await new Promise(resolve => setTimeout(resolve, 2000));
            
            this.initializeStream(sessionData.streamUrl);
            this.updateStatus('XR Session Active');
            
        } catch (error) {
            console.error('Failed to start XR session:', error);
            this.updateStatus('Error: Failed to start session');
        }
    }
    
    detectDevice() {
        const ua = navigator.userAgent;
        if (/iPad|iPhone|iPod/.test(ua)) return 'ios';
        if (/Android/.test(ua)) return 'android';
        return 'desktop';
    }
    
    initializeStream(streamUrl) {
        document.getElementById('loading').style.display = 'none';
        console.log('XR stream initialized:', streamUrl);
        
        // Simulate streaming connection
        this.simulateStreamingData();
    }
    
    simulateStreamingData() {
        setInterval(() => {
            if (this.sessionId) {
                const data = {
                    fps: Math.floor(Math.random() * 20) + 40,
                    latency: Math.floor(Math.random() * 50) + 10,
                    quality: ['HD', 'FHD', '4K'][Math.floor(Math.random() * 3)]
                };
                console.log('Streaming metrics:', data);
            }
        }, 5000);
    }
    
    toggleAR() {
        this.isARMode = !this.isARMode;
        this.updateStatus(this.isARMode ? 'AR Mode Active' : 'XR Mode Active');
        console.log('AR mode:', this.isARMode ? 'enabled' : 'disabled');
    }
    
    resetView() {
        this.updateStatus('Resetting View...');
        setTimeout(() => {
            this.updateStatus(this.sessionId ? 'XR Session Active' : 'Ready');
        }, 1000);
        console.log('View reset');
    }
    
    updateStatus(status) {
        this.status = status;
        document.getElementById('status').textContent = status;
    }
    
    updateSession(sessionId) {
        document.getElementById('session').textContent = sessionId || 'None';
    }
}

// Initialize XR client when page loads
const xrClient = new XRClient();

// Global functions for button handlers
function startXR() { xrClient.startXR(); }
function toggleAR() { xrClient.toggleAR(); }
function resetView() { xrClient.resetView(); }

// Add some sample 3D model placeholders
document.addEventListener('DOMContentLoaded', function() {
    console.log('XR Content Delivery Platform loaded');
    console.log('Sample assets available for XR streaming');
});
EOF

    # Create placeholder files for different asset types
    echo "# Sample 3D Model Metadata" > "$xr_assets_dir/models/sample-model.json"
    echo "# Sample Texture Information" > "$xr_assets_dir/textures/sample-texture.json"
    echo "# Sample Animation Data" > "$xr_assets_dir/animations/sample-animation.json"
    
    # Upload to Cloud Storage
    execute_command "gsutil -m cp -r $xr_assets_dir/* gs://$BUCKET_NAME/"
    
    # Set cache control headers
    execute_command "gsutil -m setmeta -h 'Cache-Control:public,max-age=3600' gs://$BUCKET_NAME/models/*"
    execute_command "gsutil -m setmeta -h 'Cache-Control:public,max-age=86400' gs://$BUCKET_NAME/textures/*"
    execute_command "gsutil -m setmeta -h 'Cache-Control:public,max-age=3600' gs://$BUCKET_NAME/app/*"
    
    # Cleanup temporary directory
    rm -rf "$temp_dir"
    
    log_success "Sample XR assets uploaded with optimized caching headers"
}

# Create Cloud CDN configuration
create_cdn_configuration() {
    log_info "Creating Cloud CDN configuration..."
    
    # Create backend bucket
    execute_command "gcloud compute backend-buckets create ${CDN_NAME}-backend \
        --gcs-bucket-name=$BUCKET_NAME \
        --enable-cdn \
        --cache-mode=CACHE_ALL_STATIC \
        --default-ttl=3600 \
        --max-ttl=86400"
    
    # Create URL map
    execute_command "gcloud compute url-maps create ${CDN_NAME}-urlmap \
        --default-backend-bucket=${CDN_NAME}-backend"
    
    # Create HTTP target proxy
    execute_command "gcloud compute target-http-proxies create ${CDN_NAME}-proxy \
        --url-map=${CDN_NAME}-urlmap"
    
    # Create global forwarding rule
    execute_command "gcloud compute forwarding-rules create ${CDN_NAME}-rule \
        --global \
        --target-http-proxy=${CDN_NAME}-proxy \
        --ports=80"
    
    log_success "Cloud CDN configured for global content delivery"
}

# Set up Immersive Stream for XR service
setup_xr_service() {
    log_info "Setting up Immersive Stream for XR service..."
    
    # Note: Immersive Stream for XR is currently in beta and requires special access
    # This section will create the service if available
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create XR service instance with GPU-powered rendering"
        return 0
    fi
    
    # Check if the service is available in the project
    if ! gcloud beta immersive-stream xr service-instances list --location="$REGION" &>/dev/null; then
        log_warning "Immersive Stream for XR may not be available in your project or region."
        log_warning "This service requires special access approval. Please contact Google Cloud support."
        log_warning "Continuing deployment without XR service..."
        return 0
    fi
    
    execute_command "gcloud beta immersive-stream xr service-instances create $STREAM_NAME \
        --location=$REGION \
        --gpu-class=T4 \
        --gpu-count=1 \
        --content-source=gs://$BUCKET_NAME/models \
        --session-timeout=1800 \
        --max-concurrent-sessions=10"
    
    # Enable autoscaling
    execute_command "gcloud beta immersive-stream xr service-instances update $STREAM_NAME \
        --location=$REGION \
        --enable-autoscaling \
        --min-capacity=1 \
        --max-capacity=5 \
        --target-utilization=70"
    
    log_success "Immersive Stream for XR service configured"
}

# Configure IAM permissions
configure_iam_permissions() {
    log_info "Configuring IAM permissions for XR service..."
    
    # Create service account
    execute_command "gcloud iam service-accounts create xr-streaming-sa \
        --display-name='XR Streaming Service Account' \
        --description='Service account for Immersive Stream for XR operations'"
    
    # Grant necessary permissions
    execute_command "gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member='serviceAccount:xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com' \
        --role='roles/storage.objectViewer'"
    
    execute_command "gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member='serviceAccount:xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com' \
        --role='roles/logging.logWriter'"
    
    execute_command "gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member='serviceAccount:xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com' \
        --role='roles/monitoring.metricWriter'"
    
    # Create service account key
    if [[ "$DRY_RUN" == "false" ]]; then
        execute_command "gcloud iam service-accounts keys create xr-streaming-key.json \
            --iam-account=xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    fi
    
    log_success "IAM permissions configured for XR streaming service"
}

# Set up monitoring and logging
setup_monitoring() {
    log_info "Setting up monitoring and analytics..."
    
    # Create custom metrics for XR streaming
    execute_command "gcloud logging metrics create xr_session_starts \
        --description='Number of XR streaming sessions started' \
        --log-filter='resource.type=\"immersive_stream_xr_service\" AND jsonPayload.event_type=\"session_start\"'"
    
    execute_command "gcloud logging metrics create xr_session_duration \
        --description='Duration of XR streaming sessions' \
        --log-filter='resource.type=\"immersive_stream_xr_service\" AND jsonPayload.event_type=\"session_end\"' \
        --value-extractor='jsonPayload.session_duration'"
    
    log_success "Monitoring and analytics configured for XR service"
}

# Display deployment summary
display_deployment_summary() {
    local cdn_ip=""
    if [[ "$DRY_RUN" == "false" ]]; then
        cdn_ip=$(gcloud compute forwarding-rules describe "${CDN_NAME}-rule" --global --format='value(IPAddress)' 2>/dev/null || echo "Not available")
    else
        cdn_ip="[DRY-RUN-IP]"
    fi
    
    log_success "Deployment completed successfully!"
    echo
    echo "=========================================="
    echo "🥽 XR CONTENT DELIVERY PLATFORM DEPLOYED"
    echo "=========================================="
    echo
    echo "📊 Deployment Summary:"
    echo "  • Project ID: $PROJECT_ID"
    echo "  • Region: $REGION"
    echo "  • Resource Suffix: $RANDOM_SUFFIX"
    echo
    echo "🗄️  Storage:"
    echo "  • Bucket: gs://$BUCKET_NAME"
    echo "  • CDN Backend: ${CDN_NAME}-backend"
    echo
    echo "🌐 CDN & Load Balancer:"
    echo "  • Global IP: $cdn_ip"
    echo "  • Access URL: http://$cdn_ip/app/"
    echo "  • URL Map: ${CDN_NAME}-urlmap"
    echo
    echo "🎮 XR Service:"
    echo "  • Service Name: $STREAM_NAME"
    echo "  • Location: $REGION"
    echo "  • GPU Class: T4"
    echo
    echo "🔐 Security:"
    echo "  • Service Account: xr-streaming-sa@${PROJECT_ID}.iam.gserviceaccount.com"
    echo "  • Key File: xr-streaming-key.json"
    echo
    echo "📊 Monitoring:"
    echo "  • Custom Metrics: xr_session_starts, xr_session_duration"
    echo "  • Log Filter: immersive_stream_xr_service"
    echo
    echo "🚀 Next Steps:"
    echo "  1. Visit http://$cdn_ip/app/ to test the XR web application"
    echo "  2. Check Cloud Console for XR service status and metrics"
    echo "  3. Configure custom domains and SSL certificates for production"
    echo "  4. Upload your own 3D models and XR content to gs://$BUCKET_NAME"
    echo "  5. Monitor performance through Cloud Monitoring dashboard"
    echo
    echo "📝 Log File: $LOG_FILE"
    echo "🗑️  To clean up: ./destroy.sh --project-id $PROJECT_ID --suffix $RANDOM_SUFFIX"
    echo
}

# Main deployment function
main() {
    log_info "Starting XR Content Delivery Platform deployment..."
    log_info "Log file: $LOG_FILE"
    
    check_prerequisites
    generate_resource_names
    configure_gcloud
    create_storage_bucket
    upload_sample_assets
    create_cdn_configuration
    setup_xr_service
    configure_iam_permissions
    setup_monitoring
    display_deployment_summary
    
    log_success "Deployment completed successfully!"
}

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
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        -s|--suffix)
            RANDOM_SUFFIX="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-prerequisites)
            SKIP_PREREQUISITES=true
            shift
            ;;
        --no-cleanup-on-failure)
            CLEANUP_ON_FAILURE=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROJECT_ID" ]]; then
    log_error "Project ID is required. Use --project-id option."
    usage
    exit 1
fi

# Show startup message
echo "🥽 Immersive XR Content Delivery Platform Deployment"
echo "=================================================="
echo
if [[ "$DRY_RUN" == "true" ]]; then
    echo "🔍 DRY RUN MODE - No resources will be created"
    echo
fi

# Run main deployment
main

exit 0