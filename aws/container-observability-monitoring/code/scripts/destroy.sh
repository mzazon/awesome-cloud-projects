#!/bin/bash

# Comprehensive Container Observability Performance Monitoring - Destroy Script
# This script removes all resources created by the deployment script

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
RESOURCE_STATE_FILE="${SCRIPT_DIR}/deployed_resources.json"
DEPLOYMENT_VARS_FILE="${SCRIPT_DIR}/deployment_vars.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

# Error handling function
handle_error() {
    log "${RED}ERROR: $1${NC}"
    log "${RED}Cleanup may be incomplete. Check ${LOG_FILE} for details.${NC}"
    exit 1
}

# Success function
log_success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning function
log_warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info function
log_info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Confirmation prompt
confirm_destruction() {
    local resource_count=0
    
    if [[ -f "${RESOURCE_STATE_FILE}" ]]; then
        resource_count=$(jq '.resources | length' "${RESOURCE_STATE_FILE}" 2>/dev/null || echo "0")
    fi
    
    echo ""
    log_warning "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    log_warning "This will permanently delete all observability infrastructure resources."
    log_warning "Resources to be deleted: ${resource_count}"
    echo ""
    
    if [[ -f "${DEPLOYMENT_VARS_FILE}" ]]; then
        source "${DEPLOYMENT_VARS_FILE}"
        log_info "Resources found in the following AWS account and region:"
        log_info "  AWS Account: ${AWS_ACCOUNT_ID:-Unknown}"
        log_info "  AWS Region: ${AWS_REGION:-Unknown}"
        log_info "  EKS Cluster: ${EKS_CLUSTER_NAME:-Unknown}"
        log_info "  ECS Cluster: ${ECS_CLUSTER_NAME:-Unknown}"
        echo ""
    fi
    
    read -p "Are you sure you want to proceed? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_info "Destruction cancelled by user."
        exit 0
    fi
    
    read -p "Type 'DELETE' to confirm: " -r
    if [[ $REPLY != "DELETE" ]]; then
        log_info "Destruction cancelled - confirmation text did not match."
        exit 0
    fi
    
    log_info "Starting resource destruction..."
}

# Load environment variables
load_environment() {
    log_info "Loading environment variables..."
    
    if [[ -f "${DEPLOYMENT_VARS_FILE}" ]]; then
        source "${DEPLOYMENT_VARS_FILE}"
        log_info "Environment variables loaded from ${DEPLOYMENT_VARS_FILE}"
    else
        log_warning "Environment variables file not found. Attempting to discover resources..."
        
        # Try to discover resources
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
        
        if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
            handle_error "Unable to determine AWS account ID. Please ensure AWS CLI is configured."
        fi
        
        # Try to find clusters with observability pattern
        local eks_clusters=$(aws eks list-clusters --query 'clusters[?contains(@, `observability-eks-`)]' --output text 2>/dev/null || echo "")
        local ecs_clusters=$(aws ecs list-clusters --query 'clusterArns[?contains(@, `observability-ecs-`)]' --output text 2>/dev/null || echo "")
        
        if [[ -n "${eks_clusters}" ]]; then
            export EKS_CLUSTER_NAME=$(echo "${eks_clusters}" | head -1)
            export RANDOM_SUFFIX=$(echo "${EKS_CLUSTER_NAME}" | sed 's/observability-eks-//')
        fi
        
        if [[ -n "${ecs_clusters}" ]]; then
            export ECS_CLUSTER_NAME=$(basename "${ecs_clusters}" | head -1)
            if [[ -z "${RANDOM_SUFFIX}" ]]; then
                export RANDOM_SUFFIX=$(echo "${ECS_CLUSTER_NAME}" | sed 's/observability-ecs-//')
            fi
        fi
        
        export MONITORING_NAMESPACE="monitoring"
        export OPENSEARCH_DOMAIN="container-logs-${RANDOM_SUFFIX}"
        
        log_info "Discovered resources:"
        log_info "  EKS Cluster: ${EKS_CLUSTER_NAME:-Not found}"
        log_info "  ECS Cluster: ${ECS_CLUSTER_NAME:-Not found}"
        log_info "  Random Suffix: ${RANDOM_SUFFIX:-Not found}"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("aws" "kubectl" "eksctl" "helm" "jq")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            handle_error "Required tool '$tool' is not installed or not in PATH"
        fi
    done
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        handle_error "AWS CLI is not configured. Please run 'aws configure'"
    fi
    
    log_success "Prerequisites check completed"
}

