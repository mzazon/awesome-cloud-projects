#!/bin/bash

# Network Security Monitoring with VPC Flow Logs and Security Command Center - Deployment Script
# This script deploys the complete network security monitoring infrastructure

set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

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

# Error handling function
cleanup_on_error() {
    local exit_code=$?
    log_error "Deployment failed with exit code: $exit_code"
    log_warning "Some resources may have been created. Run destroy.sh to clean up."
    exit $exit_code
}

# Set error trap
trap cleanup_on_error ERR

# Display banner
display_banner() {
    echo -e "${BLUE}"
    echo "=============================================================="
    echo "  Network Security Monitoring Infrastructure Deployment"
    echo "  GCP VPC Flow Logs + Security Command Center"
    echo "=============================================================="
    echo -e "${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if bq is installed
    if ! command -v bq &> /dev/null; then
        log_error "BigQuery CLI (bq) is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 > /dev/null; then
        log_error "Not authenticated with gcloud. Please run 'gcloud auth login'"
        exit 1
    fi
    
    # Check if project is set
    local project_id
    project_id=$(gcloud config get-value project 2>/dev/null || echo "")
    if [[ -z "$project_id" ]]; then
        log_error "No active project set. Please run 'gcloud config set project PROJECT_ID'"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
    log_info "Active project: $project_id"
}

# Validate and set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Core configuration
    export PROJECT_ID=$(gcloud config get-value project)
    export REGION="${REGION:-us-central1}"
    export ZONE="${ZONE:-us-central1-a}"
    export VPC_NAME="${VPC_NAME:-security-monitoring-vpc}"
    export SUBNET_NAME="${SUBNET_NAME:-monitored-subnet}"
    
    # Generate unique suffix for resource names
    RANDOM_SUFFIX=$(openssl rand -hex 3 2>/dev/null || echo "$(date +%s | tail -c6)")
    export INSTANCE_NAME="${INSTANCE_NAME:-test-vm-${RANDOM_SUFFIX}}"
    export LOG_SINK_NAME="${LOG_SINK_NAME:-vpc-flow-security-sink-${RANDOM_SUFFIX}}"
    export DATASET_NAME="${DATASET_NAME:-security_monitoring}"
    export PUBSUB_TOPIC="${PUBSUB_TOPIC:-security-findings-${RANDOM_SUFFIX}}"
    
    # Set default configurations for gcloud
    gcloud config set compute/region "$REGION" --quiet
    gcloud config set compute/zone "$ZONE" --quiet
    
    log_success "Environment variables configured"
    log_info "Region: $REGION, Zone: $ZONE"
    log_info "VPC: $VPC_NAME, Subnet: $SUBNET_NAME"
    log_info "Instance: $INSTANCE_NAME"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required Google Cloud APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "logging.googleapis.com"
        "monitoring.googleapis.com"
        "securitycenter.googleapis.com"
        "bigquery.googleapis.com"
        "pubsub.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        log_info "Enabling $api..."
        if ! gcloud services enable "$api" --quiet; then
            log_error "Failed to enable $api"
            exit 1
        fi
    done
    
    # Wait for APIs to be fully activated
    log_info "Waiting for APIs to be fully activated..."
    sleep 30
    
    log_success "All required APIs enabled"
}

# Create VPC network with flow logs
create_vpc_network() {
    log_info "Creating VPC network with security monitoring configuration..."
    
    # Create custom VPC network
    if ! gcloud compute networks describe "$VPC_NAME" --quiet &>/dev/null; then
        log_info "Creating VPC network: $VPC_NAME"
        gcloud compute networks create "$VPC_NAME" \
            --subnet-mode=custom \
            --description="VPC for network security monitoring demo" \
            --quiet
        log_success "VPC network created"
    else
        log_warning "VPC network $VPC_NAME already exists"
    fi
    
    # Create subnet with flow logs enabled
    if ! gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" --quiet &>/dev/null; then
        log_info "Creating subnet with flow logs: $SUBNET_NAME"
        gcloud compute networks subnets create "$SUBNET_NAME" \
            --network="$VPC_NAME" \
            --range=10.0.1.0/24 \
            --region="$REGION" \
            --enable-flow-logs \
            --flow-logs-sampling=1.0 \
            --flow-logs-interval=5s \
            --flow-logs-metadata=include-all \
            --quiet
        log_success "Subnet created with flow logs enabled"
    else
        log_warning "Subnet $SUBNET_NAME already exists"
    fi
}

# Configure firewall rules
configure_firewall_rules() {
    log_info "Configuring firewall rules for security testing..."
    
    local firewall_rules=(
        "allow-ssh-${RANDOM_SUFFIX}:tcp:22:0.0.0.0/0:security-test:Allow SSH for security monitoring test instances"
        "allow-http-${RANDOM_SUFFIX}:tcp:80,tcp:443:0.0.0.0/0:web-server:Allow HTTP/HTTPS for web service monitoring"
        "allow-internal-${RANDOM_SUFFIX}:tcp:0-65535,udp:0-65535,icmp:10.0.1.0/24:security-test:Allow internal subnet communication"
    )
    
    for rule_config in "${firewall_rules[@]}"; do
        IFS=':' read -r name protocols ports sources tags description <<< "$rule_config"
        
        if ! gcloud compute firewall-rules describe "$name" --quiet &>/dev/null; then
            log_info "Creating firewall rule: $name"
            gcloud compute firewall-rules create "$name" \
                --network="$VPC_NAME" \
                --allow="$protocols:$ports" \
                --source-ranges="$sources" \
                --target-tags="$tags" \
                --description="$description" \
                --quiet
        else
            log_warning "Firewall rule $name already exists"
        fi
    done
    
    log_success "Firewall rules configured"
}

# Deploy test VM instance
deploy_test_instance() {
    log_info "Deploying test VM instance for traffic generation..."
    
    if ! gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --quiet &>/dev/null; then
        # Create startup script
        local startup_script='#!/bin/bash
apt-get update
apt-get install -y apache2 netcat
systemctl start apache2
systemctl enable apache2
echo "<h1>Security Monitoring Test Server</h1>" > /var/www/html/index.html
echo "$(date): Security monitoring test server started" >> /var/log/startup.log'
        
        log_info "Creating VM instance: $INSTANCE_NAME"
        gcloud compute instances create "$INSTANCE_NAME" \
            --zone="$ZONE" \
            --machine-type=e2-micro \
            --subnet="$SUBNET_NAME" \
            --network-tier=PREMIUM \
            --maintenance-policy=MIGRATE \
            --image-family=ubuntu-2004-lts \
            --image-project=ubuntu-os-cloud \
            --boot-disk-size=10GB \
            --boot-disk-type=pd-standard \
            --tags=security-test,web-server \
            --metadata=startup-script="$startup_script" \
            --quiet
        
        # Wait for instance to be ready
        log_info "Waiting for instance to be ready..."
        local max_attempts=30
        local attempt=1
        
        while [[ $attempt -le $max_attempts ]]; do
            if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)" | grep -q "RUNNING"; then
                log_success "VM instance is running"
                break
            fi
            log_info "Waiting for instance to start... (attempt $attempt/$max_attempts)"
            sleep 10
            ((attempt++))
        done
        
        if [[ $attempt -gt $max_attempts ]]; then
            log_error "Instance failed to start within expected time"
            exit 1
        fi
        
    else
        log_warning "VM instance $INSTANCE_NAME already exists"
    fi
}

# Configure BigQuery dataset and logging sink
setup_logging_infrastructure() {
    log_info "Setting up logging infrastructure..."
    
    # Create BigQuery dataset
    if ! bq show --dataset "$PROJECT_ID:$DATASET_NAME" &>/dev/null; then
        log_info "Creating BigQuery dataset: $DATASET_NAME"
        bq mk --location="$REGION" \
            --description="Dataset for VPC Flow Logs security analysis" \
            "$DATASET_NAME"
        log_success "BigQuery dataset created"
    else
        log_warning "BigQuery dataset $DATASET_NAME already exists"
    fi
    
    # Create logging sink
    if ! gcloud logging sinks describe "$LOG_SINK_NAME" --quiet &>/dev/null; then
        log_info "Creating logging sink: $LOG_SINK_NAME"
        
        local log_filter='resource.type="gce_subnetwork" AND 
                         protoPayload.methodName="compute.subnetworks.insert" OR
                         logName:"compute.googleapis.com%2Fvpc_flows"'
        
        gcloud logging sinks create "$LOG_SINK_NAME" \
            "bigquery.googleapis.com/projects/$PROJECT_ID/datasets/$DATASET_NAME" \
            --log-filter="$log_filter" \
            --description="Sink for VPC Flow Logs security monitoring" \
            --quiet
        
        # Grant BigQuery permissions to sink service account
        local sink_sa
        sink_sa=$(gcloud logging sinks describe "$LOG_SINK_NAME" --format="value(writerIdentity)")
        
        log_info "Granting BigQuery permissions to sink service account"
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="$sink_sa" \
            --role="roles/bigquery.dataEditor" \
            --quiet
        
        log_success "Logging sink configured"
    else
        log_warning "Logging sink $LOG_SINK_NAME already exists"
    fi
}

# Set up Cloud Monitoring alert policies
setup_monitoring_alerts() {
    log_info "Setting up Cloud Monitoring alert policies..."
    
    # Create temporary policy files
    local high_traffic_policy="/tmp/high-traffic-alert-$RANDOM_SUFFIX.yaml"
    local suspicious_connections_policy="/tmp/suspicious-connections-alert-$RANDOM_SUFFIX.yaml"
    
    # High traffic volume alert policy
    cat > "$high_traffic_policy" << EOF
displayName: "High Network Traffic Volume Alert - $RANDOM_SUFFIX"
documentation:
  content: "Alert triggered when network traffic exceeds normal thresholds"
conditions:
  - displayName: "High egress traffic condition"
    conditionThreshold:
      filter: 'resource.type="gce_instance"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 1000000000
      duration: 300s
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_RATE
          crossSeriesReducer: REDUCE_SUM
notificationChannels: []
alertStrategy:
  autoClose: 86400s
EOF
    
    # Suspicious connections alert policy
    cat > "$suspicious_connections_policy" << EOF
displayName: "Suspicious Connection Patterns Alert - $RANDOM_SUFFIX"
documentation:
  content: "Alert for unusual connection patterns that may indicate security threats"
conditions:
  - displayName: "High connection rate condition"
    conditionThreshold:
      filter: 'resource.type="gce_subnetwork"'
      comparison: COMPARISON_GREATER_THAN
      thresholdValue: 100
      duration: 180s
      aggregations:
        - alignmentPeriod: 60s
          perSeriesAligner: ALIGN_RATE
          crossSeriesReducer: REDUCE_COUNT
notificationChannels: []
alertStrategy:
  autoClose: 43200s
EOF
    
    # Create alert policies
    log_info "Creating high traffic alert policy..."
    if gcloud alpha monitoring policies create --policy-from-file="$high_traffic_policy" --quiet; then
        log_success "High traffic alert policy created"
    else
        log_warning "Failed to create high traffic alert policy (may already exist)"
    fi
    
    log_info "Creating suspicious connections alert policy..."
    if gcloud alpha monitoring policies create --policy-from-file="$suspicious_connections_policy" --quiet; then
        log_success "Suspicious connections alert policy created"
    else
        log_warning "Failed to create suspicious connections alert policy (may already exist)"
    fi
    
    # Clean up temporary files
    rm -f "$high_traffic_policy" "$suspicious_connections_policy"
}

# Configure Security Command Center integration
setup_security_command_center() {
    log_info "Setting up Security Command Center integration..."
    
    # Create Pub/Sub topic for security findings
    if ! gcloud pubsub topics describe "$PUBSUB_TOPIC" --quiet &>/dev/null; then
        log_info "Creating Pub/Sub topic: $PUBSUB_TOPIC"
        gcloud pubsub topics create "$PUBSUB_TOPIC" --quiet
        log_success "Pub/Sub topic created"
    else
        log_warning "Pub/Sub topic $PUBSUB_TOPIC already exists"
    fi
    
    # Note: Full Security Command Center configuration requires organization-level permissions
    # which may not be available in all environments
    local org_id
    org_id=$(gcloud organizations list --format="value(name)" --filter="displayName:$PROJECT_ID" 2>/dev/null || echo "")
    
    if [[ -n "$org_id" ]]; then
        log_info "Organization found: $org_id"
        log_info "Security Command Center can be configured at organization level"
    else
        log_warning "Organization not found - using project-level monitoring only"
        log_info "Security Command Center integration may require additional setup"
    fi
}

# Generate test traffic for validation
generate_test_traffic() {
    log_info "Generating test traffic for monitoring validation..."
    
    # Get external IP of test instance
    local external_ip
    external_ip=$(gcloud compute instances describe "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "")
    
    if [[ -n "$external_ip" ]]; then
        log_info "Test instance external IP: $external_ip"
        
        # Generate HTTP traffic
        log_info "Generating HTTP traffic patterns..."
        for i in {1..5}; do
            if curl -s --connect-timeout 5 "http://$external_ip/" > /dev/null 2>&1; then
                log_info "HTTP request $i completed"
            else
                log_warning "HTTP request $i failed"
            fi
            sleep 2
        done
        
        # Test SSH connectivity
        log_info "Testing SSH connectivity..."
        if timeout 5 nc -z "$external_ip" 22 2>/dev/null; then
            log_success "SSH port is accessible"
        else
            log_warning "SSH port test failed"
        fi
        
        log_success "Test traffic generation completed"
    else
        log_warning "Could not retrieve external IP for traffic generation"
    fi
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    local validation_errors=0
    
    # Check VPC network
    if gcloud compute networks describe "$VPC_NAME" --quiet &>/dev/null; then
        log_success "✓ VPC network exists"
    else
        log_error "✗ VPC network missing"
        ((validation_errors++))
    fi
    
    # Check subnet with flow logs
    if gcloud compute networks subnets describe "$SUBNET_NAME" --region="$REGION" --quiet &>/dev/null; then
        log_success "✓ Subnet exists"
        
        # Check if flow logs are enabled
        local flow_logs_enabled
        flow_logs_enabled=$(gcloud compute networks subnets describe "$SUBNET_NAME" \
            --region="$REGION" --format="value(logConfig.enable)" 2>/dev/null || echo "false")
        
        if [[ "$flow_logs_enabled" == "True" ]]; then
            log_success "✓ VPC Flow Logs enabled"
        else
            log_error "✗ VPC Flow Logs not enabled"
            ((validation_errors++))
        fi
    else
        log_error "✗ Subnet missing"
        ((validation_errors++))
    fi
    
    # Check VM instance
    if gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --quiet &>/dev/null; then
        log_success "✓ Test VM instance exists"
    else
        log_error "✗ Test VM instance missing"
        ((validation_errors++))
    fi
    
    # Check BigQuery dataset
    if bq show --dataset "$PROJECT_ID:$DATASET_NAME" &>/dev/null; then
        log_success "✓ BigQuery dataset exists"
    else
        log_error "✗ BigQuery dataset missing"
        ((validation_errors++))
    fi
    
    # Check logging sink
    if gcloud logging sinks describe "$LOG_SINK_NAME" --quiet &>/dev/null; then
        log_success "✓ Logging sink exists"
    else
        log_error "✗ Logging sink missing"
        ((validation_errors++))
    fi
    
    # Check Pub/Sub topic
    if gcloud pubsub topics describe "$PUBSUB_TOPIC" --quiet &>/dev/null; then
        log_success "✓ Pub/Sub topic exists"
    else
        log_error "✗ Pub/Sub topic missing"
        ((validation_errors++))
    fi
    
    if [[ $validation_errors -eq 0 ]]; then
        log_success "All validation checks passed!"
        return 0
    else
        log_error "$validation_errors validation errors found"
        return 1
    fi
}

# Display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "Project ID: $PROJECT_ID"
    echo "Region: $REGION"
    echo "VPC Network: $VPC_NAME"
    echo "Subnet: $SUBNET_NAME"
    echo "Test Instance: $INSTANCE_NAME"
    echo "BigQuery Dataset: $DATASET_NAME"
    echo "Logging Sink: $LOG_SINK_NAME"
    echo "Pub/Sub Topic: $PUBSUB_TOPIC"
    echo ""
    
    # Get external IP for reference
    local external_ip
    external_ip=$(gcloud compute instances describe "$INSTANCE_NAME" \
        --zone="$ZONE" \
        --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null || echo "Not available")
    
    echo "Test Instance External IP: $external_ip"
    echo ""
    
    log_info "Next Steps:"
    echo "1. Wait 5-10 minutes for flow logs to start appearing in BigQuery"
    echo "2. Monitor VPC Flow Logs in BigQuery dataset: $DATASET_NAME"
    echo "3. Check Cloud Monitoring for alert policy triggers"
    echo "4. Review Security Command Center for security findings"
    echo "5. Generate additional traffic to test monitoring capabilities"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    display_banner
    
    log_info "Starting network security monitoring infrastructure deployment..."
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    enable_apis
    create_vpc_network
    configure_firewall_rules
    deploy_test_instance
    setup_logging_infrastructure
    setup_monitoring_alerts
    setup_security_command_center
    generate_test_traffic
    
    # Validate and summarize
    if validate_deployment; then
        log_success "🎉 Deployment completed successfully!"
        display_summary
    else
        log_error "Deployment completed with validation errors"
        log_warning "Check the errors above and run destroy.sh if needed"
        exit 1
    fi
}

# Run main function
main "$@"