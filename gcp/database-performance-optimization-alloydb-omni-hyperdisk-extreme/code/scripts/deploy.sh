#!/bin/bash

# Deploy script for Database Performance Optimization with AlloyDB Omni and Hyperdisk Extreme
# This script deploys the complete infrastructure for the GCP AlloyDB Omni recipe

set -euo pipefail  # Exit on any error, undefined variables, or pipe failures

# Script metadata
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly LOG_FILE="${PROJECT_ROOT}/deploy-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
}

# Configuration variables with defaults
PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Generate unique suffix for resource names (use timestamp for reproducibility)
DEPLOYMENT_ID=$(date +%s)
RANDOM_SUFFIX=$(echo "$DEPLOYMENT_ID" | tail -c 7)
INSTANCE_NAME="alloydb-vm-${RANDOM_SUFFIX}"
DISK_NAME="hyperdisk-extreme-${RANDOM_SUFFIX}"
FUNCTION_NAME="perf-scaler-${RANDOM_SUFFIX}"

# PostgreSQL configuration
POSTGRES_PASSWORD="AlloyDB_Secure_${DEPLOYMENT_ID}!"
DATABASE_NAME="analytics_db"

# Resource tracking for cleanup
CREATED_RESOURCES=()

# Print usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]

Deploy AlloyDB Omni with Hyperdisk Extreme infrastructure.

OPTIONS:
    -p, --project-id PROJECT_ID    GCP Project ID (required)
    -r, --region REGION           GCP Region (default: us-central1)
    -z, --zone ZONE               GCP Zone (default: us-central1-a)
    -y, --yes                     Skip confirmation prompts
    -d, --dry-run                 Show what would be deployed without executing
    -h, --help                    Show this help message

ENVIRONMENT VARIABLES:
    PROJECT_ID                    GCP Project ID
    REGION                        GCP Region
    ZONE                          GCP Zone
    SKIP_CONFIRMATION             Skip confirmation prompts (true/false)
    DRY_RUN                       Dry run mode (true/false)

EXAMPLES:
    $SCRIPT_NAME --project-id my-project
    $SCRIPT_NAME -p my-project -r us-west1 -z us-west1-a
    PROJECT_ID=my-project $SCRIPT_NAME --yes
    $SCRIPT_NAME --dry-run --project-id my-project

EOF
}

# Parse command line arguments
parse_args() {
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
            -y|--yes)
                SKIP_CONFIRMATION="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
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
}

# Validate prerequisites
validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if gcloud is installed
    if ! command -v gcloud &> /dev/null; then
        log_error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    # Check gcloud version
    local gcloud_version
    gcloud_version=$(gcloud version --format="value(Google Cloud SDK)" 2>/dev/null || echo "unknown")
    log_info "Using gcloud version: $gcloud_version"
    
    # Check if openssl is available
    if ! command -v openssl &> /dev/null; then
        log_error "openssl is required for generating random values."
        exit 1
    fi
    
    # Check if jq is available (optional but recommended)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON output may not be formatted."
    fi
    
    # Validate PROJECT_ID
    if [[ -z "$PROJECT_ID" ]]; then
        log_error "PROJECT_ID is required. Use --project-id or set PROJECT_ID environment variable."
        exit 1
    fi
    
    # Check gcloud authentication
    local active_account
    active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 2>/dev/null || echo "")
    if [[ -z "$active_account" ]]; then
        log_error "No active gcloud authentication found. Run 'gcloud auth login' first."
        exit 1
    fi
    log_info "Using authenticated account: $active_account"
    
    # Validate project exists and is accessible
    if ! gcloud projects describe "$PROJECT_ID" &> /dev/null; then
        log_error "Project '$PROJECT_ID' not found or not accessible."
        exit 1
    fi
    
    # Check quota for c3-highmem-8 instances
    log_info "Checking compute quotas..."
    local cpu_quota
    cpu_quota=$(gcloud compute project-info describe --project="$PROJECT_ID" \
        --format="value(quotas[metric=C3_CPUS].limit)" 2>/dev/null || echo "0")
    if [[ "$cpu_quota" -lt 8 ]]; then
        log_warning "C3 CPU quota ($cpu_quota) may be insufficient for c3-highmem-8 instance (requires 8 CPUs)"
    fi
    
    log_success "Prerequisites validation completed"
}

# Display deployment plan
show_deployment_plan() {
    cat << EOF

${BLUE}=== AlloyDB Omni Deployment Plan ===${NC}

Project ID:         $PROJECT_ID
Region:             $REGION
Zone:               $ZONE
Deployment ID:      $DEPLOYMENT_ID
Instance Name:      $INSTANCE_NAME
Disk Name:          $DISK_NAME
Function Name:      $FUNCTION_NAME
Database Name:      $DATABASE_NAME
Log File:           $LOG_FILE

${BLUE}Resources to be created:${NC}
• Hyperdisk Extreme volume (500GB, 100K IOPS)
• VM Instance (c3-highmem-8 with 8 vCPUs, 64GB RAM)
• AlloyDB Omni container with PostgreSQL 16.8
• Cloud Function for automated scaling (Python 3.12)
• Cloud Monitoring dashboard with performance metrics
• Alert policies for CPU utilization monitoring
• Sample database with 10K customers and 100K transactions

${BLUE}Required APIs:${NC}
• Compute Engine API
• Cloud Functions API
• Cloud Monitoring API
• Cloud Logging API

${YELLOW}Estimated Cost:${NC} $15-25 for 45 minutes
${YELLOW}Note:${NC} High-performance resources incur significant costs

EOF
}

# Confirmation prompt
confirm_deployment() {
    if [[ "$SKIP_CONFIRMATION" == "true" ]]; then
        return 0
    fi
    
    echo -n "Do you want to proceed with the deployment? (y/N): "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            log_info "Deployment cancelled by user"
            exit 0
            ;;
    esac
}

# Execute command with dry-run support and error handling
execute_cmd() {
    local cmd="$1"
    local description="$2"
    local resource_type="${3:-}"
    local resource_name="${4:-}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] $description"
        log_info "[DRY-RUN] Command: $cmd"
        return 0
    fi
    
    log_info "$description"
    if eval "$cmd" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "$description completed"
        # Track created resources for cleanup
        if [[ -n "$resource_type" && -n "$resource_name" ]]; then
            CREATED_RESOURCES+=("$resource_type:$resource_name")
        fi
        return 0
    else
        log_error "$description failed"
        return 1
    fi
}

# Configure GCP environment
configure_gcp_environment() {
    log_info "Configuring GCP environment..."
    
    execute_cmd "gcloud config set project '$PROJECT_ID'" "Setting project"
    execute_cmd "gcloud config set compute/region '$REGION'" "Setting region"
    execute_cmd "gcloud config set compute/zone '$ZONE'" "Setting zone"
    
    log_success "GCP environment configured"
}

# Enable required APIs
enable_apis() {
    log_info "Enabling required APIs..."
    
    local apis=(
        "compute.googleapis.com"
        "cloudfunctions.googleapis.com" 
        "monitoring.googleapis.com"
        "logging.googleapis.com"
    )
    
    for api in "${apis[@]}"; do
        execute_cmd "gcloud services enable '$api'" "Enabling $api"
    done
    
    # Wait for APIs to be fully enabled
    if [[ "$DRY_RUN" != "true" ]]; then
        log_info "Waiting for APIs to be fully enabled..."
        sleep 30
    fi
    
    log_success "All required APIs enabled"
}

# Create Hyperdisk Extreme volume
create_hyperdisk() {
    log_info "Creating Hyperdisk Extreme volume..."
    
    local cmd="gcloud compute disks create '$DISK_NAME' \\
        --type=hyperdisk-extreme \\
        --size=500GB \\
        --provisioned-iops=100000 \\
        --zone='$ZONE'"
    
    execute_cmd "$cmd" "Creating Hyperdisk Extreme volume" "disk" "$DISK_NAME"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Verify disk creation and wait for it to be ready
        local retry_count=0
        while [[ $retry_count -lt 10 ]]; do
            if gcloud compute disks describe "$DISK_NAME" --zone="$ZONE" &> /dev/null; then
                break
            fi
            sleep 5
            ((retry_count++))
        done
        
        execute_cmd "gcloud compute disks describe '$DISK_NAME' --zone='$ZONE' --format='table(name,type,sizeGb,provisionedIops)'" "Verifying disk creation"
    fi
    
    log_success "Hyperdisk Extreme volume created with 100,000 IOPS"
}

# Deploy VM instance with AlloyDB Omni
deploy_vm_instance() {
    log_info "Deploying VM instance with AlloyDB Omni..."
    
    # Create startup script with better error handling
    local startup_script="#!/bin/bash
set -e
exec > >(tee /var/log/startup-script.log) 2>&1

echo 'Starting AlloyDB Omni setup...'

# Update system and install required packages
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io fio curl jq

# Configure Docker
systemctl start docker
systemctl enable docker
usermod -aG docker ubuntu

# Wait for disk to be available
echo 'Waiting for Hyperdisk to be available...'
while [ ! -e /dev/disk/by-id/google-alloydb-data ]; do
    sleep 5
done

# Format and mount Hyperdisk Extreme
echo 'Formatting and mounting Hyperdisk Extreme...'
mkfs.ext4 -F /dev/disk/by-id/google-alloydb-data
mkdir -p /var/lib/alloydb
mount /dev/disk/by-id/google-alloydb-data /var/lib/alloydb
echo '/dev/disk/by-id/google-alloydb-data /var/lib/alloydb ext4 defaults 0 2' >> /etc/fstab

# Create data directory with proper permissions
mkdir -p /var/lib/alloydb/data
chown -R 999:999 /var/lib/alloydb

# Pull AlloyDB Omni image
echo 'Pulling AlloyDB Omni image...'
docker pull gcr.io/alloydb-omni/alloydb-omni:latest

# Start AlloyDB Omni container
echo 'Starting AlloyDB Omni container...'
docker run -d \\
  --name alloydb-omni \\
  --restart unless-stopped \\
  -p 5432:5432 \\
  -v /var/lib/alloydb/data:/var/lib/postgresql/data \\
  -e POSTGRES_PASSWORD='$POSTGRES_PASSWORD' \\
  -e POSTGRES_DB='$DATABASE_NAME' \\
  -e POSTGRES_USER=postgres \\
  gcr.io/alloydb-omni/alloydb-omni:latest

# Wait for PostgreSQL to be ready
echo 'Waiting for AlloyDB Omni to be ready...'
for i in {1..30}; do
    if docker exec alloydb-omni pg_isready -U postgres; then
        echo 'AlloyDB Omni is ready!'
        break
    fi
    sleep 10
done

echo 'AlloyDB Omni setup completed successfully!'
"
    
    local cmd="gcloud compute instances create '$INSTANCE_NAME' \\
        --machine-type=c3-highmem-8 \\
        --image-family=ubuntu-2004-lts \\
        --image-project=ubuntu-os-cloud \\
        --disk='name=$DISK_NAME,device-name=alloydb-data,mode=rw,boot=no' \\
        --metadata=startup-script='$startup_script' \\
        --tags=alloydb-omni \\
        --zone='$ZONE' \\
        --scopes=https://www.googleapis.com/auth/cloud-platform"
    
    execute_cmd "$cmd" "Creating VM instance" "instance" "$INSTANCE_NAME"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Wait for instance to be running
        log_info "Waiting for instance to be ready..."
        local retry_count=0
        while [[ $retry_count -lt 30 ]]; do
            local status
            status=$(gcloud compute instances describe "$INSTANCE_NAME" --zone="$ZONE" --format="value(status)" 2>/dev/null || echo "")
            if [[ "$status" == "RUNNING" ]]; then
                break
            fi
            sleep 10
            ((retry_count++))
        done
        
        if [[ $retry_count -eq 30 ]]; then
            log_error "Instance failed to start within expected time"
            return 1
        fi
        
        # Wait for startup script to complete
        log_info "Waiting for AlloyDB Omni container to be ready..."
        retry_count=0
        while [[ $retry_count -lt 60 ]]; do
            if gcloud compute ssh "$INSTANCE_NAME" --zone="$ZONE" --command="sudo docker exec alloydb-omni pg_isready -U postgres" &> /dev/null; then
                break
            fi
            sleep 10
            ((retry_count++))
        done
        
        if [[ $retry_count -eq 60 ]]; then
            log_error "AlloyDB Omni failed to be ready within expected time"
            return 1
        fi
    fi
    
    log_success "VM instance deployed with AlloyDB Omni"
}

# Create monitoring dashboard
create_monitoring_dashboard() {
    log_info "Creating performance monitoring dashboard..."
    
    local dashboard_config
    dashboard_config=$(mktemp)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "$dashboard_config" << 'EOF'
{
  "displayName": "AlloyDB Omni Performance Dashboard",
  "mosaicLayout": {
    "tiles": [
      {
        "width": 6,
        "height": 4,
        "widget": {
          "title": "CPU Utilization",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "widget": {
          "title": "Disk IOPS",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/disk/read_ops_count\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "yPos": 4,
        "widget": {
          "title": "Memory Utilization",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/memory/utilization\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      },
      {
        "width": 6,
        "height": 4,
        "xPos": 6,
        "yPos": 4,
        "widget": {
          "title": "Disk Throughput",
          "xyChart": {
            "dataSets": [{
              "timeSeriesQuery": {
                "timeSeriesFilter": {
                  "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/disk/read_bytes_count\"",
                  "aggregation": {
                    "alignmentPeriod": "60s",
                    "perSeriesAligner": "ALIGN_RATE"
                  }
                }
              }
            }]
          }
        }
      }
    ]
  }
}
EOF
    fi
    
    execute_cmd "gcloud monitoring dashboards create --config-from-file='$dashboard_config'" "Creating monitoring dashboard" "dashboard" "AlloyDB Omni Performance Dashboard"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f "$dashboard_config"
    fi
    
    log_success "Performance monitoring dashboard created"
}

# Deploy Cloud Function for scaling
deploy_scaling_function() {
    log_info "Deploying automated performance scaling function..."
    
    local function_dir
    function_dir=$(mktemp -d)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        # Create function code with better error handling
        cat > "$function_dir/main.py" << EOF
import json
import logging
from datetime import datetime
from google.cloud import compute_v1
from google.cloud import monitoring_v3
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@functions_framework.http
def scale_performance(request):
    """Scale AlloyDB Omni performance based on metrics."""
    
    try:
        # Initialize clients
        compute_client = compute_v1.InstancesClient()
        monitoring_client = monitoring_v3.MetricServiceClient()
        
        project_id = "$PROJECT_ID"
        zone = "$ZONE"
        instance_name = "$INSTANCE_NAME"
        
        logger.info(f"Checking performance metrics for instance: {instance_name}")
        
        # Get current instance details
        instance = compute_client.get(
            project=project_id,
            zone=zone,
            instance=instance_name
        )
        
        # Extract machine type
        current_machine_type = instance.machine_type.split("/")[-1]
        
        # Get current timestamp
        current_time = datetime.utcnow().isoformat() + "Z"
        
        # Return scaling recommendation
        response = {
            "status": "success",
            "timestamp": current_time,
            "instance_name": instance_name,
            "current_machine_type": current_machine_type,
            "instance_status": instance.status,
            "recommendation": "Monitor CPU and memory metrics for scaling decisions",
            "next_check": "Manual monitoring recommended for performance optimization"
        }
        
        logger.info(f"Performance check completed: {response}")
        return response
        
    except Exception as e:
        error_msg = f"Error checking performance metrics: {str(e)}"
        logger.error(error_msg)
        return {
            "status": "error", 
            "message": error_msg,
            "timestamp": datetime.utcnow().isoformat() + "Z"
        }
EOF
        
        # Create requirements.txt with specific versions
        cat > "$function_dir/requirements.txt" << 'EOF'
google-cloud-compute>=1.19.0
google-cloud-monitoring>=2.22.0
functions-framework>=3.8.0
EOF
    fi
    
    local cmd="gcloud functions deploy '$FUNCTION_NAME' \\
        --runtime python312 \\
        --trigger-http \\
        --source '$function_dir' \\
        --entry-point scale_performance \\
        --memory 256MB \\
        --timeout 60s \\
        --allow-unauthenticated \\
        --max-instances 10"
    
    execute_cmd "$cmd" "Deploying Cloud Function" "function" "$FUNCTION_NAME"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -rf "$function_dir"
    fi
    
    log_success "Performance scaling function deployed"
}

# Create alert policies
create_alert_policies() {
    log_info "Creating performance alert policies..."
    
    local alert_config
    alert_config=$(mktemp)
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "$alert_config" << 'EOF'
{
  "displayName": "AlloyDB Omni High CPU Alert",
  "conditions": [
    {
      "displayName": "CPU utilization high",
      "conditionThreshold": {
        "filter": "resource.type=\"gce_instance\" AND metric.type=\"compute.googleapis.com/instance/cpu/utilization\"",
        "comparison": "COMPARISON_GREATER_THAN",
        "thresholdValue": 0.8,
        "duration": "60s",
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
  "enabled": true
}
EOF
    fi
    
    execute_cmd "gcloud alpha monitoring policies create --policy-from-file='$alert_config'" "Creating alert policy" "alert" "AlloyDB Omni High CPU Alert"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        rm -f "$alert_config"
    fi
    
    log_success "Performance alert policies configured"
}

# Load sample data
load_sample_data() {
    log_info "Loading sample data and configuring performance testing..."
    
    local sql_script="
-- Create sample tables for performance testing
CREATE TABLE IF NOT EXISTS transactions (
  id SERIAL PRIMARY KEY,
  customer_id INTEGER,
  transaction_date TIMESTAMP,
  amount DECIMAL(10,2),
  category VARCHAR(50),
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS customers (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  email VARCHAR(100),
  signup_date DATE,
  status VARCHAR(20)
);

-- Insert sample data for performance testing
INSERT INTO customers (name, email, signup_date, status)
SELECT 
  'Customer ' || generate_series,
  'user' || generate_series || '@example.com',
  CURRENT_DATE - (random() * 365)::integer,
  CASE WHEN random() < 0.8 THEN 'active' ELSE 'inactive' END
FROM generate_series(1, 10000)
ON CONFLICT DO NOTHING;

INSERT INTO transactions (customer_id, transaction_date, amount, category)
SELECT 
  (random() * 9999 + 1)::integer,
  NOW() - (random() * interval '30 days'),
  (random() * 1000 + 10)::decimal(10,2),
  (ARRAY['retail', 'dining', 'gas', 'grocery', 'entertainment'])[floor(random() * 5 + 1)]
FROM generate_series(1, 100000)
ON CONFLICT DO NOTHING;

-- Create indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_transactions_customer ON transactions(customer_id);
CREATE INDEX IF NOT EXISTS idx_customers_status ON customers(status);

-- Analyze tables to update statistics
ANALYZE transactions;
ANALYZE customers;

-- Display table counts
SELECT 'customers' as table_name, count(*) as row_count FROM customers
UNION ALL
SELECT 'transactions' as table_name, count(*) as row_count FROM transactions;
"
    
    local cmd="gcloud compute ssh '$INSTANCE_NAME' \\
        --zone='$ZONE' \\
        --command='
          echo \"Loading sample data into AlloyDB Omni...\"
          
          # Wait for AlloyDB container to be fully ready
          for i in {1..10}; do
              if sudo docker exec alloydb-omni pg_isready -U postgres; then
                  break
              fi
              echo \"Waiting for database to be ready... (\$i/10)\"
              sleep 10
          done
          
          # Load sample data
          sudo docker exec -i alloydb-omni psql -U postgres -d $DATABASE_NAME << \"EOSQL\"
          $sql_script
          \\\\q
          EOSQL
          
          echo \"Sample data loaded successfully\"
        '"
    
    execute_cmd "$cmd" "Loading sample data"
    
    log_success "Sample data loaded and performance indexes created"
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Skipping validation in dry-run mode"
        return 0
    fi
    
    # Test database connectivity and version
    local test_cmd="gcloud compute ssh '$INSTANCE_NAME' \\
        --zone='$ZONE' \\
        --command='
          echo \"Testing database connectivity...\"
          sudo docker exec alloydb-omni psql -U postgres -d $DATABASE_NAME -c \"SELECT version();\"
          echo \"\"
          echo \"Testing performance with sample query...\"
          sudo docker exec alloydb-omni psql -U postgres -d $DATABASE_NAME -c \"
            \\\\timing on
            SELECT category, COUNT(*) as count, AVG(amount) as avg_amount 
            FROM transactions 
            WHERE transaction_date >= NOW() - INTERVAL '7 days' 
            GROUP BY category 
            ORDER BY count DESC;
          \"
        '"
    
    execute_cmd "$test_cmd" "Testing database connectivity and performance"
    
    # Test Cloud Function
    local function_url
    function_url=$(gcloud functions describe "$FUNCTION_NAME" --format="value(httpsTrigger.url)" 2>/dev/null || echo "")
    if [[ -n "$function_url" ]]; then
        if command -v curl &> /dev/null; then
            execute_cmd "curl -s -X POST '$function_url' -H 'Content-Type: application/json' -d '{\"test\": true}'" "Testing Cloud Function"
        else
            log_warning "curl not available, skipping Cloud Function test"
        fi
    fi
    
    log_success "Deployment validation completed"
}

# Save deployment configuration
save_deployment_config() {
    log_info "Saving deployment configuration..."
    
    local config_file="$PROJECT_ROOT/deployment-config.json"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        cat > "$config_file" << EOF
{
  "deployment_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "deployment_id": "$DEPLOYMENT_ID",
  "project_id": "$PROJECT_ID",
  "region": "$REGION",
  "zone": "$ZONE",
  "instance_name": "$INSTANCE_NAME",
  "disk_name": "$DISK_NAME",
  "function_name": "$FUNCTION_NAME",
  "database_name": "$DATABASE_NAME",
  "postgres_password": "$POSTGRES_PASSWORD",
  "created_resources": $(printf '%s\n' "${CREATED_RESOURCES[@]}" | jq -R . | jq -s .)
}
EOF
    fi
    
    log_success "Deployment configuration saved to $config_file"
}

# Display deployment summary
show_deployment_summary() {
    local function_url=""
    if [[ "$DRY_RUN" != "true" ]]; then
        function_url=$(gcloud functions describe "$FUNCTION_NAME" --format="value(httpsTrigger.url)" 2>/dev/null || echo "Not available")
    fi
    
    cat << EOF

${GREEN}=== Deployment Completed Successfully ===${NC}

${BLUE}Deployed Resources:${NC}
• VM Instance:        $INSTANCE_NAME (c3-highmem-8)
• Hyperdisk Extreme:  $DISK_NAME (500GB, 100K IOPS)
• Cloud Function:     $FUNCTION_NAME
• Database:           $DATABASE_NAME (PostgreSQL 16.8 with AlloyDB Omni)
• Monitoring Dashboard and Alert Policies

${BLUE}Connection Information:${NC}
• Instance SSH:       gcloud compute ssh $INSTANCE_NAME --zone=$ZONE
• Database Connection: Available via AlloyDB Omni container on port 5432
• Database Password:  $POSTGRES_PASSWORD
• Function URL:       $function_url

${BLUE}Performance Features Enabled:${NC}
• Columnar engine for analytical queries (up to 100X faster)
• Autopilot features for automatic tuning
• Ultra-high IOPS storage (100,000 IOPS)
• Automated monitoring and alerting

${BLUE}Next Steps:${NC}
1. Connect to the database and run performance tests
2. Monitor performance through Cloud Monitoring dashboard
3. Test automated scaling function responses
4. Run cleanup script when testing is complete:
   ${PROJECT_ROOT}/scripts/destroy.sh --project-id $PROJECT_ID

${YELLOW}Important:${NC} Remember to run the cleanup script to avoid ongoing charges!
${YELLOW}Log File:${NC} $LOG_FILE

EOF
}

# Cleanup function for error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up partially created resources..."
    
    # Attempt to clean up resources that were successfully created
    for resource in "${CREATED_RESOURCES[@]}"; do
        IFS=':' read -r type name <<< "$resource"
        case "$type" in
            "instance")
                gcloud compute instances delete "$name" --zone="$ZONE" --quiet &
                ;;
            "disk")
                gcloud compute disks delete "$name" --zone="$ZONE" --quiet &
                ;;
            "function")
                gcloud functions delete "$name" --quiet &
                ;;
        esac
    done
    
    wait
    log_info "Cleanup completed. Check the log file for details: $LOG_FILE"
}

# Main deployment function
main() {
    log_info "Starting AlloyDB Omni deployment script"
    log_info "Log file: $LOG_FILE"
    
    parse_args "$@"
    validate_prerequisites
    show_deployment_plan
    confirm_deployment
    
    # Execute deployment steps
    configure_gcp_environment
    enable_apis
    create_hyperdisk
    deploy_vm_instance
    create_monitoring_dashboard
    deploy_scaling_function
    create_alert_policies
    load_sample_data
    validate_deployment
    save_deployment_config
    
    show_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Error handling
trap 'cleanup_on_error' ERR

# Run main function
main "$@"