# Remove sample applications
remove_sample_applications() {
    log_info "Removing sample applications..."
    
    # Remove EKS sample application
    if [[ -n "${EKS_CLUSTER_NAME}" ]] && aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" >/dev/null 2>&1; then
        # Update kubeconfig
        aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
        
        # Remove EKS sample app
        if [[ -f "${SCRIPT_DIR}/eks-sample-app.yaml" ]]; then
            kubectl delete -f "${SCRIPT_DIR}/eks-sample-app.yaml" --ignore-not-found=true || log_warning "Failed to remove EKS sample application"
        else
            kubectl delete deployment observability-demo-app --ignore-not-found=true || true
            kubectl delete service observability-demo-service --ignore-not-found=true || true
        fi
        
        log_success "EKS sample application removed"
    else
        log_info "EKS cluster not found, skipping EKS sample application removal"
    fi
    
    # Remove ECS sample application
    if [[ -n "${ECS_CLUSTER_NAME}" ]] && aws ecs describe-clusters --clusters "${ECS_CLUSTER_NAME}" >/dev/null 2>&1; then
        # Stop and delete ECS service
        aws ecs update-service \
            --cluster "${ECS_CLUSTER_NAME}" \
            --service observability-demo-service \
            --desired-count 0 >/dev/null 2>&1 || true
        
        # Wait for service to stop
        aws ecs wait services-stable \
            --cluster "${ECS_CLUSTER_NAME}" \
            --services observability-demo-service >/dev/null 2>&1 || true
        
        aws ecs delete-service \
            --cluster "${ECS_CLUSTER_NAME}" \
            --service observability-demo-service >/dev/null 2>&1 || true
        
        # Deregister task definition
        local task_def_arn=$(aws ecs describe-task-definition \
            --task-definition observability-demo-task \
            --query 'taskDefinition.taskDefinitionArn' \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "${task_def_arn}" ]]; then
            aws ecs deregister-task-definition \
                --task-definition "${task_def_arn}" >/dev/null 2>&1 || true
        fi
        
        log_success "ECS sample application removed"
    else
        log_info "ECS cluster not found, skipping ECS sample application removal"
    fi
}

# Remove monitoring stack
remove_monitoring_stack() {
    log_info "Removing monitoring stack..."
    
    if [[ -n "${EKS_CLUSTER_NAME}" ]] && aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" >/dev/null 2>&1; then
        # Update kubeconfig
        aws eks update-kubeconfig --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1 || true
        
        # Remove Helm releases
        helm uninstall grafana -n "${MONITORING_NAMESPACE}" >/dev/null 2>&1 || log_warning "Failed to remove Grafana"
        helm uninstall prometheus -n "${MONITORING_NAMESPACE}" >/dev/null 2>&1 || log_warning "Failed to remove Prometheus"
        
        # Remove ADOT collector
        if [[ -f "${SCRIPT_DIR}/adot-collector-config.yaml" ]]; then
            kubectl delete -f "${SCRIPT_DIR}/adot-collector-config.yaml" --ignore-not-found=true || true
        fi
        
        # Remove ADOT operator
        kubectl delete -f https://github.com/aws-observability/aws-otel-operator/releases/latest/download/opentelemetry-operator.yaml --ignore-not-found=true >/dev/null 2>&1 || true
        
        # Remove Container Insights
        if [[ -f "${SCRIPT_DIR}/cwagent-fluent-bit-quickstart.yaml" ]]; then
            kubectl delete -f "${SCRIPT_DIR}/cwagent-fluent-bit-quickstart.yaml" --ignore-not-found=true || true
        fi
        
        # Remove monitoring namespace
        kubectl delete namespace "${MONITORING_NAMESPACE}" --ignore-not-found=true >/dev/null 2>&1 || true
        
        log_success "Monitoring stack removed"
    else
        log_info "EKS cluster not found, skipping monitoring stack removal"
    fi
}

# Remove CloudWatch resources
remove_cloudwatch_resources() {
    log_info "Removing CloudWatch resources..."
    
    # Remove CloudWatch alarms
    local alarm_names=(
        "EKS-High-CPU-Utilization"
        "EKS-High-Memory-Utilization"
        "ECS-Service-Unhealthy-Tasks"
        "EKS-CPU-Anomaly-Detection"
    )
    
    for alarm_name in "${alarm_names[@]}"; do
        aws cloudwatch delete-alarms --alarm-names "$alarm_name" >/dev/null 2>&1 || true
    done
    
    # Remove anomaly detectors
    if [[ -n "${EKS_CLUSTER_NAME}" ]]; then
        aws cloudwatch delete-anomaly-detector \
            --namespace "AWS/ContainerInsights" \
            --metric-name "pod_cpu_utilization" \
            --dimensions Name=ClusterName,Value="${EKS_CLUSTER_NAME}" \
            --stat Average >/dev/null 2>&1 || true
        
        aws cloudwatch delete-anomaly-detector \
            --namespace "AWS/ContainerInsights" \
            --metric-name "pod_memory_utilization" \
            --dimensions Name=ClusterName,Value="${EKS_CLUSTER_NAME}" \
            --stat Average >/dev/null 2>&1 || true
    fi
    
    # Remove dashboard
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        aws cloudwatch delete-dashboards \
            --dashboard-names "Container-Observability-${RANDOM_SUFFIX}" >/dev/null 2>&1 || true
    fi
    
    log_success "CloudWatch resources removed"
}

# Remove OpenSearch domain
remove_opensearch_domain() {
    log_info "Removing OpenSearch domain..."
    
    if [[ -n "${OPENSEARCH_DOMAIN}" ]]; then
        # Check if domain exists
        if aws opensearch describe-domain --domain-name "${OPENSEARCH_DOMAIN}" >/dev/null 2>&1; then
            log_info "Deleting OpenSearch domain (this may take 10-15 minutes)..."
            aws opensearch delete-domain --domain-name "${OPENSEARCH_DOMAIN}" >/dev/null 2>&1 || log_warning "Failed to delete OpenSearch domain"
            log_success "OpenSearch domain deletion initiated"
        else
            log_info "OpenSearch domain not found"
        fi
    else
        log_info "OpenSearch domain name not available, skipping removal"
    fi
}

# Remove Lambda functions and EventBridge rules
remove_lambda_resources() {
    log_info "Removing Lambda functions and EventBridge rules..."
    
    # Remove EventBridge rule targets
    aws events remove-targets \
        --rule "container-performance-analysis" \
        --ids "1" >/dev/null 2>&1 || true
    
    # Remove EventBridge rule
    aws events delete-rule \
        --name "container-performance-analysis" >/dev/null 2>&1 || true
    
    # Remove Lambda function
    aws lambda delete-function \
        --function-name "container-performance-optimizer" >/dev/null 2>&1 || true
    
    log_success "Lambda resources removed"
}

# Remove ECS cluster
remove_ecs_cluster() {
    log_info "Removing ECS cluster..."
    
    if [[ -n "${ECS_CLUSTER_NAME}" ]]; then
        # Check if cluster exists
        if aws ecs describe-clusters --clusters "${ECS_CLUSTER_NAME}" --query 'clusters[0].clusterName' --output text 2>/dev/null | grep -q "${ECS_CLUSTER_NAME}"; then
            
            # List and stop all services
            local services=$(aws ecs list-services --cluster "${ECS_CLUSTER_NAME}" --query 'serviceArns' --output text 2>/dev/null || echo "")
            if [[ -n "${services}" ]]; then
                for service in ${services}; do
                    local service_name=$(basename "$service")
                    aws ecs update-service \
                        --cluster "${ECS_CLUSTER_NAME}" \
                        --service "$service_name" \
                        --desired-count 0 >/dev/null 2>&1 || true
                done
                
                # Wait for services to stop
                sleep 30
                
                # Delete services
                for service in ${services}; do
                    local service_name=$(basename "$service")
                    aws ecs delete-service \
                        --cluster "${ECS_CLUSTER_NAME}" \
                        --service "$service_name" >/dev/null 2>&1 || true
                done
            fi
            
            # Delete cluster
            aws ecs delete-cluster --cluster "${ECS_CLUSTER_NAME}" >/dev/null 2>&1 || log_warning "Failed to delete ECS cluster"
            log_success "ECS cluster removed"
        else
            log_info "ECS cluster not found"
        fi
    else
        log_info "ECS cluster name not available, skipping removal"
    fi
}

# Remove EKS cluster
remove_eks_cluster() {
    log_info "Removing EKS cluster..."
    
    if [[ -n "${EKS_CLUSTER_NAME}" ]]; then
        # Check if cluster exists
        if aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" >/dev/null 2>&1; then
            log_info "Deleting EKS cluster (this may take 15-20 minutes)..."
            
            # Delete cluster using eksctl if config file exists
            if [[ -f "${SCRIPT_DIR}/eks-observability-config.yaml" ]]; then
                eksctl delete cluster -f "${SCRIPT_DIR}/eks-observability-config.yaml" --wait || log_warning "Failed to delete EKS cluster with eksctl"
            else
                eksctl delete cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" --wait || log_warning "Failed to delete EKS cluster"
            fi
            
            log_success "EKS cluster removed"
        else
            log_info "EKS cluster not found"
        fi
    else
        log_info "EKS cluster name not available, skipping removal"
    fi
}

# Remove IAM roles
remove_iam_roles() {
    log_info "Removing IAM roles..."
    
    if [[ -n "${RANDOM_SUFFIX}" ]]; then
        # Remove ECS task execution role
        local ecs_role_name="ecsTaskExecutionRole-${RANDOM_SUFFIX}"
        if aws iam get-role --role-name "$ecs_role_name" >/dev/null 2>&1; then
            # Detach policies
            local policies=(
                "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
                "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
                "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
            )
            
            for policy in "${policies[@]}"; do
                aws iam detach-role-policy \
                    --role-name "$ecs_role_name" \
                    --policy-arn "$policy" >/dev/null 2>&1 || true
            done
            
            aws iam delete-role --role-name "$ecs_role_name" >/dev/null 2>&1 || true
            log_success "ECS task execution role removed"
        fi
        
        # Remove performance optimizer role
        local optimizer_role_name="PerformanceOptimizerRole-${RANDOM_SUFFIX}"
        if aws iam get-role --role-name "$optimizer_role_name" >/dev/null 2>&1; then
            aws iam detach-role-policy \
                --role-name "$optimizer_role_name" \
                --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole >/dev/null 2>&1 || true
            
            aws iam detach-role-policy \
                --role-name "$optimizer_role_name" \
                --policy-arn arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess >/dev/null 2>&1 || true
            
            aws iam delete-role --role-name "$optimizer_role_name" >/dev/null 2>&1 || true
            log_success "Performance optimizer role removed"
        fi
    else
        log_info "Random suffix not available, skipping IAM role removal"
    fi
}

# Remove foundational resources
remove_foundational_resources() {
    log_info "Removing foundational resources..."
    
    # Remove SNS topic
    if [[ -n "${AWS_REGION}" ]] && [[ -n "${AWS_ACCOUNT_ID}" ]]; then
        aws sns delete-topic \
            --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:container-observability-alerts" >/dev/null 2>&1 || true
    fi
    
    # Remove CloudWatch log groups
    if [[ -n "${EKS_CLUSTER_NAME}" ]]; then
        local log_groups=(
            "/aws/eks/${EKS_CLUSTER_NAME}/application"
            "/aws/containerinsights/${EKS_CLUSTER_NAME}/application"
        )
        
        for log_group in "${log_groups[@]}"; do
            aws logs delete-log-group --log-group-name "$log_group" >/dev/null 2>&1 || true
        done
    fi
    
    if [[ -n "${ECS_CLUSTER_NAME}" ]]; then
        aws logs delete-log-group --log-group-name "/aws/ecs/${ECS_CLUSTER_NAME}/application" >/dev/null 2>&1 || true
    fi
    
    # Remove any EKS-related log groups
    local eks_log_groups=$(aws logs describe-log-groups \
        --log-group-name-prefix "/aws/eks/" \
        --query 'logGroups[?contains(logGroupName, `observability-eks-`)].logGroupName' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "${eks_log_groups}" ]]; then
        for log_group in ${eks_log_groups}; do
            aws logs delete-log-group --log-group-name "$log_group" >/dev/null 2>&1 || true
        done
    fi
    
    log_success "Foundational resources removed"
}

# Clean up local files
cleanup_local_files() {
    log_info "Cleaning up local files..."
    
    # Remove generated files
    local files_to_remove=(
        "${SCRIPT_DIR}/eks-observability-config.yaml"
        "${SCRIPT_DIR}/prometheus-values.yaml"
        "${SCRIPT_DIR}/grafana-values.yaml"
        "${SCRIPT_DIR}/adot-collector-config.yaml"
        "${SCRIPT_DIR}/eks-sample-app.yaml"
        "${SCRIPT_DIR}/ecs-task-definition.json"
        "${SCRIPT_DIR}/ecs-task-execution-role.json"
        "${SCRIPT_DIR}/container-observability-dashboard.json"
        "${SCRIPT_DIR}/performance-optimizer.py"
        "${SCRIPT_DIR}/performance-optimizer.zip"
        "${SCRIPT_DIR}/lambda-execution-role.json"
        "${SCRIPT_DIR}/opensearch-domain.json"
        "${SCRIPT_DIR}/firehose-opensearch-config.json"
        "${SCRIPT_DIR}/cwagent-fluent-bit-quickstart.yaml"
        "${SCRIPT_DIR}/cwagent-fluent-bit-quickstart.yaml.bak"
        "${RESOURCE_STATE_FILE}"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file" || true
        fi
    done
    
    log_success "Local files cleaned up"
}

# Update resource state
update_destruction_status() {
    if [[ -f "${RESOURCE_STATE_FILE}" ]]; then
        local temp_file=$(mktemp)
        jq '.status = "destroyed" | .end_time = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
           "${RESOURCE_STATE_FILE}" > "$temp_file" && mv "$temp_file" "${RESOURCE_STATE_FILE}" || true
    fi
}

# Main destruction function
main() {
    log_info "Starting comprehensive container observability destruction..."
    log_info "Destruction started at: $(date)"
    
    # Check prerequisites
    check_prerequisites
    
    # Load environment variables
    load_environment
    
    # Confirmation prompt
    confirm_destruction
    
    # Run destruction steps in reverse order
    remove_sample_applications
    remove_monitoring_stack
    remove_cloudwatch_resources
    remove_opensearch_domain
    remove_lambda_resources
    remove_ecs_cluster
    remove_eks_cluster
    remove_iam_roles
    remove_foundational_resources
    cleanup_local_files
    
    # Update destruction status
    update_destruction_status
    
    log_success "Comprehensive container observability destruction completed!"
    log_info "Destruction completed at: $(date)"
    
    # Final summary
    echo ""
    log_info "Destruction Summary:"
    log_info "===================="
    log_info "All resources have been removed from AWS account ${AWS_ACCOUNT_ID} in region ${AWS_REGION}"
    log_info "Some resources (like OpenSearch domains) may take additional time to fully delete"
    log_info "Destruction log available at: ${LOG_FILE}"
    
    # Keep environment file for reference
    if [[ -f "${DEPLOYMENT_VARS_FILE}" ]]; then
        log_info "Environment variables file preserved at: ${DEPLOYMENT_VARS_FILE}"
    fi
    
    echo ""
    log_success "Destruction completed successfully! 🗑️"
}

# Trap to handle script interruption
trap 'handle_error "Script interrupted"' INT TERM

# Clear log file
> "${LOG_FILE}"

# Run main function
main "$@"