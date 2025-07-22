#!/bin/bash

# Deploy AWS WAF with Rate Limiting Rules
# This script implements the AWS WAF rate limiting solution from the recipe

set -e  # Exit on any error

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

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured. Please run 'aws configure' or set environment variables."
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some output formatting may be limited."
    fi
    
    success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export WAF_WEB_ACL_NAME="waf-protection-${RANDOM_SUFFIX}"
    export RATE_LIMIT_RULE_NAME="rate-limit-rule-${RANDOM_SUFFIX}"
    export IP_REPUTATION_RULE_NAME="ip-reputation-rule-${RANDOM_SUFFIX}"
    export DASHBOARD_NAME="WAF-Security-Dashboard-${RANDOM_SUFFIX}"
    export LOG_GROUP_NAME="/aws/wafv2/security-logs"
    
    log "Environment variables configured:"
    log "  AWS_REGION: ${AWS_REGION}"
    log "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log "  WAF_WEB_ACL_NAME: ${WAF_WEB_ACL_NAME}"
    log "  RATE_LIMIT_RULE_NAME: ${RATE_LIMIT_RULE_NAME}"
    log "  IP_REPUTATION_RULE_NAME: ${IP_REPUTATION_RULE_NAME}"
    
    success "Environment setup completed"
}

# Function to create CloudWatch log group
create_log_group() {
    log "Creating CloudWatch log group for WAF logs..."
    
    # Check if log group already exists
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --region ${AWS_REGION} --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "${LOG_GROUP_NAME}"; then
        warning "Log group ${LOG_GROUP_NAME} already exists, skipping creation"
    else
        aws logs create-log-group \
            --log-group-name "${LOG_GROUP_NAME}" \
            --region ${AWS_REGION}
        success "CloudWatch log group created: ${LOG_GROUP_NAME}"
    fi
}

# Function to create WAF Web ACL
create_web_acl() {
    log "Creating AWS WAF Web Access Control List..."
    
    # Check if Web ACL already exists
    if aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].Name" --output text | grep -q "${WAF_WEB_ACL_NAME}"; then
        warning "Web ACL ${WAF_WEB_ACL_NAME} already exists, skipping creation"
    else
        aws wafv2 create-web-acl \
            --name ${WAF_WEB_ACL_NAME} \
            --scope CLOUDFRONT \
            --default-action Allow={} \
            --description "Web ACL for rate limiting and security protection" \
            --region us-east-1
        success "Web ACL created: ${WAF_WEB_ACL_NAME}"
    fi
    
    # Store the Web ACL ARN
    export WEB_ACL_ARN=$(aws wafv2 list-web-acls \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --query "WebACLs[?Name=='${WAF_WEB_ACL_NAME}'].ARN" \
        --output text)
    
    if [ -z "$WEB_ACL_ARN" ]; then
        error "Failed to retrieve Web ACL ARN"
    fi
    
    log "Web ACL ARN: ${WEB_ACL_ARN}"
}

# Function to configure rate limiting rule
configure_rate_limiting() {
    log "Configuring rate limiting rule (2000 requests per 5 minutes)..."
    
    # Get current lock token
    LOCK_TOKEN=$(aws wafv2 get-web-acl \
        --id $(echo ${WEB_ACL_ARN} | cut -d'/' -f3) \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --query 'LockToken' --output text)
    
    # Create rate limiting rule
    aws wafv2 update-web-acl \
        --id $(echo ${WEB_ACL_ARN} | cut -d'/' -f3) \
        --name ${WAF_WEB_ACL_NAME} \
        --scope CLOUDFRONT \
        --default-action Allow={} \
        --rules '[
          {
            "Name": "'${RATE_LIMIT_RULE_NAME}'",
            "Priority": 1,
            "Statement": {
              "RateBasedStatement": {
                "Limit": 2000,
                "AggregateKeyType": "IP"
              }
            },
            "Action": {
              "Block": {}
            },
            "VisibilityConfig": {
              "SampledRequestsEnabled": true,
              "CloudWatchMetricsEnabled": true,
              "MetricName": "RateLimitRule"
            }
          }
        ]' \
        --lock-token ${LOCK_TOKEN} \
        --region us-east-1
    
    success "Rate limiting rule configured (2000 req/5min limit)"
}

# Function to add IP reputation protection
add_ip_reputation() {
    log "Adding IP reputation protection rule..."
    
    # Get current lock token
    LOCK_TOKEN=$(aws wafv2 get-web-acl \
        --id $(echo ${WEB_ACL_ARN} | cut -d'/' -f3) \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --query 'LockToken' --output text)
    
    # Add both rate limiting and IP reputation rules
    aws wafv2 update-web-acl \
        --id $(echo ${WEB_ACL_ARN} | cut -d'/' -f3) \
        --name ${WAF_WEB_ACL_NAME} \
        --scope CLOUDFRONT \
        --default-action Allow={} \
        --rules '[
          {
            "Name": "'${RATE_LIMIT_RULE_NAME}'",
            "Priority": 1,
            "Statement": {
              "RateBasedStatement": {
                "Limit": 2000,
                "AggregateKeyType": "IP"
              }
            },
            "Action": {
              "Block": {}
            },
            "VisibilityConfig": {
              "SampledRequestsEnabled": true,
              "CloudWatchMetricsEnabled": true,
              "MetricName": "RateLimitRule"
            }
          },
          {
            "Name": "'${IP_REPUTATION_RULE_NAME}'",
            "Priority": 2,
            "Statement": {
              "ManagedRuleGroupStatement": {
                "VendorName": "AWS",
                "Name": "AWSManagedRulesAmazonIpReputationList"
              }
            },
            "Action": {
              "Block": {}
            },
            "VisibilityConfig": {
              "SampledRequestsEnabled": true,
              "CloudWatchMetricsEnabled": true,
              "MetricName": "IPReputationRule"
            },
            "OverrideAction": {
              "None": {}
            }
          }
        ]' \
        --lock-token ${LOCK_TOKEN} \
        --region us-east-1
    
    success "IP reputation protection rule added"
}

# Function to enable WAF logging
enable_logging() {
    log "Enabling WAF logging to CloudWatch..."
    
    # Check if logging configuration already exists
    if aws wafv2 get-logging-configuration --resource-arn ${WEB_ACL_ARN} --region us-east-1 &>/dev/null; then
        warning "Logging configuration already exists for this Web ACL"
    else
        aws wafv2 put-logging-configuration \
            --logging-configuration '{
              "ResourceArn": "'${WEB_ACL_ARN}'",
              "LogDestinationConfigs": [
                "arn:aws:logs:'${AWS_REGION}':'${AWS_ACCOUNT_ID}':log-group:'${LOG_GROUP_NAME}'"
              ],
              "RedactedFields": [
                {
                  "SingleHeader": {
                    "Name": "authorization"
                  }
                }
              ]
            }' \
            --region us-east-1
        success "WAF logging enabled to CloudWatch Logs"
    fi
}

# Function to create CloudWatch dashboard
create_dashboard() {
    log "Creating CloudWatch dashboard for WAF monitoring..."
    
    aws cloudwatch put-dashboard \
        --dashboard-name "${DASHBOARD_NAME}" \
        --dashboard-body '{
          "widgets": [
            {
              "type": "metric",
              "x": 0,
              "y": 0,
              "width": 12,
              "height": 6,
              "properties": {
                "metrics": [
                  [ "AWS/WAFV2", "AllowedRequests", "WebACL", "'${WAF_WEB_ACL_NAME}'", "Region", "CloudFront", "Rule", "ALL" ],
                  [ ".", "BlockedRequests", ".", ".", ".", ".", ".", "." ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "WAF Allowed vs Blocked Requests"
              }
            },
            {
              "type": "metric",
              "x": 0,
              "y": 6,
              "width": 12,
              "height": 6,
              "properties": {
                "metrics": [
                  [ "AWS/WAFV2", "BlockedRequests", "WebACL", "'${WAF_WEB_ACL_NAME}'", "Region", "CloudFront", "Rule", "'${RATE_LIMIT_RULE_NAME}'" ],
                  [ ".", ".", ".", ".", ".", ".", ".", "'${IP_REPUTATION_RULE_NAME}'" ]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "us-east-1",
                "title": "Blocked Requests by Rule"
              }
            }
          ]
        }' \
        --region ${AWS_REGION}
    
    success "CloudWatch dashboard created: ${DASHBOARD_NAME}"
}

# Function to validate deployment
validate_deployment() {
    log "Validating WAF deployment..."
    
    # Check Web ACL details
    log "Verifying Web ACL configuration..."
    aws wafv2 get-web-acl \
        --id $(echo ${WEB_ACL_ARN} | cut -d'/' -f3) \
        --scope CLOUDFRONT \
        --region us-east-1 \
        --query '{Name:Name,Rules:Rules[*].{Name:Name,Priority:Priority}}' \
        --output table
    
    # Check if logging is enabled
    log "Verifying logging configuration..."
    if aws wafv2 get-logging-configuration --resource-arn ${WEB_ACL_ARN} --region us-east-1 &>/dev/null; then
        success "WAF logging is properly configured"
    else
        warning "WAF logging configuration may have issues"
    fi
    
    # Check CloudWatch dashboard
    log "Verifying CloudWatch dashboard..."
    if aws cloudwatch get-dashboard --dashboard-name "${DASHBOARD_NAME}" --region ${AWS_REGION} &>/dev/null; then
        success "CloudWatch dashboard is accessible"
    else
        warning "CloudWatch dashboard may have issues"
    fi
    
    success "Deployment validation completed"
}

# Function to display deployment summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "     AWS WAF DEPLOYMENT COMPLETED"
    echo "=========================================="
    echo ""
    echo "Resources Created:"
    echo "  • Web ACL: ${WAF_WEB_ACL_NAME}"
    echo "  • Rate Limiting Rule: ${RATE_LIMIT_RULE_NAME}"
    echo "  • IP Reputation Rule: ${IP_REPUTATION_RULE_NAME}"
    echo "  • CloudWatch Dashboard: ${DASHBOARD_NAME}"
    echo "  • Log Group: ${LOG_GROUP_NAME}"
    echo ""
    echo "Web ACL ARN: ${WEB_ACL_ARN}"
    echo ""
    echo "Next Steps:"
    echo "  1. Associate the Web ACL with your CloudFront distribution or ALB"
    echo "  2. Monitor the CloudWatch dashboard for security metrics"
    echo "  3. Review WAF logs in CloudWatch Logs for blocked requests"
    echo "  4. Consider testing rate limiting with controlled traffic"
    echo ""
    echo "CloudFront Association Command:"
    echo "  aws cloudfront update-distribution --id <DISTRIBUTION_ID> \\"
    echo "    --distribution-config <CONFIG_WITH_WEB_ACL_ID>"
    echo ""
    echo "To clean up resources, run: ./destroy.sh"
    echo "=========================================="
}

# Function to save deployment state
save_deployment_state() {
    log "Saving deployment state for cleanup..."
    
    cat > .waf_deployment_state << EOF
# AWS WAF Deployment State
# Generated on $(date)
export WAF_WEB_ACL_NAME="${WAF_WEB_ACL_NAME}"
export WEB_ACL_ARN="${WEB_ACL_ARN}"
export RATE_LIMIT_RULE_NAME="${RATE_LIMIT_RULE_NAME}"
export IP_REPUTATION_RULE_NAME="${IP_REPUTATION_RULE_NAME}"
export DASHBOARD_NAME="${DASHBOARD_NAME}"
export LOG_GROUP_NAME="${LOG_GROUP_NAME}"
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
EOF
    
    success "Deployment state saved to .waf_deployment_state"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "   AWS WAF Rate Limiting Deployment"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    setup_environment
    create_log_group
    create_web_acl
    configure_rate_limiting
    add_ip_reputation
    enable_logging
    create_dashboard
    validate_deployment
    save_deployment_state
    display_summary
}

# Trap errors and provide helpful messaging
trap 'error "Deployment failed at line $LINENO. Check the error message above."' ERR

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi