#!/bin/bash

# Performance Testing Pipelines Deployment Script
# Creates automated performance testing infrastructure with Cloud Load Balancing and Cloud Monitoring

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_PREFIX="perf-testing"
readonly REGION="us-central1"
readonly ZONE="us-central1-a"
readonly MACHINE_TYPE="e2-medium"
readonly MIN_REPLICAS=2
readonly MAX_REPLICAS=10
readonly TARGET_CPU_UTILIZATION=0.7

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "Google Cloud SDK (gcloud) is not installed. Please install it first."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
        log_error "Not authenticated with Google Cloud. Run 'gcloud auth login' first."
        exit 1
    fi
    
    # Check if jq is installed for JSON processing
    if ! command -v jq &> /dev/null; then
        log_warn "jq not found. Installing jq for JSON processing..."
        # Try to install jq based on OS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install jq
            else
                log_error "Please install jq manually or install Homebrew"
                exit 1
            fi
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            sudo apt-get update && sudo apt-get install -y jq
        else
            log_error "Please install jq manually for your operating system"
            exit 1
        fi
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random strings"
        exit 1
    fi
    
    log_info "Prerequisites check completed successfully"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID if not provided
    if [[ -z "${PROJECT_ID:-}" ]]; then
        export PROJECT_ID="${PROJECT_PREFIX}-$(date +%s)"
        log_info "Generated PROJECT_ID: ${PROJECT_ID}"
    fi
    
    export REGION="${REGION}"
    export ZONE="${ZONE}"
    
    # Generate unique suffix for resource names
    readonly RANDOM_SUFFIX=$(openssl rand -hex 3)
    export FUNCTION_NAME="perf-test-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PROJECT_ID}-test-results"
    export SERVICE_ACCOUNT_NAME="perf-test-sa"
    
    # Resource names with suffix
    export INSTANCE_TEMPLATE="app-template-${RANDOM_SUFFIX}"
    export INSTANCE_GROUP="app-group-${RANDOM_SUFFIX}"
    export HEALTH_CHECK="health-check-${RANDOM_SUFFIX}"
    export BACKEND_SERVICE="backend-service-${RANDOM_SUFFIX}"
    export URL_MAP="url-map-${RANDOM_SUFFIX}"
    export HTTP_PROXY="http-proxy-${RANDOM_SUFFIX}"
    export FORWARDING_RULE="http-forwarding-rule-${RANDOM_SUFFIX}"
    export FIREWALL_RULE="allow-health-check-${RANDOM_SUFFIX}"
    export DAILY_JOB="daily-perf-test-${RANDOM_SUFFIX}"
    export HOURLY_JOB="hourly-perf-test-${RANDOM_SUFFIX}"
    
    log_info "Environment variables configured successfully"
}

# Function to configure Google Cloud project
configure_gcloud() {
    log_info "Configuring Google Cloud project..."
    
    # Set default project and region
    gcloud config set project "${PROJECT_ID}"
    gcloud config set compute/region "${REGION}"
    gcloud config set compute/zone "${ZONE}"
    
    log_info "Google Cloud configuration completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "cloudfunctions.googleapis.com"
        "cloudscheduler.googleapis.com"
        "compute.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "storage.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling ${api}..."
        if ! gcloud services enable "${api}" --quiet; then
            log_error "Failed to enable ${api}"
            exit 1
        fi
    done
    
    log_info "All required APIs enabled successfully"
}

# Function to create Cloud Storage bucket
create_storage_bucket() {
    log_info "Creating Cloud Storage bucket for test results..."
    
    if gsutil ls -b "gs://${BUCKET_NAME}" &>/dev/null; then
        log_warn "Bucket ${BUCKET_NAME} already exists, skipping creation"
    else
        gsutil mb -p "${PROJECT_ID}" \
            -c STANDARD \
            -l "${REGION}" \
            "gs://${BUCKET_NAME}"
        log_info "Storage bucket created: ${BUCKET_NAME}"
    fi
}

# Function to create service account
create_service_account() {
    log_info "Creating service account for performance testing..."
    
    # Check if service account already exists
    if gcloud iam service-accounts describe "${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
        log_warn "Service account ${SERVICE_ACCOUNT_NAME} already exists, skipping creation"
    else
        gcloud iam service-accounts create "${SERVICE_ACCOUNT_NAME}" \
            --display-name="Performance Testing Service Account" \
            --description="Service account for automated performance testing pipeline"
    fi
    
    # Get service account email
    readonly SERVICE_ACCOUNT_EMAIL="${SERVICE_ACCOUNT_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
    
    # Grant necessary IAM roles
    local roles=(
        "roles/storage.objectAdmin"
        "roles/monitoring.metricWriter"
        "roles/logging.logWriter"
    )
    
    for role in "${roles[@]}"; do
        log_info "Granting role ${role} to service account..."
        gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
            --member="serviceAccount:${SERVICE_ACCOUNT_EMAIL}" \
            --role="${role}" \
            --quiet
    done
    
    log_info "Service account created with appropriate permissions"
}

# Function to create application infrastructure
create_application_infrastructure() {
    log_info "Creating application infrastructure..."
    
    # Create instance template
    log_info "Creating instance template..."
    gcloud compute instance-templates create "${INSTANCE_TEMPLATE}" \
        --machine-type="${MACHINE_TYPE}" \
        --image-family=debian-11 \
        --image-project=debian-cloud \
        --startup-script='#!/bin/bash
apt-get update
apt-get install -y nginx
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html>
<head><title>Performance Test App</title></head>
<body>
  <h1>Performance Testing Target Application</h1>
  <p>Instance: $(hostname)</p>
  <p>Timestamp: $(date)</p>
  <p>Request processed successfully</p>
</body>
</html>
EOF
systemctl enable nginx
systemctl start nginx' \
        --tags=http-server \
        --scopes=https://www.googleapis.com/auth/monitoring.write
    
    # Create managed instance group
    log_info "Creating managed instance group..."
    gcloud compute instance-groups managed create "${INSTANCE_GROUP}" \
        --base-instance-name=app-instance \
        --template="${INSTANCE_TEMPLATE}" \
        --size=3 \
        --zone="${ZONE}"
    
    # Configure autoscaling
    log_info "Configuring autoscaling..."
    gcloud compute instance-groups managed set-autoscaling "${INSTANCE_GROUP}" \
        --zone="${ZONE}" \
        --max-num-replicas="${MAX_REPLICAS}" \
        --min-num-replicas="${MIN_REPLICAS}" \
        --target-cpu-utilization="${TARGET_CPU_UTILIZATION}"
    
    log_info "Application infrastructure created successfully"
}

# Function to create load balancer
create_load_balancer() {
    log_info "Creating HTTP load balancer..."
    
    # Create firewall rule for health checks
    log_info "Creating firewall rule for health checks..."
    gcloud compute firewall-rules create "${FIREWALL_RULE}" \
        --allow tcp:80 \
        --source-ranges 130.211.0.0/22,35.191.0.0/16 \
        --target-tags http-server \
        --description="Allow health check access to HTTP servers"
    
    # Create health check
    log_info "Creating health check..."
    gcloud compute health-checks create http "${HEALTH_CHECK}" \
        --port 80 \
        --request-path / \
        --check-interval 10s \
        --timeout 5s \
        --healthy-threshold 2 \
        --unhealthy-threshold 3
    
    # Create backend service
    log_info "Creating backend service..."
    gcloud compute backend-services create "${BACKEND_SERVICE}" \
        --protocol HTTP \
        --health-checks "${HEALTH_CHECK}" \
        --global
    
    # Add instance group to backend service
    log_info "Adding instance group to backend service..."
    gcloud compute backend-services add-backend "${BACKEND_SERVICE}" \
        --instance-group "${INSTANCE_GROUP}" \
        --instance-group-zone "${ZONE}" \
        --global
    
    # Create URL map
    log_info "Creating URL map..."
    gcloud compute url-maps create "${URL_MAP}" \
        --default-service "${BACKEND_SERVICE}"
    
    # Create HTTP proxy
    log_info "Creating HTTP proxy..."
    gcloud compute target-http-proxies create "${HTTP_PROXY}" \
        --url-map "${URL_MAP}"
    
    # Create global forwarding rule
    log_info "Creating global forwarding rule..."
    gcloud compute forwarding-rules create "${FORWARDING_RULE}" \
        --global \
        --target-http-proxy "${HTTP_PROXY}" \
        --ports 80
    
    # Get load balancer IP address
    local lb_ip
    lb_ip=$(gcloud compute forwarding-rules describe "${FORWARDING_RULE}" \
        --global --format="value(IPAddress)")
    export LB_IP="${lb_ip}"
    
    log_info "Load balancer configured with IP: ${LB_IP}"
}

