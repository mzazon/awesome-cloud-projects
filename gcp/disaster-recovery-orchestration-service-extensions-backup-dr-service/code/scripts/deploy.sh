#!/bin/bash

# Disaster Recovery Orchestration with Service Extensions and Backup and DR Service
# Deployment Script for GCP Recipe
# 
# This script deploys a complete intelligent disaster recovery system that leverages
# Google Cloud Load Balancing service extensions to detect infrastructure failures
# and automatically orchestrate backup restoration workflows.

set -euo pipefail

# Colors for output
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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    log_info "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands (respects dry-run mode)
execute_command() {
    local cmd="$1"
    local description="${2:-}"
    
    if [[ -n "$description" ]]; then
        log_info "$description"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY-RUN: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if openssl is available for random generation
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random suffixes"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique project ID and suffix
    export PROJECT_ID="${PROJECT_ID:-dr-orchestration-$(date +%s)}"
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export DR_REGION="${DR_REGION:-us-east1}"
    export DR_ZONE="${DR_ZONE:-us-east1-a}"
    
    # Generate unique suffix for resource names
    export RANDOM_SUFFIX=$(openssl rand -hex 3)
    
    log_info "Project ID: $PROJECT_ID"
    log_info "Primary Region: $REGION"
    log_info "DR Region: $DR_REGION"
    log_info "Resource Suffix: $RANDOM_SUFFIX"
}

# Function to create and configure project
setup_project() {
    log_info "Setting up Google Cloud project..."
    
    # Check if project exists
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        log_warning "Project $PROJECT_ID already exists"
    else
        execute_command "gcloud projects create $PROJECT_ID --name='DR Orchestration Demo'" \
            "Creating project: $PROJECT_ID"
    fi
    
    # Set default project and region
    execute_command "gcloud config set project $PROJECT_ID" "Setting default project"
    execute_command "gcloud config set compute/region $REGION" "Setting default region"
    execute_command "gcloud config set compute/zone $ZONE" "Setting default zone"
    
    log_success "Project setup completed"
}

# Function to enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "cloudfunctions.googleapis.com"
        "backupdr.googleapis.com"
        "monitoring.googleapis.com"
        "logging.googleapis.com"
        "serviceextensions.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_command "gcloud services enable $api" "Enabling $api"
    done
    
    # Wait for APIs to be fully enabled
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "APIs enabled successfully"
}

# Function to create primary application infrastructure
create_primary_infrastructure() {
    log_info "Creating primary application infrastructure..."
    
    # Create instance template for primary application
    execute_command "gcloud compute instance-templates create primary-app-template-$RANDOM_SUFFIX \
        --machine-type=e2-micro \
        --network-interface=network-tier=PREMIUM,subnet=default \
        --metadata=startup-script='#!/bin/bash
            apt-get update
            apt-get install -y nginx
            echo \"<h1>Primary Application - Instance: \$(hostname)</h1>\" > /var/www/html/index.html
            systemctl start nginx
            systemctl enable nginx' \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --region=$REGION \
        --tags=primary-app,http-server" \
        "Creating primary application instance template"
    
    # Create managed instance group for primary application
    execute_command "gcloud compute instance-groups managed create primary-app-group-$RANDOM_SUFFIX \
        --template=primary-app-template-$RANDOM_SUFFIX \
        --size=2 \
        --zone=$ZONE" \
        "Creating primary application instance group"
    
    # Create health check for application instances
    execute_command "gcloud compute health-checks create http primary-app-health-check-$RANDOM_SUFFIX \
        --port=80 \
        --request-path=/ \
        --check-interval=10s \
        --timeout=5s \
        --healthy-threshold=2 \
        --unhealthy-threshold=3" \
        "Creating primary application health check"
    
    log_success "Primary infrastructure created"
}

# Function to set up backup and DR service
setup_backup_dr() {
    log_info "Setting up Backup and DR Service..."
    
    # Create backup vault for immutable storage
    execute_command "gcloud backup-dr backup-vaults create primary-backup-vault-$RANDOM_SUFFIX \
        --location=$REGION \
        --description='Primary backup vault for DR orchestration' \
        --minimum-enforced-retention-days=30" \
        "Creating backup vault"
    
    # Wait for backup vault creation
    if [[ "$DRY_RUN" == "false" ]]; then
        log_info "Waiting for backup vault creation..."
        sleep 60
    fi
    
    # Create backup plan for Compute Engine instances
    execute_command "gcloud backup-dr backup-plans create primary-backup-plan-$RANDOM_SUFFIX \
        --location=$REGION \
        --backup-vault=primary-backup-vault-$RANDOM_SUFFIX \
        --description='Automated backup plan for primary infrastructure'" \
        "Creating backup plan"
    
    # Create backup rule for daily backups
    execute_command "gcloud backup-dr backup-plans add-rule primary-backup-plan-$RANDOM_SUFFIX \
        --location=$REGION \
        --rule-id=daily-backup-rule \
        --backup-retention-days=30 \
        --recurrence=DAILY \
        --backup-window-start=02:00" \
        "Adding backup rule"
    
    log_success "Backup and DR Service configured"
}

# Function to create disaster recovery infrastructure
create_dr_infrastructure() {
    log_info "Creating disaster recovery infrastructure..."
    
    # Create DR region instance template
    execute_command "gcloud compute instance-templates create dr-app-template-$RANDOM_SUFFIX \
        --machine-type=e2-micro \
        --network-interface=network-tier=PREMIUM,subnet=default \
        --metadata=startup-script='#!/bin/bash
            apt-get update
            apt-get install -y nginx
            echo \"<h1>DR Application - Instance: \$(hostname)</h1><p>Disaster Recovery Mode Active</p>\" > /var/www/html/index.html
            systemctl start nginx
            systemctl enable nginx' \
        --maintenance-policy=MIGRATE \
        --provisioning-model=STANDARD \
        --region=$DR_REGION \
        --tags=dr-app,http-server" \
        "Creating DR application instance template"
    
    # Create DR managed instance group (initially size 0 for cost efficiency)
    execute_command "gcloud compute instance-groups managed create dr-app-group-$RANDOM_SUFFIX \
        --template=dr-app-template-$RANDOM_SUFFIX \
        --size=0 \
        --zone=$DR_ZONE" \
        "Creating DR application instance group"
    
    # Create DR health check
    execute_command "gcloud compute health-checks create http dr-app-health-check-$RANDOM_SUFFIX \
        --port=80 \
        --request-path=/ \
        --check-interval=10s \
        --timeout=5s \
        --healthy-threshold=2 \
        --unhealthy-threshold=3" \
        "Creating DR application health check"
    
    log_success "DR infrastructure created"
}

# Function to deploy Cloud Function for DR orchestration
deploy_dr_function() {
    log_info "Deploying Cloud Function for DR orchestration..."
    
    # Create temporary directory for function code
    local function_dir="/tmp/dr-orchestrator-function-$$"
    mkdir -p "$function_dir"
    
    # Create main function file
    cat > "$function_dir/main.py" << 'EOF'
import functions_framework
import json
import logging
from google.cloud import compute_v1
from google.cloud import monitoring_v3
from google.cloud import backupdr_v1
import os

# Initialize clients
compute_client = compute_v1.InstanceGroupManagersClient()
monitoring_client = monitoring_v3.MetricServiceClient()

@functions_framework.http
def orchestrate_disaster_recovery(request):
    """
    Orchestrates disaster recovery based on service extension signals
    """
    try:
        # Parse incoming request from service extension
        request_json = request.get_json(silent=True)
        failure_type = request_json.get('failure_type', 'unknown')
        affected_region = request_json.get('region', os.environ.get('REGION'))
        severity = request_json.get('severity', 'medium')
        
        logging.info(f"DR triggered: {failure_type} in {affected_region}, severity: {severity}")
        
        # Assess failure severity and determine response
        response_actions = []
        
        if severity in ['high', 'critical']:
            # Scale up DR infrastructure
            dr_response = scale_dr_infrastructure()
            response_actions.append(dr_response)
            
            # Trigger backup restoration if needed
            if failure_type in ['data_corruption', 'storage_failure']:
                backup_response = trigger_backup_restoration()
                response_actions.append(backup_response)
        
        # Log metrics for monitoring
        log_dr_metrics(failure_type, severity, len(response_actions))
        
        return {
            'status': 'success',
            'actions_taken': response_actions,
            'timestamp': str(request.headers.get('X-Forwarded-For', 'unknown'))
        }
        
    except Exception as e:
        logging.error(f"DR orchestration failed: {str(e)}")
        return {'status': 'error', 'message': str(e)}, 500

def scale_dr_infrastructure():
    """Scale up disaster recovery infrastructure"""
    try:
        project_id = os.environ.get('PROJECT_ID')
        dr_zone = os.environ.get('DR_ZONE')
        random_suffix = os.environ.get('RANDOM_SUFFIX')
        
        # Scale DR instance group to 2 instances
        operation = compute_client.resize(
            project=project_id,
            zone=dr_zone,
            instance_group_manager=f"dr-app-group-{random_suffix}",
            size=2
        )
        
        logging.info(f"DR infrastructure scaling initiated: {operation.name}")
        return f"DR infrastructure scaled up in {dr_zone}"
        
    except Exception as e:
        logging.error(f"Failed to scale DR infrastructure: {str(e)}")
        return f"DR scaling failed: {str(e)}"

def trigger_backup_restoration():
    """Trigger backup restoration workflow"""
    try:
        # In production, this would trigger actual backup restoration
        # For this demo, we simulate the process
        logging.info("Backup restoration workflow initiated")
        return "Backup restoration initiated"
        
    except Exception as e:
        logging.error(f"Backup restoration failed: {str(e)}")
        return f"Backup restoration failed: {str(e)}"

def log_dr_metrics(failure_type, severity, actions_count):
    """Log custom metrics for DR monitoring"""
    try:
        project_name = f"projects/{os.environ.get('PROJECT_ID')}"
        
        # Create custom metric for DR events
        series = monitoring_v3.TimeSeries()
        series.metric.type = "custom.googleapis.com/disaster_recovery/events"
        series.metric.labels["failure_type"] = failure_type
        series.metric.labels["severity"] = severity
        
        # Add data point
        point = monitoring_v3.Point()
        point.value.int64_value = actions_count
        import time
        point.interval.end_time.seconds = int(time.time())
        series.points = [point]
        
        # Write metrics
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
    except Exception as e:
        logging.error(f"Failed to log DR metrics: {str(e)}")
EOF

    # Create requirements file
    cat > "$function_dir/requirements.txt" << 'EOF'
functions-framework==3.4.0
google-cloud-compute==1.15.0
google-cloud-monitoring==2.16.0
google-cloud-backup-dr==0.1.0
EOF

    # Deploy Cloud Function
    execute_command "gcloud functions deploy dr-orchestrator-$RANDOM_SUFFIX \
        --source=$function_dir \
        --runtime=python311 \
        --trigger=http \
        --entry-point=orchestrate_disaster_recovery \
        --memory=256MB \
        --timeout=300s \
        --set-env-vars=PROJECT_ID=$PROJECT_ID,REGION=$REGION,DR_ZONE=$DR_ZONE,RANDOM_SUFFIX=$RANDOM_SUFFIX \
        --allow-unauthenticated" \
        "Deploying DR orchestration function"
    
    # Clean up temporary directory
    rm -rf "$function_dir"
    
    log_success "DR orchestration function deployed"
}

# Function to create load balancer with backend services
create_load_balancer() {
    log_info "Creating load balancer with backend services..."
    
    # Create backend service for primary application
    execute_command "gcloud compute backend-services create primary-backend-service-$RANDOM_SUFFIX \
        --protocol=HTTP \
        --port-name=http \
        --health-checks=primary-app-health-check-$RANDOM_SUFFIX \
        --global" \
        "Creating primary backend service"
    
    # Add primary instance group to backend service
    execute_command "gcloud compute backend-services add-backend primary-backend-service-$RANDOM_SUFFIX \
        --instance-group=primary-app-group-$RANDOM_SUFFIX \
        --instance-group-zone=$ZONE \
        --global" \
        "Adding primary instance group to backend service"
    
    # Create backend service for DR application
    execute_command "gcloud compute backend-services create dr-backend-service-$RANDOM_SUFFIX \
        --protocol=HTTP \
        --port-name=http \
        --health-checks=dr-app-health-check-$RANDOM_SUFFIX \
        --global" \
        "Creating DR backend service"
    
    # Add DR instance group to backend service
    execute_command "gcloud compute backend-services add-backend dr-backend-service-$RANDOM_SUFFIX \
        --instance-group=dr-app-group-$RANDOM_SUFFIX \
        --instance-group-zone=$DR_ZONE \
        --global" \
        "Adding DR instance group to backend service"
    
    # Create URL map for traffic routing
    execute_command "gcloud compute url-maps create dr-orchestration-urlmap-$RANDOM_SUFFIX \
        --default-service=primary-backend-service-$RANDOM_SUFFIX" \
        "Creating URL map"
    
    log_success "Backend services configured"
}

# Function to configure global load balancer
configure_global_lb() {
    log_info "Configuring global load balancer..."
    
    # Create HTTP(S) proxy for load balancer
    execute_command "gcloud compute target-http-proxies create dr-orchestration-proxy-$RANDOM_SUFFIX \
        --url-map=dr-orchestration-urlmap-$RANDOM_SUFFIX" \
        "Creating HTTP proxy"
    
    # Create global forwarding rule
    execute_command "gcloud compute forwarding-rules create dr-orchestration-forwarding-rule-$RANDOM_SUFFIX \
        --global \
        --target-http-proxy=dr-orchestration-proxy-$RANDOM_SUFFIX \
        --ports=80" \
        "Creating forwarding rule"
    
    # Create firewall rules for HTTP traffic
    execute_command "gcloud compute firewall-rules create allow-http-$RANDOM_SUFFIX \
        --allow tcp:80 \
        --source-ranges 0.0.0.0/0 \
        --target-tags http-server \
        --description='Allow HTTP traffic for DR orchestration demo'" \
        "Creating firewall rule"
    
    log_success "Global load balancer configured"
}

# Function to set up monitoring and alerting
setup_monitoring() {
    log_info "Setting up monitoring and alerting..."
    
    # Create custom metrics for DR monitoring
    execute_command "gcloud logging metrics create dr-failure-detection-$RANDOM_SUFFIX \
        --description='Track disaster recovery failure detection events' \
        --log-filter='resource.type=\"cloud_function\" AND textPayload:\"DR triggered\"'" \
        "Creating failure detection metric"
    
    execute_command "gcloud logging metrics create dr-orchestration-success-$RANDOM_SUFFIX \
        --description='Track successful DR orchestration events' \
        --log-filter='resource.type=\"cloud_function\" AND textPayload:\"success\"'" \
        "Creating orchestration success metric"
    
    # Create alerting policy for DR events
    local alert_policy_file="/tmp/dr-alert-policy-$$.json"
    cat > "$alert_policy_file" << EOF
{
  "displayName": "Disaster Recovery Alert Policy $RANDOM_SUFFIX",
  "conditions": [
    {
      "displayName": "DR Orchestration Failures",
      "conditionThreshold": {
        "filter": "metric.type=\"logging.googleapis.com/user/dr-failure-detection-$RANDOM_SUFFIX\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0,
        "duration": "60s",
        "aggregations": [
          {
            "alignmentPeriod": "60s",
            "perSeriesAligner": "ALIGN_RATE"
          }
        ]
      }
    }
  ],
  "combiner": "OR",
  "enabled": true,
  "notificationChannels": [],
  "documentation": {
    "content": "Disaster recovery orchestration has been triggered. Review system status and validate recovery operations."
  }
}
EOF

    execute_command "gcloud alpha monitoring policies create --policy-from-file=$alert_policy_file" \
        "Creating alert policy"
    
    # Create dashboard for DR monitoring
    local dashboard_file="/tmp/dr-dashboard-$$.json"
    cat > "$dashboard_file" << EOF
{
  "displayName": "Disaster Recovery Orchestration Dashboard $RANDOM_SUFFIX",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "DR Events",
          "xyChart": {
            "dataSets": [
              {
                "timeSeriesQuery": {
                  "timeSeriesFilter": {
                    "filter": "metric.type=\"logging.googleapis.com/user/dr-failure-detection-$RANDOM_SUFFIX\"",
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "perSeriesAligner": "ALIGN_RATE"
                    }
                  }
                }
              }
            ]
          }
        }
      }
    ]
  }
}
EOF

    execute_command "gcloud monitoring dashboards create --config-from-file=$dashboard_file" \
        "Creating monitoring dashboard"
    
    # Clean up temporary files
    rm -f "$alert_policy_file" "$dashboard_file"
    
    log_success "Monitoring and alerting configured"
}

# Function to wait for resources and validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Skipping validation in dry-run mode"
        return 0
    fi
    
    # Wait for load balancer to become ready
    log_info "Waiting for load balancer to become ready..."
    sleep 120
    
    # Get the load balancer IP address
    local lb_ip
    lb_ip=$(gcloud compute forwarding-rules describe dr-orchestration-forwarding-rule-$RANDOM_SUFFIX \
        --global \
        --format="value(IPAddress)" 2>/dev/null || echo "")
    
    if [[ -n "$lb_ip" ]]; then
        log_success "Load Balancer IP: $lb_ip"
        log_info "Test URL: http://$lb_ip"
        
        # Test connectivity (basic check)
        if curl -s --connect-timeout 10 "http://$lb_ip" >/dev/null 2>&1; then
            log_success "Load balancer is responding"
        else
            log_warning "Load balancer may still be initializing"
        fi
    else
        log_warning "Could not retrieve load balancer IP"
    fi
    
    # Get Cloud Function URL
    local function_url
    function_url=$(gcloud functions describe dr-orchestrator-$RANDOM_SUFFIX \
        --format="value(serviceConfig.uri)" 2>/dev/null || echo "")
    
    if [[ -n "$function_url" ]]; then
        log_success "DR Function URL: $function_url"
    fi
    
    log_success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "=================================="
    echo "Project ID: $PROJECT_ID"
    echo "Primary Region: $REGION"
    echo "DR Region: $DR_REGION"
    echo "Resource Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Key Resources Created:"
    echo "- Primary Application Instance Group: primary-app-group-$RANDOM_SUFFIX"
    echo "- DR Application Instance Group: dr-app-group-$RANDOM_SUFFIX"
    echo "- Backup Vault: primary-backup-vault-$RANDOM_SUFFIX"
    echo "- Backup Plan: primary-backup-plan-$RANDOM_SUFFIX"
    echo "- DR Orchestration Function: dr-orchestrator-$RANDOM_SUFFIX"
    echo "- Load Balancer: dr-orchestration-forwarding-rule-$RANDOM_SUFFIX"
    echo ""
    
    if [[ "$DRY_RUN" == "false" ]]; then
        local lb_ip
        lb_ip=$(gcloud compute forwarding-rules describe dr-orchestration-forwarding-rule-$RANDOM_SUFFIX \
            --global \
            --format="value(IPAddress)" 2>/dev/null || echo "Not available")
        echo "Load Balancer IP: $lb_ip"
        echo "Test URL: http://$lb_ip"
        echo ""
    fi
    
    echo "To clean up resources, run: ./destroy.sh"
    echo "=================================="
}

# Main deployment function
main() {
    log_info "Starting Disaster Recovery Orchestration deployment..."
    
    check_prerequisites
    setup_environment
    setup_project
    enable_apis
    create_primary_infrastructure
    setup_backup_dr
    create_dr_infrastructure
    deploy_dr_function
    create_load_balancer
    configure_global_lb
    setup_monitoring
    validate_deployment
    display_summary
    
    log_success "Disaster Recovery Orchestration deployment completed successfully!"
}

# Error handling
trap 'log_error "Deployment failed. Check the logs above for details."; exit 1' ERR

# Run main function
main "$@"