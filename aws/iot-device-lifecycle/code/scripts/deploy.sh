#!/bin/bash

# AWS IoT Device Management Deployment Script
# This script deploys the complete IoT Device Management solution
# Recipe: IoT Device Lifecycle Management

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warn "Running in DRY-RUN mode - no resources will be created"
fi

# Script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/iot-device-management-$$"

# Cleanup function for script exit
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
    rm -f device-policy.json firmware-update-job.json shadow-update.json
}

# Set trap for cleanup
trap cleanup EXIT

# Create temp directory
mkdir -p "$TEMP_DIR"

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check AWS region
    if [[ -z "${AWS_DEFAULT_REGION:-}" && -z "$(aws configure get region)" ]]; then
        error "AWS region not configured. Please set AWS_DEFAULT_REGION or run 'aws configure'."
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Environment setup function
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=${AWS_DEFAULT_REGION:-$(aws configure get region)}
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    if command -v aws &> /dev/null; then
        random_suffix=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    else
        random_suffix=$(date +%s | tail -c 6)
    fi
    
    export FLEET_NAME="fleet-${random_suffix}"
    export THING_TYPE_NAME="sensor-type-${random_suffix}"
    export THING_GROUP_NAME="sensor-group-${random_suffix}"
    export POLICY_NAME="device-policy-${random_suffix}"
    export RANDOM_SUFFIX="$random_suffix"
    
    # Store configuration for destroy script
    cat > "$TEMP_DIR/deployment-config.env" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
FLEET_NAME=$FLEET_NAME
THING_TYPE_NAME=$THING_TYPE_NAME
THING_GROUP_NAME=$THING_GROUP_NAME
POLICY_NAME=$POLICY_NAME
RANDOM_SUFFIX=$RANDOM_SUFFIX
EOF
    
    # Copy config to scripts directory for destroy script
    cp "$TEMP_DIR/deployment-config.env" "$SCRIPT_DIR/deployment-config.env"
    
    info "Environment configured with suffix: $random_suffix"
}

# Enable fleet indexing function
enable_fleet_indexing() {
    log "Enabling IoT fleet indexing..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would enable fleet indexing"
        return
    fi
    
    aws iot update-indexing-configuration \
        --thing-indexing-configuration \
        thingIndexingMode=REGISTRY_AND_SHADOW,thingConnectivityIndexingMode=STATUS \
        --thing-group-indexing-configuration \
        thingGroupIndexingMode=ON
    
    log "Fleet indexing enabled ✅"
}

# Create IoT Thing Type
create_thing_type() {
    log "Creating IoT Thing Type: $THING_TYPE_NAME..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create thing type: $THING_TYPE_NAME"
        return
    fi
    
    aws iot create-thing-type \
        --thing-type-name "$THING_TYPE_NAME" \
        --thing-type-properties \
        "thingTypeDescription=Temperature sensor device type,searchableAttributes=location,firmwareVersion,manufacturer"
    
    log "Thing type created ✅"
}

# Create Thing Group
create_thing_group() {
    log "Creating Thing Group: $THING_GROUP_NAME..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create thing group: $THING_GROUP_NAME"
        return
    fi
    
    aws iot create-thing-group \
        --thing-group-name "$THING_GROUP_NAME" \
        --thing-group-properties \
        "thingGroupDescription=Production temperature sensors,attributePayload={attributes={Environment=Production,Location=Factory1}}"
    
    log "Thing group created ✅"
}

# Create IoT Policy
create_iot_policy() {
    log "Creating IoT Policy: $POLICY_NAME..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create IoT policy: $POLICY_NAME"
        return
    fi
    
    # Create policy document
    cat > device-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:Connect",
        "iot:Publish",
        "iot:Subscribe",
        "iot:Receive"
      ],
      "Resource": [
        "arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}",
        "arn:aws:iot:*:*:topic/device/${iot:Connection.Thing.ThingName}/*",
        "arn:aws:iot:*:*:topicfilter/device/${iot:Connection.Thing.ThingName}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "iot:GetThingShadow",
        "iot:UpdateThingShadow",
        "iot:DeleteThingShadow"
      ],
      "Resource": [
        "arn:aws:iot:*:*:thing/${iot:Connection.Thing.ThingName}"
      ]
    }
  ]
}
EOF
    
    aws iot create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file://device-policy.json
    
    log "IoT policy created ✅"
}

# Provision IoT devices
provision_devices() {
    log "Provisioning IoT devices..."
    
    local devices=("temp-sensor-01" "temp-sensor-02" "temp-sensor-03" "temp-sensor-04")
    local locations=("Building-A" "Building-B" "Building-C" "Building-D")
    
    for i in "${!devices[@]}"; do
        local device_name="${devices[$i]}"
        local location="${locations[$i]}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY-RUN] Would provision device: $device_name in $location"
            continue
        fi
        
        # Create IoT thing
        aws iot create-thing \
            --thing-name "$device_name" \
            --thing-type-name "$THING_TYPE_NAME" \
            --attribute-payload \
            "{\"attributes\":{\"location\":\"$location\",\"firmwareVersion\":\"1.0.0\",\"manufacturer\":\"AcmeSensors\"}}"
        
        # Add thing to group
        aws iot add-thing-to-thing-group \
            --thing-name "$device_name" \
            --thing-group-name "$THING_GROUP_NAME"
        
        info "Provisioned device: $device_name in $location ✅"
    done
    
    # Store device list for cleanup
    printf '%s\n' "${devices[@]}" > "$TEMP_DIR/device-list.txt"
    cp "$TEMP_DIR/device-list.txt" "$SCRIPT_DIR/device-list.txt"
    
    log "Device provisioning completed ✅"
}

# Create and attach certificates
create_certificates() {
    log "Creating and attaching certificates..."
    
    local devices=("temp-sensor-01" "temp-sensor-02" "temp-sensor-03" "temp-sensor-04")
    local cert_ids=()
    
    for device in "${devices[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY-RUN] Would create certificate for device: $device"
            continue
        fi
        
        # Create certificate
        local cert_output
        cert_output=$(aws iot create-keys-and-certificate \
            --set-as-active \
            --query '{certificateArn:certificateArn,certificateId:certificateId}' \
            --output json)
        
        local cert_arn cert_id
        cert_arn=$(echo "$cert_output" | jq -r '.certificateArn')
        cert_id=$(echo "$cert_output" | jq -r '.certificateId')
        
        # Store certificate ID for cleanup
        cert_ids+=("$cert_id")
        
        # Attach policy to certificate
        aws iot attach-policy \
            --policy-name "$POLICY_NAME" \
            --target "$cert_arn"
        
        # Attach certificate to thing
        aws iot attach-thing-principal \
            --thing-name "$device" \
            --principal "$cert_arn"
        
        info "Certificate attached to device: $device ✅"
    done
    
    # Store certificate IDs for cleanup
    printf '%s\n' "${cert_ids[@]}" > "$TEMP_DIR/certificate-ids.txt"
    cp "$TEMP_DIR/certificate-ids.txt" "$SCRIPT_DIR/certificate-ids.txt"
    
    log "Certificate creation completed ✅"
}

# Create dynamic thing groups
create_dynamic_groups() {
    log "Creating dynamic thing groups..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create dynamic thing groups"
        return
    fi
    
    # Create dynamic group for devices with old firmware
    aws iot create-dynamic-thing-group \
        --thing-group-name "outdated-firmware-${RANDOM_SUFFIX}" \
        --query-string "attributes.firmwareVersion:1.0.0" \
        --thing-group-properties \
        "thingGroupDescription=Devices requiring firmware updates"
    
    # Create dynamic group for building A devices
    aws iot create-dynamic-thing-group \
        --thing-group-name "building-a-sensors-${RANDOM_SUFFIX}" \
        --query-string "attributes.location:Building-A" \
        --thing-group-properties \
        "thingGroupDescription=All sensors in Building A"
    
    log "Dynamic thing groups created ✅"
}

# Setup monitoring and logging
setup_monitoring() {
    log "Setting up fleet monitoring and logging..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would setup monitoring and logging"
        return
    fi
    
    # Set logging level for the thing group
    aws iot set-v2-logging-level \
        --log-target \
        "{\"targetType\":\"THING_GROUP\",\"targetName\":\"$THING_GROUP_NAME\"}" \
        --log-level INFO
    
    # Create CloudWatch log group
    aws logs create-log-group \
        --log-group-name "/aws/iot/device-management-${RANDOM_SUFFIX}" \
        --retention-in-days 30
    
    log "Monitoring and logging configured ✅"
}

