#!/bin/bash

# Deploy script for DNS Security Monitoring with Route 53 Resolver DNS Firewall and CloudWatch
# This script implements automated DNS security monitoring with comprehensive threat detection

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
STACK_NAME="dns-security-monitoring"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }

# Error handler
error_handler() {
    local line_number=$1
    error "Script failed at line ${line_number}"
    error "Check ${LOG_FILE} for detailed error information"
    exit 1
}

trap 'error_handler ${LINENO}' ERR

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version (require v2)
    local aws_version=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2 | cut -d'.' -f1)
    if [ "${aws_version}" -lt 2 ]; then
        error "AWS CLI v2 or higher is required. Current version: $(aws --version)"
        exit 1
    fi
    
    # Check if authenticated with AWS
    if ! aws sts get-caller-identity &> /dev/null; then
        error "Not authenticated with AWS. Please run 'aws configure' or set credentials."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Installing jq for JSON processing..."
        if command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v brew &> /dev/null; then
            brew install jq
        else
            error "Could not install jq. Please install it manually."
            exit 1
        fi
    fi
    
    success "Prerequisites check completed successfully"
}

# Function to initialize environment variables
initialize_environment() {
    info "Initializing environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION="us-east-1"
        warn "No AWS region configured, using default: ${AWS_REGION}"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Get default VPC ID
    export VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=is-default,Values=true" \
        --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")
    
    if [ "${VPC_ID}" == "None" ] || [ -z "${VPC_ID}" ]; then
        # Get first available VPC if no default VPC exists
        export VPC_ID=$(aws ec2 describe-vpcs \
            --query "Vpcs[0].VpcId" --output text 2>/dev/null || echo "")
        
        if [ "${VPC_ID}" == "None" ] || [ -z "${VPC_ID}" ]; then
            error "No VPC found. Please create a VPC first."
            exit 1
        fi
        warn "No default VPC found. Using VPC: ${VPC_ID}"
    fi
    
    info "Environment initialized:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
    info "  VPC ID: ${VPC_ID}"
}

# Function to create SNS topic
create_sns_topic() {
    info "Creating SNS topic for DNS security alerts..."
    
    aws sns create-topic \
        --name "dns-security-alerts-${RANDOM_SUFFIX}" \
        --tags Key=Project,Value=DNSSecurityMonitoring Key=Environment,Value=Production \
        > /dev/null
    
    export SNS_TOPIC_ARN=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'dns-security-alerts-${RANDOM_SUFFIX}')].TopicArn" \
        --output text)
    
    success "SNS topic created: ${SNS_TOPIC_ARN}"
}

# Function to create DNS Firewall domain list
create_firewall_domain_list() {
    info "Creating DNS Firewall domain list for malicious domains..."
    
    aws route53resolver create-firewall-domain-list \
        --creator-request-id "dns-security-${RANDOM_SUFFIX}" \
        --name "malicious-domains-${RANDOM_SUFFIX}" \
        --tags Key=Project,Value=DNSSecurityMonitoring Key=Environment,Value=Production \
        > /dev/null
    
    # Wait for domain list to be created
    info "Waiting for domain list creation..."
    sleep 10
    
    export DOMAIN_LIST_ID=$(aws route53resolver list-firewall-domain-lists \
        --query "FirewallDomainLists[?Name=='malicious-domains-${RANDOM_SUFFIX}'].Id" \
        --output text)
    
    # Add sample malicious domains
    aws route53resolver update-firewall-domains \
        --firewall-domain-list-id "${DOMAIN_LIST_ID}" \
        --operation ADD \
        --domains malware.example suspicious.tk phishing.com badactor.ru cryptominer.xyz botnet.info \
        > /dev/null
    
    success "Domain list created with ID: ${DOMAIN_LIST_ID}"
}

# Function to create DNS Firewall rule group
create_firewall_rule_group() {
    info "Creating DNS Firewall rule group with security rules..."
    
    aws route53resolver create-firewall-rule-group \
        --creator-request-id "rule-group-${RANDOM_SUFFIX}" \
        --name "dns-security-rules-${RANDOM_SUFFIX}" \
        --tags Key=Project,Value=DNSSecurityMonitoring Key=Environment,Value=Production \
        > /dev/null
    
    # Wait for rule group to be created
    info "Waiting for rule group creation..."
    sleep 10
    
    export RULE_GROUP_ID=$(aws route53resolver list-firewall-rule-groups \
        --query "FirewallRuleGroups[?Name=='dns-security-rules-${RANDOM_SUFFIX}'].Id" \
        --output text)
    
    # Create blocking rule for malicious domains
    aws route53resolver create-firewall-rule \
        --name "block-malicious-domains" \
        --firewall-rule-group-id "${RULE_GROUP_ID}" \
        --firewall-domain-list-id "${DOMAIN_LIST_ID}" \
        --priority 100 \
        --action BLOCK \
        --block-response NXDOMAIN \
        > /dev/null
    
    success "DNS Firewall rule group created: ${RULE_GROUP_ID}"
}

# Function to associate firewall with VPC
associate_firewall_with_vpc() {
    info "Associating DNS Firewall rule group with VPC..."
    
    aws route53resolver associate-firewall-rule-group \
        --name "vpc-dns-security-${RANDOM_SUFFIX}" \
        --firewall-rule-group-id "${RULE_GROUP_ID}" \
        --vpc-id "${VPC_ID}" \
        --priority 101 \
        --tags Key=Project,Value=DNSSecurityMonitoring Key=Environment,Value=Production \
        > /dev/null
    
    export ASSOCIATION_ID=$(aws route53resolver list-firewall-rule-group-associations \
        --query "FirewallRuleGroupAssociations[?VpcId=='${VPC_ID}'].Id" \
        --output text)
    
    success "DNS Firewall associated with VPC: ${ASSOCIATION_ID}"
}

# Function to create CloudWatch log group
create_cloudwatch_log_group() {
    info "Creating CloudWatch log group for DNS query analysis..."
    
    export LOG_GROUP_NAME="/aws/route53resolver/dns-security-${RANDOM_SUFFIX}"
    
    aws logs create-log-group \
        --log-group-name "${LOG_GROUP_NAME}" \
        --retention-in-days 30 \
        --tags Project=DNSSecurityMonitoring,Environment=Production \
        > /dev/null
    
    # Create log stream
    aws logs create-log-stream \
        --log-group-name "${LOG_GROUP_NAME}" \
        --log-stream-name "dns-firewall-queries-$(date +%Y%m%d)" \
        > /dev/null
    
    success "CloudWatch log group created: ${LOG_GROUP_NAME}"
}

# Function to enable DNS query logging
enable_dns_query_logging() {
    info "Enabling DNS query logging configuration..."
    
    aws route53resolver put-resolver-query-log-config \
        --name "dns-security-logs-${RANDOM_SUFFIX}" \
        --destination-arn "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}" \
        --tags Key=Project,Value=DNSSecurityMonitoring Key=Environment,Value=Production \
        > /dev/null
    
    export QUERY_LOG_CONFIG_ID=$(aws route53resolver list-resolver-query-log-configs \
        --query "ResolverQueryLogConfigs[?Name=='dns-security-logs-${RANDOM_SUFFIX}'].Id" \
        --output text)
    
    # Associate query logging with VPC
    aws route53resolver associate-resolver-query-log-config \
        --resolver-query-log-config-id "${QUERY_LOG_CONFIG_ID}" \
        --resource-id "${VPC_ID}" \
        > /dev/null
    
    success "DNS query logging enabled for VPC: ${VPC_ID}"
}

# Function to create Lambda function
create_lambda_function() {
    info "Creating Lambda function for automated threat response..."
    
    # Create IAM role for Lambda
    local trust_policy=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
    
    aws iam create-role \
        --role-name "dns-security-lambda-role-${RANDOM_SUFFIX}" \
        --assume-role-policy-document "${trust_policy}" \
        --tags Key=Project,Value=DNSSecurityMonitoring Key=Environment,Value=Production \
        > /dev/null
    
    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "dns-security-lambda-role-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
        > /dev/null
    
    # Wait for role to be propagated
    info "Waiting for IAM role propagation..."
    sleep 15
    
    # Create Lambda function code
    local lambda_code_dir="${SCRIPT_DIR}/../lambda"
    mkdir -p "${lambda_code_dir}"
    
    cat > "${lambda_code_dir}/dns-security-function.py" << 'EOF'
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    try:
        # Parse CloudWatch alarm data
        message = json.loads(event['Records'][0]['Sns']['Message'])
        alarm_name = message['AlarmName']
        alarm_description = message['AlarmDescription']
        metric_name = message['Trigger']['MetricName']
        
        # Create detailed alert message
        alert_message = f"""
DNS Security Alert Triggered

Alarm: {alarm_name}
Description: {alarm_description}
Metric: {metric_name}
Timestamp: {datetime.now().isoformat()}
Account: {context.invoked_function_arn.split(':')[4]}
Region: {context.invoked_function_arn.split(':')[3]}

Recommended Actions:
1. Review DNS query logs for suspicious patterns
2. Investigate source IP addresses and instances
3. Update DNS Firewall rules if needed
4. Consider blocking additional domains or IP ranges

This alert was generated automatically by the DNS Security Monitoring system.
"""
        
        # Log the event for audit trail
        logger.info(f"DNS security event processed: {alarm_name}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'DNS security alert processed successfully',
                'alarm': alarm_name
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing DNS security alert: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF
    
    # Package Lambda function
    cd "${lambda_code_dir}"
    zip -q dns-security-function.zip dns-security-function.py
    cd "${SCRIPT_DIR}"
    
    # Create Lambda function
    aws lambda create-function \
        --function-name "dns-security-response-${RANDOM_SUFFIX}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${AWS_ACCOUNT_ID}:role/dns-security-lambda-role-${RANDOM_SUFFIX}" \
        --handler dns-security-function.lambda_handler \
        --zip-file "fileb://${lambda_code_dir}/dns-security-function.zip" \
        --timeout 60 \
        --memory-size 256 \
        --tags Project=DNSSecurityMonitoring,Environment=Production \
        > /dev/null
    
    export LAMBDA_FUNCTION_ARN=$(aws lambda get-function \
        --function-name "dns-security-response-${RANDOM_SUFFIX}" \
        --query "Configuration.FunctionArn" --output text)
    
    success "Lambda function created: ${LAMBDA_FUNCTION_ARN}"
}

# Function to configure CloudWatch alarms
configure_cloudwatch_alarms() {
    info "Configuring CloudWatch alarms for DNS threat detection..."
    
    # Create alarm for blocked DNS queries
    aws cloudwatch put-metric-alarm \
        --alarm-name "DNS-High-Block-Rate-${RANDOM_SUFFIX}" \
        --alarm-description "High rate of blocked DNS queries detected" \
        --metric-name "QueryCount" \
        --namespace "AWS/Route53Resolver" \
        --statistic "Sum" \
        --period 300 \
        --threshold 50 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=FirewallRuleGroupId,Value="${RULE_GROUP_ID}" \
        --tags Key=Project,Value=DNSSecurityMonitoring Key=Environment,Value=Production \
        > /dev/null
    
    # Create alarm for unusual query volume
    aws cloudwatch put-metric-alarm \
        --alarm-name "DNS-Unusual-Volume-${RANDOM_SUFFIX}" \
        --alarm-description "Unusual DNS query volume detected" \
        --metric-name "QueryCount" \
        --namespace "AWS/Route53Resolver" \
        --statistic "Sum" \
        --period 900 \
        --threshold 1000 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 1 \
        --alarm-actions "${SNS_TOPIC_ARN}" \
        --dimensions Name=VpcId,Value="${VPC_ID}" \
        --tags Key=Project,Value=DNSSecurityMonitoring Key=Environment,Value=Production \
        > /dev/null
    
    success "CloudWatch alarms configured for DNS threat detection"
}

# Function to setup SNS subscriptions
setup_sns_subscriptions() {
    info "Setting up SNS email notifications for security alerts..."
    
    # Prompt for email address if not provided as environment variable
    if [ -z "${EMAIL_ADDRESS:-}" ]; then
        read -p "Enter your email address for DNS security alerts: " EMAIL_ADDRESS
    fi
    
    # Subscribe email to SNS topic
    aws sns subscribe \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --protocol email \
        --notification-endpoint "${EMAIL_ADDRESS}" \
        > /dev/null
    
    # Subscribe Lambda function to SNS topic
    aws sns subscribe \
        --topic-arn "${SNS_TOPIC_ARN}" \
        --protocol lambda \
        --notification-endpoint "${LAMBDA_FUNCTION_ARN}" \
        > /dev/null
    
    # Grant SNS permission to invoke Lambda function
    aws lambda add-permission \
        --function-name "dns-security-response-${RANDOM_SUFFIX}" \
        --statement-id allow-sns-invoke \
        --action lambda:InvokeFunction \
        --principal sns.amazonaws.com \
        --source-arn "${SNS_TOPIC_ARN}" \
        > /dev/null
    
    success "SNS notifications configured for ${EMAIL_ADDRESS}"
    warn "Please check your email and confirm the SNS subscription to receive alerts"
}

# Function to save deployment information
save_deployment_info() {
    info "Saving deployment information..."
    
    local deployment_info="${SCRIPT_DIR}/deployment-info.json"
    
    cat > "${deployment_info}" << EOF
{
    "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "random_suffix": "${RANDOM_SUFFIX}",
    "vpc_id": "${VPC_ID}",
    "sns_topic_arn": "${SNS_TOPIC_ARN}",
    "domain_list_id": "${DOMAIN_LIST_ID}",
    "rule_group_id": "${RULE_GROUP_ID}",
    "association_id": "${ASSOCIATION_ID}",
    "log_group_name": "${LOG_GROUP_NAME}",
    "query_log_config_id": "${QUERY_LOG_CONFIG_ID}",
    "lambda_function_arn": "${LAMBDA_FUNCTION_ARN}",
    "email_address": "${EMAIL_ADDRESS:-}"
}
EOF
    
    success "Deployment information saved to ${deployment_info}"
}

# Function to run validation tests
run_validation_tests() {
    info "Running validation tests..."
    
    # Test DNS Firewall rule group status
    local rule_group_status=$(aws route53resolver get-firewall-rule-group \
        --firewall-rule-group-id "${RULE_GROUP_ID}" \
        --query "FirewallRuleGroup.Status" --output text)
    
    if [ "${rule_group_status}" != "COMPLETE" ]; then
        warn "DNS Firewall rule group status: ${rule_group_status} (may still be creating)"
    else
        success "DNS Firewall rule group is active"
    fi
    
    # Test VPC association status
    local association_status=$(aws route53resolver list-firewall-rule-group-associations \
        --query "FirewallRuleGroupAssociations[?VpcId=='${VPC_ID}'].Status" --output text)
    
    if [ "${association_status}" != "COMPLETE" ]; then
        warn "VPC association status: ${association_status} (may still be creating)"
    else
        success "VPC association is active"
    fi
    
    # Test CloudWatch alarms
    local alarm_count=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "DNS-" \
        --query "length(MetricAlarms[?starts_with(AlarmName, 'DNS-')])" \
        --output text)
    
    if [ "${alarm_count}" -ge 2 ]; then
        success "CloudWatch alarms are configured (${alarm_count} alarms)"
    else
        warn "CloudWatch alarms may not be fully configured"
    fi
    
    success "Validation tests completed"
}

# Main deployment function
main() {
    info "Starting DNS Security Monitoring deployment..."
    info "Logs are being written to: ${LOG_FILE}"
    
    check_prerequisites
    initialize_environment
    create_sns_topic
    create_firewall_domain_list
    create_firewall_rule_group
    associate_firewall_with_vpc
    create_cloudwatch_log_group
    enable_dns_query_logging
    create_lambda_function
    configure_cloudwatch_alarms
    setup_sns_subscriptions
    save_deployment_info
    
    # Wait for resources to stabilize
    info "Waiting for resources to stabilize..."
    sleep 30
    
    run_validation_tests
    
    success "DNS Security Monitoring deployment completed successfully!"
    echo ""
    info "Deployment Summary:"
    info "  VPC ID: ${VPC_ID}"
    info "  DNS Firewall Rule Group: ${RULE_GROUP_ID}"
    info "  SNS Topic: ${SNS_TOPIC_ARN}"
    info "  Lambda Function: ${LAMBDA_FUNCTION_ARN}"
    info "  CloudWatch Log Group: ${LOG_GROUP_NAME}"
    echo ""
    info "Next Steps:"
    info "1. Confirm your email subscription to receive DNS security alerts"
    info "2. Test the DNS firewall by querying blocked domains from EC2 instances"
    info "3. Monitor CloudWatch metrics and logs for DNS activity"
    info "4. Consider adding additional threat intelligence domains to the firewall"
    echo ""
    warn "Remember to run ./destroy.sh when you want to remove all resources"
}

# Run main function
main "$@"