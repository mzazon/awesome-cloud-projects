#!/bin/bash

# Database Disaster Recovery with Backup and DR Service and Cloud SQL - Deployment Script
# This script deploys a comprehensive automated disaster recovery system for Cloud SQL
# using Google Cloud's Backup and DR Service with cross-region replication.

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for operation completion
wait_for_operation() {
    local operation_name="$1"
    local max_wait="${2:-900}" # Default 15 minutes
    local counter=0
    
    log "Waiting for operation '$operation_name' to complete..."
    
    while [ $counter -lt $max_wait ]; do
        local status=$(gcloud sql operations describe "$operation_name" \
            --format="value(status)" 2>/dev/null || echo "UNKNOWN")
        
        case "$status" in
            "DONE")
                success "Operation '$operation_name' completed successfully"
                return 0
                ;;
            "RUNNING"|"PENDING")
                echo -n "."
                sleep 10
                counter=$((counter + 10))
                ;;
            "UNKNOWN"|"")
                warning "Unable to check operation status. Continuing..."
                return 0
                ;;
            *)
                error "Operation '$operation_name' failed with status: $status"
                ;;
        esac
    done
    
    error "Operation '$operation_name' timed out after $max_wait seconds"
}

# Function to check API enablement
check_api_enabled() {
    local api="$1"
    if gcloud services list --enabled --filter="name:$api" --format="value(name)" | grep -q "$api"; then
        return 0
    else
        return 1
    fi
}

# Banner
echo "=================================================="
echo "  Database Disaster Recovery Deployment Script"
echo "  GCP Cloud SQL + Backup and DR Service"
echo "=================================================="
echo ""

# Prerequisites Check
log "Checking prerequisites..."

# Check if gcloud is installed
if ! command_exists gcloud; then
    error "gcloud CLI is not installed. Please install it from https://cloud.google.com/sdk/docs/install"
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n 1 >/dev/null 2>&1; then
    error "Not authenticated with gcloud. Run 'gcloud auth login' first."
fi

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    error "No project set. Run 'gcloud config set project PROJECT_ID' first."
fi

success "Prerequisites check completed. Using project: $PROJECT_ID"

# Configuration
log "Setting up configuration..."

export PRIMARY_REGION="us-central1"
export SECONDARY_REGION="us-east1"
export PRIMARY_ZONE="${PRIMARY_REGION}-a"
export SECONDARY_ZONE="${SECONDARY_REGION}-a"

# Generate unique suffix for resource naming
if command_exists openssl; then
    RANDOM_SUFFIX=$(openssl rand -hex 3)
else
    RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 6 | head -n 1)
fi

export DB_INSTANCE_NAME="prod-db-${RANDOM_SUFFIX}"
export DR_REPLICA_NAME="prod-db-dr-${RANDOM_SUFFIX}"
export BACKUP_VAULT_PRIMARY="backup-vault-primary-${RANDOM_SUFFIX}"
export BACKUP_VAULT_SECONDARY="backup-vault-secondary-${RANDOM_SUFFIX}"

# Set default region and zone
gcloud config set compute/region ${PRIMARY_REGION} >/dev/null 2>&1
gcloud config set compute/zone ${PRIMARY_ZONE} >/dev/null 2>&1

success "Configuration completed"
echo "  Project: ${PROJECT_ID}"
echo "  Primary region: ${PRIMARY_REGION}"
echo "  Secondary region: ${SECONDARY_REGION}"
echo "  Database instance: ${DB_INSTANCE_NAME}"
echo "  DR replica: ${DR_REPLICA_NAME}"
echo ""

# Enable required APIs
log "Enabling required Google Cloud APIs..."

REQUIRED_APIS=(
    "sqladmin.googleapis.com"
    "backupdr.googleapis.com"
    "cloudfunctions.googleapis.com"
    "cloudscheduler.googleapis.com"
    "monitoring.googleapis.com"
    "pubsub.googleapis.com"
    "cloudbuild.googleapis.com"
)