# Create firmware update job
create_firmware_job() {
    log "Creating firmware update job..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create firmware update job"
        return
    fi
    
    # Create job document
    cat > firmware-update-job.json << 'EOF'
{
  "operation": "firmwareUpdate",
  "firmwareVersion": "1.1.0",
  "downloadUrl": "https://example-firmware-bucket.s3.amazonaws.com/firmware-v1.1.0.bin",
  "checksum": "abc123def456",
  "rebootRequired": true,
  "timeout": 300
}
EOF
    
    # Get thing group ARN
    local thing_group_arn
    thing_group_arn=$(aws iot describe-thing-group \
        --thing-group-name "$THING_GROUP_NAME" \
        --query thingGroupArn --output text)
    
    # Create continuous job
    aws iot create-job \
        --job-id "firmware-update-${RANDOM_SUFFIX}" \
        --targets "$thing_group_arn" \
        --document file://firmware-update-job.json \
        --description "Firmware update to version 1.1.0" \
        --target-selection CONTINUOUS \
        --job-executions-config \
        "maxConcurrentExecutions=5" \
        --timeout-config \
        "inProgressTimeoutInMinutes=30"
    
    log "Firmware update job created ✅"
}

# Update device shadow
update_device_shadow() {
    log "Updating device shadow..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would update device shadow"
        return
    fi
    
    # Create shadow document
    cat > shadow-update.json << 'EOF'
{
  "state": {
    "reported": {
      "temperature": 22.5,
      "humidity": 45.2,
      "batteryLevel": 85,
      "lastSeen": "2024-01-15T10:30:00Z",
      "firmwareVersion": "1.0.0"
    },
    "desired": {
      "reportingInterval": 60,
      "alertThreshold": 30.0
    }
  }
}
EOF
    
    # Update shadow for first device
    aws iot-data update-thing-shadow \
        --thing-name "temp-sensor-01" \
        --payload file://shadow-update.json \
        shadow-output.json
    
    log "Device shadow updated ✅"
}

# Create fleet metrics
create_fleet_metrics() {
    log "Creating fleet metrics..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would create fleet metrics"
        return
    fi
    
    # Create fleet metric for device connectivity
    aws iot put-fleet-metric \
        --metric-name "ConnectedDevices-${RANDOM_SUFFIX}" \
        --query-string "connectivity.connected:true" \
        --aggregation-type name=Statistics,values=count \
        --period 300 \
        --aggregation-field "connectivity.connected" \
        --description "Count of connected devices in fleet"
    
    # Create fleet metric for firmware versions
    aws iot put-fleet-metric \
        --metric-name "FirmwareVersions-${RANDOM_SUFFIX}" \
        --query-string "attributes.firmwareVersion:*" \
        --aggregation-type name=Statistics,values=count \
        --period 300 \
        --aggregation-field "attributes.firmwareVersion" \
        --description "Distribution of firmware versions"
    
    log "Fleet metrics created ✅"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY-RUN] Would validate deployment"
        return
    fi
    
    # Check thing group membership
    local device_count
    device_count=$(aws iot list-things-in-thing-group \
        --thing-group-name "$THING_GROUP_NAME" \
        --query 'things' --output text | wc -w)
    
    if [[ "$device_count" -eq 4 ]]; then
        log "Thing group validation passed: $device_count devices ✅"
    else
        warn "Thing group validation failed: Expected 4 devices, found $device_count"
    fi
    
    # Check dynamic groups
    local dynamic_count
    dynamic_count=$(aws iot list-things-in-thing-group \
        --thing-group-name "outdated-firmware-${RANDOM_SUFFIX}" \
        --query 'things' --output text | wc -w)
    
    if [[ "$dynamic_count" -eq 4 ]]; then
        log "Dynamic group validation passed: $dynamic_count devices ✅"
    else
        warn "Dynamic group validation failed: Expected 4 devices, found $dynamic_count"
    fi
    
    log "Deployment validation completed ✅"
}

# Main deployment function
main() {
    log "Starting AWS IoT Device Management deployment..."
    
    # Check prerequisites
    check_prerequisites
    
    # Setup environment
    setup_environment
    
    # Enable fleet indexing
    enable_fleet_indexing
    
    # Create resources
    create_thing_type
    create_thing_group
    create_iot_policy
    provision_devices
    create_certificates
    create_dynamic_groups
    setup_monitoring
    create_firmware_job
    update_device_shadow
    create_fleet_metrics
    
    # Validate deployment
    validate_deployment
    
    log "Deployment completed successfully! ✅"
    
    # Display deployment information
    info "Deployment Summary:"
    info "- Fleet Name: $FLEET_NAME"
    info "- Thing Type: $THING_TYPE_NAME"
    info "- Thing Group: $THING_GROUP_NAME"
    info "- Policy Name: $POLICY_NAME"
    info "- Random Suffix: $RANDOM_SUFFIX"
    info "- AWS Region: $AWS_REGION"
    info ""
    info "To clean up resources, run: ./destroy.sh"
    info "Configuration saved to: $SCRIPT_DIR/deployment-config.env"
}

# Run main function
main "$@"