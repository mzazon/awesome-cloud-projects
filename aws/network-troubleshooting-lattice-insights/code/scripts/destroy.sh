#!/bin/bash

# Destroy script for Network Troubleshooting VPC Lattice with Network Insights
# This script removes all infrastructure components for the network troubleshooting solution

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to check prerequisites
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
    
    success "Prerequisites check passed"
}

# Function to load deployment state
load_deployment_state() {
    log "Loading deployment state..."
    
    if [ -f "deployment_state.env" ]; then
        # Source the environment file
        set -a  # Automatically export all variables
        source deployment_state.env
        set +a  # Stop auto-export
        
        success "Deployment state loaded from deployment_state.env"
        log "Found resources with suffix: ${RANDOM_SUFFIX:-unknown}"
    else
        warning "deployment_state.env not found. Will attempt to discover resources..."
        
        # Set basic environment variables
        export AWS_REGION=$(aws configure get region)
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to discover resources by scanning for patterns
        discover_resources
    fi
}

# Function to discover resources when state file is missing
discover_resources() {
    log "Attempting to discover resources..."
    
    # Look for VPC Lattice service networks with troubleshooting pattern
    local service_networks=$(aws vpc-lattice list-service-networks \
        --query "items[?contains(name, 'troubleshooting-network-')]" \
        --output text)
    
    if [ -n "$service_networks" ]; then
        warning "Found VPC Lattice service networks that may need cleanup"
        aws vpc-lattice list-service-networks \
            --query "items[?contains(name, 'troubleshooting-network-')].{Name:name,Id:id}" \
            --output table
    fi
    
    # Look for IAM roles with troubleshooting pattern
    local iam_roles=$(aws iam list-roles \
        --query "Roles[?contains(RoleName, 'NetworkTroubleshooting')]" \
        --output text)
    
    if [ -n "$iam_roles" ]; then
        warning "Found IAM roles that may need cleanup"
        aws iam list-roles \
            --query "Roles[?contains(RoleName, 'NetworkTroubleshooting')].{RoleName:RoleName,Created:CreateDate}" \
            --output table
    fi
    
    # Look for Lambda functions with troubleshooting pattern
    local lambda_functions=$(aws lambda list-functions \
        --query "Functions[?contains(FunctionName, 'network-troubleshooting-')]" \
        --output text)
    
    if [ -n "$lambda_functions" ]; then
        warning "Found Lambda functions that may need cleanup"
        aws lambda list-functions \
            --query "Functions[?contains(FunctionName, 'network-troubleshooting-')].{FunctionName:FunctionName,Runtime:Runtime}" \
            --output table
    fi
    
    warning "Manual cleanup may be required. Check the AWS console for remaining resources."
}

# Function to remove Lambda function and SNS resources
cleanup_lambda_sns() {
    log "Cleaning up Lambda function and SNS resources..."
    
    # Delete Lambda function
    if [ -n "${LAMBDA_FUNCTION_NAME:-}" ]; then
        if aws lambda get-function --function-name ${LAMBDA_FUNCTION_NAME} &> /dev/null; then
            aws lambda delete-function --function-name ${LAMBDA_FUNCTION_NAME}
            success "Lambda function ${LAMBDA_FUNCTION_NAME} deleted"
        else
            warning "Lambda function ${LAMBDA_FUNCTION_NAME} not found"
        fi
    else
        # Try to find and delete Lambda functions with pattern
        local lambda_functions=$(aws lambda list-functions \
            --query "Functions[?contains(FunctionName, 'network-troubleshooting-')].FunctionName" \
            --output text)
        
        for func in $lambda_functions; do
            if [ -n "$func" ]; then
                aws lambda delete-function --function-name $func
                success "Lambda function $func deleted"
            fi
        done
    fi
    
    # Delete SNS topic
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        if aws sns get-topic-attributes --topic-arn ${SNS_TOPIC_ARN} &> /dev/null; then
            aws sns delete-topic --topic-arn ${SNS_TOPIC_ARN}
            success "SNS topic deleted"
        else
            warning "SNS topic ${SNS_TOPIC_ARN} not found"
        fi
    else
        # Try to find and delete SNS topics with pattern
        local sns_topics=$(aws sns list-topics \
            --query "Topics[?contains(TopicArn, 'network-alerts-')].TopicArn" \
            --output text)
        
        for topic in $sns_topics; do
            if [ -n "$topic" ]; then
                aws sns delete-topic --topic-arn $topic
                success "SNS topic $topic deleted"
            fi
        done
    fi
}

# Function to delete CloudWatch resources
cleanup_cloudwatch() {
    log "Cleaning up CloudWatch resources..."
    
    # Delete CloudWatch alarms
    local alarm_names=()
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        alarm_names+=("VPCLattice-HighErrorRate-${RANDOM_SUFFIX}")
        alarm_names+=("VPCLattice-HighLatency-${RANDOM_SUFFIX}")
    else
        # Find alarms with pattern
        local found_alarms=$(aws cloudwatch describe-alarms \
            --alarm-name-prefix "VPCLattice-" \
            --query "MetricAlarms[?contains(AlarmName, 'HighErrorRate-') || contains(AlarmName, 'HighLatency-')].AlarmName" \
            --output text)
        
        for alarm in $found_alarms; do
            if [ -n "$alarm" ]; then
                alarm_names+=("$alarm")
            fi
        done
    fi
    
    if [ ${#alarm_names[@]} -gt 0 ]; then
        aws cloudwatch delete-alarms --alarm-names "${alarm_names[@]}"
        success "CloudWatch alarms deleted"
    else
        warning "No CloudWatch alarms found to delete"
    fi
    
    # Delete CloudWatch dashboard
    if [ -n "${RANDOM_SUFFIX:-}" ]; then
        local dashboard_name="VPCLatticeNetworkTroubleshooting-${RANDOM_SUFFIX}"
        if aws cloudwatch get-dashboard --dashboard-name ${dashboard_name} &> /dev/null; then
            aws cloudwatch delete-dashboards --dashboard-names ${dashboard_name}
            success "CloudWatch dashboard deleted"
        else
            warning "CloudWatch dashboard ${dashboard_name} not found"
        fi
    else
        # Find dashboards with pattern
        local dashboards=$(aws cloudwatch list-dashboards \
            --dashboard-name-prefix "VPCLatticeNetworkTroubleshooting-" \
            --query "DashboardEntries[].DashboardName" \
            --output text)
        
        for dashboard in $dashboards; do
            if [ -n "$dashboard" ]; then
                aws cloudwatch delete-dashboards --dashboard-names $dashboard
                success "CloudWatch dashboard $dashboard deleted"
            fi
        done
    fi
    
    # Delete log group
    if [ -n "${SERVICE_NETWORK_ID:-}" ]; then
        local log_group="/aws/vpclattice/servicenetwork/${SERVICE_NETWORK_ID}"
        if aws logs describe-log-groups --log-group-name-prefix ${log_group} &> /dev/null; then
            aws logs delete-log-group --log-group-name ${log_group}
            success "CloudWatch log group deleted"
        else
            warning "CloudWatch log group ${log_group} not found"
        fi
    else
        # Find log groups with pattern
        local log_groups=$(aws logs describe-log-groups \
            --log-group-name-prefix "/aws/vpclattice/servicenetwork/" \
            --query "logGroups[].logGroupName" \
            --output text)
        
        for log_group in $log_groups; do
            if [ -n "$log_group" ]; then
                aws logs delete-log-group --log-group-name $log_group
                success "CloudWatch log group $log_group deleted"
            fi
        done
    fi
}

# Function to clean up Network Insights resources
cleanup_network_insights() {
    log "Cleaning up Network Insights resources..."
    
    # Find and delete network insights analyses
    local analyses=$(aws ec2 describe-network-insights-analyses \
        --filters "Name=tag:Name,Values=AutomatedAnalysis" \
        --query "NetworkInsightsAnalyses[*].NetworkInsightsAnalysisId" \
        --output text)
    
    for analysis in $analyses; do
        if [ -n "$analysis" ] && [ "$analysis" != "None" ]; then
            aws ec2 delete-network-insights-analysis \
                --network-insights-analysis-id $analysis || true
            success "Network insights analysis $analysis deleted"
        fi
    done
    
    # Find and delete network insights paths
    local paths=$(aws ec2 describe-network-insights-paths \
        --filters "Name=tag:Name,Values=AutomatedTroubleshooting" \
        --query "NetworkInsightsPaths[*].NetworkInsightsPathId" \
        --output text)
    
    for path in $paths; do
        if [ -n "$path" ] && [ "$path" != "None" ]; then
            aws ec2 delete-network-insights-path \
                --network-insights-path-id $path || true
            success "Network insights path $path deleted"
        fi
    done
    
    if [ -z "$analyses" ] && [ -z "$paths" ]; then
        warning "No Network Insights resources found to clean up"
    fi
}

# Function to remove Systems Manager automation document
cleanup_automation() {
    log "Cleaning up Systems Manager automation document..."
    
    if [ -n "${AUTOMATION_DOCUMENT_NAME:-}" ]; then
        if aws ssm describe-document --name ${AUTOMATION_DOCUMENT_NAME} &> /dev/null; then
            aws ssm delete-document --name ${AUTOMATION_DOCUMENT_NAME}
            success "Automation document ${AUTOMATION_DOCUMENT_NAME} deleted"
        else
            warning "Automation document ${AUTOMATION_DOCUMENT_NAME} not found"
        fi
    else
        # Find documents with pattern
        local documents=$(aws ssm list-documents \
            --filters "Key=Name,Values=NetworkReachabilityAnalysis-*" \
            --query "DocumentIdentifiers[].Name" \
            --output text)
        
        for doc in $documents; do
            if [ -n "$doc" ]; then
                aws ssm delete-document --name $doc
                success "Automation document $doc deleted"
            fi
        done
    fi
}

# Function to delete VPC Lattice resources
cleanup_lattice() {
    log "Cleaning up VPC Lattice resources..."
    
    # Delete VPC association first
    if [ -n "${VPC_ASSOCIATION_ID:-}" ]; then
        if aws vpc-lattice get-service-network-vpc-association \
            --service-network-vpc-association-identifier ${VPC_ASSOCIATION_ID} &> /dev/null; then
            
            aws vpc-lattice delete-service-network-vpc-association \
                --service-network-vpc-association-identifier ${VPC_ASSOCIATION_ID}
            
            # Wait for association deletion
            log "Waiting for VPC association deletion..."
            local max_attempts=30
            local attempt=0
            
            while [ $attempt -lt $max_attempts ]; do
                if ! aws vpc-lattice get-service-network-vpc-association \
                    --service-network-vpc-association-identifier ${VPC_ASSOCIATION_ID} &> /dev/null; then
                    break
                fi
                sleep 10
                attempt=$((attempt + 1))
            done
            
            success "VPC association deleted"
        else
            warning "VPC association ${VPC_ASSOCIATION_ID} not found"
        fi
    fi
    
    # Delete service network
    if [ -n "${SERVICE_NETWORK_ID:-}" ]; then
        if aws vpc-lattice get-service-network \
            --service-network-identifier ${SERVICE_NETWORK_ID} &> /dev/null; then
            
            aws vpc-lattice delete-service-network \
                --service-network-identifier ${SERVICE_NETWORK_ID}
            success "VPC Lattice service network ${SERVICE_NETWORK_ID} deleted"
        else
            warning "VPC Lattice service network ${SERVICE_NETWORK_ID} not found"
        fi
    else
        # Find and delete service networks with pattern
        local service_networks=$(aws vpc-lattice list-service-networks \
            --query "items[?contains(name, 'troubleshooting-network-')].{Name:name,Id:id}" \
            --output text)
        
        if [ -n "$service_networks" ]; then
            echo "$service_networks" | while read name id; do
                if [ -n "$id" ] && [ "$id" != "None" ]; then
                    # First delete any VPC associations
                    local vpc_associations=$(aws vpc-lattice list-service-network-vpc-associations \
                        --service-network-identifier $id \
                        --query "items[].id" \
                        --output text)
                    
                    for assoc in $vpc_associations; do
                        if [ -n "$assoc" ] && [ "$assoc" != "None" ]; then
                            aws vpc-lattice delete-service-network-vpc-association \
                                --service-network-vpc-association-identifier $assoc
                            sleep 15  # Wait for deletion
                        fi
                    done
                    
                    # Then delete the service network
                    aws vpc-lattice delete-service-network \
                        --service-network-identifier $id
                    success "VPC Lattice service network $name ($id) deleted"
                fi
            done
        else
            warning "No VPC Lattice service networks found to delete"
        fi
    fi
}

# Function to remove EC2 test resources
cleanup_ec2() {
    log "Cleaning up EC2 test resources..."
    
    # Terminate test instance
    if [ -n "${INSTANCE_ID:-}" ]; then
        if aws ec2 describe-instances \
            --instance-ids ${INSTANCE_ID} \
            --query "Reservations[0].Instances[0].State.Name" \
            --output text 2>/dev/null | grep -v "terminated" &> /dev/null; then
            
            aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}
            
            # Wait for termination
            log "Waiting for instance termination..."
            aws ec2 wait instance-terminated --instance-ids ${INSTANCE_ID}
            success "Test instance ${INSTANCE_ID} terminated"
        else
            warning "Test instance ${INSTANCE_ID} not found or already terminated"
        fi
    else
        # Find instances with pattern
        local instances=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=lattice-test-*" \
                      "Name=instance-state-name,Values=running,stopped,stopping" \
            --query "Reservations[].Instances[].InstanceId" \
            --output text)
        
        for instance in $instances; do
            if [ -n "$instance" ] && [ "$instance" != "None" ]; then
                aws ec2 terminate-instances --instance-ids $instance
                success "Test instance $instance terminated"
            fi
        done
    fi
    
    # Delete security group (after instance termination)
    if [ -n "${SG_ID:-}" ]; then
        # Wait a bit for instance termination to complete
        sleep 30
        
        if aws ec2 describe-security-groups --group-ids ${SG_ID} &> /dev/null; then
            aws ec2 delete-security-group --group-id ${SG_ID}
            success "Security group ${SG_ID} deleted"
        else
            warning "Security group ${SG_ID} not found"
        fi
    else
        # Find security groups with pattern
        local security_groups=$(aws ec2 describe-security-groups \
            --filters "Name=group-name,Values=lattice-test-sg-*" \
            --query "SecurityGroups[].GroupId" \
            --output text)
        
        sleep 30  # Wait for instances to terminate
        
        for sg in $security_groups; do
            if [ -n "$sg" ] && [ "$sg" != "None" ]; then
                aws ec2 delete-security-group --group-id $sg || true
                success "Security group $sg deleted"
            fi
        done
    fi
}

# Function to delete IAM roles
cleanup_iam_roles() {
    log "Cleaning up IAM roles..."
    
    # Define role names
    local roles_to_delete=()
    if [ -n "${AUTOMATION_ROLE_NAME:-}" ]; then
        roles_to_delete+=("${AUTOMATION_ROLE_NAME}")
    fi
    if [ -n "${LAMBDA_ROLE_NAME:-}" ]; then
        roles_to_delete+=("${LAMBDA_ROLE_NAME}")
    fi
    
    # If no specific role names, find by pattern
    if [ ${#roles_to_delete[@]} -eq 0 ]; then
        local found_roles=$(aws iam list-roles \
            --query "Roles[?contains(RoleName, 'NetworkTroubleshooting')].RoleName" \
            --output text)
        
        for role in $found_roles; do
            if [ -n "$role" ]; then
                roles_to_delete+=("$role")
            fi
        done
    fi
    
    # Process each role
    for role_name in "${roles_to_delete[@]}"; do
        if aws iam get-role --role-name ${role_name} &> /dev/null; then
            # Detach policies first
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name ${role_name} \
                --query "AttachedPolicies[].PolicyArn" \
                --output text)
            
            for policy_arn in $attached_policies; do
                if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
                    aws iam detach-role-policy \
                        --role-name ${role_name} \
                        --policy-arn ${policy_arn}
                fi
            done
            
            # Delete the role
            aws iam delete-role --role-name ${role_name}
            success "IAM role ${role_name} deleted"
        else
            warning "IAM role ${role_name} not found"
        fi
    done
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "ssm-trust-policy.json"
        "lambda-trust-policy.json"
        "network-dashboard.json"
        "reachability-analysis.json"
        "troubleshooting_function.py"
        "troubleshooting_function.zip"
        "test-event.json"
        "response.json"
        "deployment_state.env"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            success "Temporary file $file deleted"
        fi
    done
}

# Function to display cleanup summary
display_cleanup_summary() {
    log "Cleanup Summary"
    echo "==============="
    echo "The following resources have been cleaned up:"
    echo "- Lambda function and SNS topic"
    echo "- CloudWatch alarms, dashboard, and log groups"
    echo "- Network Insights paths and analyses"
    echo "- Systems Manager automation document"
    echo "- VPC Lattice service network and associations"
    echo "- EC2 test instances and security groups"
    echo "- IAM roles and attached policies"
    echo "- Temporary files"
    echo ""
    success "All network troubleshooting infrastructure has been removed!"
    echo ""
    warning "Please verify in the AWS console that all resources have been properly cleaned up"
    log "You can also check for any remaining costs in the AWS Billing console"
}

# Function to handle partial cleanup when state file is missing
cleanup_discovered_resources() {
    log "Performing discovery-based cleanup..."
    
    warning "deployment_state.env not found. Attempting to discover and clean up resources..."
    warning "This may not catch all resources. Manual verification recommended."
    
    # Try to clean up resources by pattern matching
    cleanup_lambda_sns
    cleanup_cloudwatch
    cleanup_network_insights
    cleanup_automation
    cleanup_lattice
    cleanup_ec2
    cleanup_iam_roles
    cleanup_temp_files
    
    warning "Discovery-based cleanup completed. Please check AWS console for any remaining resources."
}

# Main cleanup function
main() {
    log "Starting Network Troubleshooting VPC Lattice cleanup..."
    
    # Check if running with --help
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        echo "Network Troubleshooting VPC Lattice Cleanup Script"
        echo ""
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --force        Skip confirmation prompts"
        echo "  --discovered   Clean up discovered resources even without state file"
        echo ""
        echo "This script removes all infrastructure components including:"
        echo "- VPC Lattice service mesh"
        echo "- Test EC2 instances and security groups"
        echo "- CloudWatch monitoring resources"
        echo "- Systems Manager automation documents"
        echo "- Lambda functions and SNS topics"
        echo "- IAM roles and policies"
        echo ""
        exit 0
    fi
    
    # Confirmation prompt unless --force is used
    if [[ "${1:-}" != "--force" ]] && [[ "${1:-}" != "--discovered" ]]; then
        echo "This will delete ALL network troubleshooting infrastructure components:"
        echo "- VPC Lattice service network and associations"
        echo "- Test EC2 instances and security groups"
        echo "- CloudWatch dashboards, alarms, and log groups"
        echo "- Systems Manager automation documents"
        echo "- Lambda functions and SNS topics"
        echo "- IAM roles and attached policies"
        echo "- All temporary files"
        echo ""
        warning "This action is IRREVERSIBLE!"
        echo ""
        read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Check prerequisites
    check_prerequisites
    
    # Load deployment state or discover resources
    if [[ "${1:-}" == "--discovered" ]]; then
        export AWS_REGION=$(aws configure get region)
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        cleanup_discovered_resources
    else
        load_deployment_state
        
        if [ -f "deployment_state.env" ]; then
            # Execute cleanup steps in reverse order of deployment
            cleanup_lambda_sns
            cleanup_cloudwatch
            cleanup_network_insights
            cleanup_automation
            cleanup_lattice
            cleanup_ec2
            cleanup_iam_roles
            cleanup_temp_files
            
            display_cleanup_summary
        else
            cleanup_discovered_resources
        fi
    fi
}

# Run main function with all arguments
main "$@"