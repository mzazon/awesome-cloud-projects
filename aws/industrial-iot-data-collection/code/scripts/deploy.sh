#!/bin/bash

# AWS IoT SiteWise Industrial Data Collection - Deployment Script
# This script deploys the complete infrastructure for industrial IoT data collection
# using AWS IoT SiteWise, Timestream, and CloudWatch monitoring

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version | cut -d/ -f2 | cut -d' ' -f1)
    info "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check if user is authenticated
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or you don't have valid credentials."
        exit 1
    fi
    
    # Check required permissions
    log "Verifying AWS permissions..."
    
    # Test IoT SiteWise permissions
    if ! aws iotsitewise describe-default-encryption-configuration --region ${AWS_REGION} &> /dev/null; then
        error "Missing permissions for IoT SiteWise or service not available in region ${AWS_REGION}"
        exit 1
    fi
    
    # Test Timestream permissions
    if ! aws timestream-write describe-endpoints --region ${AWS_REGION} &> /dev/null; then
        error "Missing permissions for Timestream or service not available in region ${AWS_REGION}"
        exit 1
    fi
    
    # Test CloudWatch permissions
    if ! aws cloudwatch list-metrics --region ${AWS_REGION} &> /dev/null; then
        error "Missing permissions for CloudWatch"
        exit 1
    fi
    
    log "Prerequisites check completed successfully"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    if [ -z "$RANDOM_SUFFIX" ]; then
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    fi
    
    export SITEWISE_PROJECT_NAME="manufacturing-plant-${RANDOM_SUFFIX}"
    export TIMESTREAM_DB_NAME="industrial-data-${RANDOM_SUFFIX}"
    export GATEWAY_NAME="manufacturing-gateway-${RANDOM_SUFFIX}"
    export ALARM_NAME="ProductionLine-A-HighTemperature-${RANDOM_SUFFIX}"
    
    # Create state file for cleanup
    STATE_FILE="/tmp/sitewise-deployment-${RANDOM_SUFFIX}.state"
    echo "AWS_REGION=${AWS_REGION}" > "$STATE_FILE"
    echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}" >> "$STATE_FILE"
    echo "SITEWISE_PROJECT_NAME=${SITEWISE_PROJECT_NAME}" >> "$STATE_FILE"
    echo "TIMESTREAM_DB_NAME=${TIMESTREAM_DB_NAME}" >> "$STATE_FILE"
    echo "GATEWAY_NAME=${GATEWAY_NAME}" >> "$STATE_FILE"
    echo "ALARM_NAME=${ALARM_NAME}" >> "$STATE_FILE"
    echo "RANDOM_SUFFIX=${RANDOM_SUFFIX}" >> "$STATE_FILE"
    
    info "Environment configured:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "  Project Name: ${SITEWISE_PROJECT_NAME}"
    info "  Timestream DB: ${TIMESTREAM_DB_NAME}"
    info "  State file: ${STATE_FILE}"
    
    log "Environment setup completed"
}

# Create Industrial Asset Model
create_asset_model() {
    log "Creating Industrial Asset Model..."
    
    # Check if asset model already exists
    if [ -f "/tmp/asset-model-${RANDOM_SUFFIX}.id" ]; then
        ASSET_MODEL_ID=$(cat "/tmp/asset-model-${RANDOM_SUFFIX}.id")
        info "Asset model already exists with ID: ${ASSET_MODEL_ID}"
        return 0
    fi
    
    # Create asset model for manufacturing equipment
    ASSET_MODEL_ID=$(aws iotsitewise create-asset-model \
        --region ${AWS_REGION} \
        --asset-model-name "ProductionLineEquipment-${RANDOM_SUFFIX}" \
        --asset-model-description "Model for production line machinery - ${SITEWISE_PROJECT_NAME}" \
        --asset-model-properties '[
            {
                "name": "Temperature",
                "dataType": "DOUBLE",
                "unit": "Celsius",
                "type": {
                    "measurement": {}
                }
            },
            {
                "name": "Pressure",
                "dataType": "DOUBLE", 
                "unit": "PSI",
                "type": {
                    "measurement": {}
                }
            },
            {
                "name": "OperationalEfficiency",
                "dataType": "DOUBLE",
                "unit": "Percent",
                "type": {
                    "transform": {
                        "expression": "temp / 100 * pressure / 50",
                        "variables": [
                            {
                                "name": "temp",
                                "value": {
                                    "propertyId": "Temperature"
                                }
                            },
                            {
                                "name": "pressure", 
                                "value": {
                                    "propertyId": "Pressure"
                                }
                            }
                        ]
                    }
                }
            }
        ]' \
        --tags "Environment=Development,Project=${SITEWISE_PROJECT_NAME}" \
        --query 'assetModelId' --output text)
    
    if [ $? -eq 0 ] && [ -n "$ASSET_MODEL_ID" ]; then
        echo "$ASSET_MODEL_ID" > "/tmp/asset-model-${RANDOM_SUFFIX}.id"
        echo "ASSET_MODEL_ID=${ASSET_MODEL_ID}" >> "$STATE_FILE"
        log "Asset model created successfully: ${ASSET_MODEL_ID}"
        
        # Wait for asset model to be active
        info "Waiting for asset model to become active..."
        aws iotsitewise wait asset-model-active --asset-model-id ${ASSET_MODEL_ID} --region ${AWS_REGION}
        log "Asset model is now active"
    else
        error "Failed to create asset model"
        exit 1
    fi
}

# Create Physical Asset Instance
create_asset_instance() {
    log "Creating Physical Asset Instance..."
    
    # Check if asset already exists
    if [ -f "/tmp/asset-${RANDOM_SUFFIX}.id" ]; then
        ASSET_ID=$(cat "/tmp/asset-${RANDOM_SUFFIX}.id")
        info "Asset instance already exists with ID: ${ASSET_ID}"
        return 0
    fi
    
    # Get asset model ID
    ASSET_MODEL_ID=$(cat "/tmp/asset-model-${RANDOM_SUFFIX}.id")
    
    # Create asset instance representing actual equipment
    ASSET_ID=$(aws iotsitewise create-asset \
        --region ${AWS_REGION} \
        --asset-name "ProductionLine-A-Pump-001-${RANDOM_SUFFIX}" \
        --asset-model-id ${ASSET_MODEL_ID} \
        --tags "Environment=Development,Project=${SITEWISE_PROJECT_NAME}" \
        --query 'assetId' --output text)
    
    if [ $? -eq 0 ] && [ -n "$ASSET_ID" ]; then
        echo "$ASSET_ID" > "/tmp/asset-${RANDOM_SUFFIX}.id"
        echo "ASSET_ID=${ASSET_ID}" >> "$STATE_FILE"
        log "Asset instance created successfully: ${ASSET_ID}"
        
        # Wait for asset to be active
        info "Waiting for asset to become active..."
        aws iotsitewise wait asset-active --asset-id ${ASSET_ID} --region ${AWS_REGION}
        log "Asset instance is now active"
    else
        error "Failed to create asset instance"
        exit 1
    fi
}

# Configure Timestream Database
configure_timestream() {
    log "Configuring Timestream Database..."
    
    # Check if database already exists
    if aws timestream-write describe-database --database-name ${TIMESTREAM_DB_NAME} --region ${AWS_REGION} &> /dev/null; then
        info "Timestream database already exists: ${TIMESTREAM_DB_NAME}"
    else
        # Create Timestream database for industrial data
        aws timestream-write create-database \
            --region ${AWS_REGION} \
            --database-name ${TIMESTREAM_DB_NAME} \
            --tags "Environment=Development,Project=${SITEWISE_PROJECT_NAME}"
        
        if [ $? -eq 0 ]; then
            log "Timestream database created successfully: ${TIMESTREAM_DB_NAME}"
        else
            error "Failed to create Timestream database"
            exit 1
        fi
    fi
    
    # Check if table already exists
    if aws timestream-write describe-table --database-name ${TIMESTREAM_DB_NAME} --table-name "equipment-metrics" --region ${AWS_REGION} &> /dev/null; then
        info "Timestream table already exists: equipment-metrics"
    else
        # Create table for SiteWise data
        aws timestream-write create-table \
            --region ${AWS_REGION} \
            --database-name ${TIMESTREAM_DB_NAME} \
            --table-name "equipment-metrics" \
            --retention-properties '{
                "MemoryStoreRetentionPeriodInHours": 24,
                "MagneticStoreRetentionPeriodInDays": 365
            }' \
            --tags "Environment=Development,Project=${SITEWISE_PROJECT_NAME}"
        
        if [ $? -eq 0 ]; then
            log "Timestream table created successfully: equipment-metrics"
        else
            error "Failed to create Timestream table"
            exit 1
        fi
    fi
    
    log "Timestream configuration completed"
}

# Configure CloudWatch Monitoring
configure_monitoring() {
    log "Configuring CloudWatch Monitoring..."
    
    # Check if alarm already exists
    if aws cloudwatch describe-alarms --alarm-names ${ALARM_NAME} --region ${AWS_REGION} --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "${ALARM_NAME}"; then
        info "CloudWatch alarm already exists: ${ALARM_NAME}"
    else
        # Create CloudWatch alarm for temperature threshold
        aws cloudwatch put-metric-alarm \
            --region ${AWS_REGION} \
            --alarm-name ${ALARM_NAME} \
            --alarm-description "Alert when equipment temperature exceeds threshold - ${SITEWISE_PROJECT_NAME}" \
            --metric-name "Temperature" \
            --namespace "AWS/IoTSiteWise" \
            --statistic "Average" \
            --period 300 \
            --threshold 80.0 \
            --comparison-operator "GreaterThanThreshold" \
            --evaluation-periods 2 \
            --treat-missing-data "notBreaching" \
            --tags "Key=Environment,Value=Development" "Key=Project,Value=${SITEWISE_PROJECT_NAME}"
        
        if [ $? -eq 0 ]; then
            log "CloudWatch alarm created successfully: ${ALARM_NAME}"
        else
            warn "Failed to create CloudWatch alarm (may need SNS topic setup)"
        fi
    fi
    
    # Create custom metric for operational efficiency tracking
    aws cloudwatch put-metric-data \
        --region ${AWS_REGION} \
        --namespace "Manufacturing/Efficiency" \
        --metric-data '[
            {
                "MetricName": "OperationalEfficiency",
                "Value": 85.5,
                "Unit": "Percent",
                "Dimensions": [
                    {
                        "Name": "Project",
                        "Value": "'${SITEWISE_PROJECT_NAME}'"
                    }
                ]
            }
        ]'
    
    if [ $? -eq 0 ]; then
        log "Custom metrics published successfully"
    else
        warn "Failed to publish custom metrics"
    fi
    
    log "CloudWatch monitoring configuration completed"
}

