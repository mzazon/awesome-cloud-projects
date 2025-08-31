#!/bin/bash

# SSL Certificate Monitoring Deployment Script
# This script deploys SSL certificate monitoring using ACM, CloudWatch, and SNS
# Version: 1.0
# Last Updated: 2025-07-12

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic test)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [[ -z "$account_id" ]]; then
        error "Unable to retrieve AWS account information. Check your credentials."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Function to validate email address format
validate_email() {
    local email=$1
    if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        error "Invalid email address format: $email"
        exit 1
    fi
}

# Function to prompt for email if not provided
get_notification_email() {
    if [[ -z "${NOTIFICATION_EMAIL}" ]]; then
        echo -n "Enter your email address for notifications: "
        read -r NOTIFICATION_EMAIL
        export NOTIFICATION_EMAIL
    fi
    
    validate_email "${NOTIFICATION_EMAIL}"
    log "Using email address: ${NOTIFICATION_EMAIL}"
}

# Function to setup environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No default region found, using us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set resource names
    export SNS_TOPIC_NAME="ssl-cert-alerts-${RANDOM_SUFFIX}"
    export ALARM_NAME="SSL-Certificate-Expiring-${RANDOM_SUFFIX}"
    
    # Get notification email
    get_notification_email
    
    success "Environment configured - Region: ${AWS_REGION}, Account: ${AWS_ACCOUNT_ID}"
}

# Function to create SNS topic
create_sns_topic() {
    log "Creating SNS topic for certificate alerts..."
    
    # Check if topic already exists
    local existing_topic
    existing_topic=$(aws sns list-topics --query "Topics[?contains(TopicArn, '${SNS_TOPIC_NAME}')].TopicArn" --output text)
    
    if [[ -n "$existing_topic" ]]; then
        warning "SNS topic already exists: $existing_topic"
        export SNS_TOPIC_ARN="$existing_topic"
    else
        # Create new SNS topic
        export SNS_TOPIC_ARN=$(aws sns create-topic \
            --name "${SNS_TOPIC_NAME}" \
            --query TopicArn --output text)
        
        if [[ -z "$SNS_TOPIC_ARN" ]]; then
            error "Failed to create SNS topic"
            exit 1
        fi
        
        success "SNS topic created: ${SNS_TOPIC_ARN}"
    fi
    
    # Add tags to the topic
    aws sns tag-resource \
        --resource-arn "${SNS_TOPIC_ARN}" \
        --tags Key=Purpose,Value=SSLCertificateMonitoring \
               Key=Environment,Value=Production \
               Key=ManagedBy,Value=DeploymentScript &> /dev/null || true
}

# Function to subscribe email to SNS topic
subscribe_email() {
    log "Subscribing email to SNS topic..."
    
    # Check if subscription already exists
    local existing_subscription
    existing_subscription=$(aws sns list-subscriptions-by-topic \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --query "Subscriptions[?Endpoint=='${NOTIFICATION_EMAIL}'].SubscriptionArn" \
        --output text)
    
    if [[ -n "$existing_subscription" && "$existing_subscription" != "PendingConfirmation" ]]; then
        warning "Email subscription already exists and confirmed"
    else
        # Create email subscription
        aws sns subscribe \
            --topic-arn "${SNS_TOPIC_ARN}" \
            --protocol email \
            --notification-endpoint "${NOTIFICATION_EMAIL}" > /dev/null
        
        success "Email subscription created - please check your inbox and confirm"
        warning "IMPORTANT: You must confirm the email subscription to receive alerts!"
    fi
}

# Function to get SSL certificates
get_certificates() {
    log "Retrieving SSL certificates..."
    
    # List all issued certificates
    local cert_count
    cert_count=$(aws acm list-certificates \
        --certificate-statuses ISSUED \
        --query 'length(CertificateSummaryList)' --output text)
    
    if [[ "$cert_count" -eq 0 ]]; then
        error "No issued SSL certificates found in AWS Certificate Manager"
        echo "Please create at least one SSL certificate before running this script."
        exit 1
    fi
    
    log "Found ${cert_count} SSL certificate(s)"
    
    # Display certificates
    aws acm list-certificates \
        --certificate-statuses ISSUED \
        --query 'CertificateSummaryList[*].[CertificateArn,DomainName]' \
        --output table
    
    # Get the first certificate for monitoring
    export CERTIFICATE_ARN=$(aws acm list-certificates \
        --certificate-statuses ISSUED \
        --query 'CertificateSummaryList[0].CertificateArn' \
        --output text)
    
    if [[ -z "$CERTIFICATE_ARN" ]]; then
        error "Failed to retrieve certificate ARN"
        exit 1
    fi
    
    local domain_name
    domain_name=$(aws acm describe-certificate \
        --certificate-arn "${CERTIFICATE_ARN}" \
        --query 'Certificate.DomainName' --output text)
    
    success "Selected certificate for monitoring: ${domain_name}"
}

# Function to create CloudWatch alarm
create_cloudwatch_alarm() {
    log "Creating CloudWatch alarm for certificate expiration..."
    
    # Check if alarm already exists
    local existing_alarm
    existing_alarm=$(aws cloudwatch describe-alarms \
        --alarm-names "${ALARM_NAME}" \
        --query 'MetricAlarms[0].AlarmArn' --output text 2>/dev/null)
    
    if [[ -n "$existing_alarm" && "$existing_alarm" != "None" ]]; then
        warning "CloudWatch alarm already exists: ${ALARM_NAME}"
    else
        # Create CloudWatch alarm
        aws cloudwatch put-metric-alarm \
            --alarm-name "${ALARM_NAME}" \
            --alarm-description "Alert when SSL certificate expires in 30 days" \
            --metric-name DaysToExpiry \
            --namespace AWS/CertificateManager \
            --statistic Minimum \
            --period 86400 \
            --threshold 30 \
            --comparison-operator LessThanThreshold \
            --dimensions Name=CertificateArn,Value="${CERTIFICATE_ARN}" \
            --evaluation-periods 1 \
            --alarm-actions "${SNS_TOPIC_ARN}" \
            --treat-missing-data notBreaching \
            --tags Key=Purpose,Value=SSLCertificateMonitoring \
                   Key=Environment,Value=Production \
                   Key=ManagedBy,Value=DeploymentScript
        
        success "CloudWatch alarm created: ${ALARM_NAME}"
    fi
}

# Function to create additional alarms for all certificates
create_all_certificate_alarms() {
    log "Creating alarms for all certificates (optional)..."
    
    local cert_count=0
    
    # Process each certificate
    aws acm list-certificates \
        --certificate-statuses ISSUED \
        --query 'CertificateSummaryList[].CertificateArn' \
        --output text | tr '\t' '\n' | while read -r cert_arn; do
        
        if [[ -z "$cert_arn" ]]; then
            continue
        fi
        
        # Get domain name for the certificate
        local domain_name
        domain_name=$(aws acm describe-certificate \
            --certificate-arn "$cert_arn" \
            --query 'Certificate.DomainName' --output text)
        
        # Clean domain name for alarm name (replace dots and wildcards)
        local clean_domain
        clean_domain=$(echo "$domain_name" | sed 's/\*//g' | sed 's/\./-/g')
        local alarm_name="SSL-${clean_domain}-Expiring-${RANDOM_SUFFIX}"
        
        # Check if alarm already exists
        local existing_alarm
        existing_alarm=$(aws cloudwatch describe-alarms \
            --alarm-names "$alarm_name" \
            --query 'MetricAlarms[0].AlarmArn' --output text 2>/dev/null)
        
        if [[ -n "$existing_alarm" && "$existing_alarm" != "None" ]]; then
            log "Alarm already exists for ${domain_name}"
        else
            # Create alarm for this certificate
            aws cloudwatch put-metric-alarm \
                --alarm-name "$alarm_name" \
                --alarm-description "Alert for ${domain_name} certificate expiration" \
                --metric-name DaysToExpiry \
                --namespace AWS/CertificateManager \
                --statistic Minimum \
                --period 86400 \
                --threshold 30 \
                --comparison-operator LessThanThreshold \
                --dimensions Name=CertificateArn,Value="$cert_arn" \
                --evaluation-periods 1 \
                --alarm-actions "${SNS_TOPIC_ARN}" \
                --treat-missing-data notBreaching \
                --tags Key=Purpose,Value=SSLCertificateMonitoring \
                       Key=Certificate,Value="$domain_name" \
                       Key=Environment,Value=Production \
                       Key=ManagedBy,Value=DeploymentScript
            
            success "Monitoring configured for certificate: ${domain_name}"
        fi
        
        ((cert_count++))
    done
    
    log "Processed ${cert_count} certificates for monitoring"
}

# Function to verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    # Check SNS topic
    local topic_exists
    topic_exists=$(aws sns get-topic-attributes \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --query 'Attributes.TopicArn' --output text 2>/dev/null)
    
    if [[ "$topic_exists" == "${SNS_TOPIC_ARN}" ]]; then
        success "SNS topic verified: ${SNS_TOPIC_NAME}"
    else
        error "SNS topic verification failed"
        return 1
    fi
    
    # Check CloudWatch alarm
    local alarm_state
    alarm_state=$(aws cloudwatch describe-alarms \
        --alarm-names "${ALARM_NAME}" \
        --query 'MetricAlarms[0].StateValue' --output text 2>/dev/null)
    
    if [[ -n "$alarm_state" ]]; then
        success "CloudWatch alarm verified: ${ALARM_NAME} (State: ${alarm_state})"
    else
        error "CloudWatch alarm verification failed"
        return 1
    fi
    
    # Test SNS notification
    log "Sending test notification..."
    aws sns publish \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --message "Test: SSL Certificate Monitoring System Active - Deployment completed successfully" \
        --subject "SSL Certificate Alert Test - System Ready" > /dev/null
    
    success "Test notification sent"
}

# Function to save deployment information
save_deployment_info() {
    local info_file="./deployment-info.txt"
    
    log "Saving deployment information to ${info_file}..."
    
    cat > "$info_file" << EOF
SSL Certificate Monitoring Deployment Information
================================================
Deployment Date: $(date)
AWS Region: ${AWS_REGION}
AWS Account ID: ${AWS_ACCOUNT_ID}

Resources Created:
-----------------
SNS Topic Name: ${SNS_TOPIC_NAME}
SNS Topic ARN: ${SNS_TOPIC_ARN}
CloudWatch Alarm: ${ALARM_NAME}
Notification Email: ${NOTIFICATION_EMAIL}
Monitored Certificate: ${CERTIFICATE_ARN}

Cleanup Command:
---------------
./destroy.sh

Notes:
------
- Don't forget to confirm your email subscription
- Alarms will trigger when certificates have less than 30 days remaining
- Check CloudWatch console for alarm status and history
EOF
    
    success "Deployment information saved to ${info_file}"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "SSL Certificate Monitoring Deployment"
    echo "=========================================="
    echo
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_sns_topic
    subscribe_email
    get_certificates
    create_cloudwatch_alarm
    
    # Ask if user wants to monitor all certificates
    echo
    echo -n "Do you want to create alarms for ALL certificates? (y/N): "
    read -r create_all
    if [[ "$create_all" =~ ^[Yy]$ ]]; then
        create_all_certificate_alarms
    fi
    
    verify_deployment
    save_deployment_info
    
    echo
    echo "=========================================="
    success "Deployment completed successfully!"
    echo "=========================================="
    echo
    echo "Next Steps:"
    echo "1. Check your email and confirm the SNS subscription"
    echo "2. Monitor CloudWatch console for alarm status"
    echo "3. Certificates will be monitored for expiration (30-day threshold)"
    echo
    echo "Resources created:"
    echo "- SNS Topic: ${SNS_TOPIC_NAME}"
    echo "- CloudWatch Alarm: ${ALARM_NAME}"
    echo "- Email subscription for: ${NOTIFICATION_EMAIL}"
    echo
    echo "To clean up resources, run: ./destroy.sh"
    echo
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi