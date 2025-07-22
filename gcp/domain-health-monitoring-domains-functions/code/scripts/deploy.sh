#!/bin/bash

# Deploy script for Domain Health Monitoring with Cloud Domains and Cloud Functions
# This script deploys the complete infrastructure for automated domain health monitoring

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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if gcloud is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "gcloud is not authenticated. Please run 'gcloud auth login'."
        exit 1
    fi
    
    # Check if gsutil is available
    if ! command -v gsutil &> /dev/null; then
        log_error "gsutil is not available. Please install Google Cloud SDK with gsutil."
        exit 1
    fi
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed. Please install curl."
        exit 1
    fi
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is not installed. Please install openssl."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to validate project configuration
validate_project() {
    local project_id=$(gcloud config get-value project 2>/dev/null)
    
    if [[ -z "$project_id" ]]; then
        log_error "No Google Cloud project is configured. Please set a project with 'gcloud config set project PROJECT_ID'."
        exit 1
    fi
    
    # Check if billing is enabled
    local billing_enabled=$(gcloud beta billing projects describe "$project_id" --format="value(billingEnabled)" 2>/dev/null || echo "false")
    if [[ "$billing_enabled" != "True" ]]; then
        log_warning "Billing may not be enabled for project $project_id. Some services may not work without billing."
    fi
    
    log_success "Project validation completed for: $project_id"
    return 0
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set default values or use existing environment variables
    export PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    
    # Generate unique suffix for resource names
    if [[ -z "${RANDOM_SUFFIX:-}" ]]; then
        export RANDOM_SUFFIX=$(openssl rand -hex 3)
    fi
    
    export FUNCTION_NAME="${FUNCTION_NAME:-domain-health-monitor-${RANDOM_SUFFIX}}"
    export BUCKET_NAME="${BUCKET_NAME:-domain-monitor-storage-${RANDOM_SUFFIX}}"
    export TOPIC_NAME="${TOPIC_NAME:-domain-alerts-${RANDOM_SUFFIX}}"
    export SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-domain-monitor-schedule}"
    
    # Set gcloud defaults
    gcloud config set project "${PROJECT_ID}" --quiet
    gcloud config set compute/region "${REGION}" --quiet
    gcloud config set compute/zone "${ZONE}" --quiet
    
    log_success "Environment variables configured"
    log_info "Project ID: ${PROJECT_ID}"
    log_info "Region: ${REGION}"
    log_info "Function Name: ${FUNCTION_NAME}"
    log_info "Bucket Name: ${BUCKET_NAME}"
    log_info "Topic Name: ${TOPIC_NAME}"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "monitoring.googleapis.com"
        "domains.googleapis.com"
        "storage.googleapis.com"
        "pubsub.googleapis.com"
        "cloudbuild.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling API: $api"
        if gcloud services enable "$api" --quiet; then
            log_success "API enabled: $api"
        else
            log_error "Failed to enable API: $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully enabled
    log_info "Waiting for APIs to be fully enabled..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket: ${BUCKET_NAME}"
    
    # Check if bucket already exists
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warning "Bucket gs://${BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create storage bucket
    if gsutil mb -p "${PROJECT_ID}" -c STANDARD -l "${REGION}" "gs://${BUCKET_NAME}"; then
        log_success "Storage bucket created: gs://${BUCKET_NAME}"
    else
        log_error "Failed to create storage bucket: gs://${BUCKET_NAME}"
        exit 1
    fi
    
    # Enable versioning
    if gsutil versioning set on "gs://${BUCKET_NAME}"; then
        log_success "Versioning enabled for bucket: gs://${BUCKET_NAME}"
    else
        log_warning "Failed to enable versioning for bucket: gs://${BUCKET_NAME}"
    fi
}

# Function to create Pub/Sub topic and subscription
create_pubsub_resources() {
    log_info "Creating Pub/Sub topic: ${TOPIC_NAME}"
    
    # Check if topic already exists
    if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
        log_warning "Pub/Sub topic ${TOPIC_NAME} already exists, skipping creation"
    else
        if gcloud pubsub topics create "${TOPIC_NAME}"; then
            log_success "Pub/Sub topic created: ${TOPIC_NAME}"
        else
            log_error "Failed to create Pub/Sub topic: ${TOPIC_NAME}"
            exit 1
        fi
    fi
    
    # Create subscription
    local subscription_name="${TOPIC_NAME}-sub"
    if gcloud pubsub subscriptions describe "${subscription_name}" &>/dev/null; then
        log_warning "Pub/Sub subscription ${subscription_name} already exists, skipping creation"
    else
        if gcloud pubsub subscriptions create "${subscription_name}" --topic="${TOPIC_NAME}"; then
            log_success "Pub/Sub subscription created: ${subscription_name}"
        else
            log_error "Failed to create Pub/Sub subscription: ${subscription_name}"
            exit 1
        fi
    fi
}

# Function to create function source code
create_function_source() {
    log_info "Creating Cloud Function source code..."
    
    local function_dir="domain-monitor-function"
    
    # Create function directory
    if [[ -d "$function_dir" ]]; then
        log_warning "Function directory $function_dir already exists, recreating..."
        rm -rf "$function_dir"
    fi
    
    mkdir -p "$function_dir"
    cd "$function_dir"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
google-cloud-monitoring==2.16.0
google-cloud-domains==1.5.0
google-cloud-storage==2.10.0
google-cloud-pubsub==2.18.0
requests==2.31.0
cryptography==41.0.4
dnspython==2.4.2
functions-framework==3.4.0
EOF
    
    # Create main.py with domain health monitoring logic
    cat > main.py << 'EOF'
import ssl
import socket
import requests
import dns.resolver
from datetime import datetime, timedelta
from google.cloud import monitoring_v3
from google.cloud import domains_v1
from google.cloud import storage
from google.cloud import pubsub_v1
import json
import os

def domain_health_check(request):
    """Cloud Function to perform comprehensive domain health checks"""
    
    try:
        # Initialize Google Cloud clients
        monitoring_client = monitoring_v3.MetricServiceClient()
        storage_client = storage.Client()
        publisher = pubsub_v1.PublisherClient()
        
        project_id = os.environ.get('GCP_PROJECT')
        topic_name = os.environ.get('TOPIC_NAME')
        bucket_name = os.environ.get('BUCKET_NAME')
        
        if not all([project_id, topic_name, bucket_name]):
            raise ValueError("Missing required environment variables")
        
        topic_path = publisher.topic_path(project_id, topic_name)
        
        # Domain list - customize based on your domains
        domains_to_check = [
            'google.com',
            'example.com'
        ]
        
        results = []
        
        for domain in domains_to_check:
            result = {
                'domain': domain,
                'timestamp': datetime.utcnow().isoformat(),
                'ssl_valid': False,
                'ssl_expires': None,
                'dns_resolves': False,
                'http_responds': False,
                'alerts': []
            }
            
            try:
                # Check SSL certificate
                ssl_info = check_ssl_certificate(domain)
                result['ssl_valid'] = ssl_info['valid']
                result['ssl_expires'] = ssl_info['expires']
                
                if ssl_info.get('days_until_expiry', 0) < 30 and ssl_info['valid']:
                    alert_msg = f"SSL certificate for {domain} expires in {ssl_info['days_until_expiry']} days"
                    result['alerts'].append(alert_msg)
                    send_alert(publisher, topic_path, alert_msg)
                
                # Check DNS resolution
                dns_result = check_dns_resolution(domain)
                result['dns_resolves'] = dns_result
                
                if not dns_result:
                    alert_msg = f"DNS resolution failed for {domain}"
                    result['alerts'].append(alert_msg)
                    send_alert(publisher, topic_path, alert_msg)
                
                # Check HTTP response
                http_result = check_http_response(domain)
                result['http_responds'] = http_result
                
                if not http_result:
                    alert_msg = f"HTTP response check failed for {domain}"
                    result['alerts'].append(alert_msg)
                    send_alert(publisher, topic_path, alert_msg)
                
                # Send metrics to Cloud Monitoring
                send_metrics(monitoring_client, project_id, domain, result)
                
            except Exception as e:
                error_msg = f"Error checking {domain}: {str(e)}"
                result['alerts'].append(error_msg)
                send_alert(publisher, topic_path, error_msg)
            
            results.append(result)
        
        # Store results in Cloud Storage
        store_results(storage_client, bucket_name, results)
        
        return {'status': 'completed', 'checked_domains': len(results), 'results': results}
        
    except Exception as e:
        error_response = {'status': 'error', 'message': str(e)}
        print(f"Function error: {error_response}")
        return error_response

def check_ssl_certificate(domain):
    """Check SSL certificate validity and expiration"""
    try:
        context = ssl.create_default_context()
        with socket.create_connection((domain, 443), timeout=10) as sock:
            with context.wrap_socket(sock, server_hostname=domain) as ssock:
                cert = ssock.getpeercert()
                
                # Parse expiration date
                expire_date = datetime.strptime(cert['notAfter'], '%b %d %H:%M:%S %Y %Z')
                days_until_expiry = (expire_date - datetime.utcnow()).days
                
                return {
                    'valid': True,
                    'expires': expire_date.isoformat(),
                    'days_until_expiry': days_until_expiry
                }
    except Exception as e:
        return {
            'valid': False,
            'expires': None,
            'days_until_expiry': 0,
            'error': str(e)
        }

def check_dns_resolution(domain):
    """Check if domain resolves correctly"""
    try:
        result = dns.resolver.resolve(domain, 'A')
        return len(result) > 0
    except Exception:
        return False

def check_http_response(domain):
    """Check if domain responds to HTTP requests"""
    try:
        response = requests.get(f'https://{domain}', timeout=10, verify=True)
        return response.status_code < 400
    except Exception:
        return False

def send_metrics(client, project_id, domain, result):
    """Send metrics to Cloud Monitoring"""
    try:
        project_name = f"projects/{project_id}"
        
        # Create time series data
        interval = monitoring_v3.TimeInterval()
        now = datetime.utcnow()
        interval.end_time.seconds = int(now.timestamp())
        
        # SSL validity metric
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/domain/ssl_valid"
        series.resource.type = "global"
        series.metric.labels["domain"] = domain
        
        point = monitoring_v3.Point()
        point.value.double_value = 1.0 if result['ssl_valid'] else 0.0
        point.interval.CopyFrom(interval)
        series.points = [point]
        
        client.create_time_series(name=project_name, time_series=[series])
        
    except Exception as e:
        print(f"Error sending metrics for {domain}: {str(e)}")

def send_alert(publisher, topic_path, message):
    """Send alert message to Pub/Sub"""
    try:
        alert_data = {
            'message': message,
            'timestamp': datetime.utcnow().isoformat(),
            'severity': 'warning'
        }
        
        publisher.publish(topic_path, json.dumps(alert_data).encode('utf-8'))
        
    except Exception as e:
        print(f"Error sending alert: {str(e)}")

def store_results(storage_client, bucket_name, results):
    """Store monitoring results in Cloud Storage"""
    try:
        bucket = storage_client.bucket(bucket_name)
        
        timestamp = datetime.utcnow().strftime('%Y-%m-%d-%H-%M-%S')
        blob_name = f"monitoring-results/{timestamp}.json"
        
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(results, indent=2))
        
    except Exception as e:
        print(f"Error storing results: {str(e)}")
