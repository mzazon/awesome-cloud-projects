#!/bin/bash

# Deploy script for EKS CloudWatch Container Insights
# This script deploys comprehensive monitoring and alerting for Amazon EKS clusters
# using CloudWatch Container Insights with enhanced observability

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy EKS CloudWatch Container Insights monitoring solution.

OPTIONS:
    -c, --cluster-name CLUSTER_NAME    Name of the EKS cluster (required)
    -r, --region REGION               AWS region (default: us-west-2)
    -e, --email EMAIL                 Email address for SNS notifications (required)
    -d, --dry-run                     Show what would be deployed without making changes
    -h, --help                        Show this help message

EXAMPLES:
    $0 -c my-eks-cluster -e admin@example.com
    $0 --cluster-name production-cluster --region us-east-1 --email ops@company.com
    $0 -c test-cluster -e test@example.com --dry-run

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - kubectl configured with cluster access
    - eksctl installed for IRSA management
    - Running EKS cluster (version 1.21 or later)

EOF
}

# Default values
AWS_REGION="us-west-2"
DRY_RUN=false
CLUSTER_NAME=""
EMAIL=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -e|--email)
            EMAIL="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$CLUSTER_NAME" ]]; then
    error "Cluster name is required. Use -c or --cluster-name option."
    show_help
    exit 1
fi

if [[ -z "$EMAIL" ]]; then
    error "Email address is required. Use -e or --email option."
    show_help
    exit 1
fi

# Validate email format
if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    error "Invalid email format: $EMAIL"
    exit 1
fi

log "Starting EKS CloudWatch Container Insights deployment"
log "Cluster: $CLUSTER_NAME"
log "Region: $AWS_REGION"
log "Email: $EMAIL"
log "Dry run: $DRY_RUN"

# Prerequisites check function
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check eksctl
    if ! command -v eksctl &> /dev/null; then
        error "eksctl is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    
    # Get AWS account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        error "Unable to retrieve AWS account ID"
        exit 1
    fi
    
    # Check kubectl access to cluster
    if ! kubectl get nodes &> /dev/null; then
        error "kubectl is not configured for cluster access or cluster is not accessible"
        exit 1
    fi
    
    # Verify cluster name matches
    CURRENT_CLUSTER=$(kubectl config current-context | cut -d'/' -f2)
    if [[ "$CURRENT_CLUSTER" != "$CLUSTER_NAME" ]]; then
        warning "Current kubectl context cluster ($CURRENT_CLUSTER) doesn't match specified cluster ($CLUSTER_NAME)"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    success "Prerequisites check completed"
}

# Deploy function
deploy_monitoring() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN MODE - No actual changes will be made"
        return 0
    fi
    
    log "Step 1: Creating SNS topic for alerts..."
    TOPIC_ARN=$(aws sns create-topic \
        --name "eks-monitoring-alerts-${CLUSTER_NAME}" \
        --region "$AWS_REGION" \
        --query TopicArn --output text)
    
    if [[ -z "$TOPIC_ARN" ]]; then
        error "Failed to create SNS topic"
        exit 1
    fi
    success "SNS topic created: $TOPIC_ARN"
    
    log "Step 2: Subscribing email to SNS topic..."
    aws sns subscribe \
        --topic-arn "$TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$EMAIL" \
        --region "$AWS_REGION" > /dev/null
    
    success "Email subscription created. Please check your email and confirm the subscription."
    
    log "Step 3: Enabling EKS control plane logging..."
    aws eks update-cluster-config \
        --region "$AWS_REGION" \
        --name "$CLUSTER_NAME" \
        --logging '{"enable":["api","audit","authenticator","controllerManager","scheduler"]}' > /dev/null
    
    success "EKS control plane logging enabled"
    
    log "Step 4: Creating CloudWatch namespace..."
    kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml
    
    success "CloudWatch namespace created"
    
    log "Step 5: Creating IRSA service account..."
    if eksctl get iamserviceaccount --cluster="$CLUSTER_NAME" --name=cloudwatch-agent --namespace=amazon-cloudwatch &> /dev/null; then
        warning "CloudWatch agent service account already exists, updating..."
        eksctl delete iamserviceaccount \
            --name cloudwatch-agent \
            --namespace amazon-cloudwatch \
            --cluster "$CLUSTER_NAME" \
            --region "$AWS_REGION" \
            --wait
    fi
    
    eksctl create iamserviceaccount \
        --name cloudwatch-agent \
        --namespace amazon-cloudwatch \
        --cluster "$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --attach-policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
        --approve \
        --override-existing-serviceaccounts
    
    success "IRSA service account created"
    
    log "Step 6: Deploying CloudWatch agent DaemonSet..."
    curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml | \
    sed "s/{{cluster_name}}/$CLUSTER_NAME/;s/{{region_name}}/$AWS_REGION/" | \
    kubectl apply -f -
    
    success "CloudWatch agent deployed"
    
    log "Step 7: Deploying Fluent Bit for log collection..."
    curl -s https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml | \
    sed "s/{{cluster_name}}/$CLUSTER_NAME/;s/{{region_name}}/$AWS_REGION/;s/{{http_server_toggle}}/On/;s/{{http_server_port}}/2020/;s/{{read_from_head}}/Off/;s/{{read_from_tail}}/On/" | \
    kubectl apply -f -
    
    success "Fluent Bit deployed"
    
    log "Step 8: Waiting for monitoring pods to be ready..."
    kubectl wait --for=condition=Ready pod -l name=cloudwatch-agent -n amazon-cloudwatch --timeout=300s
    kubectl wait --for=condition=Ready pod -l name=fluent-bit -n amazon-cloudwatch --timeout=300s
    
    success "Monitoring pods are ready"
    
    log "Step 9: Creating CloudWatch alarms..."
    
    # High CPU alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "EKS-${CLUSTER_NAME}-HighCPU" \
        --alarm-description "EKS cluster high CPU utilization" \
        --metric-name node_cpu_utilization \
        --namespace ContainerInsights \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=ClusterName,Value="$CLUSTER_NAME" \
        --evaluation-periods 2 \
        --alarm-actions "$TOPIC_ARN" \
        --treat-missing-data notBreaching \
        --region "$AWS_REGION"
    
    # High Memory alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "EKS-${CLUSTER_NAME}-HighMemory" \
        --alarm-description "EKS cluster high memory utilization" \
        --metric-name node_memory_utilization \
        --namespace ContainerInsights \
        --statistic Average \
        --period 300 \
        --threshold 85 \
        --comparison-operator GreaterThanThreshold \
        --dimensions Name=ClusterName,Value="$CLUSTER_NAME" \
        --evaluation-periods 2 \
        --alarm-actions "$TOPIC_ARN" \
        --treat-missing-data notBreaching \
        --region "$AWS_REGION"
    
    # Failed Pods alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "EKS-${CLUSTER_NAME}-FailedPods" \
        --alarm-description "EKS cluster has failed pods" \
        --metric-name cluster_failed_node_count \
        --namespace ContainerInsights \
        --statistic Maximum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --dimensions Name=ClusterName,Value="$CLUSTER_NAME" \
        --evaluation-periods 1 \
        --alarm-actions "$TOPIC_ARN" \
        --treat-missing-data notBreaching \
        --region "$AWS_REGION"
    
    success "CloudWatch alarms created"
    
    log "Step 10: Validating deployment..."
    
    # Check metrics are being received
    log "Waiting for metrics to appear in CloudWatch (this may take a few minutes)..."
    sleep 60
    
    METRICS_COUNT=$(aws cloudwatch list-metrics \
        --namespace ContainerInsights \
        --dimensions Name=ClusterName,Value="$CLUSTER_NAME" \
        --region "$AWS_REGION" \
        --query 'length(Metrics)' --output text)
    
    if [[ "$METRICS_COUNT" -gt 0 ]]; then
        success "Container Insights metrics are being collected ($METRICS_COUNT metrics found)"
    else
        warning "No metrics found yet. This is normal for new deployments and metrics should appear within 5-10 minutes."
    fi
    
    # Check pod status
    AGENT_PODS=$(kubectl get pods -n amazon-cloudwatch -l name=cloudwatch-agent --no-headers | wc -l)
    FLUENT_PODS=$(kubectl get pods -n amazon-cloudwatch -l name=fluent-bit --no-headers | wc -l)
    
    success "Monitoring infrastructure deployed:"
    success "  - CloudWatch Agent pods: $AGENT_PODS"
    success "  - Fluent Bit pods: $FLUENT_PODS"
    success "  - SNS Topic: $TOPIC_ARN"
    success "  - CloudWatch Alarms: 3 created"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up partial deployment..."
    
    # Only cleanup if not in dry-run mode
    if [[ "$DRY_RUN" == "false" ]]; then
        # Delete alarms if they exist
        aws cloudwatch delete-alarms --alarm-names \
            "EKS-${CLUSTER_NAME}-HighCPU" \
            "EKS-${CLUSTER_NAME}-HighMemory" \
            "EKS-${CLUSTER_NAME}-FailedPods" \
            --region "$AWS_REGION" 2>/dev/null || true
        
        # Delete SNS topic if it exists
        if [[ -n "${TOPIC_ARN:-}" ]]; then
            aws sns delete-topic --topic-arn "$TOPIC_ARN" --region "$AWS_REGION" 2>/dev/null || true
        fi
        
        # Delete Kubernetes resources
        kubectl delete -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluent-bit/fluent-bit.yaml 2>/dev/null || true
        
        kubectl delete -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml 2>/dev/null || true
        
        eksctl delete iamserviceaccount \
            --name cloudwatch-agent \
            --namespace amazon-cloudwatch \
            --cluster "$CLUSTER_NAME" \
            --region "$AWS_REGION" 2>/dev/null || true
        
        kubectl delete namespace amazon-cloudwatch 2>/dev/null || true
    fi
    
    error "Cleanup completed"
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Main execution
main() {
    check_prerequisites
    deploy_monitoring
    
    success "✅ EKS CloudWatch Container Insights deployment completed successfully!"
    success ""
    success "Next steps:"
    success "1. Confirm your email subscription by clicking the link in the confirmation email"
    success "2. Access Container Insights dashboard at: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#container-insights:performance"
    success "3. Monitor cluster metrics and logs through the CloudWatch console"
    success "4. Test alerting by running: kubectl run cpu-stress --image=progrium/stress -- stress --cpu 2 --timeout 300s"
    success ""
    success "For more information, visit: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-EKS.html"
}

# Execute main function
main "$@"