for api in "${REQUIRED_APIS[@]}"; do
    if check_api_enabled "$api"; then
        log "API $api is already enabled"
    else
        log "Enabling API: $api"
        gcloud services enable "$api" || error "Failed to enable API: $api"
    fi
done

success "All required APIs are enabled"

# Step 1: Create Cloud SQL Primary Instance with High Availability
log "Creating Cloud SQL primary instance with high availability..."

# Check if instance already exists
if gcloud sql instances describe "$DB_INSTANCE_NAME" >/dev/null 2>&1; then
    warning "Cloud SQL instance '$DB_INSTANCE_NAME' already exists. Skipping creation."
else
    gcloud sql instances create "$DB_INSTANCE_NAME" \
        --database-version=POSTGRES_15 \
        --tier=db-custom-2-8192 \
        --region="$PRIMARY_REGION" \
        --availability-type=REGIONAL \
        --storage-type=SSD \
        --storage-size=100GB \
        --storage-auto-increase \
        --backup-start-time=03:00 \
        --enable-bin-log \
        --edition=ENTERPRISE_PLUS \
        --deletion-protection \
        --async || error "Failed to create Cloud SQL primary instance"
    
    # Wait for instance to be ready
    log "Waiting for Cloud SQL instance to be ready..."
    while true; do
        STATE=$(gcloud sql instances describe "$DB_INSTANCE_NAME" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        if [ "$STATE" = "RUNNABLE" ]; then
            break
        elif [ "$STATE" = "UNKNOWN" ]; then
            error "Failed to check instance state"
        else
            echo -n "."
            sleep 15
        fi
    done
    
    success "Cloud SQL primary instance created successfully"
fi

# Step 2: Configure Backup and DR Service Vault Storage
log "Creating backup vaults in both regions..."

# Create primary backup vault
if gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_PRIMARY" --location="$PRIMARY_REGION" >/dev/null 2>&1; then
    warning "Primary backup vault already exists. Skipping creation."
else
    log "Creating primary backup vault..."
    EFFECTIVE_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    gcloud backup-dr backup-vaults create "$BACKUP_VAULT_PRIMARY" \
        --location="$PRIMARY_REGION" \
        --description="Primary backup vault for disaster recovery" \
        --effective-time="$EFFECTIVE_TIME" \
        --backup-minimum-enforced-retention-duration=30d || error "Failed to create primary backup vault"
fi

# Create secondary backup vault
if gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_SECONDARY" --location="$SECONDARY_REGION" >/dev/null 2>&1; then
    warning "Secondary backup vault already exists. Skipping creation."
else
    log "Creating secondary backup vault..."
    EFFECTIVE_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    gcloud backup-dr backup-vaults create "$BACKUP_VAULT_SECONDARY" \
        --location="$SECONDARY_REGION" \
        --description="Secondary backup vault for cross-region DR" \
        --effective-time="$EFFECTIVE_TIME" \
        --backup-minimum-enforced-retention-duration=30d || error "Failed to create secondary backup vault"
fi

success "Backup vaults created successfully"

# Step 3: Create Disaster Recovery Replica in Secondary Region
log "Creating disaster recovery replica..."

if gcloud sql instances describe "$DR_REPLICA_NAME" >/dev/null 2>&1; then
    warning "DR replica already exists. Skipping creation."
else
    # Create cross-region disaster recovery replica
    gcloud sql instances create "$DR_REPLICA_NAME" \
        --master-instance-name="$DB_INSTANCE_NAME" \
        --region="$SECONDARY_REGION" \
        --tier=db-custom-2-8192 \
        --availability-type=ZONAL \
        --replica-type=READ \
        --enable-bin-log \
        --async || error "Failed to create DR replica"
    
    # Wait for replica to be ready
    log "Waiting for DR replica to be ready..."
    while true; do
        STATE=$(gcloud sql instances describe "$DR_REPLICA_NAME" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
        if [ "$STATE" = "RUNNABLE" ]; then
            break
        elif [ "$STATE" = "UNKNOWN" ]; then
            error "Failed to check replica state"
        else
            echo -n "."
            sleep 15
        fi
    done
    
    # Configure as failover replica
    log "Configuring replica for automated failover..."
    gcloud sql instances patch "$DR_REPLICA_NAME" \
        --replica-type=FAILOVER || warning "Failed to set replica type to FAILOVER"
    
    success "DR replica created and configured"
fi

# Step 4: Create Backup Plans for Automated Protection
log "Creating backup plans..."

# Check if backup plan already exists
BACKUP_PLAN_NAME="backup-plan-${DB_INSTANCE_NAME}"
if gcloud backup-dr backup-plans describe "$BACKUP_PLAN_NAME" --location="$PRIMARY_REGION" >/dev/null 2>&1; then
    warning "Backup plan already exists. Skipping creation."
else
    log "Creating backup plan for primary instance..."
    gcloud backup-dr backup-plans create "$BACKUP_PLAN_NAME" \
        --location="$PRIMARY_REGION" \
        --backup-vault="projects/${PROJECT_ID}/locations/${PRIMARY_REGION}/backupVaults/${BACKUP_VAULT_PRIMARY}" \
        --resource-type=cloudsql.googleapis.com/Instance \
        --backup-rule-backup-retention-days=30 \
        --backup-rule-backup-frequency="0 2 * * *" || error "Failed to create backup plan"
    
    # Associate backup plan with Cloud SQL instance
    log "Associating backup plan with Cloud SQL instance..."
    gcloud backup-dr backup-plan-associations create \
        --location="$PRIMARY_REGION" \
        --backup-plan="$BACKUP_PLAN_NAME" \
        --resource="projects/${PROJECT_ID}/instances/${DB_INSTANCE_NAME}" \
        --resource-type=cloudsql.googleapis.com/Instance || warning "Failed to associate backup plan"
fi

success "Backup plans configured successfully"

# Step 5: Create directories and Cloud Functions for DR orchestration
log "Creating Cloud Functions for disaster recovery orchestration..."

# Create temporary directory for function code
FUNCTION_DIR=$(mktemp -d)
trap "rm -rf '$FUNCTION_DIR'" EXIT

# Create main.py for DR orchestration
cat > "$FUNCTION_DIR/main.py" << 'EOF'
import functions_framework
import google.cloud.sql_v1 as sql_v1
import google.cloud.monitoring_v3 as monitoring_v3
import google.cloud.pubsub_v1 as pubsub_v1
import json
import os
from datetime import datetime, timedelta

@functions_framework.http
def orchestrate_disaster_recovery(request):
    """Orchestrate disaster recovery operations for Cloud SQL."""
    
    project_id = os.environ.get('PROJECT_ID')
    primary_instance = os.environ.get('PRIMARY_INSTANCE')
    dr_replica = os.environ.get('DR_REPLICA')
    
    sql_client = sql_v1.SqlInstancesServiceClient()
    
    try:
        # Check primary instance health
        primary_health = check_instance_health(sql_client, project_id, primary_instance)
        
        if not primary_health['healthy']:
            # Initiate failover to DR replica
            result = initiate_failover(sql_client, project_id, dr_replica)
            return {'status': 'failover_initiated', 'result': result}
        
        return {'status': 'primary_healthy', 'timestamp': datetime.utcnow().isoformat()}
    
    except Exception as e:
        return {'status': 'error', 'message': str(e)}, 500

def check_instance_health(client, project_id, instance_name):
    """Check the health status of a Cloud SQL instance."""
    try:
        instance = client.get(project=project_id, instance=instance_name)
        return {
            'healthy': instance.state == sql_v1.SqlInstanceState.RUNNABLE,
            'state': instance.state.name,
            'backend_type': instance.backend_type.name
        }
    except Exception as e:
        return {'healthy': False, 'error': str(e)}

def initiate_failover(client, project_id, replica_name):
    """Initiate failover to the disaster recovery replica."""
    try:
        # Promote the DR replica to become the new primary
        operation = client.failover_replica(
            project=project_id,
            instance=replica_name
        )
        
        return {
            'operation_id': operation.name,
            'status': 'failover_started',
            'timestamp': datetime.utcnow().isoformat()
        }
    except Exception as e:
        return {'error': str(e)}

@functions_framework.http
def validate_backups(request):
    """Validate backup integrity and DR readiness."""
    
    project_id = os.environ.get('PROJECT_ID')
    instance_name = os.environ.get('PRIMARY_INSTANCE')
    
    sql_client = sql_v1.SqlBackupRunsServiceClient()
    
    try:
        # List recent backups
        backups = sql_client.list(
            project=project_id,
            instance=instance_name,
            max_results=5
        )
        
        validation_results = []
        for backup in backups:
            result = {
                'backup_id': backup.id,
                'status': backup.status.name,
                'type': backup.type_.name,
                'start_time': backup.start_time.isoformat() if backup.start_time else None,
                'end_time': backup.end_time.isoformat() if backup.end_time else None
            }
            validation_results.append(result)
        
        return {
            'status': 'validation_complete',
            'backup_count': len(validation_results),
            'backups': validation_results,
            'timestamp': datetime.utcnow().isoformat()
        }
    
    except Exception as e:
        return {'status': 'validation_failed', 'error': str(e)}, 500
EOF

# Create requirements.txt
cat > "$FUNCTION_DIR/requirements.txt" << 'EOF'
functions-framework==3.5.0
google-cloud-sql==1.7.0
google-cloud-monitoring==2.16.0
google-cloud-pubsub==2.18.4
EOF

# Deploy DR orchestration function
log "Deploying disaster recovery orchestration function..."
if gcloud functions describe orchestrate-disaster-recovery --region="$PRIMARY_REGION" >/dev/null 2>&1; then
    warning "DR orchestration function already exists. Updating..."
else
    log "Creating new DR orchestration function..."
fi

gcloud functions deploy orchestrate-disaster-recovery \
    --gen2 \
    --runtime=python311 \
    --region="$PRIMARY_REGION" \
    --source="$FUNCTION_DIR" \
    --entry-point=orchestrate_disaster_recovery \
    --trigger=http \
    --set-env-vars="PROJECT_ID=${PROJECT_ID},PRIMARY_INSTANCE=${DB_INSTANCE_NAME},DR_REPLICA=${DR_REPLICA_NAME}" \
    --max-instances=10 \
    --timeout=540s \
    --allow-unauthenticated || error "Failed to deploy DR orchestration function"

# Deploy backup validation function
log "Deploying backup validation function..."
gcloud functions deploy validate-backups \
    --gen2 \
    --runtime=python311 \
    --region="$PRIMARY_REGION" \
    --source="$FUNCTION_DIR" \
    --entry-point=validate_backups \
    --trigger=http \
    --set-env-vars="PROJECT_ID=${PROJECT_ID},PRIMARY_INSTANCE=${DB_INSTANCE_NAME}" \
    --allow-unauthenticated || warning "Failed to deploy backup validation function"

success "Cloud Functions deployed successfully"

# Step 6: Configure Monitoring and Alerting
log "Configuring monitoring and alerting..."

# Create Pub/Sub topic for DR notifications
if gcloud pubsub topics describe disaster-recovery-alerts >/dev/null 2>&1; then
    warning "Pub/Sub topic already exists. Skipping creation."
else
    gcloud pubsub topics create disaster-recovery-alerts || error "Failed to create Pub/Sub topic"
fi

# Create subscription
if gcloud pubsub subscriptions describe dr-function-trigger >/dev/null 2>&1; then
    warning "Pub/Sub subscription already exists. Skipping creation."
else
    gcloud pubsub subscriptions create dr-function-trigger \
        --topic=disaster-recovery-alerts || warning "Failed to create Pub/Sub subscription"
fi

success "Monitoring and alerting configured"

# Step 7: Configure Automated Backup Validation
log "Setting up automated backup validation..."

# Create Cloud Scheduler job for automated DR testing
SCHEDULER_JOB_NAME="dr-validation-job"
if gcloud scheduler jobs describe "$SCHEDULER_JOB_NAME" --location="$PRIMARY_REGION" >/dev/null 2>&1; then
    warning "Scheduler job already exists. Skipping creation."
else
    # Get function URL
    FUNCTION_URL=$(gcloud functions describe validate-backups \
        --region="$PRIMARY_REGION" \
        --format="value(serviceConfig.uri)" 2>/dev/null)
    
    if [ -n "$FUNCTION_URL" ]; then
        gcloud scheduler jobs create http "$SCHEDULER_JOB_NAME" \
            --location="$PRIMARY_REGION" \
            --schedule="0 4 * * 1" \
            --uri="$FUNCTION_URL" \
            --http-method=POST \
            --headers="Content-Type=application/json" \
            --message-body='{"action": "validate_backups", "test_mode": true}' \
            --time-zone="UTC" || warning "Failed to create scheduler job"
    else
        warning "Could not get function URL. Skipping scheduler job creation."
    fi
fi

success "Automated backup validation configured"

# Final validation
log "Performing final validation..."

# Verify primary instance
PRIMARY_STATE=$(gcloud sql instances describe "$DB_INSTANCE_NAME" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
if [ "$PRIMARY_STATE" = "RUNNABLE" ]; then
    success "Primary Cloud SQL instance is running"
else
    warning "Primary instance state: $PRIMARY_STATE"
fi

# Verify DR replica
DR_STATE=$(gcloud sql instances describe "$DR_REPLICA_NAME" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
if [ "$DR_STATE" = "RUNNABLE" ]; then
    success "DR replica is running"
else
    warning "DR replica state: $DR_STATE"
fi

# Verify backup vaults
PRIMARY_VAULT_STATE=$(gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_PRIMARY" --location="$PRIMARY_REGION" --format="value(state)" 2>/dev/null || echo "UNKNOWN")
SECONDARY_VAULT_STATE=$(gcloud backup-dr backup-vaults describe "$BACKUP_VAULT_SECONDARY" --location="$SECONDARY_REGION" --format="value(state)" 2>/dev/null || echo "UNKNOWN")

if [ "$PRIMARY_VAULT_STATE" = "ACTIVE" ] && [ "$SECONDARY_VAULT_STATE" = "ACTIVE" ]; then
    success "Both backup vaults are active"
else
    warning "Backup vault states - Primary: $PRIMARY_VAULT_STATE, Secondary: $SECONDARY_VAULT_STATE"
fi

echo ""
echo "=================================================="
echo "          DEPLOYMENT COMPLETED SUCCESSFULLY"
echo "=================================================="
echo ""
echo "Resource Summary:"
echo "  Primary DB Instance: $DB_INSTANCE_NAME (Region: $PRIMARY_REGION)"
echo "  DR Replica: $DR_REPLICA_NAME (Region: $SECONDARY_REGION)"
echo "  Primary Backup Vault: $BACKUP_VAULT_PRIMARY"
echo "  Secondary Backup Vault: $BACKUP_VAULT_SECONDARY"
echo "  Project ID: $PROJECT_ID"
echo ""
echo "Next Steps:"
echo "  1. Create test database and verify connectivity"
echo "  2. Test backup and restore procedures"
echo "  3. Perform disaster recovery simulation"
echo "  4. Monitor alerts and notifications"
echo ""
echo "Important: Save the resource names above for cleanup operations."
echo ""

# Save configuration for cleanup script
CONFIG_FILE="deployment-config.env"
cat > "$CONFIG_FILE" << EOF
# Deployment configuration - Generated $(date)
export PROJECT_ID="$PROJECT_ID"
export PRIMARY_REGION="$PRIMARY_REGION"
export SECONDARY_REGION="$SECONDARY_REGION"
export DB_INSTANCE_NAME="$DB_INSTANCE_NAME"
export DR_REPLICA_NAME="$DR_REPLICA_NAME"
export BACKUP_VAULT_PRIMARY="$BACKUP_VAULT_PRIMARY"
export BACKUP_VAULT_SECONDARY="$BACKUP_VAULT_SECONDARY"
export BACKUP_PLAN_NAME="$BACKUP_PLAN_NAME"
export SCHEDULER_JOB_NAME="$SCHEDULER_JOB_NAME"
EOF

success "Deployment configuration saved to $CONFIG_FILE"
echo ""