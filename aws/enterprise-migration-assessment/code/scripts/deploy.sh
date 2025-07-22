#!/bin/bash

# Enterprise Migration Assessment with AWS Application Discovery Service - Deployment Script
# This script automates the deployment of AWS Application Discovery Service for enterprise migration assessment

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DEPLOYMENT_STATE_FILE="${SCRIPT_DIR}/.deployment_state"

# Function to log messages with timestamp
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

# Function to log and display colored messages
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    log "INFO" "$*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    log "SUCCESS" "$*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
    log "WARNING" "$*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    log "ERROR" "$*"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI and credentials
validate_aws_setup() {
    log_info "Validating AWS CLI setup and credentials..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: ${aws_version}"
    
    # Test AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS credentials not configured or invalid. Run 'aws configure' first."
        exit 1
    fi
    
    # Get account info
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    if [[ -z "${AWS_REGION}" ]]; then
        log_error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    log_success "AWS setup validated. Account: ${ACCOUNT_ID}, Region: ${AWS_REGION}"
}

# Function to check required permissions
check_permissions() {
    log_info "Checking required AWS permissions..."
    
    local required_permissions=(
        "application-discovery"
        "migrationhub"
        "s3"
        "logs"
        "events"
        "secretsmanager"
    )
    
    local permission_check_failed=false
    
    for permission in "${required_permissions[@]}"; do
        case $permission in
            "application-discovery")
                if ! aws discovery describe-configurations --configuration-type SERVER >/dev/null 2>&1; then
                    if [[ $? -ne 255 ]]; then  # 255 means permission denied, other codes might be acceptable
                        log_warning "Application Discovery Service permissions may be limited"
                    fi
                fi
                ;;
            "migrationhub")
                if ! aws migrationhub list-progress-update-streams --region us-west-2 >/dev/null 2>&1; then
                    if [[ $? -eq 255 ]]; then
                        log_warning "Migration Hub permissions may be limited"
                    fi
                fi
                ;;
            "s3")
                if ! aws s3 ls >/dev/null 2>&1; then
                    log_error "S3 permissions required but not available"
                    permission_check_failed=true
                fi
                ;;
            "logs")
                if ! aws logs describe-log-groups --limit 1 >/dev/null 2>&1; then
                    log_warning "CloudWatch Logs permissions may be limited"
                fi
                ;;
        esac
    done
    
    if [[ "$permission_check_failed" == "true" ]]; then
        log_error "Critical permissions missing. Please ensure your IAM role/user has necessary permissions."
        exit 1
    fi
    
    log_success "Permission check completed"
}

# Function to generate unique resource names
generate_resource_names() {
    log_info "Generating unique resource names..."
    
    # Generate random suffix for unique naming
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || openssl rand -hex 3)
    
    # Set resource names
    export MIGRATION_PROJECT_NAME="enterprise-migration-${RANDOM_SUFFIX}"
    export S3_BUCKET_NAME="migration-discovery-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/discovery/${MIGRATION_PROJECT_NAME}"
    export EVENTBRIDGE_RULE_NAME="weekly-discovery-export"
    
    log_success "Resource names generated:"
    log_info "  Migration Project: ${MIGRATION_PROJECT_NAME}"
    log_info "  S3 Bucket: ${S3_BUCKET_NAME}"
    log_info "  Log Group: ${LOG_GROUP_NAME}"
    
    # Save deployment state
    cat > "${DEPLOYMENT_STATE_FILE}" << EOF
AWS_REGION=${AWS_REGION}
ACCOUNT_ID=${ACCOUNT_ID}
MIGRATION_PROJECT_NAME=${MIGRATION_PROJECT_NAME}
S3_BUCKET_NAME=${S3_BUCKET_NAME}
LOG_GROUP_NAME=${LOG_GROUP_NAME}
EVENTBRIDGE_RULE_NAME=${EVENTBRIDGE_RULE_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
DEPLOYMENT_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
EOF
}

# Function to create S3 bucket
create_s3_bucket() {
    log_info "Creating S3 bucket for discovery data export..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" >/dev/null 2>&1; then
        log_warning "S3 bucket ${S3_BUCKET_NAME} already exists, skipping creation"
        return 0
    fi
    
    # Create bucket
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb "s3://${S3_BUCKET_NAME}"
    else
        aws s3 mb "s3://${S3_BUCKET_NAME}" --region "${AWS_REGION}"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${S3_BUCKET_NAME}" \
        --versioning-configuration Status=Enabled
    
    # Enable server-side encryption
    aws s3api put-bucket-encryption \
        --bucket "${S3_BUCKET_NAME}" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "${S3_BUCKET_NAME}" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    log_success "S3 bucket ${S3_BUCKET_NAME} created with security configurations"
}

# Function to enable Application Discovery Service
enable_discovery_service() {
    log_info "Enabling AWS Application Discovery Service..."
    
    # Try to enable the service by starting data collection
    # This is idempotent - if already enabled, it won't cause issues
    if aws discovery start-data-collection-by-agent-ids --agent-ids [] >/dev/null 2>&1; then
        log_success "Application Discovery Service enabled successfully"
    else
        # Check if service is already enabled by trying to describe configurations
        if aws discovery describe-configurations --configuration-type SERVER >/dev/null 2>&1; then
            log_success "Application Discovery Service is already enabled"
        else
            log_warning "Could not verify Application Discovery Service status. Manual verification may be needed."
        fi
    fi
    
    # Wait a moment for service to initialize
    sleep 2
}

# Function to create Migration Hub project
create_migration_hub_project() {
    log_info "Creating Migration Hub project..."
    
    # Set Migration Hub home region (us-west-2 is the primary hub region)
    local hub_region="us-west-2"
    
    # Create progress update stream
    if aws migrationhub create-progress-update-stream \
        --progress-update-stream-name "${MIGRATION_PROJECT_NAME}" \
        --region "${hub_region}" >/dev/null 2>&1; then
        log_success "Migration Hub progress stream created: ${MIGRATION_PROJECT_NAME}"
    else
        # Check if it already exists
        if aws migrationhub list-progress-update-streams \
            --region "${hub_region}" \
            --query "ProgressUpdateStreamSummaryList[?ProgressUpdateStreamName=='${MIGRATION_PROJECT_NAME}']" \
            --output text | grep -q "${MIGRATION_PROJECT_NAME}"; then
            log_success "Migration Hub progress stream already exists: ${MIGRATION_PROJECT_NAME}"
        else
            log_warning "Could not create Migration Hub progress stream. Manual setup may be required."
        fi
    fi
}

# Function to create CloudWatch Log Group
create_log_group() {
    log_info "Creating CloudWatch Log Group..."
    
    # Check if log group already exists
    if aws logs describe-log-groups \
        --log-group-name-prefix "${LOG_GROUP_NAME}" \
        --query "logGroups[?logGroupName=='${LOG_GROUP_NAME}']" \
        --output text | grep -q "${LOG_GROUP_NAME}"; then
        log_success "CloudWatch Log Group already exists: ${LOG_GROUP_NAME}"
        return 0
    fi
    
    # Create log group
    aws logs create-log-group --log-group-name "${LOG_GROUP_NAME}"
    
    # Set retention policy (30 days)
    aws logs put-retention-policy \
        --log-group-name "${LOG_GROUP_NAME}" \
        --retention-in-days 30
    
    log_success "CloudWatch Log Group created: ${LOG_GROUP_NAME}"
}

# Function to start continuous export
start_continuous_export() {
    log_info "Starting continuous data export to S3..."
    
    # Start continuous export for agent data
    local export_result
    export_result=$(aws discovery start-continuous-export \
        --s3-bucket "${S3_BUCKET_NAME}" \
        --s3-prefix "discovery-data/" \
        --data-source AGENT 2>&1)
    
    if [[ $? -eq 0 ]]; then
        local export_id
        export_id=$(echo "${export_result}" | grep -o '"exportId":"[^"]*"' | cut -d'"' -f4)
        echo "CONTINUOUS_EXPORT_ID=${export_id}" >> "${DEPLOYMENT_STATE_FILE}"
        log_success "Continuous export started with ID: ${export_id}"
    else
        if echo "${export_result}" | grep -q "already.*export.*running"; then
            log_success "Continuous export is already running"
        else
            log_warning "Could not start continuous export: ${export_result}"
        fi
    fi
}

# Function to create configuration files
create_config_files() {
    log_info "Creating configuration files..."
    
    # Create agent configuration
    cat > "${SCRIPT_DIR}/agent-config.json" << EOF
{
    "region": "${AWS_REGION}",
    "enableSSL": true,
    "collectionConfiguration": {
        "collectProcesses": true,
        "collectNetworkConnections": true,
        "collectPerformanceData": true
    }
}
EOF
    
    # Create connector configuration template
    cat > "${SCRIPT_DIR}/connector-config.json" << EOF
{
    "connectorName": "enterprise-connector-${RANDOM_SUFFIX}",
    "awsRegion": "${AWS_REGION}",
    "vCenterDetails": {
        "hostname": "vcenter.example.com",
        "username": "discovery-user",
        "enableSSL": true
    },
    "dataCollectionPreferences": {
        "collectVMMetrics": true,
        "collectNetworkInfo": true,
        "collectPerformanceData": true
    }
}
EOF
    
    # Create migration wave planning template
    cat > "${SCRIPT_DIR}/migration-waves.json" << EOF
{
    "waves": [
        {
            "waveNumber": 1,
            "name": "Pilot Wave - Low Risk Applications",
            "description": "Standalone applications with minimal dependencies",
            "targetMigrationDate": "2024-Q2"
        },
        {
            "waveNumber": 2,
            "name": "Business Applications Wave",
            "description": "Core business applications with managed dependencies",
            "targetMigrationDate": "2024-Q3"
        },
        {
            "waveNumber": 3,
            "name": "Legacy Systems Wave",
            "description": "Complex legacy systems requiring refactoring",
            "targetMigrationDate": "2024-Q4"
        }
    ]
}
EOF
    
    # Upload planning file to S3
    aws s3 cp "${SCRIPT_DIR}/migration-waves.json" \
        "s3://${S3_BUCKET_NAME}/planning/migration-waves.json"
    
    log_success "Configuration files created in ${SCRIPT_DIR}"
}

# Function to setup EventBridge for automated exports
setup_eventbridge_automation() {
    log_info "Setting up EventBridge for automated weekly exports..."
    
    # Create EventBridge rule for weekly exports
    aws events put-rule \
        --name "${EVENTBRIDGE_RULE_NAME}" \
        --schedule-expression "rate(7 days)" \
        --state ENABLED \
        --description "Weekly automated discovery data export" >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        log_success "EventBridge rule created: ${EVENTBRIDGE_RULE_NAME}"
    else
        log_warning "Could not create EventBridge rule for automated exports"
    fi
}

# Function to perform initial export
perform_initial_export() {
    log_info "Performing initial discovery data export..."
    
    # Start export task
    local export_result
    export_result=$(aws discovery start-export-task \
        --export-data-format CSV \
        --filters 'name=AgentId,values=*,condition=EQUALS' \
        --s3-bucket "${S3_BUCKET_NAME}" \
        --s3-prefix "exports/" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        local export_id
        export_id=$(echo "${export_result}" | grep -o '"exportId":"[^"]*"' | cut -d'"' -f4)
        echo "INITIAL_EXPORT_ID=${export_id}" >> "${DEPLOYMENT_STATE_FILE}"
        log_success "Initial export started with ID: ${export_id}"
        log_info "Export status can be checked with: aws discovery describe-export-tasks --export-ids ${export_id}"
    else
        log_warning "Could not start initial export: ${export_result}"
    fi
}

# Function to display deployment summary
display_deployment_summary() {
    echo
    log_success "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
    echo
    log_info "Resources created:"
    log_info "  • S3 Bucket: ${S3_BUCKET_NAME}"
    log_info "  • Migration Project: ${MIGRATION_PROJECT_NAME}"
    log_info "  • CloudWatch Log Group: ${LOG_GROUP_NAME}"
    log_info "  • Configuration files in: ${SCRIPT_DIR}"
    echo
    log_info "Next Steps:"
    log_info "  1. Download and install Discovery Agents:"
    log_info "     Windows: https://aws-discovery-agent.s3.amazonaws.com/windows/latest/AWSApplicationDiscoveryAgentInstaller.exe"
    log_info "     Linux: https://aws-discovery-agent.s3.amazonaws.com/linux/latest/aws-discovery-agent.tar.gz"
    echo
    log_info "  2. For VMware environments, download Discovery Connector OVA:"
    log_info "     https://aws-discovery-connector.s3.amazonaws.com/VMware/latest/AWS-Discovery-Connector.ova"
    echo
    log_info "  3. Configure and deploy agents/connectors using the generated config files"
    echo
    log_info "  4. Monitor agent health with:"
    log_info "     aws discovery describe-agents"
    echo
    log_info "  5. Track discovery progress in Migration Hub console (us-west-2 region)"
    echo
    log_warning "IMPORTANT: Let discovery run for at least 2 weeks for comprehensive data collection"
    echo
    log_info "Deployment state saved to: ${DEPLOYMENT_STATE_FILE}"
    log_info "Deployment log saved to: ${LOG_FILE}"
}

# Function to handle cleanup on script exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Deployment failed with exit code: ${exit_code}"
        log_info "Check the log file for details: ${LOG_FILE}"
        log_info "To clean up partial deployment, run: ./destroy.sh"
    fi
}

# Main deployment function
main() {
    echo "=============================================================="
    echo "  AWS Application Discovery Service Deployment Script"
    echo "  Enterprise Migration Assessment"
    echo "=============================================================="
    echo
    
    # Setup trap for cleanup
    trap cleanup_on_exit EXIT
    
    # Initialize log file
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] Starting deployment..." > "${LOG_FILE}"
    
    # Run deployment steps
    validate_aws_setup
    check_permissions
    generate_resource_names
    create_s3_bucket
    enable_discovery_service
    create_migration_hub_project
    create_log_group
    start_continuous_export
    create_config_files
    setup_eventbridge_automation
    perform_initial_export
    display_deployment_summary
    
    log_success "Deployment completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi