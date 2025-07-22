#!/bin/bash

# Deploy script for Amazon Connect Contact Center Solution
# This script deploys a complete contact center infrastructure using Amazon Connect

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running with proper permissions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check required permissions
    log_info "Verifying AWS permissions..."
    aws iam get-user &> /dev/null || aws sts get-caller-identity &> /dev/null || error_exit "Unable to verify AWS identity"
    
    log_success "Prerequisites check completed"
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Deployment failed. Cleaning up resources..."
    
    # Store the deployment state file
    if [ -f "deployment_state.json" ]; then
        mv deployment_state.json deployment_state_failed_$(date +%Y%m%d_%H%M%S).json
        log_info "Deployment state saved for debugging"
    fi
    
    log_info "Please run ./destroy.sh to clean up any remaining resources"
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Create deployment state file to track resources
create_deployment_state() {
    cat > deployment_state.json << EOF
{
    "deployment_id": "${RANDOM_SUFFIX}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "region": "${AWS_REGION}",
    "account_id": "${AWS_ACCOUNT_ID}",
    "resources": {}
}
EOF
}

# Update deployment state
update_deployment_state() {
    local key=$1
    local value=$2
    jq --arg key "$key" --arg value "$value" '.resources[$key] = $value' deployment_state.json > tmp.json && mv tmp.json deployment_state.json
}

# Main deployment function
deploy_contact_center() {
    log_info "Starting Amazon Connect Contact Center deployment..."
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region configured. Using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export CONNECT_INSTANCE_ALIAS="contact-center-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="connect-recordings-${AWS_ACCOUNT_ID}-${RANDOM_SUFFIX}"
    
    log_info "Deployment ID: ${RANDOM_SUFFIX}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "AWS Account: ${AWS_ACCOUNT_ID}"
    
    # Create deployment state tracking
    create_deployment_state
    
    # Step 1: Create S3 bucket for call recordings
    log_info "Creating S3 bucket for call recordings..."
    if aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}; then
        update_deployment_state "s3_bucket" "${S3_BUCKET_NAME}"
        log_success "S3 bucket created: ${S3_BUCKET_NAME}"
    else
        error_exit "Failed to create S3 bucket"
    fi
    
    # Step 2: Create Amazon Connect instance
    log_info "Creating Amazon Connect instance..."
    INSTANCE_RESULT=$(aws connect create-instance \
        --identity-management-type CONNECT_MANAGED \
        --instance-alias ${CONNECT_INSTANCE_ALIAS} \
        --inbound-calls-enabled \
        --outbound-calls-enabled \
        --output json)
    
    export INSTANCE_ID=$(echo $INSTANCE_RESULT | jq -r '.Id')
    export INSTANCE_ARN=$(echo $INSTANCE_RESULT | jq -r '.Arn')
    
    update_deployment_state "instance_id" "${INSTANCE_ID}"
    update_deployment_state "instance_arn" "${INSTANCE_ARN}"
    update_deployment_state "instance_alias" "${CONNECT_INSTANCE_ALIAS}"
    
    log_success "Connect instance created: ${INSTANCE_ID}"
    
    # Wait for instance to be ready
    log_info "Waiting for Connect instance to be ready..."
    for i in {1..30}; do
        INSTANCE_STATUS=$(aws connect describe-instance \
            --instance-id ${INSTANCE_ID} \
            --query 'Instance.InstanceStatus' \
            --output text)
        
        if [ "$INSTANCE_STATUS" == "ACTIVE" ]; then
            log_success "Connect instance is active"
            break
        fi
        
        if [ $i -eq 30 ]; then
            error_exit "Timeout waiting for Connect instance to become active"
        fi
        
        log_info "Instance status: ${INSTANCE_STATUS}. Waiting... (${i}/30)"
        sleep 10
    done
    
    # Step 3: Configure instance storage
    log_info "Configuring instance storage..."
    
    # Configure call recordings storage
    aws connect associate-instance-storage-config \
        --instance-id ${INSTANCE_ID} \
        --resource-type CALL_RECORDINGS \
        --storage-config "S3Config={BucketName=${S3_BUCKET_NAME},BucketPrefix=call-recordings/}" \
        --output table
    
    # Configure chat transcripts storage
    aws connect associate-instance-storage-config \
        --instance-id ${INSTANCE_ID} \
        --resource-type CHAT_TRANSCRIPTS \
        --storage-config "S3Config={BucketName=${S3_BUCKET_NAME},BucketPrefix=chat-transcripts/}" \
        --output table
    
    log_success "Storage configuration completed"
    
    # Step 4: Get security profiles and routing profiles
    log_info "Retrieving security and routing profiles..."
    
    ADMIN_PROFILE_ID=$(aws connect list-security-profiles \
        --instance-id ${INSTANCE_ID} \
        --query 'SecurityProfileSummaryList[?Name==`Admin`].Id' \
        --output text)
    
    AGENT_PROFILE_ID=$(aws connect list-security-profiles \
        --instance-id ${INSTANCE_ID} \
        --query 'SecurityProfileSummaryList[?Name==`Agent`].Id' \
        --output text)
    
    ROUTING_PROFILE_ID=$(aws connect list-routing-profiles \
        --instance-id ${INSTANCE_ID} \
        --query 'RoutingProfileSummaryList[0].Id' \
        --output text)
    
    update_deployment_state "admin_profile_id" "${ADMIN_PROFILE_ID}"
    update_deployment_state "agent_profile_id" "${AGENT_PROFILE_ID}"
    update_deployment_state "default_routing_profile_id" "${ROUTING_PROFILE_ID}"
    
    # Step 5: Create administrative user
    log_info "Creating administrative user..."
    
    USER_RESULT=$(aws connect create-user \
        --username "connect-admin" \
        --password "TempPass123!" \
        --identity-info "FirstName=Connect,LastName=Administrator" \
        --phone-config "PhoneType=SOFT_PHONE,AutoAccept=false,AfterContactWorkTimeLimit=120" \
        --security-profile-ids ${ADMIN_PROFILE_ID} \
        --routing-profile-id ${ROUTING_PROFILE_ID} \
        --instance-id ${INSTANCE_ID} \
        --output json)
    
    export ADMIN_USER_ID=$(echo $USER_RESULT | jq -r '.UserId')
    update_deployment_state "admin_user_id" "${ADMIN_USER_ID}"
    
    log_success "Admin user created: connect-admin"
    
    # Step 6: Create customer service queue
    log_info "Creating customer service queue..."
    
    HOURS_ID=$(aws connect list-hours-of-operations \
        --instance-id ${INSTANCE_ID} \
        --query 'HoursOfOperationSummaryList[0].Id' \
        --output text)
    
    QUEUE_RESULT=$(aws connect create-queue \
        --instance-id ${INSTANCE_ID} \
        --name "CustomerService" \
        --description "Main customer service queue for general inquiries" \
        --hours-of-operation-id ${HOURS_ID} \
        --max-contacts 50 \
        --tags "Purpose=CustomerService,Environment=Production" \
        --output json)
    
    export QUEUE_ID=$(echo $QUEUE_RESULT | jq -r '.QueueId')
    update_deployment_state "queue_id" "${QUEUE_ID}"
    update_deployment_state "hours_operation_id" "${HOURS_ID}"
    
    log_success "Customer service queue created: ${QUEUE_ID}"
    
    # Step 7: Search for and claim phone number (optional)
    log_info "Searching for available phone numbers..."
    
    AVAILABLE_NUMBERS=$(aws connect search-available-phone-numbers \
        --target-arn ${INSTANCE_ARN} \
        --phone-number-country-code US \
        --phone-number-type TOLL_FREE \
        --max-results 1 \
        --output json 2>/dev/null || echo '{"AvailableNumbersList":[]}')
    
    if [ "$(echo $AVAILABLE_NUMBERS | jq '.AvailableNumbersList | length')" -gt 0 ]; then
        PHONE_NUMBER=$(echo $AVAILABLE_NUMBERS | jq -r '.AvailableNumbersList[0]')
        
        aws connect claim-phone-number \
            --target-arn ${INSTANCE_ARN} \
            --phone-number ${PHONE_NUMBER} \
            --phone-number-description "Main customer service line" \
            --tags "Purpose=CustomerService" \
            --output json
        
        export CONTACT_NUMBER=$PHONE_NUMBER
        update_deployment_state "contact_number" "${PHONE_NUMBER}"
        log_success "Phone number claimed: ${PHONE_NUMBER}"
    else
        log_warning "No toll-free numbers available. You can claim a number manually through the Connect console."
    fi
    
    # Step 8: Create contact flow
    log_info "Creating contact flow..."
    
    # Create contact flow JSON configuration
    cat > contact-flow.json << 'EOF'
{
  "Version": "2019-10-30",
  "StartAction": "12345678-1234-1234-1234-123456789012",
  "Metadata": {
    "entryPointPosition": {"x": 20, "y": 20},
    "snapToGrid": false,
    "ActionMetadata": {
      "12345678-1234-1234-1234-123456789012": {
        "position": {"x": 178, "y": 52}
      },
      "87654321-4321-4321-4321-210987654321": {
        "position": {"x": 392, "y": 154}
      },
      "11111111-2222-3333-4444-555555555555": {
        "position": {"x": 626, "y": 154}
      }
    }
  },
  "Actions": [
    {
      "Identifier": "12345678-1234-1234-1234-123456789012",
      "Type": "MessageParticipant",
      "Parameters": {
        "Text": "Thank you for calling our customer service. Please wait while we connect you to an available agent."
      },
      "Transitions": {
        "NextAction": "87654321-4321-4321-4321-210987654321"
      }
    },
    {
      "Identifier": "87654321-4321-4321-4321-210987654321", 
      "Type": "SetRecordingBehavior",
      "Parameters": {
        "RecordingBehaviorOption": "Enable",
        "RecordingParticipantOption": "Both"
      },
      "Transitions": {
        "NextAction": "11111111-2222-3333-4444-555555555555"
      }
    },
    {
      "Identifier": "11111111-2222-3333-4444-555555555555",
      "Type": "TransferToQueue",
      "Parameters": {
        "QueueId": "arn:aws:connect:REGION:ACCOUNT:instance/INSTANCE_ID/queue/QUEUE_ID"
      },
      "Transitions": {}
    }
  ]
}
EOF
    
    # Update the contact flow with actual values
    sed -i.bak "s/REGION/${AWS_REGION}/g" contact-flow.json
    sed -i.bak "s/ACCOUNT/${AWS_ACCOUNT_ID}/g" contact-flow.json  
    sed -i.bak "s/INSTANCE_ID/${INSTANCE_ID}/g" contact-flow.json
    sed -i.bak "s/QUEUE_ID/${QUEUE_ID}/g" contact-flow.json
    rm -f contact-flow.json.bak
    
    FLOW_RESULT=$(aws connect create-contact-flow \
        --instance-id ${INSTANCE_ID} \
        --name "CustomerServiceFlow" \
        --type CONTACT_FLOW \
        --description "Main customer service contact flow with recording" \
        --content file://contact-flow.json \
        --output json)
    
    export FLOW_ID=$(echo $FLOW_RESULT | jq -r '.ContactFlowId')
    update_deployment_state "flow_id" "${FLOW_ID}"
    
    # Clean up temporary file
    rm -f contact-flow.json
    
    log_success "Contact flow created: ${FLOW_ID}"
    
    # Step 9: Create agent routing profile and user
    log_info "Creating agent routing profile..."
    
    AGENT_ROUTING_RESULT=$(aws connect create-routing-profile \
        --instance-id ${INSTANCE_ID} \
        --name "CustomerServiceAgents" \
        --description "Routing profile for customer service representatives" \
        --default-outbound-queue-id ${QUEUE_ID} \
        --queue-configs "QueueReference={QueueId=${QUEUE_ID},Channel=VOICE},Priority=1,Delay=0" \
        --media-concurrencies "Channel=VOICE,Concurrency=1" \
        --output json)
    
    export AGENT_ROUTING_ID=$(echo $AGENT_ROUTING_RESULT | jq -r '.RoutingProfileId')
    update_deployment_state "agent_routing_id" "${AGENT_ROUTING_ID}"
    
    log_info "Creating agent user..."
    
    AGENT_USER_RESULT=$(aws connect create-user \
        --username "service-agent-01" \
        --password "AgentPass123!" \
        --identity-info "FirstName=Service,LastName=Agent" \
        --phone-config "PhoneType=SOFT_PHONE,AutoAccept=true,AfterContactWorkTimeLimit=180" \
        --security-profile-ids ${AGENT_PROFILE_ID} \
        --routing-profile-id ${AGENT_ROUTING_ID} \
        --instance-id ${INSTANCE_ID} \
        --output json)
    
    export AGENT_USER_ID=$(echo $AGENT_USER_RESULT | jq -r '.UserId')
    update_deployment_state "agent_user_id" "${AGENT_USER_ID}"
    
    log_success "Agent user and routing profile created"
    
    # Step 10: Enable CloudWatch metrics and monitoring
    log_info "Enabling CloudWatch metrics and monitoring..."
    
    # Enable contact events for CloudWatch
    aws connect update-instance-attribute \
        --instance-id ${INSTANCE_ID} \
        --attribute-type CONTACTFLOW_LOGS \
        --value true
    
    # Enable Contact Lens for analytics (if available in region)
    aws connect update-instance-attribute \
        --instance-id ${INSTANCE_ID} \
        --attribute-type CONTACT_LENS \
        --value true 2>/dev/null || log_warning "Contact Lens not available in this region"
    
    # Create CloudWatch dashboard
    cat > dashboard-config.json << EOF
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Connect", "ContactsReceived", "InstanceId", "${INSTANCE_ID}"],
          [".", "ContactsHandled", ".", "."],
          [".", "ContactsAbandoned", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "Contact Center Metrics"
      }
    }
  ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "ConnectContactCenter-${RANDOM_SUFFIX}" \
        --dashboard-body file://dashboard-config.json
    
    update_deployment_state "dashboard_name" "ConnectContactCenter-${RANDOM_SUFFIX}"
    
    # Clean up temporary file
    rm -f dashboard-config.json
    
    log_success "CloudWatch monitoring configured"
    
    # Final deployment summary
    log_success "Amazon Connect Contact Center deployment completed successfully!"
    echo
    log_info "Deployment Summary:"
    echo "  Instance ID: ${INSTANCE_ID}"
    echo "  Instance Alias: ${CONNECT_INSTANCE_ALIAS}"
    echo "  S3 Bucket: ${S3_BUCKET_NAME}"
    echo "  Admin User: connect-admin (password: TempPass123!)"
    echo "  Agent User: service-agent-01 (password: AgentPass123!)"
    if [ ! -z "${CONTACT_NUMBER:-}" ]; then
        echo "  Contact Number: ${CONTACT_NUMBER}"
    fi
    echo "  Dashboard: ConnectContactCenter-${RANDOM_SUFFIX}"
    echo
    log_info "Access your Connect instance at:"
    echo "  https://${CONNECT_INSTANCE_ALIAS}.my.connect.aws/connect/login"
    echo
    log_warning "Remember to change default passwords after first login!"
    echo
    log_info "Deployment state saved to: deployment_state.json"
}

# Main execution
main() {
    echo "================================================================"
    echo "Amazon Connect Contact Center Deployment Script"
    echo "================================================================"
    echo
    
    check_prerequisites
    deploy_contact_center
    
    echo
    echo "================================================================"
    echo "Deployment completed successfully!"
    echo "================================================================"
}

# Run main function
main "$@"