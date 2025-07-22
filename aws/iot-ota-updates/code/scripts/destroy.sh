#!/bin/bash

# IoT Fleet Management and OTA Updates - Cleanup Script
# This script removes all resources created by the deployment script
# WARNING: This will permanently delete all IoT devices, policies, and S3 data

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

# Function to confirm destructive actions
confirm_action() {
    local action="$1"
    local resource="$2"
    
    if [[ "$FORCE" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  WARNING: This will $action $resource${NC}"
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Operation cancelled by user"
        return 1
    fi
    return 0
}

# Function to safely execute cleanup commands
safe_cleanup() {
    local cmd="$1"
    local description="$2"
    local ignore_errors="${3:-false}"
    
    log "$description"
    
    if [[ "$ignore_errors" == "true" ]]; then
        eval "$cmd" 2>/dev/null || {
            log_warn "$description failed (ignoring)"
            return 0
        }
    else
        eval "$cmd" || {
            log_error "$description failed"
            return 1
        }
    fi
    
    echo "✅ $description completed"
    return 0
}

# Check for force flag
FORCE=false
if [[ "$1" == "--force" ]]; then
    FORCE=true
    log_warn "Running in FORCE mode - no confirmation prompts"
fi

# Check if running with confirmation
if [[ "$1" == "--confirm" ]]; then
    FORCE=true
fi

# Check prerequisites
log "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI is not installed"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS credentials not configured"
    exit 1
fi

# Load environment variables from deployment
if [[ -f "/tmp/iot-fleet-vars.sh" ]]; then
    source /tmp/iot-fleet-vars.sh
    log "Loaded environment variables from deployment"
else
    log_warn "Environment variables file not found. Please provide variables manually."
    
    # Prompt for required variables
    read -p "Enter IoT Policy Name: " IOT_POLICY_NAME
    read -p "Enter Thing Group Name: " THING_GROUP_NAME
    read -p "Enter S3 Bucket Name: " S3_BUCKET_NAME
    read -p "Enter Job ID: " JOB_ID
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

# Display what will be destroyed
log "🔍 Resources to be destroyed:"
log "  - IoT Policy: ${IOT_POLICY_NAME}"
log "  - Thing Group: ${THING_GROUP_NAME}"
log "  - S3 Bucket: ${S3_BUCKET_NAME}"
log "  - Job ID: ${JOB_ID}"
log "  - All devices and certificates in the fleet"
log ""

# Final confirmation
if ! confirm_action "PERMANENTLY DELETE" "all IoT fleet resources"; then
    log "Cleanup cancelled"
    exit 0
fi

# Step 1: Cancel any running jobs
log "Cancelling IoT jobs..."
if [[ -n "$JOB_ID" ]]; then
    safe_cleanup "aws iot cancel-job --job-id \${JOB_ID} --comment \"Cleanup - removing test job\"" \
        "Cancelling job: $JOB_ID" true
    
    # Wait for job to be cancelled
    sleep 2
    
    # Delete the job document
    safe_cleanup "aws iot delete-job --job-id \${JOB_ID} --force" \
        "Deleting job: $JOB_ID" true
fi

# Step 2: Remove devices from fleet and clean up certificates
log "Removing devices from fleet..."

# Get list of things in group
THINGS_IN_GROUP=()
if aws iot list-things-in-thing-group --thing-group-name ${THING_GROUP_NAME} &>/dev/null; then
    while IFS= read -r thing; do
        THINGS_IN_GROUP+=("$thing")
    done < <(aws iot list-things-in-thing-group --thing-group-name ${THING_GROUP_NAME} --query 'things[*]' --output text)
fi

# Also check for things from temp file
if [[ -f "/tmp/iot-thing-names.txt" ]]; then
    while IFS= read -r thing; do
        if [[ -n "$thing" ]]; then
            THINGS_IN_GROUP+=("$thing")
        fi
    done < /tmp/iot-thing-names.txt
fi

# Remove duplicate thing names
if [[ ${#THINGS_IN_GROUP[@]} -gt 0 ]]; then
    UNIQUE_THINGS=($(printf '%s\n' "${THINGS_IN_GROUP[@]}" | sort -u))
    
    for THING_NAME in "${UNIQUE_THINGS[@]}"; do
        if [[ -n "$THING_NAME" && "$THING_NAME" != "None" ]]; then
            log "Processing device: $THING_NAME"
            
            # Remove from thing group
            safe_cleanup "aws iot remove-thing-from-thing-group --thing-group-name \${THING_GROUP_NAME} --thing-name \${THING_NAME}" \
                "Removing $THING_NAME from thing group" true
            
            # Get and process certificates
            PRINCIPALS=$(aws iot list-thing-principals --thing-name ${THING_NAME} --query 'principals[*]' --output text 2>/dev/null || echo "")
            
            for PRINCIPAL in $PRINCIPALS; do
                if [[ -n "$PRINCIPAL" && "$PRINCIPAL" != "None" ]]; then
                    log "Processing certificate: $PRINCIPAL"
                    
                    # Detach certificate from thing
                    safe_cleanup "aws iot detach-thing-principal --thing-name \${THING_NAME} --principal \${PRINCIPAL}" \
                        "Detaching certificate from $THING_NAME" true
                    
                    # Detach policy from certificate
                    safe_cleanup "aws iot detach-policy --policy-name \${IOT_POLICY_NAME} --target \${PRINCIPAL}" \
                        "Detaching policy from certificate" true
                    
                    # Extract certificate ID and deactivate/delete
                    CERT_ID=$(echo ${PRINCIPAL} | cut -d'/' -f2)
                    if [[ -n "$CERT_ID" ]]; then
                        safe_cleanup "aws iot update-certificate --certificate-id \${CERT_ID} --new-status INACTIVE" \
                            "Deactivating certificate $CERT_ID" true
                        
                        safe_cleanup "aws iot delete-certificate --certificate-id \${CERT_ID}" \
                            "Deleting certificate $CERT_ID" true
                    fi
                fi
            done
            
            # Delete the thing
            safe_cleanup "aws iot delete-thing --thing-name \${THING_NAME}" \
                "Deleting thing $THING_NAME" true
        fi
    done
fi

# Clean up certificates from temp file
if [[ -f "/tmp/iot-cert-ids.txt" ]]; then
    while IFS= read -r cert_id; do
        if [[ -n "$cert_id" ]]; then
            safe_cleanup "aws iot update-certificate --certificate-id \${cert_id} --new-status INACTIVE" \
                "Deactivating certificate $cert_id" true
            
            safe_cleanup "aws iot delete-certificate --certificate-id \${cert_id}" \
                "Deleting certificate $cert_id" true
        fi
    done < /tmp/iot-cert-ids.txt
fi

# Step 3: Delete thing group
log "Deleting thing group..."
if [[ -n "$THING_GROUP_NAME" ]]; then
    safe_cleanup "aws iot delete-thing-group --thing-group-name \${THING_GROUP_NAME}" \
        "Deleting thing group: $THING_GROUP_NAME" true
fi

# Step 4: Delete IoT policy
log "Deleting IoT policy..."
if [[ -n "$IOT_POLICY_NAME" ]]; then
    # List policy versions and delete non-default versions first
    POLICY_VERSIONS=$(aws iot list-policy-versions --policy-name ${IOT_POLICY_NAME} --query 'policyVersions[?!isDefaultVersion].versionId' --output text 2>/dev/null || echo "")
    
    for VERSION in $POLICY_VERSIONS; do
        if [[ -n "$VERSION" ]]; then
            safe_cleanup "aws iot delete-policy-version --policy-name \${IOT_POLICY_NAME} --policy-version-id \${VERSION}" \
                "Deleting policy version $VERSION" true
        fi
    done
    
    # Delete the policy
    safe_cleanup "aws iot delete-policy --policy-name \${IOT_POLICY_NAME}" \
        "Deleting IoT policy: $IOT_POLICY_NAME" true
fi

# Step 5: Clean up S3 bucket
log "Cleaning up S3 bucket..."
if [[ -n "$S3_BUCKET_NAME" ]]; then
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${S3_BUCKET_NAME} 2>/dev/null; then
        # Remove all objects from bucket
        safe_cleanup "aws s3 rm s3://\${S3_BUCKET_NAME} --recursive" \
            "Removing all objects from S3 bucket" true
        
        # Delete the bucket
        safe_cleanup "aws s3 rb s3://\${S3_BUCKET_NAME}" \
            "Deleting S3 bucket: $S3_BUCKET_NAME" true
    else
        log_warn "S3 bucket $S3_BUCKET_NAME does not exist or is not accessible"
    fi
fi

# Step 6: Clean up local temporary files
log "Cleaning up temporary files..."
safe_cleanup "rm -f /tmp/iot-fleet-vars.sh" \
    "Removing environment variables file" true

safe_cleanup "rm -f /tmp/iot-thing-names.txt" \
    "Removing thing names file" true

safe_cleanup "rm -f /tmp/iot-cert-ids.txt" \
    "Removing certificate IDs file" true

safe_cleanup "rm -f iot-device-policy.json firmware-update-job.json firmware-*.bin" \
    "Removing local policy and firmware files" true

# Step 7: Final verification
log "Performing final verification..."

# Check if policy still exists
if aws iot get-policy --policy-name ${IOT_POLICY_NAME} &>/dev/null; then
    log_warn "IoT Policy $IOT_POLICY_NAME still exists"
else
    log "✅ IoT Policy successfully deleted"
fi

# Check if thing group still exists
if aws iot describe-thing-group --thing-group-name ${THING_GROUP_NAME} &>/dev/null; then
    log_warn "Thing Group $THING_GROUP_NAME still exists"
else
    log "✅ Thing Group successfully deleted"
fi

# Check if S3 bucket still exists
if aws s3api head-bucket --bucket ${S3_BUCKET_NAME} 2>/dev/null; then
    log_warn "S3 Bucket $S3_BUCKET_NAME still exists"
else
    log "✅ S3 Bucket successfully deleted"
fi

# Check for any remaining jobs
if aws iot describe-job --job-id ${JOB_ID} &>/dev/null; then
    log_warn "Job $JOB_ID still exists"
else
    log "✅ Job successfully deleted"
fi

log "🎉 IoT Fleet Management cleanup completed successfully!"
log ""
log "📋 Cleanup Summary:"
log "  - ✅ IoT Policy deleted: $IOT_POLICY_NAME"
log "  - ✅ Thing Group deleted: $THING_GROUP_NAME"
log "  - ✅ S3 Bucket deleted: $S3_BUCKET_NAME"
log "  - ✅ Job deleted: $JOB_ID"
log "  - ✅ All devices and certificates removed"
log "  - ✅ Temporary files cleaned up"
log ""
log "💡 If you encounter any issues, you can:"
log "  - Check the AWS IoT console for remaining resources"
log "  - Run this script again with --force to bypass confirmations"
log "  - Manually delete resources using the AWS CLI or console"
log ""
log "🔒 All sensitive data and certificates have been permanently deleted"