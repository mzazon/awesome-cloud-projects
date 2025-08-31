#!/bin/bash
set -e

# Service Performance Cost Analytics with VPC Lattice and CloudWatch Insights
# Cleanup/Destroy Script
#
# This script safely removes all infrastructure components deployed for the
# VPC Lattice performance cost analytics solution, ensuring complete cleanup
# while avoiding common deletion errors due to resource dependencies.

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites for cleanup..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid"
        exit 1
    fi
    
    # Check for jq
    if ! command -v jq &> /dev/null; then
        error "jq is required but not installed"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [[ ! -f "deployment_state.env" ]]; then
        error "deployment_state.env not found. This file is required for cleanup."
        error "If you deployed manually, create this file with the resource identifiers."
        exit 1
    fi
    
    # Source the deployment state
    source deployment_state.env
    
    # Validate required variables
    local required_vars=(
        "AWS_REGION" 
        "AWS_ACCOUNT_ID" 
        "RANDOM_SUFFIX" 
        "SERVICE_NETWORK_NAME" 
        "LOG_GROUP_NAME" 
        "LAMBDA_ROLE_NAME"
    )
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var}" ]]; then
            error "Required variable $var not found in deployment_state.env"
            exit 1
        fi
    done
    
    success "Deployment state loaded successfully"
    log "Region: ${AWS_REGION}, Suffix: ${RANDOM_SUFFIX}"
}

# Confirmation prompt
confirm_deletion() {
    echo
    warning "This will permanently delete ALL resources created by the deployment!"
    echo
    echo "Resources to be deleted:"
    echo "- VPC Lattice Service Network: ${SERVICE_NETWORK_NAME}"
    echo "- CloudWatch Log Group: ${LOG_GROUP_NAME}"
    echo "- Lambda Functions: performance-analyzer-${RANDOM_SUFFIX}, cost-correlator-${RANDOM_SUFFIX}, report-generator-${RANDOM_SUFFIX}"
    echo "- IAM Role: ${LAMBDA_ROLE_NAME}"
    echo "- EventBridge Rule: analytics-scheduler-${RANDOM_SUFFIX}"
    echo "- CloudWatch Dashboard: VPC-Lattice-Performance-Cost-Analytics-${RANDOM_SUFFIX}"
    echo "- Cost Anomaly Detection (if configured)"
    echo
    read -p "Are you sure you want to proceed? (yes/no): " -r
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Cleanup cancelled by user"
        exit 0
    fi
    
    echo
    log "Proceeding with resource cleanup..."
}

# Remove EventBridge rule and targets
remove_eventbridge_resources() {
    log "Removing EventBridge rule and targets..."
    
    local rule_name="analytics-scheduler-${RANDOM_SUFFIX}"
    
    # Check if rule exists
    if aws events describe-rule --name "$rule_name" &> /dev/null; then
        # Remove targets from EventBridge rule
        if aws events list-targets-by-rule --rule "$rule_name" --query 'Targets[0].Id' --output text | grep -q .; then
            log "Removing targets from EventBridge rule..."
            aws events remove-targets \
                --rule "$rule_name" \
                --ids "1"
            sleep 2
        fi
        
        # Delete EventBridge rule
        aws events delete-rule \
            --name "$rule_name"
        
        success "EventBridge rule removed: $rule_name"
    else
        warning "EventBridge rule $rule_name not found, skipping"
    fi
}

# Remove Lambda functions
remove_lambda_functions() {
    log "Removing Lambda functions..."
    
    local functions=("performance-analyzer" "cost-correlator" "report-generator")
    
    for func_base in "${functions[@]}"; do
        local func_name="${func_base}-${RANDOM_SUFFIX}"
        
        if aws lambda get-function --function-name "$func_name" &> /dev/null; then
            # Remove EventBridge permission if it exists
            aws lambda remove-permission \
                --function-name "$func_name" \
                --statement-id "analytics-eventbridge-${RANDOM_SUFFIX}" \
                2>/dev/null || true
            
            # Delete the Lambda function
            aws lambda delete-function \
                --function-name "$func_name"
            
            success "Lambda function deleted: $func_name"
        else
            warning "Lambda function $func_name not found, skipping"
        fi
    done
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log "Removing CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    local dashboard_name="VPC-Lattice-Performance-Cost-Analytics-${RANDOM_SUFFIX}"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" &> /dev/null; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "$dashboard_name"
        success "CloudWatch dashboard deleted: $dashboard_name"
    else
        warning "CloudWatch dashboard $dashboard_name not found, skipping"
    fi
    
    # Delete CloudWatch Log Group
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query "logGroups[?logGroupName=='${LOG_GROUP_NAME}']" --output text | grep -q "${LOG_GROUP_NAME}"; then
        aws logs delete-log-group \
            --log-group-name ${LOG_GROUP_NAME}
        success "CloudWatch Log Group deleted: ${LOG_GROUP_NAME}"
    else
        warning "CloudWatch Log Group ${LOG_GROUP_NAME} not found, skipping"
    fi
}

# Remove VPC Lattice resources
remove_vpc_lattice_resources() {
    log "Removing VPC Lattice resources..."
    
    # Get service network details if they exist
    local service_network_id=""
    local service_network_arn=""
    
    if aws vpc-lattice list-service-networks --query "serviceNetworks[?name=='${SERVICE_NETWORK_NAME}'].id" --output text | grep -q .; then
        service_network_id=$(aws vpc-lattice list-service-networks \
            --query "serviceNetworks[?name=='${SERVICE_NETWORK_NAME}'].id" \
            --output text)
        service_network_arn=$(aws vpc-lattice list-service-networks \
            --query "serviceNetworks[?name=='${SERVICE_NETWORK_NAME}'].arn" \
            --output text)
    fi
    
    if [[ -n "$service_network_id" ]]; then
        # Remove access log subscription
        if aws vpc-lattice get-access-log-subscription --resource-identifier "$service_network_arn" &> /dev/null; then
            aws vpc-lattice delete-access-log-subscription \
                --resource-identifier "$service_network_arn"
            success "Access log subscription removed"
        fi
        
        # Get and remove service network service associations
        local associations=$(aws vpc-lattice list-service-network-service-associations \
            --service-network-identifier "$service_network_id" \
            --query "serviceNetworkServiceAssociations[].id" \
            --output text)
        
        if [[ -n "$associations" ]] && [[ "$associations" != "None" ]]; then
            for association_id in $associations; do
                log "Removing service network association: $association_id"
                aws vpc-lattice delete-service-network-service-association \
                    --service-network-service-association-identifier "$association_id"
                sleep 2
            done
            success "Service network associations removed"
        fi
        
        # Find and delete sample services
        local sample_service_name="sample-analytics-service-${RANDOM_SUFFIX}"
        local sample_service_id=$(aws vpc-lattice list-services \
            --query "services[?name=='${sample_service_name}'].id" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$sample_service_id" ]] && [[ "$sample_service_id" != "None" ]]; then
            log "Deleting sample service: $sample_service_name"
            aws vpc-lattice delete-service \
                --service-identifier "$sample_service_id"
            success "Sample service deleted: $sample_service_name"
        fi
        
        # Wait for associations to be fully removed
        log "Waiting for service associations to be fully removed..."
        sleep 10
        
        # Delete service network
        aws vpc-lattice delete-service-network \
            --service-network-identifier "$service_network_id"
        success "VPC Lattice service network deleted: ${SERVICE_NETWORK_NAME}"
    else
        warning "VPC Lattice service network ${SERVICE_NETWORK_NAME} not found, skipping"
    fi
}

# Remove Cost Anomaly Detection resources
remove_cost_anomaly_resources() {
    log "Removing Cost Anomaly Detection resources..."
    
    # Try to find and remove cost anomaly subscription
    local subscription_arn=$(aws ce get-anomaly-subscriptions \
        --query "AnomalySubscriptions[?AnomalySubscriptionName=='lattice-cost-alerts-${RANDOM_SUFFIX}'].SubscriptionArn" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$subscription_arn" ]] && [[ "$subscription_arn" != "None" ]]; then
        aws ce delete-anomaly-subscription \
            --subscription-arn "$subscription_arn"
        success "Cost anomaly subscription removed"
    else
        warning "Cost anomaly subscription not found, skipping"
    fi
    
    # Try to find and remove cost anomaly detector
    local detector_arn=$(aws ce get-anomaly-detectors \
        --query "AnomalyDetectors[?AnomalyDetectorName=='vpc-lattice-cost-anomalies-${RANDOM_SUFFIX}'].AnomalyDetectorArn" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$detector_arn" ]] && [[ "$detector_arn" != "None" ]]; then
        aws ce delete-anomaly-detector \
            --anomaly-detector-arn "$detector_arn"
        success "Cost anomaly detector removed"
    else
        warning "Cost anomaly detector not found, skipping"
    fi
}

# Remove IAM resources
remove_iam_resources() {
    log "Removing IAM resources..."
    
    local role_name="${LAMBDA_ROLE_NAME}"
    local policy_name="CostExplorerAnalyticsPolicy-${RANDOM_SUFFIX}"
    
    # Check if role exists
    if aws iam get-role --role-name "$role_name" &> /dev/null; then
        # Detach policies from IAM role
        log "Detaching policies from IAM role..."
        
        # Detach AWS managed policies
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
            2>/dev/null || warning "Failed to detach AWSLambdaBasicExecutionRole policy"
        
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchLogsFullAccess \
            2>/dev/null || warning "Failed to detach CloudWatchLogsFullAccess policy"
        
        # Detach custom policy
        aws iam detach-role-policy \
            --role-name "$role_name" \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name" \
            2>/dev/null || warning "Failed to detach custom policy"
        
        # Delete IAM role
        aws iam delete-role \
            --role-name "$role_name"
        success "IAM role deleted: $role_name"
    else
        warning "IAM role $role_name not found, skipping"
    fi
    
    # Delete custom policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name" &> /dev/null; then
        aws iam delete-policy \
            --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$policy_name"
        success "Custom IAM policy deleted: $policy_name"
    else
        warning "Custom IAM policy $policy_name not found, skipping"
    fi
}

# Clean up local files
cleanup_local_files() {
    log "Cleaning up local files..."
    
    local files_to_remove=(
        "deployment_state.env"
        "deployment_summary.json"
        "lambda-trust-policy.json"
        "cost-explorer-policy.json"
        "dashboard-config.json"
        "lattice-insights-queries.json"
        "performance_analyzer.py"
        "cost_correlator.py"
        "report_generator.py"
        "performance-analyzer.zip"
        "cost-correlator.zip"
        "report-generator.zip"
        "response-performance.json"
        "response-cost.json"
        "analytics-report.json"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log "Removed: $file"
        fi
    done
    
    success "Local files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=()
    
    # Check VPC Lattice service network
    if aws vpc-lattice list-service-networks --query "serviceNetworks[?name=='${SERVICE_NETWORK_NAME}'].id" --output text 2>/dev/null | grep -q .; then
        cleanup_issues+=("VPC Lattice service network still exists: ${SERVICE_NETWORK_NAME}")
    fi
    
    # Check Lambda functions
    local functions=("performance-analyzer" "cost-correlator" "report-generator")
    for func_base in "${functions[@]}"; do
        local func_name="${func_base}-${RANDOM_SUFFIX}"
        if aws lambda get-function --function-name "$func_name" &> /dev/null; then
            cleanup_issues+=("Lambda function still exists: $func_name")
        fi
    done
    
    # Check IAM role
    if aws iam get-role --role-name "${LAMBDA_ROLE_NAME}" &> /dev/null; then
        cleanup_issues+=("IAM role still exists: ${LAMBDA_ROLE_NAME}")
    fi
    
    # Check CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" --query "logGroups[?logGroupName=='${LOG_GROUP_NAME}']" --output text 2>/dev/null | grep -q "${LOG_GROUP_NAME}"; then
        cleanup_issues+=("CloudWatch log group still exists: ${LOG_GROUP_NAME}")
    fi
    
    if [[ ${#cleanup_issues[@]} -eq 0 ]]; then
        success "Cleanup verification passed - all resources removed successfully"
    else
        warning "Cleanup verification found remaining resources:"
        for issue in "${cleanup_issues[@]}"; do
            warning "  - $issue"
        done
        echo
        warning "Some resources may take additional time to be fully deleted, or manual cleanup may be required."
        warning "Please check the AWS console to verify complete resource removal."
    fi
}

# Error handling
handle_error() {
    error "An error occurred during cleanup. Some resources may not have been deleted."
    error "Please check the AWS console and consider manual cleanup of remaining resources."
    warning "Common issues:"
    echo "  - Resource dependencies may prevent deletion"
    echo "  - IAM eventual consistency delays"
    echo "  - Regional service propagation delays"
    echo
    warning "Try running the cleanup script again after a few minutes if errors persist."
}

# Main cleanup function
main() {
    log "Starting Service Performance Cost Analytics cleanup..."
    
    # Set error trap
    trap handle_error ERR
    
    # Run cleanup steps in dependency order
    check_prerequisites
    load_deployment_state
    confirm_deletion
    
    log "Beginning resource cleanup..."
    
    # Remove resources in reverse dependency order
    remove_eventbridge_resources
    remove_lambda_functions
    remove_cloudwatch_resources
    remove_vpc_lattice_resources
    remove_cost_anomaly_resources
    remove_iam_resources
    cleanup_local_files
    
    # Verify cleanup
    verify_cleanup
    
    success "Cleanup completed successfully!"
    echo
    log "All AWS resources and local files have been removed."
    log "Please verify in the AWS console that all resources are deleted."
    echo
    log "Summary of actions taken:"
    echo "  ✅ EventBridge rule and targets removed"
    echo "  ✅ Lambda functions deleted"
    echo "  ✅ CloudWatch dashboard and log group removed"
    echo "  ✅ VPC Lattice service network and services deleted"
    echo "  ✅ Cost anomaly detection resources removed"
    echo "  ✅ IAM role and policies deleted"
    echo "  ✅ Local files cleaned up"
}

# Run main function
main "$@"