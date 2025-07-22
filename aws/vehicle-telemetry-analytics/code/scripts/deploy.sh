#!/bin/bash

# AWS IoT FleetWise and Timestream Vehicle Telemetry Analytics Deployment Script
# This script deploys the complete infrastructure for real-time vehicle telemetry analytics

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
    log_error "Deployment failed. Cleaning up resources created so far..."
    if [[ -f "./destroy.sh" ]]; then
        chmod +x ./destroy.sh
        ./destroy.sh --force
    fi
    exit 1
}

trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        log_error "AWS CLI v2 is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    # Check if jq is available (optional but helpful)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some output formatting may be limited."
    fi
    
    log_success "Prerequisites check completed"
}

# Validate region support
validate_region() {
    local region=$1
    
    # IoT FleetWise is only available in specific regions
    if [[ "$region" != "us-east-1" && "$region" != "eu-central-1" ]]; then
        log_error "AWS IoT FleetWise is only available in us-east-1 and eu-central-1 regions."
        log_error "Current region: $region"
        exit 1
    fi
    
    log_success "Region $region is supported for IoT FleetWise"
}

# Parse command line arguments
FORCE_DEPLOY=false
DRY_RUN=false
CUSTOM_REGION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE_DEPLOY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --force     Force deployment even if resources exist"
            echo "  --dry-run   Show what would be deployed without actually deploying"
            echo "  --region    Specify AWS region (must be us-east-1 or eu-central-1)"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Main deployment function
main() {
    log_info "Starting AWS IoT FleetWise and Timestream deployment..."
    
    check_prerequisites
    
    # Set environment variables
    if [[ -n "$CUSTOM_REGION" ]]; then
        export AWS_REGION="$CUSTOM_REGION"
    else
        export AWS_REGION="${AWS_REGION:-us-east-1}"
    fi
    
    validate_region "$AWS_REGION"
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export FLEET_NAME="vehicle-fleet-${RANDOM_SUFFIX}"
    export TIMESTREAM_DB="telemetry_db_${RANDOM_SUFFIX}"
    export TIMESTREAM_TABLE="vehicle_metrics"
    export S3_BUCKET="fleetwise-data-${RANDOM_SUFFIX}"
    export VEHICLE_NAME="vehicle-001-${RANDOM_SUFFIX}"
    export CAMPAIGN_NAME="TelemetryCampaign-${RANDOM_SUFFIX}"
    export IAM_ROLE_NAME="FleetWiseServiceRole-${RANDOM_SUFFIX}"
    export GRAFANA_WORKSPACE_NAME="FleetTelemetry-${RANDOM_SUFFIX}"
    
    # Save configuration to file for cleanup script
    cat > deployment_config.env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
FLEET_NAME=$FLEET_NAME
TIMESTREAM_DB=$TIMESTREAM_DB
TIMESTREAM_TABLE=$TIMESTREAM_TABLE
S3_BUCKET=$S3_BUCKET
VEHICLE_NAME=$VEHICLE_NAME
CAMPAIGN_NAME=$CAMPAIGN_NAME
IAM_ROLE_NAME=$IAM_ROLE_NAME
GRAFANA_WORKSPACE_NAME=$GRAFANA_WORKSPACE_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    log_info "Configuration saved to deployment_config.env"
    log_info "Deployment ID: $RANDOM_SUFFIX"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE - Would deploy the following resources:"
        echo "  - S3 Bucket: $S3_BUCKET"
        echo "  - Timestream Database: $TIMESTREAM_DB"
        echo "  - Timestream Table: $TIMESTREAM_TABLE"
        echo "  - IoT FleetWise Fleet: $FLEET_NAME"
        echo "  - Vehicle: $VEHICLE_NAME"
        echo "  - IAM Role: $IAM_ROLE_NAME"
        echo "  - Grafana Workspace: $GRAFANA_WORKSPACE_NAME"
        echo "  - Campaign: $CAMPAIGN_NAME"
        return 0
    fi
    
    # Step 1: Create S3 bucket
    log_info "Step 1: Creating S3 bucket for data archival..."
    if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            log_error "S3 bucket $S3_BUCKET already exists. Use --force to proceed."
            exit 1
        fi
        log_warning "S3 bucket already exists, continuing..."
    else
        aws s3 mb s3://${S3_BUCKET} --region ${AWS_REGION}
        aws s3api put-bucket-versioning \
            --bucket ${S3_BUCKET} \
            --versioning-configuration Status=Enabled
        log_success "S3 bucket created and versioning enabled"
    fi
    
    # Step 2: Create IAM role for FleetWise
    log_info "Step 2: Creating IAM role for FleetWise..."
    cat > fleetwise-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "iotfleetwise.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            log_error "IAM role $IAM_ROLE_NAME already exists. Use --force to proceed."
            exit 1
        fi
        log_warning "IAM role already exists, continuing..."
        FLEETWISE_ROLE_ARN=$(aws iam get-role --role-name "$IAM_ROLE_NAME" --query 'Role.Arn' --output text)
    else
        FLEETWISE_ROLE_ARN=$(aws iam create-role \
            --role-name "$IAM_ROLE_NAME" \
            --assume-role-policy-document file://fleetwise-trust-policy.json \
            --query 'Role.Arn' --output text)
        log_success "IAM role created"
    fi
    
    # Step 3: Create Timestream database and table
    log_info "Step 3: Creating Timestream database and table..."
    if aws timestream-write describe-database --database-name "$TIMESTREAM_DB" --region "$AWS_REGION" &>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            log_error "Timestream database $TIMESTREAM_DB already exists. Use --force to proceed."
            exit 1
        fi
        log_warning "Timestream database already exists, continuing..."
    else
        aws timestream-write create-database \
            --database-name ${TIMESTREAM_DB} \
            --region ${AWS_REGION}
        log_success "Timestream database created"
    fi
    
    if aws timestream-write describe-table --database-name "$TIMESTREAM_DB" --table-name "$TIMESTREAM_TABLE" --region "$AWS_REGION" &>/dev/null; then
        log_warning "Timestream table already exists, continuing..."
    else
        aws timestream-write create-table \
            --database-name ${TIMESTREAM_DB} \
            --table-name ${TIMESTREAM_TABLE} \
            --retention-properties \
              MemoryStoreRetentionPeriodInHours=24,MagneticStoreRetentionPeriodInDays=30 \
            --region ${AWS_REGION}
        log_success "Timestream table created with retention policies"
    fi
    
    # Step 4: Create signal catalog
    log_info "Step 4: Creating signal catalog..."
    cat > signal-catalog.json << 'EOF'
{
  "name": "VehicleSignalCatalog",
  "description": "Standard vehicle telemetry signals",
  "nodes": [
    {
      "branch": {
        "fullyQualifiedName": "Vehicle"
      }
    },
    {
      "branch": {
        "fullyQualifiedName": "Vehicle.Engine"
      }
    },
    {
      "sensor": {
        "fullyQualifiedName": "Vehicle.Engine.RPM",
        "dataType": "DOUBLE",
        "unit": "rpm",
        "min": 0,
        "max": 8000
      }
    },
    {
      "sensor": {
        "fullyQualifiedName": "Vehicle.Speed",
        "dataType": "DOUBLE",
        "unit": "km/h",
        "min": 0,
        "max": 300
      }
    },
    {
      "sensor": {
        "fullyQualifiedName": "Vehicle.Engine.Temperature",
        "dataType": "DOUBLE",
        "unit": "Celsius",
        "min": -40,
        "max": 200
      }
    },
    {
      "sensor": {
        "fullyQualifiedName": "Vehicle.FuelLevel",
        "dataType": "DOUBLE",
        "unit": "Percentage",
        "min": 0,
        "max": 100
      }
    }
  ]
}
EOF
    
    if aws iotfleetwise get-signal-catalog --name "VehicleSignalCatalog" &>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            log_error "Signal catalog already exists. Use --force to proceed."
            exit 1
        fi
        log_warning "Signal catalog already exists, continuing..."
        CATALOG_ARN=$(aws iotfleetwise get-signal-catalog --name "VehicleSignalCatalog" --query 'arn' --output text)
    else
        CATALOG_ARN=$(aws iotfleetwise create-signal-catalog \
            --cli-input-json file://signal-catalog.json \
            --query 'arn' --output text)
        log_success "Signal catalog created"
    fi
    
    # Step 5: Create model manifest
    log_info "Step 5: Creating vehicle model manifest..."
    cat > model-manifest.json << EOF
{
  "name": "StandardVehicleModel",
  "description": "Model for standard fleet vehicles",
  "signalCatalogArn": "${CATALOG_ARN}",
  "nodes": [
    "Vehicle.Engine.RPM",
    "Vehicle.Speed", 
    "Vehicle.Engine.Temperature",
    "Vehicle.FuelLevel"
  ]
}
EOF
    
    if aws iotfleetwise get-model-manifest --name "StandardVehicleModel" &>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            log_error "Model manifest already exists. Use --force to proceed."
            exit 1
        fi
        log_warning "Model manifest already exists, continuing..."
        MODEL_ARN=$(aws iotfleetwise get-model-manifest --name "StandardVehicleModel" --query 'arn' --output text)
    else
        MODEL_ARN=$(aws iotfleetwise create-model-manifest \
            --cli-input-json file://model-manifest.json \
            --query 'arn' --output text)
        
        aws iotfleetwise update-model-manifest \
            --name "StandardVehicleModel" \
            --status "ACTIVE"
        log_success "Vehicle model created and activated"
    fi
    
    # Step 6: Create decoder manifest
    log_info "Step 6: Creating decoder manifest..."
    cat > decoder-manifest.json << EOF
{
  "name": "StandardDecoder",
  "description": "Decoder for standard vehicle signals",
  "modelManifestArn": "${MODEL_ARN}",
  "signalDecoders": [
    {
      "fullyQualifiedName": "Vehicle.Engine.RPM",
      "type": "CAN_SIGNAL",
      "canSignal": {
        "messageId": 419364097,
        "isBigEndian": false,
        "isSigned": false,
        "startBit": 24,
        "offset": 0.0,
        "factor": 0.25,
        "length": 16
      }
    },
    {
      "fullyQualifiedName": "Vehicle.Speed",
      "type": "CAN_SIGNAL",
      "canSignal": {
        "messageId": 419364352,
        "isBigEndian": false,
        "isSigned": false,
        "startBit": 0,
        "offset": 0.0,
        "factor": 0.01,
        "length": 16
      }
    }
  ]
}
EOF
    
    if aws iotfleetwise get-decoder-manifest --name "StandardDecoder" &>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            log_error "Decoder manifest already exists. Use --force to proceed."
            exit 1
        fi
        log_warning "Decoder manifest already exists, continuing..."
        DECODER_ARN=$(aws iotfleetwise get-decoder-manifest --name "StandardDecoder" --query 'arn' --output text)
    else
        DECODER_ARN=$(aws iotfleetwise create-decoder-manifest \
            --cli-input-json file://decoder-manifest.json \
            --query 'arn' --output text)
        
        aws iotfleetwise update-decoder-manifest \
            --name "StandardDecoder" \
            --status "ACTIVE"
        log_success "Decoder manifest created and activated"
    fi
    
    # Step 7: Create fleet and vehicle
    log_info "Step 7: Creating fleet and registering vehicle..."
    if aws iotfleetwise get-fleet --fleet-id "$FLEET_NAME" &>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            log_error "Fleet already exists. Use --force to proceed."
            exit 1
        fi
        log_warning "Fleet already exists, continuing..."
        FLEET_ARN=$(aws iotfleetwise get-fleet --fleet-id "$FLEET_NAME" --query 'arn' --output text)
    else
        FLEET_ARN=$(aws iotfleetwise create-fleet \
            --fleet-id ${FLEET_NAME} \
            --description "Production vehicle fleet" \
            --signal-catalog-arn ${CATALOG_ARN} \
            --query 'arn' --output text)
        log_success "Fleet created"
    fi
    
    # Create IoT thing for the vehicle
    if aws iot describe-thing --thing-name "$VEHICLE_NAME" --region "$AWS_REGION" &>/dev/null; then
        log_warning "IoT thing already exists, continuing..."
    else
        aws iot create-thing \
            --thing-name ${VEHICLE_NAME} \
            --region ${AWS_REGION}
        log_success "IoT thing created for vehicle"
    fi
    
    # Create vehicle in FleetWise
    if aws iotfleetwise get-vehicle --vehicle-name "$VEHICLE_NAME" &>/dev/null; then
        log_warning "Vehicle already exists in FleetWise, continuing..."
    else
        aws iotfleetwise create-vehicle \
            --vehicle-name ${VEHICLE_NAME} \
            --model-manifest-arn ${MODEL_ARN} \
            --decoder-manifest-arn ${DECODER_ARN}
        
        aws iotfleetwise associate-vehicle-fleet \
            --vehicle-name ${VEHICLE_NAME} \
            --fleet-id ${FLEET_NAME}
        log_success "Vehicle created and associated with fleet"
    fi
    
    # Step 8: Configure IAM permissions for Timestream
    log_info "Step 8: Configuring IAM permissions for Timestream..."
    cat > timestream-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "timestream:WriteRecords",
        "timestream:DescribeEndpoints"
      ],
      "Resource": [
        "arn:aws:timestream:${AWS_REGION}:${AWS_ACCOUNT_ID}:database/${TIMESTREAM_DB}/table/${TIMESTREAM_TABLE}"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "timestream:DescribeEndpoints",
      "Resource": "*"
    }
  ]
}
EOF
    
    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name TimestreamWritePolicy \
        --policy-document file://timestream-policy.json
    log_success "IAM permissions configured for Timestream"
    
    # Step 9: Create data collection campaign
    log_info "Step 9: Creating data collection campaign..."
    cat > campaign.json << EOF
{
  "name": "${CAMPAIGN_NAME}",
  "description": "Collect vehicle telemetry data",
  "signalCatalogArn": "${CATALOG_ARN}",
  "targetArn": "${FLEET_ARN}",
  "dataDestinationConfigs": [
    {
      "timestreamConfig": {
        "timestreamTableArn": "arn:aws:timestream:${AWS_REGION}:${AWS_ACCOUNT_ID}:database/${TIMESTREAM_DB}/table/${TIMESTREAM_TABLE}",
        "executionRoleArn": "${FLEETWISE_ROLE_ARN}"
      }
    }
  ],
  "collectionScheme": {
    "timeBasedCollectionScheme": {
      "periodMs": 10000
    }
  },
  "signalsToCollect": [
    {
      "name": "Vehicle.Engine.RPM"
    },
    {
      "name": "Vehicle.Speed"
    },
    {
      "name": "Vehicle.Engine.Temperature"
    },
    {
      "name": "Vehicle.FuelLevel"
    }
  ],
  "postTriggerCollectionDuration": 0,
  "diagnosticsMode": "OFF",
  "spoolingMode": "TO_DISK",
  "compression": "SNAPPY"
}
EOF
    
    if aws iotfleetwise get-campaign --name "$CAMPAIGN_NAME" &>/dev/null; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            log_error "Campaign already exists. Use --force to proceed."
            exit 1
        fi
        log_warning "Campaign already exists, continuing..."
        CAMPAIGN_ARN=$(aws iotfleetwise get-campaign --name "$CAMPAIGN_NAME" --query 'arn' --output text)
    else
        CAMPAIGN_ARN=$(aws iotfleetwise create-campaign \
            --cli-input-json file://campaign.json \
            --query 'arn' --output text)
        log_success "Data collection campaign created"
    fi
    
    # Step 10: Deploy and start campaign
    log_info "Step 10: Deploying and starting campaign..."
    aws iotfleetwise update-campaign \
        --name "$CAMPAIGN_NAME" \
        --action APPROVE
    
    sleep 5
    
    aws iotfleetwise update-campaign \
        --name "$CAMPAIGN_NAME" \
        --action RESUME
    
    CAMPAIGN_STATUS=$(aws iotfleetwise get-campaign \
        --name "$CAMPAIGN_NAME" \
        --query 'status' --output text)
    log_success "Campaign deployed and running: $CAMPAIGN_STATUS"
    
    # Step 11: Create Grafana workspace
    log_info "Step 11: Creating Amazon Managed Grafana workspace..."
    if aws grafana list-workspaces --query "workspaces[?name=='$GRAFANA_WORKSPACE_NAME'].id" --output text | grep -q .; then
        if [[ "$FORCE_DEPLOY" == "false" ]]; then
            log_error "Grafana workspace already exists. Use --force to proceed."
            exit 1
        fi
        log_warning "Grafana workspace already exists, continuing..."
        WORKSPACE_ID=$(aws grafana list-workspaces --query "workspaces[?name=='$GRAFANA_WORKSPACE_NAME'].id" --output text)
    else
        WORKSPACE_ID=$(aws grafana create-workspace \
            --workspace-name "$GRAFANA_WORKSPACE_NAME" \
            --workspace-description "Vehicle telemetry dashboards" \
            --account-access-type "CURRENT_ACCOUNT" \
            --authentication-providers "AWS_SSO" \
            --permission-type "SERVICE_MANAGED" \
            --workspace-data-sources "TIMESTREAM" \
            --query 'workspace.id' --output text)
        log_success "Grafana workspace created"
    fi
    
    # Wait for workspace to be active
    log_info "Waiting for Grafana workspace to become active..."
    aws grafana wait workspace-active --workspace-id ${WORKSPACE_ID}
    
    GRAFANA_ENDPOINT=$(aws grafana describe-workspace \
        --workspace-id ${WORKSPACE_ID} \
        --query 'workspace.endpoint' --output text)
    
    # Step 12: Configure Grafana service account
    log_info "Step 12: Configuring Grafana service account..."
    if aws grafana list-workspace-service-accounts --workspace-id "$WORKSPACE_ID" --query "serviceAccounts[?name=='terraform-sa'].id" --output text | grep -q .; then
        log_warning "Service account already exists, continuing..."
        SERVICE_ACCOUNT=$(aws grafana list-workspace-service-accounts --workspace-id "$WORKSPACE_ID" --query "serviceAccounts[?name=='terraform-sa'].id" --output text)
    else
        SERVICE_ACCOUNT=$(aws grafana create-workspace-service-account \
            --workspace-id ${WORKSPACE_ID} \
            --grafana-role "ADMIN" \
            --name "terraform-sa" \
            --query 'id' --output text)
        log_success "Grafana service account created"
    fi
    
    # Clean up temporary files
    rm -f fleetwise-trust-policy.json signal-catalog.json model-manifest.json \
        decoder-manifest.json campaign.json timestream-policy.json
    
    # Display deployment summary
    log_success "Deployment completed successfully!"
    echo ""
    echo "==================== DEPLOYMENT SUMMARY ===================="
    echo "Deployment ID: $RANDOM_SUFFIX"
    echo "AWS Region: $AWS_REGION"
    echo "S3 Bucket: $S3_BUCKET"
    echo "Timestream Database: $TIMESTREAM_DB"
    echo "Timestream Table: $TIMESTREAM_TABLE"
    echo "Fleet Name: $FLEET_NAME"
    echo "Vehicle Name: $VEHICLE_NAME"
    echo "Campaign Name: $CAMPAIGN_NAME"
    echo "IAM Role: $IAM_ROLE_NAME"
    echo "Grafana Workspace: $GRAFANA_WORKSPACE_NAME (ID: $WORKSPACE_ID)"
    echo "Grafana URL: https://$GRAFANA_ENDPOINT"
    echo ""
    echo "==================== NEXT STEPS ===================="
    echo "1. Configure AWS IoT FleetWise Edge Agent on your vehicles"
    echo "2. Set up Timestream data source in Grafana:"
    echo "   - Navigate to: https://$GRAFANA_ENDPOINT"
    echo "   - Go to Configuration > Data Sources"
    echo "   - Add Timestream data source"
    echo "   - Set Database: $TIMESTREAM_DB"
    echo "   - Set Table: $TIMESTREAM_TABLE"
    echo "3. Create dashboards for vehicle telemetry visualization"
    echo "4. Configure alerts for critical vehicle conditions"
    echo ""
    echo "Configuration saved to: deployment_config.env"
    echo "To clean up all resources, run: ./destroy.sh"
    echo "============================================================"
}

# Run main function
main "$@"