# Function to deploy Cloud Function
deploy_cloud_function() {
    log_info "Deploying load generation Cloud Function..."
    
    # Create temporary directory for function code
    local temp_dir
    temp_dir=$(mktemp -d)
    cd "${temp_dir}"
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
requests==2.31.0
google-cloud-monitoring==2.16.0
google-cloud-storage==2.10.0
functions-framework==3.*
EOF
    
    # Create main.py with load generation logic
    cat > main.py << 'EOF'
import json
import time
import requests
import concurrent.futures
from datetime import datetime
from google.cloud import monitoring_v3
from google.cloud import storage
import functions_framework

def execute_load_test(target_url, duration_seconds, concurrent_users, requests_per_second):
    """Execute load test against target URL"""
    results = {
        'start_time': datetime.utcnow().isoformat(),
        'target_url': target_url,
        'duration_seconds': duration_seconds,
        'concurrent_users': concurrent_users,
        'requests_per_second': requests_per_second,
        'total_requests': 0,
        'successful_requests': 0,
        'failed_requests': 0,
        'response_times': [],
        'error_details': []
    }
    
    start_time = time.time()
    request_interval = 1.0 / requests_per_second if requests_per_second > 0 else 0.1
    
    def make_request():
        try:
            response_start = time.time()
            response = requests.get(target_url, timeout=30)
            response_time = time.time() - response_start
            
            if response.status_code == 200:
                return {'success': True, 'response_time': response_time}
            else:
                return {'success': False, 'error': f'HTTP {response.status_code}', 'response_time': response_time}
        except Exception as e:
            return {'success': False, 'error': str(e), 'response_time': 0}
    
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrent_users) as executor:
        while time.time() - start_time < duration_seconds:
            future = executor.submit(make_request)
            try:
                result = future.result(timeout=35)
                results['total_requests'] += 1
                
                if result['success']:
                    results['successful_requests'] += 1
                    results['response_times'].append(result['response_time'])
                else:
                    results['failed_requests'] += 1
                    results['error_details'].append(result['error'])
                
                time.sleep(request_interval)
            except concurrent.futures.TimeoutError:
                results['failed_requests'] += 1
                results['error_details'].append('Request timeout')
    
    results['end_time'] = datetime.utcnow().isoformat()
    return results

def publish_metrics(results, project_id):
    """Publish performance metrics to Cloud Monitoring"""
    client = monitoring_v3.MetricServiceClient()
    project_name = f"projects/{project_id}"
    
    series = monitoring_v3.TimeSeries()
    series.metric.type = "custom.googleapis.com/performance_test/response_time"
    series.resource.type = "global"
    
    if results['response_times']:
        avg_response_time = sum(results['response_times']) / len(results['response_times'])
        
        point = series.points.add()
        point.value.double_value = avg_response_time
        now = time.time()
        point.interval.end_time.seconds = int(now)
        point.interval.end_time.nanos = int((now - int(now)) * 10**9)
        
        client.create_time_series(name=project_name, time_series=[series])

@functions_framework.http
def load_test_function(request):
    """Cloud Function entry point for load testing"""
    try:
        request_json = request.get_json()
        
        target_url = request_json.get('target_url', '')
        duration_seconds = request_json.get('duration_seconds', 60)
        concurrent_users = request_json.get('concurrent_users', 10)
        requests_per_second = request_json.get('requests_per_second', 5)
        
        if not target_url:
            return {'error': 'target_url is required'}, 400
        
        # Execute load test
        results = execute_load_test(target_url, duration_seconds, concurrent_users, requests_per_second)
        
        # Publish metrics to Cloud Monitoring
        project_id = request_json.get('project_id', '')
        if project_id:
            publish_metrics(results, project_id)
        
        # Store results in Cloud Storage
        bucket_name = request_json.get('bucket_name', '')
        if bucket_name:
            storage_client = storage.Client()
            bucket = storage_client.bucket(bucket_name)
            blob_name = f"test-results/{datetime.utcnow().strftime('%Y%m%d_%H%M%S')}_results.json"
            blob = bucket.blob(blob_name)
            blob.upload_from_string(json.dumps(results, indent=2))
        
        return {'status': 'completed', 'results_summary': {
            'total_requests': results['total_requests'],
            'successful_requests': results['successful_requests'],
            'failed_requests': results['failed_requests'],
            'average_response_time': sum(results['response_times']) / len(results['response_times']) if results['response_times'] else 0
        }}
        
    except Exception as e:
        return {'error': str(e)}, 500
EOF
    
    # Deploy Cloud Function
    gcloud functions deploy "${FUNCTION_NAME}" \
        --runtime python311 \
        --trigger http \
        --entry-point load_test_function \
        --service-account "${SERVICE_ACCOUNT_EMAIL}" \
        --memory 512MB \
        --timeout 540s \
        --max-instances 10 \
        --allow-unauthenticated \
        --quiet
    
    # Get function URL
    readonly FUNCTION_URL=$(gcloud functions describe "${FUNCTION_NAME}" \
        --format="value(httpsTrigger.url)")
    export FUNCTION_URL
    
    log_info "Load generation function deployed successfully"
    
    # Clean up temporary directory
    cd "${SCRIPT_DIR}"
    rm -rf "${temp_dir}"
}

# Function to create monitoring dashboard
create_monitoring_dashboard() {
    log_info "Creating performance monitoring dashboard..."
    
    # Create dashboard configuration
    local dashboard_config
    dashboard_config=$(mktemp)
    cat > "${dashboard_config}" << EOF
{
  "displayName": "Performance Testing Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "HTTP Load Balancer Request Rate",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_backend_service\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "yAxis": {
              "label": "Requests/second"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Backend Response Latency",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_backend_service\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "yAxis": {
              "label": "Latency (ms)"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "yPos": 4,
        "widget": {
          "title": "Performance Test Response Time",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"custom.googleapis.com/performance_test/response_time\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "yAxis": {
              "label": "Response Time (seconds)"
            }
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "yPos": 4,
        "widget": {
          "title": "Instance Group Size",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "resource.type=\"gce_instance_group\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_MEAN"
                    }
                  }
                },
                "plotType": "LINE"
              }
            ],
            "yAxis": {
              "label": "Number of Instances"
            }
          }
        }
      }
    ]
  }
}
EOF
    
    # Create dashboard
    local dashboard_id
    dashboard_id=$(gcloud monitoring dashboards create \
        --config-from-file="${dashboard_config}" \
        --format="value(name)" | sed 's|.*/||')
    export DASHBOARD_ID="${dashboard_id}"
    
    log_info "Performance monitoring dashboard created: ${DASHBOARD_ID}"
    
    # Clean up temporary file
    rm -f "${dashboard_config}"
}