EOF
    
    cd ..
    log_success "Cloud Function source code created"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying Cloud Function: ${FUNCTION_NAME}"
    
    cd domain-monitor-function
    
    # Check if function already exists
    if gcloud functions describe "${FUNCTION_NAME}" --region="${REGION}" &>/dev/null; then
        log_warning "Function ${FUNCTION_NAME} already exists, updating..."
        local operation="update"
    else
        local operation="create"
    fi
    
    # Deploy Cloud Function with environment variables
    if gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python39 \
        --trigger-http \
        --source . \
        --entry-point domain_health_check \
        --memory 512MB \
        --timeout 300s \
        --region="${REGION}" \
        --set-env-vars="TOPIC_NAME=${TOPIC_NAME},BUCKET_NAME=${BUCKET_NAME}" \
        --allow-unauthenticated \
        --quiet; then
        log_success "Cloud Function ${operation}d: ${FUNCTION_NAME}"
    else
        log_error "Failed to deploy Cloud Function: ${FUNCTION_NAME}"
        cd ..
        exit 1
    fi
    
    # Get function URL
    local function_url=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(httpsTrigger.url)")
    
    if [[ -n "$function_url" ]]; then
        export FUNCTION_URL="$function_url"
        log_success "Function URL: ${FUNCTION_URL}"
    else
        log_error "Failed to get function URL"
        cd ..
        exit 1
    fi
    
    cd ..
}

# Function to create Cloud Scheduler job
create_scheduler_job() {
    log_info "Creating Cloud Scheduler job: ${SCHEDULER_JOB_NAME}"
    
    # Check if scheduler job already exists
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" &>/dev/null; then
        log_warning "Scheduler job ${SCHEDULER_JOB_NAME} already exists, updating..."
        
        # Update existing job
        if gcloud scheduler jobs update http "${SCHEDULER_JOB_NAME}" \
            --schedule="0 */6 * * *" \
            --uri="${FUNCTION_URL}" \
            --http-method=GET \
            --location="${REGION}" \
            --description="Domain health monitoring every 6 hours" \
            --quiet; then
            log_success "Cloud Scheduler job updated: ${SCHEDULER_JOB_NAME}"
        else
            log_error "Failed to update Cloud Scheduler job: ${SCHEDULER_JOB_NAME}"
            exit 1
        fi
    else
        # Create new job
        if gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
            --schedule="0 */6 * * *" \
            --uri="${FUNCTION_URL}" \
            --http-method=GET \
            --location="${REGION}" \
            --description="Domain health monitoring every 6 hours" \
            --quiet; then
            log_success "Cloud Scheduler job created: ${SCHEDULER_JOB_NAME}"
        else
            log_error "Failed to create Cloud Scheduler job: ${SCHEDULER_JOB_NAME}"
            exit 1
        fi
    fi
    
    # Run initial execution
    log_info "Running initial function execution..."
    if gcloud scheduler jobs run "${SCHEDULER_JOB_NAME}" --location="${REGION}" --quiet; then
        log_success "Initial function execution triggered"
    else
        log_warning "Failed to trigger initial execution, but scheduler is configured"
    fi
}

# Function to create monitoring alert policy
create_alert_policy() {
    log_info "Creating Cloud Monitoring alert policy..."
    
    # Create alerting policy configuration
    cat > alert-policy.json << EOF
{
  "displayName": "Domain Health Alert Policy - ${RANDOM_SUFFIX}",
  "conditions": [
    {
      "displayName": "SSL Certificate Expiring Soon",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/domain/ssl_valid\"",
        "comparison": "COMPARISON_LESS_THAN",
        "thresholdValue": 1.0,
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
    if gcloud alpha monitoring policies create --policy-from-file=alert-policy.json --quiet; then
        log_success "Cloud Monitoring alert policy created"
    else
        log_warning "Failed to create alert policy, but monitoring will still work"
    fi
    
    # Clean up temporary file
    rm -f alert-policy.json
}

# Function to create notification channels
create_notification_channels() {
    log_info "Creating notification channels..."
    
    # Note: Email address should be customized by user
    local email_address="${NOTIFICATION_EMAIL:-admin@example.com}"
    
    if [[ "$email_address" == "admin@example.com" ]]; then
        log_warning "Using default email address for notifications. Update NOTIFICATION_EMAIL environment variable with your actual email."
    fi
    
    # Create email notification channel
    if gcloud alpha monitoring channels create \
        --display-name="Domain Alerts Email - ${RANDOM_SUFFIX}" \
        --type=email \
        --channel-labels=email_address="${email_address}" \
        --quiet; then
        log_success "Email notification channel created for: ${email_address}"
    else
        log_warning "Failed to create email notification channel"
    fi
}

# Function to validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check Cloud Function status
    local function_status=$(gcloud functions describe "${FUNCTION_NAME}" \
        --region="${REGION}" \
        --format="value(status)" 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$function_status" == "ACTIVE" ]]; then
        log_success "Cloud Function is active: ${FUNCTION_NAME}"
    else
        log_error "Cloud Function is not active. Status: ${function_status}"
        return 1
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "${TOPIC_NAME}" &>/dev/null; then
        log_success "Pub/Sub topic exists: ${TOPIC_NAME}"
    else
        log_error "Pub/Sub topic not found: ${TOPIC_NAME}"
        return 1
    fi
    
    # Check Cloud Storage bucket
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_success "Cloud Storage bucket exists: gs://${BUCKET_NAME}"
    else
        log_error "Cloud Storage bucket not found: gs://${BUCKET_NAME}"
        return 1
    fi
    
    # Check Cloud Scheduler job
    if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${REGION}" &>/dev/null; then
        log_success "Cloud Scheduler job exists: ${SCHEDULER_JOB_NAME}"
    else
        log_error "Cloud Scheduler job not found: ${SCHEDULER_JOB_NAME}"
        return 1
    fi
    
    # Test function execution
    log_info "Testing function execution..."
    if curl -s -o /dev/null -w "%{http_code}" "${FUNCTION_URL}" | grep -q "200"; then
        log_success "Function responds successfully"
    else
        log_warning "Function test failed, but function is deployed"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_success "=== Deployment Summary ==="
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Function Name: ${FUNCTION_NAME}"
    echo "Function URL: ${FUNCTION_URL}"
    echo "Bucket Name: ${BUCKET_NAME}"
    echo "Topic Name: ${TOPIC_NAME}"
    echo "Scheduler Job: ${SCHEDULER_JOB_NAME}"
    echo ""
    echo "Next steps:"
    echo "1. Customize the domain list in the Cloud Function source code"
    echo "2. Update notification email address if needed"
    echo "3. Monitor function logs: gcloud functions logs read ${FUNCTION_NAME} --region=${REGION}"
    echo "4. Check monitoring results: gsutil ls gs://${BUCKET_NAME}/monitoring-results/"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting Domain Health Monitoring deployment..."
    
    check_prerequisites
    validate_project
    setup_environment
    enable_apis
    create_storage_bucket
    create_pubsub_resources
    create_function_source
    deploy_cloud_function
    create_scheduler_job
    create_alert_policy
    create_notification_channels
    validate_deployment
    display_summary
    
    log_success "Domain Health Monitoring deployment completed successfully!"
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi