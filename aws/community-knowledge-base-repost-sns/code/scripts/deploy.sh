#!/bin/bash

# Community Knowledge Base with re:Post Private and SNS - Deployment Script
# This script automates the deployment of AWS re:Post Private integration with SNS notifications
# Author: AWS Recipes Generator
# Version: 1.0

set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/deploy.log"
readonly CONFIG_FILE="${SCRIPT_DIR}/.deploy_config"

# Default configuration
DEFAULT_TEAM_EMAILS=("admin@example.com")
DRY_RUN=false
VERBOSE=false

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*${NC}" | tee -a "${LOG_FILE}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}" | tee -a "${LOG_FILE}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "${LOG_FILE}"
}

debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*${NC}" | tee -a "${LOG_FILE}"
    fi
}

# Cleanup function for script interruption
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Script interrupted or failed with exit code: $exit_code"
        error "Check the log file for details: ${LOG_FILE}"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Community Knowledge Base with re:Post Private and SNS integration.

OPTIONS:
    -e, --emails EMAIL1,EMAIL2    Comma-separated list of team email addresses
    -n, --dry-run                Run in dry-run mode (show what would be done)
    -v, --verbose                Enable verbose logging
    -h, --help                   Show this help message
    -c, --config FILE            Load configuration from file

EXAMPLES:
    $0 --emails "dev1@company.com,dev2@company.com,lead@company.com"
    $0 --dry-run --verbose
    $0 --config my_config.env

PREREQUISITES:
    - AWS CLI installed and configured
    - AWS Enterprise Support or Enterprise On-Ramp Support plan
    - Organization admin access for re:Post Private
    - Valid email addresses for notifications

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--emails)
                IFS=',' read -ra TEAM_EMAILS <<< "$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -c|--config)
                if [[ -f "$2" ]]; then
                    # shellcheck source=/dev/null
                    source "$2"
                    log "Configuration loaded from: $2"
                else
                    error "Configuration file not found: $2"
                    exit 1
                fi
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Set default team emails if not provided
    if [[ ${#TEAM_EMAILS[@]} -eq 0 ]]; then
        TEAM_EMAILS=("${DEFAULT_TEAM_EMAILS[@]}")
        warn "No team emails provided, using defaults. Use --emails to specify team addresses."
    fi
}

# Validate email addresses
validate_emails() {
    local email_regex='^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    
    for email in "${TEAM_EMAILS[@]}"; do
        if [[ ! $email =~ $email_regex ]]; then
            error "Invalid email address format: $email"
            return 1
        fi
    done
    
    log "Email addresses validated: ${TEAM_EMAILS[*]}"
    return 0
}

# Check prerequisites
check_prerequisites() {
    log "Checking deployment prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        return 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
        return 1
    fi
    
    # Check for Enterprise Support (required for re:Post Private)
    debug "Checking Enterprise Support access..."
    if ! aws support describe-services --language en &> /dev/null; then
        warn "Cannot verify Enterprise Support plan. re:Post Private requires Enterprise Support or Enterprise On-Ramp."
        warn "Please ensure you have the appropriate support plan before proceeding."
        
        if [[ "${DRY_RUN}" == "false" ]]; then
            read -p "Do you want to continue anyway? (y/N): " -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                error "Deployment cancelled by user."
                exit 1
            fi
        fi
    else
        log "Enterprise Support access verified"
    fi
    
    # Validate email addresses
    if ! validate_emails; then
        return 1
    fi
    
    log "Prerequisites check completed successfully"
    return 0
}

# Setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export SNS_TOPIC_NAME="repost-knowledge-notifications-${random_suffix}"
    
    # Save configuration for cleanup script
    cat > "${CONFIG_FILE}" << EOF
# Deployment configuration - Generated $(date)
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export SNS_TOPIC_NAME="${SNS_TOPIC_NAME}"
export DEPLOYMENT_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF
    
    debug "Environment variables configured:"
    debug "  AWS_REGION: ${AWS_REGION}"
    debug "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    debug "  SNS_TOPIC_NAME: ${SNS_TOPIC_NAME}"
    
    log "Environment setup completed"
}

# Create SNS topic for notifications
create_sns_topic() {
    log "Creating SNS topic for knowledge base notifications..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY-RUN] Would create SNS topic: ${SNS_TOPIC_NAME}"
        export TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
        return 0
    fi
    
    # Create SNS topic
    local create_output
    create_output=$(aws sns create-topic --name "${SNS_TOPIC_NAME}" 2>&1) || {
        error "Failed to create SNS topic: $create_output"
        return 1
    }
    
    # Get the topic ARN
    export TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" \
        --output text)
    
    if [[ -z "${TOPIC_ARN}" ]]; then
        error "Failed to retrieve SNS topic ARN"
        return 1
    fi
    
    # Add topic ARN to config file
    echo "export TOPIC_ARN=\"${TOPIC_ARN}\"" >> "${CONFIG_FILE}"
    
    log "✅ SNS topic created successfully: ${TOPIC_ARN}"
    return 0
}

# Subscribe team emails to SNS notifications
subscribe_team_emails() {
    log "Subscribing team email addresses to notifications..."
    
    local subscription_count=0
    local failed_subscriptions=()
    
    for email in "${TEAM_EMAILS[@]}"; do
        if [[ "${DRY_RUN}" == "true" ]]; then
            log "[DRY-RUN] Would subscribe email: ${email}"
            ((subscription_count++))
            continue
        fi
        
        debug "Subscribing email: ${email}"
        
        if aws sns subscribe \
            --topic-arn "${TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${email}" &> /dev/null; then
            log "✅ Subscription created for: ${email}"
            ((subscription_count++))
        else
            error "Failed to subscribe email: ${email}"
            failed_subscriptions+=("${email}")
        fi
    done
    
    # Save subscription info to config
    if [[ "${DRY_RUN}" == "false" ]]; then
        printf 'export SUBSCRIBED_EMAILS=(' >> "${CONFIG_FILE}"
        printf '"%s" ' "${TEAM_EMAILS[@]}" >> "${CONFIG_FILE}"
        printf ')\n' >> "${CONFIG_FILE}"
    fi
    
    if [[ ${#failed_subscriptions[@]} -gt 0 ]]; then
        warn "Failed to subscribe the following emails: ${failed_subscriptions[*]}"
        warn "You may need to subscribe them manually or check their validity"
    fi
    
    if [[ $subscription_count -gt 0 ]]; then
        log "✅ Successfully processed ${subscription_count} email subscriptions"
        if [[ "${DRY_RUN}" == "false" ]]; then
            warn "⚠️  Team members must confirm email subscriptions by clicking links in their email"
        fi
    else
        error "No email subscriptions were successful"
        return 1
    fi
    
    return 0
}

# Display re:Post Private setup information
setup_repost_private() {
    log "Setting up re:Post Private access information..."
    
    # Create configuration files
    local repost_checklist="${SCRIPT_DIR}/repost-config-checklist.txt"
    local content_guide="${SCRIPT_DIR}/content-creation-guide.txt"
    
    cat > "${repost_checklist}" << 'EOF'
re:Post Private Configuration Checklist:

✓ Customize Appearance:
  - Organization title and welcome message
  - Upload company logo (max 2 MiB, 150x50px)
  - Set primary and button colors for branding

✓ Configure Content Management:
  - Create custom tags for internal projects
  - Define custom topics for knowledge organization
  - Set blocked terminology for compliance

✓ Select Knowledge Areas:
  - Choose AWS service topics of interest
  - Configure learning paths and selections
  - Enable curated content for your use cases
EOF
    
    cat > "${content_guide}" << 'EOF'
Initial Content Creation Guidelines:

🚀 Welcome Articles to Create:
  - "Getting Started with Our AWS Environment"
  - "Common Troubleshooting Procedures"
  - "Best Practices for Our Cloud Architecture"
  - "Escalation Procedures and Support Contacts"

💡 Discussion Topics to Start:
  - "Share Your Latest AWS Learning"
  - "Weekly Technical Challenges"
  - "Resource Optimization Tips"
  - "Security Best Practices Discussion"

📊 Content Types to Include:
  - Step-by-step tutorials
  - Architecture decision records
  - Troubleshooting runbooks
  - Learning resource recommendations
EOF
    
    log "Configuration files created:"
    log "  - Configuration checklist: ${repost_checklist}"
    log "  - Content creation guide: ${content_guide}"
    
    log "🔗 Access re:Post Private at: https://console.aws.amazon.com/repost-private/"
    log "📋 Complete the setup using the generated configuration checklist"
    
    return 0
}

# Send test notification
send_test_notification() {
    log "Sending test notification to verify SNS setup..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "[DRY-RUN] Would send test notification to all subscribers"
        return 0
    fi
    
    local test_message="This is a test notification from your enterprise knowledge base system. New discussions and solutions will be shared through this channel to keep everyone informed about valuable AWS insights and troubleshooting discoveries."
    
    if aws sns publish \
        --topic-arn "${TOPIC_ARN}" \
        --subject "Knowledge Base Alert: Test Notification" \
        --message "${test_message}" &> /dev/null; then
        log "✅ Test notification sent successfully"
        log "📧 Team members should check their email for the test message"
    else
        warn "Failed to send test notification. SNS topic may not be ready yet."
        warn "You can test notifications manually after email confirmations are complete."
    fi
    
    return 0
}

# Generate deployment summary
generate_summary() {
    log "Generating deployment summary..."
    
    local summary_file="${SCRIPT_DIR}/deployment-summary.txt"
    
    cat > "${summary_file}" << EOF
Community Knowledge Base Deployment Summary
Generated: $(date)

DEPLOYMENT CONFIGURATION:
- AWS Region: ${AWS_REGION}
- AWS Account ID: ${AWS_ACCOUNT_ID}
- SNS Topic Name: ${SNS_TOPIC_NAME}
- SNS Topic ARN: ${TOPIC_ARN:-"Not created (dry-run)"}

SUBSCRIBED EMAILS:
$(printf '  - %s\n' "${TEAM_EMAILS[@]}")

NEXT STEPS:
1. Team members must confirm email subscriptions
2. Access re:Post Private at: https://console.aws.amazon.com/repost-private/
3. Complete initial configuration using the checklist
4. Create initial knowledge content
5. Test the notification system

CONFIGURATION FILES:
- Deployment config: ${CONFIG_FILE}
- re:Post checklist: ${SCRIPT_DIR}/repost-config-checklist.txt
- Content guide: ${SCRIPT_DIR}/content-creation-guide.txt
- This summary: ${summary_file}

CLEANUP:
To remove all resources, run: ./destroy.sh

EOF
    
    log "✅ Deployment summary saved to: ${summary_file}"
}

# Main deployment function
main() {
    log "Starting Community Knowledge Base deployment..."
    log "Script version: 1.0"
    log "Log file: ${LOG_FILE}"
    
    # Parse command line arguments
    parse_arguments "$@"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        log "🧪 Running in DRY-RUN mode - no resources will be created"
    fi
    
    # Execute deployment steps
    check_prerequisites || exit 1
    setup_environment || exit 1
    create_sns_topic || exit 1
    subscribe_team_emails || exit 1
    setup_repost_private || exit 1
    send_test_notification || exit 1
    generate_summary || exit 1
    
    log "🎉 Community Knowledge Base deployment completed successfully!"
    
    if [[ "${DRY_RUN}" == "false" ]]; then
        log ""
        log "IMPORTANT NEXT STEPS:"
        log "1. Team members must confirm their email subscriptions"
        log "2. Access re:Post Private console to complete setup"
        log "3. Follow the configuration checklist to customize your instance"
        log "4. Create initial content using the content creation guide"
        log ""
        log "📊 View deployment summary: ${SCRIPT_DIR}/deployment-summary.txt"
    fi
}

# Run main function with all arguments
main "$@"