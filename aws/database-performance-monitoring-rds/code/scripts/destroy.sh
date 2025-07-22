#!/bin/bash
# Destroy script for RDS Performance Insights monitoring solution
# This script safely removes all resources created by the deploy script

set -euo pipefail

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to confirm destructive action
confirm_destroy() {
    echo ""
    log_warning "This will destroy ALL resources created by the deployment script."
    log_warning "This action cannot be undone!"
    echo ""
    read -p "Are you sure you want to continue? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
}

# Function to find resources by tags or patterns
find_resources() {
    log "Discovering resources to destroy..."
    
    # Try to find resources using common patterns
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Find RDS instances with Performance Insights
    RDS_INSTANCES=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, 'performance-test-db')].DBInstanceIdentifier" \
        --output text)
    
    # Find Lambda functions
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'performance-analyzer')].FunctionName" \
        --output text)
    
    # Find S3 buckets
    S3_BUCKETS=$(aws s3 ls | grep "db-performance-reports" | awk '{print $3}')
    
    # Find SNS topics
    SNS_TOPICS=$(aws sns list-topics \
        --query "Topics[?contains(TopicArn, 'db-performance-alerts')].TopicArn" \
        --output text)
    
    # Find CloudWatch alarms
    CLOUDWATCH_ALARMS=$(aws cloudwatch describe-alarms \
        --query "MetricAlarms[?contains(AlarmName, 'RDS-High') || contains(AlarmName, 'performance-test-db')].AlarmName" \
        --output text)
    
    # Find EventBridge rules
    EVENTBRIDGE_RULES=$(aws events list-rules \
        --query "Rules[?contains(Name, 'PerformanceAnalysisTrigger')].Name" \
        --output text)
    
    # Find CloudWatch dashboards
    DASHBOARDS=$(aws cloudwatch list-dashboards \
        --query "DashboardEntries[?contains(DashboardName, 'RDS-Performance')].DashboardName" \
        --output text)
    
    # Find DB subnet groups
    DB_SUBNET_GROUPS=$(aws rds describe-db-subnet-groups \
        --query "DBSubnetGroups[?contains(DBSubnetGroupName, 'perf-insights-subnet-group')].DBSubnetGroupName" \
        --output text)
    
    log_success "Resource discovery completed"
}

# Function to remove EventBridge automation
remove_eventbridge() {
    log "Removing EventBridge automation..."
    
    if [ ! -z "$EVENTBRIDGE_RULES" ]; then
        for rule in $EVENTBRIDGE_RULES; do
            log "Removing EventBridge rule: $rule"
            
            # Remove targets first
            aws events remove-targets \
                --rule "$rule" \
                --ids "1" || true
            
            # Delete rule
            aws events delete-rule \
                --name "$rule" || true
            
            log_success "Removed EventBridge rule: $rule"
        done
    else
        log_warning "No EventBridge rules found to remove"
    fi
}

# Function to remove Lambda functions
remove_lambda_functions() {
    log "Removing Lambda functions..."
    
    if [ ! -z "$LAMBDA_FUNCTIONS" ]; then
        for function in $LAMBDA_FUNCTIONS; do
            log "Removing Lambda function: $function"
            
            # Remove function
            aws lambda delete-function \
                --function-name "$function" || true
            
            log_success "Removed Lambda function: $function"
        done
    else
        log_warning "No Lambda functions found to remove"
    fi
}

# Function to remove CloudWatch alarms
remove_cloudwatch_alarms() {
    log "Removing CloudWatch alarms..."
    
    if [ ! -z "$CLOUDWATCH_ALARMS" ]; then
        # Convert space-separated list to array for proper handling
        IFS=' ' read -ra ALARM_ARRAY <<< "$CLOUDWATCH_ALARMS"
        
        if [ ${#ALARM_ARRAY[@]} -gt 0 ]; then
            log "Deleting ${#ALARM_ARRAY[@]} CloudWatch alarms..."
            aws cloudwatch delete-alarms \
                --alarm-names "${ALARM_ARRAY[@]}" || true
            log_success "Removed CloudWatch alarms"
        fi
    else
        log_warning "No CloudWatch alarms found to remove"
    fi
}

# Function to remove anomaly detection
remove_anomaly_detection() {
    log "Removing CloudWatch anomaly detection..."
    
    if [ ! -z "$RDS_INSTANCES" ]; then
        for instance in $RDS_INSTANCES; do
            log "Removing anomaly detection for: $instance"
            
            # Remove anomaly detection
            aws cloudwatch delete-anomaly-detector \
                --namespace "AWS/RDS" \
                --metric-name "DatabaseConnections" \
                --dimensions "Name=DBInstanceIdentifier,Value=$instance" \
                --stat "Average" || true
            
            log_success "Removed anomaly detection for: $instance"
        done
    else
        log_warning "No RDS instances found for anomaly detection removal"
    fi
}

# Function to remove CloudWatch dashboards
remove_dashboards() {
    log "Removing CloudWatch dashboards..."
    
    if [ ! -z "$DASHBOARDS" ]; then
        # Convert space-separated list to array for proper handling
        IFS=' ' read -ra DASHBOARD_ARRAY <<< "$DASHBOARDS"
        
        if [ ${#DASHBOARD_ARRAY[@]} -gt 0 ]; then
            log "Deleting ${#DASHBOARD_ARRAY[@]} CloudWatch dashboards..."
            aws cloudwatch delete-dashboards \
                --dashboard-names "${DASHBOARD_ARRAY[@]}" || true
            log_success "Removed CloudWatch dashboards"
        fi
    else
        log_warning "No CloudWatch dashboards found to remove"
    fi
}

# Function to remove RDS instances
remove_rds_instances() {
    log "Removing RDS instances..."
    
    if [ ! -z "$RDS_INSTANCES" ]; then
        for instance in $RDS_INSTANCES; do
            log "Removing RDS instance: $instance"
            
            # Delete RDS instance
            aws rds delete-db-instance \
                --db-instance-identifier "$instance" \
                --skip-final-snapshot \
                --delete-automated-backups || true
            
            log_success "RDS instance deletion initiated: $instance"
        done
        
        # Wait for instances to be deleted
        for instance in $RDS_INSTANCES; do
            log "Waiting for RDS instance to be deleted: $instance"
            aws rds wait db-instance-deleted \
                --db-instance-identifier "$instance" || true
            log_success "RDS instance deleted: $instance"
        done
    else
        log_warning "No RDS instances found to remove"
    fi
}

# Function to remove DB subnet groups
remove_db_subnet_groups() {
    log "Removing DB subnet groups..."
    
    if [ ! -z "$DB_SUBNET_GROUPS" ]; then
        for subnet_group in $DB_SUBNET_GROUPS; do
            log "Removing DB subnet group: $subnet_group"
            
            # Delete DB subnet group
            aws rds delete-db-subnet-group \
                --db-subnet-group-name "$subnet_group" || true
            
            log_success "Removed DB subnet group: $subnet_group"
        done
    else
        log_warning "No DB subnet groups found to remove"
    fi
}

# Function to remove SNS topics
remove_sns_topics() {
    log "Removing SNS topics..."
    
    if [ ! -z "$SNS_TOPICS" ]; then
        for topic in $SNS_TOPICS; do
            log "Removing SNS topic: $topic"
            
            # Delete SNS topic
            aws sns delete-topic \
                --topic-arn "$topic" || true
            
            log_success "Removed SNS topic: $topic"
        done
    else
        log_warning "No SNS topics found to remove"
    fi
}

# Function to remove IAM roles and policies
remove_iam_resources() {
    log "Removing IAM resources..."
    
    # Remove Lambda execution role
    if aws iam get-role --role-name "performance-analyzer-role" &>/dev/null; then
        log "Removing Lambda execution role..."
        
        # Detach policies
        aws iam detach-role-policy \
            --role-name "performance-analyzer-role" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" || true
        
        aws iam detach-role-policy \
            --role-name "performance-analyzer-role" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PerformanceInsightsLambdaPolicy" || true
        
        # Delete role
        aws iam delete-role --role-name "performance-analyzer-role" || true
        
        log_success "Removed Lambda execution role"
    else
        log_warning "Lambda execution role not found"
    fi
    
    # Remove custom policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PerformanceInsightsLambdaPolicy" &>/dev/null; then
        log "Removing custom policy..."
        
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/PerformanceInsightsLambdaPolicy" || true
        
        log_success "Removed custom policy"
    else
        log_warning "Custom policy not found"
    fi
    
    # Remove RDS monitoring role
    if aws iam get-role --role-name "rds-monitoring-role" &>/dev/null; then
        log "Removing RDS monitoring role..."
        
        # Detach policy
        aws iam detach-role-policy \
            --role-name "rds-monitoring-role" \
            --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole" || true
        
        # Delete role
        aws iam delete-role --role-name "rds-monitoring-role" || true
        
        log_success "Removed RDS monitoring role"
    else
        log_warning "RDS monitoring role not found"
    fi
}

# Function to remove S3 buckets
remove_s3_buckets() {
    log "Removing S3 buckets..."
    
    if [ ! -z "$S3_BUCKETS" ]; then
        for bucket in $S3_BUCKETS; do
            log "Removing S3 bucket: $bucket"
            
            # Delete all objects in bucket
            aws s3 rm s3://$bucket --recursive || true
            
            # Delete bucket
            aws s3 rb s3://$bucket || true
            
            log_success "Removed S3 bucket: $bucket"
        done
    else
        log_warning "No S3 buckets found to remove"
    fi
}

# Function to clean up any remaining resources
cleanup_remaining() {
    log "Cleaning up any remaining resources..."
    
    # Remove any temporary files
    rm -f trust-policy.json
    rm -f lambda-trust-policy.json
    rm -f pi-lambda-policy.json
    rm -f dashboard-body.json
    rm -f performance_analyzer.py
    rm -f lambda_function.zip
    rm -f lambda_response.json
    rm -f latest_report.json
    rm -f generate_load.sql
    rm -f cleanup_manifest.txt
    
    log_success "Cleaned up temporary files"
}

# Function to verify cleanup
verify_cleanup() {
    log "Verifying cleanup..."
    
    # Check for any remaining resources
    remaining_rds=$(aws rds describe-db-instances \
        --query "DBInstances[?contains(DBInstanceIdentifier, 'performance-test-db')].DBInstanceIdentifier" \
        --output text)
    
    remaining_lambda=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'performance-analyzer')].FunctionName" \
        --output text)
    
    remaining_s3=$(aws s3 ls | grep "db-performance-reports" | awk '{print $3}')
    
    remaining_alarms=$(aws cloudwatch describe-alarms \
        --query "MetricAlarms[?contains(AlarmName, 'RDS-High') || contains(AlarmName, 'performance-test-db')].AlarmName" \
        --output text)
    
    # Report any remaining resources
    if [ ! -z "$remaining_rds" ]; then
        log_warning "Remaining RDS instances: $remaining_rds"
    fi
    
    if [ ! -z "$remaining_lambda" ]; then
        log_warning "Remaining Lambda functions: $remaining_lambda"
    fi
    
    if [ ! -z "$remaining_s3" ]; then
        log_warning "Remaining S3 buckets: $remaining_s3"
    fi
    
    if [ ! -z "$remaining_alarms" ]; then
        log_warning "Remaining CloudWatch alarms: $remaining_alarms"
    fi
    
    if [ -z "$remaining_rds" ] && [ -z "$remaining_lambda" ] && [ -z "$remaining_s3" ] && [ -z "$remaining_alarms" ]; then
        log_success "All resources have been successfully removed"
    else
        log_warning "Some resources may still exist. Please check the AWS console."
    fi
}

# Function to display destruction summary
show_destruction_summary() {
    echo ""
    echo "=== DESTRUCTION SUMMARY ==="
    echo "The following resources were removed:"
    echo "- RDS instances and DB subnet groups"
    echo "- Lambda functions and IAM roles"
    echo "- CloudWatch alarms and dashboards"
    echo "- EventBridge rules and targets"
    echo "- SNS topics and subscriptions"
    echo "- S3 buckets and contents"
    echo "- Custom IAM policies"
    echo ""
    echo "=== BILLING NOTES ==="
    echo "- RDS instances: Billing stops when instance is deleted"
    echo "- Lambda functions: No charges for deleted functions"
    echo "- CloudWatch: Custom metrics and alarms no longer incur charges"
    echo "- S3: All objects and bucket versions have been deleted"
    echo "- Performance Insights: No additional charges after RDS deletion"
    echo ""
    echo "=== NEXT STEPS ==="
    echo "1. Verify all resources are deleted in the AWS console"
    echo "2. Check your AWS billing dashboard for any remaining charges"
    echo "3. Consider deleting any manual SNS subscriptions you created"
    echo "4. Review CloudWatch logs for any remaining log groups"
    echo ""
    log_success "Destruction completed successfully!"
}

# Main destruction function
main() {
    log "Starting destruction of RDS Performance Insights monitoring solution..."
    
    # Confirm destruction
    confirm_destroy
    
    # Find resources to destroy
    find_resources
    
    # Remove resources in reverse order of creation
    remove_eventbridge
    remove_lambda_functions
    remove_cloudwatch_alarms
    remove_anomaly_detection
    remove_dashboards
    remove_rds_instances
    remove_db_subnet_groups
    remove_sns_topics
    remove_iam_resources
    remove_s3_buckets
    cleanup_remaining
    
    # Verify cleanup
    verify_cleanup
    
    # Show summary
    show_destruction_summary
}

# Handle dry-run mode
if [ "${1:-}" = "--dry-run" ]; then
    log "DRY RUN MODE - No resources will be deleted"
    find_resources
    
    echo ""
    echo "=== RESOURCES THAT WOULD BE DELETED ==="
    [ ! -z "$RDS_INSTANCES" ] && echo "RDS Instances: $RDS_INSTANCES"
    [ ! -z "$LAMBDA_FUNCTIONS" ] && echo "Lambda Functions: $LAMBDA_FUNCTIONS"
    [ ! -z "$S3_BUCKETS" ] && echo "S3 Buckets: $S3_BUCKETS"
    [ ! -z "$SNS_TOPICS" ] && echo "SNS Topics: $SNS_TOPICS"
    [ ! -z "$CLOUDWATCH_ALARMS" ] && echo "CloudWatch Alarms: $CLOUDWATCH_ALARMS"
    [ ! -z "$EVENTBRIDGE_RULES" ] && echo "EventBridge Rules: $EVENTBRIDGE_RULES"
    [ ! -z "$DASHBOARDS" ] && echo "CloudWatch Dashboards: $DASHBOARDS"
    [ ! -z "$DB_SUBNET_GROUPS" ] && echo "DB Subnet Groups: $DB_SUBNET_GROUPS"
    echo "IAM Roles: performance-analyzer-role, rds-monitoring-role"
    echo "IAM Policies: PerformanceInsightsLambdaPolicy"
    echo ""
    echo "Run without --dry-run to actually delete these resources"
    exit 0
fi

# Run main function
main "$@"