# Ingest Sample Data
ingest_sample_data() {
    log "Ingesting sample industrial data..."
    
    # Get asset ID
    ASSET_ID=$(cat "/tmp/asset-${RANDOM_SUFFIX}.id")
    
    # Get property IDs for measurements
    TEMP_PROPERTY_ID=$(aws iotsitewise describe-asset \
        --region ${AWS_REGION} \
        --asset-id ${ASSET_ID} \
        --query 'assetProperties[?name==`Temperature`].id' \
        --output text)
    
    PRESSURE_PROPERTY_ID=$(aws iotsitewise describe-asset \
        --region ${AWS_REGION} \
        --asset-id ${ASSET_ID} \
        --query 'assetProperties[?name==`Pressure`].id' \
        --output text)
    
    if [ -n "$TEMP_PROPERTY_ID" ] && [ -n "$PRESSURE_PROPERTY_ID" ]; then
        echo "TEMP_PROPERTY_ID=${TEMP_PROPERTY_ID}" >> "$STATE_FILE"
        echo "PRESSURE_PROPERTY_ID=${PRESSURE_PROPERTY_ID}" >> "$STATE_FILE"
        
        # Simulate batch data ingestion
        TIMESTAMP=$(date +%s)
        aws iotsitewise batch-put-asset-property-value \
            --region ${AWS_REGION} \
            --entries '[
                {
                    "entryId": "temp-reading-'${TIMESTAMP}'",
                    "assetId": "'${ASSET_ID}'",
                    "propertyId": "'${TEMP_PROPERTY_ID}'",
                    "propertyValues": [
                        {
                            "value": {
                                "doubleValue": 75.5
                            },
                            "timestamp": {
                                "timeInSeconds": '${TIMESTAMP}'
                            }
                        }
                    ]
                },
                {
                    "entryId": "pressure-reading-'${TIMESTAMP}'", 
                    "assetId": "'${ASSET_ID}'",
                    "propertyId": "'${PRESSURE_PROPERTY_ID}'",
                    "propertyValues": [
                        {
                            "value": {
                                "doubleValue": 45.2
                            },
                            "timestamp": {
                                "timeInSeconds": '${TIMESTAMP}'
                            }
                        }
                    ]
                }
            ]'
        
        if [ $? -eq 0 ]; then
            log "Sample data ingested successfully"
        else
            warn "Failed to ingest sample data"
        fi
    else
        warn "Could not retrieve property IDs for data ingestion"
    fi
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check asset model status
    ASSET_MODEL_ID=$(cat "/tmp/asset-model-${RANDOM_SUFFIX}.id")
    MODEL_STATUS=$(aws iotsitewise describe-asset-model \
        --region ${AWS_REGION} \
        --asset-model-id ${ASSET_MODEL_ID} \
        --query 'assetModelStatus.state' \
        --output text)
    
    if [ "$MODEL_STATUS" = "ACTIVE" ]; then
        log "✅ Asset model is active"
    else
        warn "Asset model status: $MODEL_STATUS"
    fi
    
    # Check asset instance status
    ASSET_ID=$(cat "/tmp/asset-${RANDOM_SUFFIX}.id")
    ASSET_STATUS=$(aws iotsitewise describe-asset \
        --region ${AWS_REGION} \
        --asset-id ${ASSET_ID} \
        --query 'assetStatus.state' \
        --output text)
    
    if [ "$ASSET_STATUS" = "ACTIVE" ]; then
        log "✅ Asset instance is active"
    else
        warn "Asset instance status: $ASSET_STATUS"
    fi
    
    # Check Timestream database
    if aws timestream-write describe-database --database-name ${TIMESTREAM_DB_NAME} --region ${AWS_REGION} &> /dev/null; then
        log "✅ Timestream database is accessible"
    else
        warn "Timestream database validation failed"
    fi
    
    # Check CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names ${ALARM_NAME} --region ${AWS_REGION} --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "${ALARM_NAME}"; then
        log "✅ CloudWatch alarm is configured"
    else
        warn "CloudWatch alarm validation failed"
    fi
    
    log "Deployment validation completed"
}

# Print deployment summary
print_summary() {
    log "Deployment Summary:"
    info "===================="
    info "AWS Region: ${AWS_REGION}"
    info "Project Name: ${SITEWISE_PROJECT_NAME}"
    info "Asset Model ID: $(cat /tmp/asset-model-${RANDOM_SUFFIX}.id 2>/dev/null || echo 'Not found')"
    info "Asset ID: $(cat /tmp/asset-${RANDOM_SUFFIX}.id 2>/dev/null || echo 'Not found')"
    info "Timestream Database: ${TIMESTREAM_DB_NAME}"
    info "CloudWatch Alarm: ${ALARM_NAME}"
    info "State File: ${STATE_FILE}"
    info "===================="
    info ""
    info "Next Steps:"
    info "1. Connect your industrial equipment to the IoT SiteWise gateway"
    info "2. Configure data streams from your PLCs/SCADA systems"
    info "3. Set up additional monitoring and alerting as needed"
    info "4. Use the destroy.sh script to clean up resources when done"
    info ""
    info "Useful Commands:"
    info "- View asset data: aws iotsitewise get-asset-property-value --asset-id $(cat /tmp/asset-${RANDOM_SUFFIX}.id) --property-id <property-id>"
    info "- Query Timestream: aws timestream-query query --query-string \"SELECT * FROM \\\"${TIMESTREAM_DB_NAME}\\\".\\\"equipment-metrics\\\" LIMIT 10\""
    info "- Check alarms: aws cloudwatch describe-alarms --alarm-names ${ALARM_NAME}"
}

# Main execution
main() {
    log "Starting AWS IoT SiteWise Industrial Data Collection deployment..."
    
    check_prerequisites
    setup_environment
    create_asset_model
    create_asset_instance
    configure_timestream
    configure_monitoring
    ingest_sample_data
    validate_deployment
    print_summary
    
    log "Deployment completed successfully! 🎉"
    info "State file saved to: ${STATE_FILE}"
    info "Use this file with destroy.sh to clean up resources"
}

# Handle script interruption
cleanup_on_exit() {
    warn "Script interrupted. Partial deployment may exist."
    warn "Use destroy.sh to clean up any created resources."
    exit 1
}

trap cleanup_on_exit INT TERM

# Run main function
main "$@"