# Function to create alert policies
create_alert_policies() {
    log_info "Creating alert policies for performance monitoring..."
    
    # Create alert policy for high response times
    local response_time_policy
    response_time_policy=$(mktemp)
    cat > "${response_time_policy}" << EOF
{
  "displayName": "Performance Test - High Response Time",
  "conditions": [
    {
      "displayName": "Response time exceeds threshold",
      "conditionThreshold": {
        "filter": "metric.type=\"custom.googleapis.com/performance_test/response_time\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 2.0,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_MEAN"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": []
}
EOF
    
    gcloud alpha monitoring policies create \
        --policy-from-file="${response_time_policy}" \
        --quiet
    
    # Create alert policy for high error rate
    local error_rate_policy
    error_rate_policy=$(mktemp)
    cat > "${error_rate_policy}" << EOF
{
  "displayName": "Performance Test - High Error Rate",
  "conditions": [
    {
      "displayName": "Error rate exceeds 5%",
      "conditionThreshold": {
        "filter": "resource.type=\"gce_backend_service\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.05,
        "duration": "300s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "alertStrategy": {
    "autoClose": "1800s"
  },
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": []
}
EOF
    
    gcloud alpha monitoring policies create \
        --policy-from-file="${error_rate_policy}" \
        --quiet
    
    log_info "Alert policies created for performance monitoring"
    
    # Clean up temporary files
    rm -f "${response_time_policy}" "${error_rate_policy}"
}

# Function to create scheduled jobs
create_scheduled_jobs() {
    log_info "Creating scheduled performance tests..."
    
    # Create payload for daily tests
    local daily_payload
    daily_payload=$(mktemp)
    cat > "${daily_payload}" << EOF
{
  "target_url": "http://${LB_IP}",
  "duration_seconds": 300,
  "concurrent_users": 20,
  "requests_per_second": 10,
  "project_id": "${PROJECT_ID}",
  "bucket_name": "${BUCKET_NAME}"
}
EOF
    
    # Create scheduled job for daily performance tests
    gcloud scheduler jobs create http "${DAILY_JOB}" \
        --schedule="0 2 * * *" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body-from-file="${daily_payload}" \
        --time-zone="UTC" \
        --description="Daily automated performance test"
    
    # Create payload for hourly light testing
    local hourly_payload
    hourly_payload=$(mktemp)
    cat > "${hourly_payload}" << EOF
{
  "target_url": "http://${LB_IP}",
  "duration_seconds": 60,
  "concurrent_users": 5,
  "requests_per_second": 5,
  "project_id": "${PROJECT_ID}",
  "bucket_name": "${BUCKET_NAME}"
}
EOF
    
    gcloud scheduler jobs create http "${HOURLY_JOB}" \
        --schedule="0 * * * *" \
        --uri="${FUNCTION_URL}" \
        --http-method=POST \
        --headers="Content-Type=application/json" \
        --message-body-from-file="${hourly_payload}" \
        --time-zone="UTC" \
        --description="Hourly light performance validation"
    
    log_info "Scheduled performance tests configured successfully"
    
    # Clean up temporary files
    rm -f "${daily_payload}" "${hourly_payload}"
}

# Function to run validation tests
run_validation() {
    log_info "Running validation tests..."
    
    # Test load balancer accessibility
    log_info "Testing load balancer accessibility..."
    local max_attempts=30
    local attempt=1
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if curl -s --max-time 10 "http://${LB_IP}" | grep -q "Performance Test App"; then
            log_info "Load balancer is accessible and responding correctly"
            break
        else
            log_warn "Attempt ${attempt}/${max_attempts}: Load balancer not yet accessible, waiting..."
            sleep 10
            ((attempt++))
        fi
    done
    
    if [[ ${attempt} -gt ${max_attempts} ]]; then
        log_error "Load balancer not accessible after ${max_attempts} attempts"
        return 1
    fi
    
    # Test Cloud Function
    log_info "Testing Cloud Function..."
    local function_test_response
    function_test_response=$(curl -s -X POST "${FUNCTION_URL}" \
        -H "Content-Type: application/json" \
        -d "{
            \"target_url\": \"http://${LB_IP}\",
            \"duration_seconds\": 30,
            \"concurrent_users\": 3,
            \"requests_per_second\": 2,
            \"project_id\": \"${PROJECT_ID}\",
            \"bucket_name\": \"${BUCKET_NAME}\"
        }" \
        --max-time 60)
    
    if echo "${function_test_response}" | jq -e '.status == "completed"' >/dev/null; then
        log_info "Cloud Function test completed successfully"
    else
        log_error "Cloud Function test failed"
        echo "Response: ${function_test_response}"
        return 1
    fi
    
    log_info "All validation tests passed successfully"
}

# Function to save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/../deployment-info.json"
    cat > "${info_file}" << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "project_id": "${PROJECT_ID}",
  "region": "${REGION}",
  "zone": "${ZONE}",
  "load_balancer_ip": "${LB_IP}",
  "function_url": "${FUNCTION_URL}",
  "bucket_name": "${BUCKET_NAME}",
  "dashboard_id": "${DASHBOARD_ID:-}",
  "resources": {
    "function_name": "${FUNCTION_NAME}",
    "service_account": "${SERVICE_ACCOUNT_EMAIL}",
    "instance_template": "${INSTANCE_TEMPLATE}",
    "instance_group": "${INSTANCE_GROUP}",
    "health_check": "${HEALTH_CHECK}",
    "backend_service": "${BACKEND_SERVICE}",
    "url_map": "${URL_MAP}",
    "http_proxy": "${HTTP_PROXY}",
    "forwarding_rule": "${FORWARDING_RULE}",
    "firewall_rule": "${FIREWALL_RULE}",
    "daily_job": "${DAILY_JOB}",
    "hourly_job": "${HOURLY_JOB}"
  }
}
EOF
    
    log_info "Deployment information saved to: ${info_file}"
}

# Function to display deployment summary
display_summary() {
    log_info "=== Deployment Summary ==="
    echo
    echo "Project ID: ${PROJECT_ID}"
    echo "Region: ${REGION}"
    echo "Zone: ${ZONE}"
    echo
    echo "Load Balancer IP: ${LB_IP}"
    echo "Cloud Function URL: ${FUNCTION_URL}"
    echo "Storage Bucket: ${BUCKET_NAME}"
    echo "Dashboard ID: ${DASHBOARD_ID:-}"
    echo
    echo "Scheduled Jobs:"
    echo "  - Daily comprehensive test: ${DAILY_JOB} (2:00 AM UTC)"
    echo "  - Hourly light test: ${HOURLY_JOB} (every hour)"
    echo
    echo "Test the load balancer:"
    echo "  curl http://${LB_IP}"
    echo
    echo "Manual performance test example:"
    echo "  curl -X POST '${FUNCTION_URL}' \\"
    echo "    -H 'Content-Type: application/json' \\"
    echo "    -d '{\"target_url\": \"http://${LB_IP}\", \"duration_seconds\": 60}'"
    echo
    echo "View monitoring dashboard:"
    echo "  https://console.cloud.google.com/monitoring/dashboards/custom/${DASHBOARD_ID:-}"
    echo
    log_info "Deployment completed successfully!"
}

# Main deployment function
main() {
    log_info "Starting Performance Testing Pipelines deployment..."
    
    check_prerequisites
    setup_environment
    configure_gcloud
    enable_apis
    create_storage_bucket
    create_service_account
    create_application_infrastructure
    create_load_balancer
    deploy_cloud_function
    create_monitoring_dashboard
    create_alert_policies
    create_scheduled_jobs
    run_validation
    save_deployment_info
    display_summary
}

# Handle script interruption
trap 'log_error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"