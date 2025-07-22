#!/bin/bash

# WAF Rules Web Application Security - Deployment Script
# This script deploys a comprehensive AWS WAF setup with managed rules,
# custom rules, rate limiting, and monitoring capabilities.

set -euo pipefail

# Color codes for output
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

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log_info "AWS CLI version: $aws_version"
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        exit 1
    fi
    
    # Check required permissions
    log_info "Checking AWS permissions..."
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local region=$(aws configure get region)
    
    if [[ -z "$region" ]]; then
        log_error "AWS region not configured. Please set your default region."
        exit 1
    fi
    
    log_success "Prerequisites check completed."
    log_info "Account ID: $account_id"
    log_info "Region: $region"
}

# Function to validate CloudFront distribution
validate_cloudfront_distribution() {
    local distribution_id="$1"
    
    log_info "Validating CloudFront distribution: $distribution_id"
    
    if ! aws cloudfront get-distribution --id "$distribution_id" &> /dev/null; then
        log_error "CloudFront distribution $distribution_id not found or not accessible."
        return 1
    fi
    
    local status=$(aws cloudfront get-distribution --id "$distribution_id" \
        --query "Distribution.Status" --output text)
    
    if [[ "$status" != "Deployed" ]]; then
        log_warning "CloudFront distribution status is '$status', not 'Deployed'."
        log_warning "Deployment may fail or take longer than expected."
    fi
    
    log_success "CloudFront distribution validated."
    return 0
}

# Function to generate unique suffix
generate_unique_suffix() {
    aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
    echo "$(date +%s | tail -c 6)"
}

# Function to create environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(generate_unique_suffix)
    export RANDOM_SUFFIX="$random_suffix"
    
    export WAF_NAME="webapp-security-waf-${random_suffix}"
    export LOG_GROUP_NAME="/aws/wafv2/${WAF_NAME}"
    export CLOUDWATCH_ALARM_NAME="waf-high-blocked-requests-${random_suffix}"
    export IP_SET_NAME="blocked-ips-${random_suffix}"
    export REGEX_SET_NAME="suspicious-patterns-${random_suffix}"
    export SNS_TOPIC_NAME="waf-security-alerts-${random_suffix}"
    export DASHBOARD_NAME="WAF-Security-Dashboard-${random_suffix}"
    
    # Create state file for cleanup
    cat > /tmp/waf_deployment_state.env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
RANDOM_SUFFIX=$random_suffix
WAF_NAME=$WAF_NAME
LOG_GROUP_NAME=$LOG_GROUP_NAME
CLOUDWATCH_ALARM_NAME=$CLOUDWATCH_ALARM_NAME
IP_SET_NAME=$IP_SET_NAME
REGEX_SET_NAME=$REGEX_SET_NAME
SNS_TOPIC_NAME=$SNS_TOPIC_NAME
DASHBOARD_NAME=$DASHBOARD_NAME
EOF
    
    log_success "Environment variables configured."
    log_info "Random suffix: $random_suffix"
}

# Function to create CloudWatch Log Group
create_log_group() {
    log_info "Creating CloudWatch Log Group..."
    
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" \
        --query "logGroups[?logGroupName=='$LOG_GROUP_NAME']" \
        --output text | grep -q "$LOG_GROUP_NAME"; then
        log_warning "Log group $LOG_GROUP_NAME already exists."
    else
        aws logs create-log-group \
            --log-group-name "$LOG_GROUP_NAME" \
            --region "$AWS_REGION"
        log_success "Created CloudWatch Log Group: $LOG_GROUP_NAME"
    fi
}

# Function to create WAF Web ACL with managed rules
create_waf_web_acl() {
    log_info "Creating WAF Web ACL with managed rule groups..."
    
    local rules_json='[
        {
            "Name": "AWSManagedRulesCommonRuleSet",
            "Priority": 1,
            "Statement": {
                "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesCommonRuleSet"
                }
            },
            "OverrideAction": {
                "None": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "CommonRuleSetMetric"
            }
        },
        {
            "Name": "AWSManagedRulesKnownBadInputsRuleSet",
            "Priority": 2,
            "Statement": {
                "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesKnownBadInputsRuleSet"
                }
            },
            "OverrideAction": {
                "None": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "KnownBadInputsMetric"
            }
        },
        {
            "Name": "AWSManagedRulesSQLiRuleSet",
            "Priority": 3,
            "Statement": {
                "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesSQLiRuleSet"
                }
            },
            "OverrideAction": {
                "None": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "SQLiRuleSetMetric"
            }
        }
    ]'
    
    # Check if WAF already exists
    if aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "WebACLs[?Name=='$WAF_NAME']" --output text | grep -q "$WAF_NAME"; then
        log_warning "WAF Web ACL $WAF_NAME already exists."
        export WAF_ARN=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
            --query "WebACLs[?Name=='$WAF_NAME'].ARN" --output text)
    else
        aws wafv2 create-web-acl \
            --name "$WAF_NAME" \
            --scope CLOUDFRONT \
            --default-action Allow={} \
            --description "Comprehensive WAF for web application security" \
            --rules "$rules_json" \
            --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName="${WAF_NAME}Metric" \
            --region "$AWS_REGION"
        
        export WAF_ARN=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
            --query "WebACLs[?Name=='$WAF_NAME'].ARN" --output text)
        
        log_success "Created WAF Web ACL: $WAF_NAME"
    fi
    
    log_info "WAF ARN: $WAF_ARN"
    echo "WAF_ARN=$WAF_ARN" >> /tmp/waf_deployment_state.env
}

# Function to create IP Set
create_ip_set() {
    log_info "Creating IP Set for blocking malicious IPs..."
    
    if aws wafv2 list-ip-sets --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "IPSets[?Name=='$IP_SET_NAME']" --output text | grep -q "$IP_SET_NAME"; then
        log_warning "IP Set $IP_SET_NAME already exists."
    else
        aws wafv2 create-ip-set \
            --name "$IP_SET_NAME" \
            --scope CLOUDFRONT \
            --ip-address-version IPV4 \
            --addresses '["192.0.2.44/32","203.0.113.0/24"]' \
            --description "IP addresses to block - example addresses" \
            --region "$AWS_REGION"
        
        log_success "Created IP Set: $IP_SET_NAME"
    fi
    
    export IP_SET_ARN=$(aws wafv2 list-ip-sets --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "IPSets[?Name=='$IP_SET_NAME'].ARN" --output text)
    log_info "IP Set ARN: $IP_SET_ARN"
    echo "IP_SET_ARN=$IP_SET_ARN" >> /tmp/waf_deployment_state.env
}

# Function to create regex pattern set
create_regex_pattern_set() {
    log_info "Creating regex pattern set for custom threat detection..."
    
    if aws wafv2 list-regex-pattern-sets --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "RegexPatternSets[?Name=='$REGEX_SET_NAME']" --output text | grep -q "$REGEX_SET_NAME"; then
        log_warning "Regex pattern set $REGEX_SET_NAME already exists."
    else
        local patterns='[
            {"RegexString": "(?i)(union.*select|select.*from|insert.*into|drop.*table)"},
            {"RegexString": "(?i)(<script|javascript:|onerror=|onload=)"},
            {"RegexString": "(?i)(\\.\\./)|(\\\\\\.\\.\\\\)"},
            {"RegexString": "(?i)(cmd\\.exe|powershell|/bin/bash|/bin/sh)"}
        ]'
        
        aws wafv2 create-regex-pattern-set \
            --name "$REGEX_SET_NAME" \
            --scope CLOUDFRONT \
            --regular-expression-list "$patterns" \
            --description "Patterns for detecting common attack signatures" \
            --region "$AWS_REGION"
        
        log_success "Created regex pattern set: $REGEX_SET_NAME"
    fi
    
    export REGEX_SET_ARN=$(aws wafv2 list-regex-pattern-sets --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "RegexPatternSets[?Name=='$REGEX_SET_NAME'].ARN" --output text)
    log_info "Regex Pattern Set ARN: $REGEX_SET_ARN"
    echo "REGEX_SET_ARN=$REGEX_SET_ARN" >> /tmp/waf_deployment_state.env
}

# Function to update WAF with comprehensive rules
update_waf_comprehensive_rules() {
    log_info "Updating WAF with comprehensive security rules..."
    
    local comprehensive_rules='[
        {
            "Name": "AWSManagedRulesCommonRuleSet",
            "Priority": 1,
            "Statement": {
                "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesCommonRuleSet"
                }
            },
            "OverrideAction": {
                "None": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "CommonRuleSetMetric"
            }
        },
        {
            "Name": "AWSManagedRulesKnownBadInputsRuleSet",
            "Priority": 2,
            "Statement": {
                "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesKnownBadInputsRuleSet"
                }
            },
            "OverrideAction": {
                "None": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "KnownBadInputsMetric"
            }
        },
        {
            "Name": "AWSManagedRulesSQLiRuleSet",
            "Priority": 3,
            "Statement": {
                "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesSQLiRuleSet"
                }
            },
            "OverrideAction": {
                "None": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "SQLiRuleSetMetric"
            }
        },
        {
            "Name": "AWSManagedRulesBotControlRuleSet",
            "Priority": 4,
            "Statement": {
                "ManagedRuleGroupStatement": {
                    "VendorName": "AWS",
                    "Name": "AWSManagedRulesBotControlRuleSet"
                }
            },
            "OverrideAction": {
                "None": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "BotControlMetric"
            }
        },
        {
            "Name": "RateLimitRule",
            "Priority": 5,
            "Statement": {
                "RateBasedStatement": {
                    "Limit": 10000,
                    "AggregateKeyType": "IP"
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "RateLimitMetric"
            }
        },
        {
            "Name": "BlockHighRiskCountries",
            "Priority": 6,
            "Statement": {
                "GeoMatchStatement": {
                    "CountryCodes": ["CN", "RU", "KP"]
                }
            },
            "Action": {
                "Block": {}
            },
            "VisibilityConfig": {
                "SampledRequestsEnabled": true,
                "CloudWatchMetricsEnabled": true,
                "MetricName": "GeoBlockMetric"
            }
        }
    ]'
    
    local waf_id=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region "$AWS_REGION" \
        --query "WebACLs[?Name=='$WAF_NAME'].Id" --output text)
    
    local lock_token=$(aws wafv2 get-web-acl --scope CLOUDFRONT --id "$waf_id" \
        --region "$AWS_REGION" --query "LockToken" --output text)
    
    aws wafv2 update-web-acl \
        --scope CLOUDFRONT \
        --id "$waf_id" \
        --name "$WAF_NAME" \
        --default-action Allow={} \
        --description "Comprehensive WAF for web application security" \
        --rules "$comprehensive_rules" \
        --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName="${WAF_NAME}Metric" \
        --lock-token "$lock_token" \
        --region "$AWS_REGION"
    
    log_success "Updated WAF with comprehensive security rules including:"
    log_info "  - Common rule set protection"
    log_info "  - Known bad inputs blocking"
    log_info "  - SQL injection protection"
    log_info "  - Bot control protection"
    log_info "  - Rate limiting (10,000 requests per 5 minutes per IP)"
    log_info "  - Geographic blocking for high-risk countries"
}

# Function to enable WAF logging
enable_waf_logging() {
    log_info "Enabling WAF logging to CloudWatch..."
    
    local logging_config='{
        "ResourceArn": "'"$WAF_ARN"'",
        "LogDestinationConfigs": [
            "arn:aws:logs:'"$AWS_REGION"':'"$AWS_ACCOUNT_ID"':log-group:'"$LOG_GROUP_NAME"'"
        ],
        "LogType": "WAF_LOGS",
        "LogScope": "SECURITY_EVENTS",
        "RedactedFields": []
    }'
    
    if aws wafv2 get-logging-configuration --resource-arn "$WAF_ARN" \
        --region "$AWS_REGION" &> /dev/null; then
        log_warning "WAF logging already configured."
    else
        aws wafv2 put-logging-configuration \
            --logging-configuration "$logging_config" \
            --region "$AWS_REGION"
        
        log_success "Enabled WAF logging to CloudWatch"
    fi
}

# Function to create SNS topic and CloudWatch alarm
create_monitoring() {
    log_info "Creating security monitoring with SNS and CloudWatch alarms..."
    
    # Create SNS topic
    if aws sns get-topic-attributes --topic-arn "arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME" &> /dev/null; then
        log_warning "SNS topic $SNS_TOPIC_NAME already exists."
        export SNS_TOPIC_ARN="arn:aws:sns:$AWS_REGION:$AWS_ACCOUNT_ID:$SNS_TOPIC_NAME"
    else
        export SNS_TOPIC_ARN=$(aws sns create-topic \
            --name "$SNS_TOPIC_NAME" \
            --region "$AWS_REGION" \
            --query "TopicArn" \
            --output text)
        
        log_success "Created SNS topic: $SNS_TOPIC_ARN"
    fi
    
    echo "SNS_TOPIC_ARN=$SNS_TOPIC_ARN" >> /tmp/waf_deployment_state.env
    
    # Create CloudWatch alarm
    if aws cloudwatch describe-alarms --alarm-names "$CLOUDWATCH_ALARM_NAME" \
        --region "$AWS_REGION" --query "MetricAlarms" --output text | grep -q "$CLOUDWATCH_ALARM_NAME"; then
        log_warning "CloudWatch alarm $CLOUDWATCH_ALARM_NAME already exists."
    else
        aws cloudwatch put-metric-alarm \
            --alarm-name "$CLOUDWATCH_ALARM_NAME" \
            --alarm-description "High number of blocked requests detected" \
            --metric-name "BlockedRequests" \
            --namespace "AWS/WAFV2" \
            --statistic "Sum" \
            --period 300 \
            --threshold 1000 \
            --comparison-operator "GreaterThanThreshold" \
            --evaluation-periods 2 \
            --alarm-actions "$SNS_TOPIC_ARN" \
            --dimensions Name=WebACL,Value="$WAF_NAME" Name=Region,Value="$AWS_REGION" \
            --region "$AWS_REGION"
        
        log_success "Created CloudWatch alarm: $CLOUDWATCH_ALARM_NAME"
    fi
}

# Function to create CloudWatch dashboard
create_dashboard() {
    log_info "Creating CloudWatch dashboard for WAF monitoring..."
    
    local dashboard_body='{
        "widgets": [
            {
                "type": "metric",
                "x": 0,
                "y": 0,
                "width": 12,
                "height": 6,
                "properties": {
                    "metrics": [
                        ["AWS/WAFV2", "AllowedRequests", "WebACL", "'"$WAF_NAME"'", "Region", "'"$AWS_REGION"'"],
                        [".", "BlockedRequests", ".", ".", ".", "."]
                    ],
                    "view": "timeSeries",
                    "stacked": false,
                    "region": "'"$AWS_REGION"'",
                    "title": "WAF Request Statistics",
                    "period": 300
                }
            },
            {
                "type": "metric",
                "x": 12,
                "y": 0,
                "width": 12,
                "height": 6,
                "properties": {
                    "metrics": [
                        ["AWS/WAFV2", "BlockedRequests", "WebACL", "'"$WAF_NAME"'", "Region", "'"$AWS_REGION"'", "Rule", "CommonRuleSetMetric"],
                        ["...", "KnownBadInputsMetric"],
                        ["...", "SQLiRuleSetMetric"],
                        ["...", "RateLimitMetric"],
                        ["...", "GeoBlockMetric"],
                        ["...", "BotControlMetric"]
                    ],
                    "view": "timeSeries",
                    "stacked": false,
                    "region": "'"$AWS_REGION"'",
                    "title": "Blocked Requests by Rule",
                    "period": 300
                }
            }
        ]
    }'
    
    if aws cloudwatch list-dashboards --region "$AWS_REGION" \
        --query "DashboardEntries[?DashboardName=='$DASHBOARD_NAME']" \
        --output text | grep -q "$DASHBOARD_NAME"; then
        log_warning "CloudWatch dashboard $DASHBOARD_NAME already exists."
    else
        aws cloudwatch put-dashboard \
            --dashboard-name "$DASHBOARD_NAME" \
            --dashboard-body "$dashboard_body" \
            --region "$AWS_REGION"
        
        log_success "Created CloudWatch dashboard: $DASHBOARD_NAME"
    fi
}

# Function to prompt for CloudFront association
associate_with_cloudfront() {
    log_info "WAF Web ACL created successfully."
    log_warning "To complete the setup, you need to associate the WAF with your CloudFront distribution."
    
    echo
    log_info "Available CloudFront distributions:"
    aws cloudfront list-distributions \
        --query "DistributionList.Items[*].[Id,Origins.Items[0].DomainName,Status]" \
        --output table 2>/dev/null || log_warning "No CloudFront distributions found or insufficient permissions."
    
    echo
    read -p "Would you like to associate the WAF with a CloudFront distribution now? (y/n): " -r associate_now
    
    if [[ $associate_now =~ ^[Yy]$ ]]; then
        read -p "Enter your CloudFront Distribution ID: " distribution_id
        
        if [[ -n "$distribution_id" ]] && validate_cloudfront_distribution "$distribution_id"; then
            log_info "Associating WAF with CloudFront distribution: $distribution_id"
            
            # Get current distribution config
            aws cloudfront get-distribution-config --id "$distribution_id" \
                --query "DistributionConfig" > /tmp/distribution-config.json
            
            # Update config to include WAF
            jq '.WebACLId = "'"$WAF_ARN"'"' /tmp/distribution-config.json > /tmp/updated-config.json
            
            # Get ETag
            local etag=$(aws cloudfront get-distribution-config --id "$distribution_id" \
                --query "ETag" --output text)
            
            # Update distribution
            aws cloudfront update-distribution \
                --id "$distribution_id" \
                --distribution-config file:///tmp/updated-config.json \
                --if-match "$etag" \
                --region "$AWS_REGION"
            
            echo "CLOUDFRONT_DISTRIBUTION_ID=$distribution_id" >> /tmp/waf_deployment_state.env
            
            log_success "Successfully associated WAF with CloudFront distribution: $distribution_id"
            log_info "The configuration will propagate to all edge locations within 15-20 minutes."
            
            # Cleanup temp files
            rm -f /tmp/distribution-config.json /tmp/updated-config.json
        else
            log_error "Invalid CloudFront distribution ID or distribution not accessible."
            log_info "You can associate the WAF manually later using the AWS Console or CLI."
        fi
    else
        log_info "Skipping CloudFront association. You can associate the WAF manually later."
        log_info "WAF ARN: $WAF_ARN"
    fi
}

# Function to display deployment summary
display_summary() {
    log_success "WAF deployment completed successfully!"
    
    echo
    echo "=================================="
    echo "Deployment Summary"
    echo "=================================="
    echo "WAF Name: $WAF_NAME"
    echo "WAF ARN: $WAF_ARN"
    echo "Log Group: $LOG_GROUP_NAME"
    echo "SNS Topic: $SNS_TOPIC_ARN"
    echo "CloudWatch Alarm: $CLOUDWATCH_ALARM_NAME"
    echo "Dashboard: $DASHBOARD_NAME"
    echo
    echo "Security Features Enabled:"
    echo "  ✅ AWS Managed Rules (Common, Known Bad Inputs, SQL Injection)"
    echo "  ✅ Bot Control Protection"
    echo "  ✅ Rate Limiting (10,000 requests per 5 minutes per IP)"
    echo "  ✅ Geographic Blocking (High-risk countries)"
    echo "  ✅ Custom Pattern Detection"
    echo "  ✅ Comprehensive Logging"
    echo "  ✅ CloudWatch Monitoring and Alerts"
    echo
    echo "Next Steps:"
    echo "  1. Associate the WAF with your CloudFront distribution or ALB"
    echo "  2. Subscribe to the SNS topic for security alerts"
    echo "  3. Review the CloudWatch dashboard for monitoring"
    echo "  4. Customize rate limits and blocked countries as needed"
    echo "  5. Test the WAF rules with your application"
    echo
    echo "Cleanup: Run ./destroy.sh to remove all resources"
    echo "State file saved to: /tmp/waf_deployment_state.env"
    echo "=================================="
}

# Main deployment function
main() {
    log_info "Starting WAF Rules Web Application Security deployment..."
    
    # Check if dry run mode
    local dry_run=false
    if [[ "${1:-}" == "--dry-run" ]]; then
        dry_run=true
        log_info "Running in dry-run mode - no resources will be created"
    fi
    
    if [[ "$dry_run" == "false" ]]; then
        check_prerequisites
        setup_environment
        create_log_group
        create_waf_web_acl
        create_ip_set
        create_regex_pattern_set
        update_waf_comprehensive_rules
        enable_waf_logging
        create_monitoring
        create_dashboard
        associate_with_cloudfront
        display_summary
    else
        log_info "Dry run completed - no resources were created"
    fi
}

# Handle script interruption
trap 'log_error "Script interrupted. Some resources may have been created."; exit 1' INT TERM

# Run main function
main "$@"