#!/bin/bash

# IoT Fleet Management and OTA Updates - Deployment Script
# This script deploys the complete IoT fleet management infrastructure
# including device registration, fleet organization, and OTA update capabilities

set -e
set -o pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
    log_warn "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands with dry-run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${BLUE}[DRY-RUN]${NC} $description"
        echo "  Command: $cmd"
        return 0
    fi
    
    log "$description"
    eval "$cmd"
    if [[ $? -eq 0 ]]; then
        echo "✅ $description completed successfully"
    else
        log_error "$description failed"
        return 1
    fi
}

# Cleanup function for script interruption
cleanup_on_exit() {
    if [[ $? -ne 0 ]]; then
        log_error "Script interrupted. Some resources may have been created."
        log_error "Run destroy.sh to clean up any partial deployment."
    fi
}

trap cleanup_on_exit EXIT

# Check prerequisites
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

# Check required permissions
log "Verifying AWS permissions..."
REQUIRED_PERMISSIONS=(
    "iot:CreatePolicy"
    "iot:CreateThingGroup"
    "iot:CreateThing"
    "iot:CreateKeysAndCertificate"
    "iot:CreateJob"
    "s3:CreateBucket"
    "s3:PutObject"
)

for permission in "${REQUIRED_PERMISSIONS[@]}"; do
    if ! aws iam simulate-principal-policy \
        --policy-source-arn "$(aws sts get-caller-identity --query Arn --output text)" \
        --action-names "$permission" \
        --resource-arns "*" \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>/dev/null | grep -q "allowed"; then
        log_warn "May not have permission for: $permission"
    fi
done

log "✅ Prerequisites check completed"

# Set environment variables
log "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    log_warn "No region configured, using default: us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers for resources
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 6 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")

export IOT_POLICY_NAME="IoTDevicePolicy-${RANDOM_SUFFIX}"
export THING_GROUP_NAME="ProductionDevices-${RANDOM_SUFFIX}"
export S3_BUCKET_NAME="iot-firmware-updates-${RANDOM_SUFFIX}"
export FIRMWARE_VERSION="v2.1.0"
export JOB_ID="firmware-update-${FIRMWARE_VERSION}-${RANDOM_SUFFIX}"

log "Environment variables set:"
log "  AWS_REGION: $AWS_REGION"
log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
log "  IOT_POLICY_NAME: $IOT_POLICY_NAME"
log "  THING_GROUP_NAME: $THING_GROUP_NAME"
log "  S3_BUCKET_NAME: $S3_BUCKET_NAME"
log "  FIRMWARE_VERSION: $FIRMWARE_VERSION"

# Store variables for cleanup script
cat > /tmp/iot-fleet-vars.sh << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export IOT_POLICY_NAME="$IOT_POLICY_NAME"
export THING_GROUP_NAME="$THING_GROUP_NAME"
export S3_BUCKET_NAME="$S3_BUCKET_NAME"
export FIRMWARE_VERSION="$FIRMWARE_VERSION"
export JOB_ID="$JOB_ID"
EOF

# Step 1: Create S3 bucket for firmware storage
execute_cmd "aws s3 mb s3://\${S3_BUCKET_NAME} --region \${AWS_REGION}" \
    "Creating S3 bucket for firmware storage"

# Create sample firmware file
if [[ "$DRY_RUN" == "false" ]]; then
    echo "Firmware update package v2.1.0 - Created on $(date)" > firmware-${FIRMWARE_VERSION}.bin
    execute_cmd "aws s3 cp firmware-\${FIRMWARE_VERSION}.bin s3://\${S3_BUCKET_NAME}/firmware/" \
        "Uploading sample firmware file"
fi

# Step 2: Create IoT Device Policy
log "Creating IoT device policy..."
if [[ "$DRY_RUN" == "false" ]]; then
    cat > iot-device-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:Connect"
      ],
      "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:client/\${iot:Connection.Thing.ThingName}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iot:Publish",
        "iot:Subscribe",
        "iot:Receive"
      ],
      "Resource": [
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/\$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*",
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topicfilter/\$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*"
      ]
    }
  ]
}
EOF
fi

execute_cmd "aws iot create-policy --policy-name \${IOT_POLICY_NAME} --policy-document file://iot-device-policy.json" \
    "Creating IoT device policy"

# Step 3: Create Thing Group
execute_cmd "aws iot create-thing-group --thing-group-name \${THING_GROUP_NAME} --thing-group-properties 'thingGroupDescription=\"Production IoT devices for OTA updates\",attributePayload={attributes={\"environment\":\"production\",\"updatePolicy\":\"automatic\",\"firmwareVersion\":\"v2.0.0\"}}'" \
    "Creating thing group for fleet organization"

# Step 4: Register IoT Devices
log "Registering IoT devices in the fleet..."
for i in {1..3}; do
    THING_NAME="IoTDevice-${RANDOM_SUFFIX}-${i}"
    
    execute_cmd "aws iot create-thing --thing-name \${THING_NAME} --attribute-payload 'attributes={\"deviceType\":\"sensor\",\"firmwareVersion\":\"v2.0.0\",\"location\":\"factory-floor-${i}\"}'" \
        "Creating IoT device: $THING_NAME"
    
    execute_cmd "aws iot add-thing-to-thing-group --thing-group-name \${THING_GROUP_NAME} --thing-name \${THING_NAME}" \
        "Adding device to thing group: $THING_NAME"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Create and attach certificates
        CERT_OUTPUT=$(aws iot create-keys-and-certificate --set-as-active --query '[certificateArn,certificateId,keyPair.PrivateKey,certificatePem]' --output text)
        CERT_ARN=$(echo ${CERT_OUTPUT} | cut -d' ' -f1)
        CERT_ID=$(echo ${CERT_OUTPUT} | cut -d' ' -f2)
        
        # Store certificate ID for cleanup
        echo "$CERT_ID" >> /tmp/iot-cert-ids.txt
        
        execute_cmd "aws iot attach-policy --policy-name \${IOT_POLICY_NAME} --target \${CERT_ARN}" \
            "Attaching policy to certificate for $THING_NAME"
        
        execute_cmd "aws iot attach-thing-principal --thing-name \${THING_NAME} --principal \${CERT_ARN}" \
            "Attaching certificate to thing: $THING_NAME"
        
        # Store thing name for cleanup
        echo "$THING_NAME" >> /tmp/iot-thing-names.txt
    fi
done

# Step 5: Create Job Document
log "Creating firmware update job document..."
if [[ "$DRY_RUN" == "false" ]]; then
    cat > firmware-update-job.json << EOF
{
  "operation": "firmwareUpdate",
  "firmwareVersion": "${FIRMWARE_VERSION}",
  "downloadUrl": "https://${S3_BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/firmware/firmware-${FIRMWARE_VERSION}.bin",
  "checksumAlgorithm": "SHA256",
  "checksum": "placeholder-checksum-for-demo",
  "installationSteps": [
    "Download firmware package from specified URL",
    "Validate package integrity using checksum",
    "Backup current firmware version",
    "Install new firmware version",
    "Restart device and validate functionality",
    "Report installation status to AWS IoT"
  ],
  "rollbackInstructions": {
    "enabled": true,
    "maxAttempts": 3,
    "fallbackVersion": "v2.0.0"
  },
  "timeoutConfig": {
    "inProgressTimeoutInMinutes": 30,
    "stepTimeoutInMinutes": 10
  }
}
EOF
fi

# Step 6: Deploy OTA Update Job
execute_cmd "aws iot create-job --job-id \${JOB_ID} --targets \"arn:aws:iot:\${AWS_REGION}:\${AWS_ACCOUNT_ID}:thinggroup/\${THING_GROUP_NAME}\" --document file://firmware-update-job.json --description \"Deploy firmware version \${FIRMWARE_VERSION} to production devices\" --job-executions-rollout-config 'maximumPerMinute=10,exponentialRate={baseRatePerMinute=5,incrementFactor=2,rateIncreaseCriteria={numberOfNotifiedThings=5,numberOfSucceededThings=3}}' --abort-config 'criteriaList=[{failureType=\"FAILED\",action=\"CANCEL\",thresholdPercentage=25,minNumberOfExecutedThings=3}]' --timeout-config 'inProgressTimeoutInMinutes=60'" \
    "Creating firmware update job"

# Step 7: Monitor Job Status
log "Monitoring job execution status..."
if [[ "$DRY_RUN" == "false" ]]; then
    sleep 2
    aws iot describe-job --job-id ${JOB_ID} --query '[jobArn,status,jobExecutionsRolloutConfig,description]' --output table
    
    aws iot list-job-executions-for-job --job-id ${JOB_ID} --query 'executionSummaries[*].[thingArn,status,queuedAt,startedAt,lastUpdatedAt]' --output table
fi

# Step 8: Simulate Device Processing (for demonstration)
log "Simulating device job processing..."
if [[ "$DRY_RUN" == "false" ]]; then
    SAMPLE_THING=$(aws iot list-things-in-thing-group --thing-group-name ${THING_GROUP_NAME} --query 'things[0]' --output text)
    
    if [[ "$SAMPLE_THING" != "None" && "$SAMPLE_THING" != "" ]]; then
        # Simulate device updating job status
        aws iot update-job-execution \
            --job-id ${JOB_ID} \
            --thing-name ${SAMPLE_THING} \
            --status IN_PROGRESS \
            --status-details '{"step":"downloading","progress":"25%","details":"Downloading firmware package"}' || true
        
        sleep 2
        
        # Simulate successful completion
        aws iot update-job-execution \
            --job-id ${JOB_ID} \
            --thing-name ${SAMPLE_THING} \
            --status SUCCEEDED \
            --status-details '{"step":"completed","progress":"100%","details":"Firmware update completed successfully","newVersion":"'${FIRMWARE_VERSION}'"}' || true
        
        log "✅ Device ${SAMPLE_THING} completed firmware update simulation"
    fi
fi

# Step 9: Update Device Metadata
log "Updating device fleet metadata..."
if [[ "$DRY_RUN" == "false" ]]; then
    for THING_NAME in $(aws iot list-things-in-thing-group --thing-group-name ${THING_GROUP_NAME} --query 'things[*]' --output text); do
        JOB_STATUS=$(aws iot describe-job-execution --job-id ${JOB_ID} --thing-name ${THING_NAME} --query 'execution.status' --output text 2>/dev/null || echo "QUEUED")
        
        if [[ "${JOB_STATUS}" == "SUCCEEDED" ]]; then
            aws iot update-thing --thing-name ${THING_NAME} --attribute-payload 'attributes={"deviceType":"sensor","firmwareVersion":"'${FIRMWARE_VERSION}'","lastUpdateTime":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","updateStatus":"success"}'
            log "✅ Updated metadata for ${THING_NAME} with firmware ${FIRMWARE_VERSION}"
        else
            log_warn "Device ${THING_NAME} update status: ${JOB_STATUS}"
        fi
    done
    
    # Update thing group attributes
    aws iot update-thing-group --thing-group-name ${THING_GROUP_NAME} --thing-group-properties 'thingGroupDescription="Production IoT devices - Updated to '${FIRMWARE_VERSION}'",attributePayload={attributes={"environment":"production","updatePolicy":"automatic","firmwareVersion":"'${FIRMWARE_VERSION}'","lastFleetUpdate":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}}'
fi

# Final validation
log "Performing final validation..."
if [[ "$DRY_RUN" == "false" ]]; then
    # Check job status
    JOB_STATUS=$(aws iot describe-job --job-id ${JOB_ID} --query 'status' --output text)
    log "Job status: $JOB_STATUS"
    
    # Check device count in thing group
    DEVICE_COUNT=$(aws iot list-things-in-thing-group --thing-group-name ${THING_GROUP_NAME} --query 'things | length(@)')
    log "Devices in fleet: $DEVICE_COUNT"
    
    # Check S3 bucket contents
    aws s3 ls s3://${S3_BUCKET_NAME}/firmware/ --human-readable
fi

log "🎉 IoT Fleet Management and OTA Updates deployment completed successfully!"
log ""
log "📋 Deployment Summary:"
log "  - IoT Policy: $IOT_POLICY_NAME"
log "  - Thing Group: $THING_GROUP_NAME"
log "  - S3 Bucket: $S3_BUCKET_NAME"
log "  - Firmware Version: $FIRMWARE_VERSION"
log "  - Job ID: $JOB_ID"
log "  - Region: $AWS_REGION"
log ""
log "🔧 To validate the deployment:"
log "  aws iot describe-job --job-id $JOB_ID"
log "  aws iot list-things-in-thing-group --thing-group-name $THING_GROUP_NAME"
log ""
log "🧹 To clean up resources:"
log "  ./destroy.sh"
log ""
log "💡 Environment variables have been saved to /tmp/iot-fleet-vars.sh for cleanup"

# Cleanup temporary files
if [[ "$DRY_RUN" == "false" ]]; then
    rm -f iot-device-policy.json firmware-update-job.json firmware-*.bin
fi