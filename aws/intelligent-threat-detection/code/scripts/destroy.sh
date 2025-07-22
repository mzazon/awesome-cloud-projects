#!/bin/bash

# Destroy script for GuardDuty Threat Detection Recipe
# This script safely removes all GuardDuty infrastructure
# with proper confirmation prompts and error handling

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
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

confirm() {
    while true; do
        read -p "$1 (y/N): " response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* | "" ) return 1;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# Banner
echo -e "${RED}"
echo "=============================================="
echo "   GuardDuty Threat Detection Cleanup"
echo "=============================================="
echo -e "${NC}"

warning "This script will destroy all GuardDuty threat detection infrastructure!"
echo

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
fi

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS CLI is not configured or you don't have proper credentials."
fi

success "Prerequisites check passed"

# Load deployment configuration if it exists
if [ -f "guardduty-deployment.env" ]; then
    log "Loading deployment configuration from guardduty-deployment.env..."
    source guardduty-deployment.env
    success "Configuration loaded"
else
    warning "No deployment configuration found. Will attempt to discover resources..."
    
    # Set basic environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
fi

log "Using AWS Region: ${AWS_REGION}"
log "Using AWS Account: ${AWS_ACCOUNT_ID}"

# Final confirmation
echo
warning "This will permanently delete the following resources:"
echo "  • GuardDuty detector and all findings"
echo "  • SNS topic and email subscriptions"
echo "  • EventBridge rules and targets"
echo "  • CloudWatch dashboard"
echo "  • S3 bucket with all stored findings"
echo "  • All associated IAM policies"
echo

if ! confirm "Are you absolutely sure you want to proceed?"; then
    log "Cleanup cancelled by user"
    exit 0
fi

if ! confirm "This action cannot be undone. Continue?"; then
    log "Cleanup cancelled by user"
    exit 0
fi

echo

# Step 1: Remove GuardDuty findings export configuration
log "Step 1: Removing GuardDuty findings export configuration..."

# Find detector ID if not loaded from config
if [ -z "${DETECTOR_ID:-}" ]; then
    DETECTOR_ID=$(aws guardduty list-detectors --query 'DetectorIds[0]' --output text 2>/dev/null || echo "")
fi

if [ -n "$DETECTOR_ID" ] && [ "$DETECTOR_ID" != "None" ] && [ "$DETECTOR_ID" != "null" ]; then
    # List and delete publishing destinations
    DESTINATIONS=$(aws guardduty list-publishing-destinations \
        --detector-id ${DETECTOR_ID} \
        --query 'Destinations[].DestinationId' --output text 2>/dev/null || echo "")
    
    if [ -n "$DESTINATIONS" ] && [ "$DESTINATIONS" != "None" ]; then
        for DESTINATION_ID in $DESTINATIONS; do
            aws guardduty delete-publishing-destination \
                --detector-id ${DETECTOR_ID} \
                --destination-id ${DESTINATION_ID} 2>/dev/null || true
            success "Removed publishing destination: ${DESTINATION_ID}"
        done
    else
        log "No publishing destinations found"
    fi
else
    warning "No GuardDuty detector found or detector ID not available"
fi

# Step 2: Delete S3 bucket and contents
log "Step 2: Deleting S3 bucket and contents..."

# Try to find S3 bucket if not loaded from config
if [ -z "${S3_BUCKET_NAME:-}" ]; then
    # Look for GuardDuty findings buckets
    POTENTIAL_BUCKETS=$(aws s3api list-buckets \
        --query "Buckets[?contains(Name, 'guardduty-findings-${AWS_ACCOUNT_ID}')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$POTENTIAL_BUCKETS" ]; then
        S3_BUCKET_NAME=$(echo $POTENTIAL_BUCKETS | cut -d' ' -f1)
        log "Found potential GuardDuty bucket: ${S3_BUCKET_NAME}"
    fi
fi

if [ -n "${S3_BUCKET_NAME:-}" ]; then
    # Check if bucket exists
    if aws s3api head-bucket --bucket ${S3_BUCKET_NAME} 2>/dev/null; then
        # Remove all objects from bucket
        log "Removing all objects from bucket ${S3_BUCKET_NAME}..."
        aws s3 rm s3://${S3_BUCKET_NAME} --recursive 2>/dev/null || true
        
        # Delete bucket
        aws s3 rb s3://${S3_BUCKET_NAME} 2>/dev/null || true
        success "S3 bucket deleted: ${S3_BUCKET_NAME}"
    else
        log "S3 bucket ${S3_BUCKET_NAME} not found or already deleted"
    fi
else
    log "No S3 bucket name found in configuration"
fi

# Step 3: Remove EventBridge rule and targets
log "Step 3: Removing EventBridge rule and targets..."

# Check if rule exists and remove targets
if aws events describe-rule --name guardduty-finding-events &>/dev/null; then
    # Remove targets first
    TARGETS=$(aws events list-targets-by-rule \
        --rule guardduty-finding-events \
        --query 'Targets[].Id' --output text 2>/dev/null || echo "")
    
    if [ -n "$TARGETS" ] && [ "$TARGETS" != "None" ]; then
        aws events remove-targets \
            --rule guardduty-finding-events \
            --ids ${TARGETS} 2>/dev/null || true
        success "Removed EventBridge targets"
    fi
    
    # Delete the rule
    aws events delete-rule --name guardduty-finding-events 2>/dev/null || true
    success "EventBridge rule deleted"
else
    log "EventBridge rule 'guardduty-finding-events' not found"
fi

# Step 4: Delete SNS topic
log "Step 4: Deleting SNS topic..."

# Try to find SNS topic if not loaded from config
if [ -z "${SNS_TOPIC_ARN:-}" ] && [ -n "${SNS_TOPIC_NAME:-}" ]; then
    SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
elif [ -z "${SNS_TOPIC_ARN:-}" ]; then
    # Look for GuardDuty alert topics
    POTENTIAL_TOPICS=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'guardduty-alerts')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$POTENTIAL_TOPICS" ]; then
        SNS_TOPIC_ARN=$(echo $POTENTIAL_TOPICS | cut -d' ' -f1)
        log "Found potential GuardDuty SNS topic: ${SNS_TOPIC_ARN}"
    fi
fi

if [ -n "${SNS_TOPIC_ARN:-}" ]; then
    # Check if topic exists and delete it
    if aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN} &>/dev/null; then
        aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN} 2>/dev/null || true
        success "SNS topic deleted: ${SNS_TOPIC_ARN}"
    else
        log "SNS topic ${SNS_TOPIC_ARN} not found or already deleted"
    fi
else
    log "No SNS topic ARN found in configuration"
fi

# Step 5: Delete CloudWatch dashboard
log "Step 5: Deleting CloudWatch dashboard..."

if aws cloudwatch describe-dashboards --dashboard-names GuardDuty-Security-Monitoring &>/dev/null; then
    aws cloudwatch delete-dashboards \
        --dashboard-names GuardDuty-Security-Monitoring 2>/dev/null || true
    success "CloudWatch dashboard deleted"
else
    log "CloudWatch dashboard 'GuardDuty-Security-Monitoring' not found"
fi

# Step 6: Disable GuardDuty (optional - with additional confirmation)
log "Step 6: GuardDuty detector cleanup..."

if [ -n "${DETECTOR_ID:-}" ] && [ "$DETECTOR_ID" != "None" ] && [ "$DETECTOR_ID" != "null" ]; then
    echo
    warning "GuardDuty detector is still active and monitoring your environment."
    warning "Disabling GuardDuty will stop all threat detection capabilities!"
    echo
    
    if confirm "Do you want to completely disable GuardDuty?"; then
        # Delete GuardDuty detector (this disables GuardDuty)
        aws guardduty delete-detector --detector-id ${DETECTOR_ID} 2>/dev/null || true
        success "GuardDuty detector deleted: ${DETECTOR_ID}"
    else
        warning "GuardDuty detector left active. Detector ID: ${DETECTOR_ID}"
        log "You can manually disable it later from the AWS console if needed"
    fi
else
    log "No active GuardDuty detector found"
fi

# Step 7: Clean up local files
log "Step 7: Cleaning up local configuration files..."

if [ -f "guardduty-deployment.env" ]; then
    rm guardduty-deployment.env
    success "Removed local configuration file"
fi

# Verification
log "Performing cleanup verification..."

# Verify SNS topic deletion
if [ -n "${SNS_TOPIC_ARN:-}" ]; then
    if aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN} &>/dev/null; then
        warning "SNS topic still exists: ${SNS_TOPIC_ARN}"
    fi
fi

# Verify S3 bucket deletion
if [ -n "${S3_BUCKET_NAME:-}" ]; then
    if aws s3api head-bucket --bucket ${S3_BUCKET_NAME} &>/dev/null; then
        warning "S3 bucket still exists: ${S3_BUCKET_NAME}"
    fi
fi

# Verify EventBridge rule deletion
if aws events describe-rule --name guardduty-finding-events &>/dev/null; then
    warning "EventBridge rule still exists"
fi

# Verify CloudWatch dashboard deletion
if aws cloudwatch describe-dashboards --dashboard-names GuardDuty-Security-Monitoring &>/dev/null; then
    warning "CloudWatch dashboard still exists"
fi

success "Cleanup verification completed"

# Final summary
echo -e "\n${GREEN}=========================================="
echo "   Cleanup Completed Successfully!"
echo "==========================================${NC}"
echo

if [ -n "${DETECTOR_ID:-}" ] && aws guardduty get-detector --detector-id ${DETECTOR_ID} &>/dev/null; then
    warning "GuardDuty is still active and will continue monitoring your environment"
    log "To completely disable GuardDuty, run this script again or use the AWS console"
else
    success "All GuardDuty threat detection infrastructure has been removed"
fi

echo
log "If you had email subscriptions, you may still receive a final confirmation email"
log "Consider reviewing your AWS bill to ensure no unexpected charges"
echo
echo -e "${BLUE}Cleanup completed successfully! 🧹${NC}"