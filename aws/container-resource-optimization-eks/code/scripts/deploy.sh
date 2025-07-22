#!/bin/bash

# AWS EKS Container Resource Optimization Deployment Script
# This script implements the complete container resource optimization solution
# with Vertical Pod Autoscaler (VPA) and CloudWatch monitoring

set -e
set -o pipefail

# Colors for output
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

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check the logs above for details."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up resources due to error..."
    
    # Clean up test applications
    kubectl delete deployment resource-test-app -n cost-optimization 2>/dev/null || true
    kubectl delete service resource-test-app -n cost-optimization 2>/dev/null || true
    kubectl delete vpa resource-test-app-vpa -n cost-optimization 2>/dev/null || true
    kubectl delete vpa resource-test-app-vpa-auto -n cost-optimization 2>/dev/null || true
    
    # Clean up namespace
    kubectl delete namespace cost-optimization 2>/dev/null || true
    
    log_warning "Partial cleanup completed"
}

# Trap errors and cleanup
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed and configured
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please run 'aws configure' or set up AWS credentials."
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error_exit "kubectl is not installed. Please install kubectl."
    fi
    
    # Check if git is installed (needed for VPA installation)
    if ! command -v git &> /dev/null; then
        error_exit "git is not installed. Please install git."
    fi
    
    log_success "Prerequisites check passed"
}

# Validate EKS cluster connectivity
validate_cluster() {
    log_info "Validating EKS cluster connectivity..."
    
    if [ -z "$CLUSTER_NAME" ]; then
        read -p "Enter your EKS cluster name: " CLUSTER_NAME
        export CLUSTER_NAME
    fi
    
    # Update kubeconfig
    aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || \
        error_exit "Failed to update kubeconfig for cluster $CLUSTER_NAME"
    
    # Test cluster connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error_exit "Cannot connect to EKS cluster. Please check your cluster name and AWS region."
    fi
    
    # Check if cluster has nodes
    local node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
    if [ "$node_count" -lt 1 ]; then
        error_exit "EKS cluster has no worker nodes. Please ensure your cluster has at least one worker node."
    fi
    
    log_success "EKS cluster connectivity validated"
}

# Set up environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        error_exit "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    log_success "Environment variables configured"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
    log_info "Random Suffix: $RANDOM_SUFFIX"
}

# Create namespace and enable cluster logging
setup_cluster() {
    log_info "Setting up cluster configuration..."
    
    # Create namespace for cost optimization workloads
    kubectl create namespace cost-optimization 2>/dev/null || \
        log_warning "Namespace cost-optimization already exists"
    
    # Enable Container Insights for the cluster
    log_info "Enabling EKS cluster logging..."
    aws eks put-cluster-logging \
        --region "$AWS_REGION" \
        --name "$CLUSTER_NAME" \
        --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' || \
        log_warning "Failed to enable cluster logging (may already be enabled)"
    
    log_success "Cluster configuration completed"
}

# Deploy Kubernetes Metrics Server
deploy_metrics_server() {
    log_info "Deploying Kubernetes Metrics Server..."
    
    # Check if Metrics Server is already installed
    if kubectl get deployment metrics-server -n kube-system &> /dev/null; then
        log_warning "Metrics Server already exists"
    else
        # Deploy Metrics Server
        kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml || \
            error_exit "Failed to deploy Metrics Server"
    fi
    
    # Wait for Metrics Server to be ready
    log_info "Waiting for Metrics Server to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/metrics-server -n kube-system || \
        error_exit "Metrics Server failed to become ready"
    
    log_success "Metrics Server deployed successfully"
}

# Install Vertical Pod Autoscaler (VPA)
install_vpa() {
    log_info "Installing Vertical Pod Autoscaler (VPA)..."
    
    # Check if VPA is already installed
    if kubectl get pods -n kube-system | grep -q vpa; then
        log_warning "VPA components already exist"
        return 0
    fi
    
    # Create temporary directory for VPA installation
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Clone the VPA repository
    log_info "Downloading VPA source code..."
    git clone https://github.com/kubernetes/autoscaler.git || \
        error_exit "Failed to clone VPA repository"
    
    cd autoscaler/vertical-pod-autoscaler/
    
    # Deploy VPA components
    log_info "Deploying VPA components..."
    ./hack/vpa-up.sh || error_exit "Failed to deploy VPA components"
    
    # Verify VPA components are running
    log_info "Verifying VPA components..."
    sleep 30
    local vpa_pods=$(kubectl get pods -n kube-system | grep vpa | grep Running | wc -l)
    if [ "$vpa_pods" -lt 3 ]; then
        error_exit "VPA components are not running properly"
    fi
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    log_success "VPA components deployed successfully"
}

# Deploy sample application for testing
deploy_test_application() {
    log_info "Deploying test application..."
    
    # Create test application with suboptimal resource settings
    cat <<EOF | kubectl apply -f - || error_exit "Failed to deploy test application"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: resource-test-app
  namespace: cost-optimization
spec:
  replicas: 3
  selector:
    matchLabels:
      app: resource-test-app
  template:
    metadata:
      labels:
        app: resource-test-app
    spec:
      containers:
      - name: app
        image: nginx:1.20
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 500m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1024Mi
        # Add some load generation
        command: ["/bin/sh"]
        args: ["-c", "while true; do echo 'Load test'; sleep 30; done & nginx -g 'daemon off;'"]
---
apiVersion: v1
kind: Service
metadata:
  name: resource-test-app
  namespace: cost-optimization
spec:
  selector:
    app: resource-test-app
  ports:
  - port: 80
    targetPort: 80
EOF

    # Wait for deployment to be ready
    log_info "Waiting for test application to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/resource-test-app -n cost-optimization || \
        error_exit "Test application failed to become ready"
    
    log_success "Test application deployed successfully"
}

# Create VPA configuration
create_vpa_config() {
    log_info "Creating VPA configuration..."
    
    # Create VPA policy for the test application (starting in Off mode)
    cat <<EOF | kubectl apply -f - || error_exit "Failed to create VPA configuration"
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: resource-test-app-vpa
  namespace: cost-optimization
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: resource-test-app
  updatePolicy:
    updateMode: "Off"  # Start with recommendation mode only
  resourcePolicy:
    containerPolicies:
    - containerName: app
      minAllowed:
        cpu: 50m
        memory: 64Mi
      maxAllowed:
        cpu: 2000m
        memory: 2048Mi
      controlledResources: ["cpu", "memory"]
EOF

    log_success "VPA configuration created"
}

# Install CloudWatch Container Insights
install_container_insights() {
    log_info "Installing CloudWatch Container Insights..."
    
    # Create CloudWatch namespace if it doesn't exist
    kubectl create namespace amazon-cloudwatch 2>/dev/null || \
        log_warning "Namespace amazon-cloudwatch already exists"
    
    # Deploy CloudWatch agent configuration
    cat <<EOF | kubectl apply -f - || error_exit "Failed to create CloudWatch configuration"
apiVersion: v1
kind: ConfigMap
metadata:
  name: cwagentconfig
  namespace: amazon-cloudwatch
data:
  cwagentconfig.json: |
    {
      "logs": {
        "metrics_collected": {
          "kubernetes": {
            "metrics_collection_interval": 60,
            "resources": [
              "namespace",
              "pod",
              "container",
              "service"
            ]
          }
        },
        "force_flush_interval": 5
      }
    }
EOF

    # Deploy CloudWatch agent components
    log_info "Deploying CloudWatch agent components..."
    
    kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml || \
        log_warning "CloudWatch namespace already exists"
    
    kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml || \
        error_exit "Failed to create CloudWatch service account"
    
    kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-configmap.yaml || \
        error_exit "Failed to create CloudWatch config map"
    
    kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml || \
        error_exit "Failed to create CloudWatch daemonset"
    
    log_success "CloudWatch Container Insights deployed"
}

# Create cost monitoring dashboard
create_cost_dashboard() {
    log_info "Creating cost monitoring dashboard..."
    
    # Create CloudWatch dashboard for cost monitoring
    aws cloudwatch put-dashboard \
        --dashboard-name "EKS-Cost-Optimization-${RANDOM_SUFFIX}" \
        --dashboard-body "{
          \"widgets\": [
            {
              \"type\": \"metric\",
              \"properties\": {
                \"metrics\": [
                  [\"ContainerInsights\", \"pod_cpu_utilization\", \"Namespace\", \"cost-optimization\"],
                  [\".\", \"pod_memory_utilization\", \".\", \".\"],
                  [\".\", \"pod_cpu_reserved_capacity\", \".\", \".\"],
                  [\".\", \"pod_memory_reserved_capacity\", \".\", \".\"]
                ],
                \"period\": 300,
                \"stat\": \"Average\",
                \"region\": \"$AWS_REGION\",
                \"title\": \"Resource Utilization vs Reserved Capacity\"
              }
            }
          ]
        }" || error_exit "Failed to create cost monitoring dashboard"
    
    log_success "Cost monitoring dashboard created"
}

# Set up cost alerts
setup_cost_alerts() {
    log_info "Setting up cost alerts..."
    
    # Create SNS topic for cost alerts
    local topic_arn=$(aws sns create-topic \
        --name "eks-cost-optimization-alerts-${RANDOM_SUFFIX}" \
        --query TopicArn --output text) || \
        error_exit "Failed to create SNS topic"
    
    export TOPIC_ARN="$topic_arn"
    
    # Create CloudWatch alarm for high resource waste
    aws cloudwatch put-metric-alarm \
        --alarm-name "EKS-High-Resource-Waste-${RANDOM_SUFFIX}" \
        --alarm-description "Alert when container resource utilization is low" \
        --metric-name pod_cpu_utilization \
        --namespace ContainerInsights \
        --statistic Average \
        --period 300 \
        --threshold 30 \
        --comparison-operator LessThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$topic_arn" \
        --dimensions Name=Namespace,Value=cost-optimization || \
        error_exit "Failed to create CloudWatch alarm"
    
    log_success "Cost alerts configured"
    log_info "SNS Topic ARN: $topic_arn"
}

# Generate VPA recommendations script
create_vpa_report_script() {
    log_info "Creating VPA recommendations script..."
    
    cat <<'EOF' > generate-vpa-recommendations.sh
#!/bin/bash

echo "=== VPA Recommendations Report ==="
echo "Generated on: $(date)"
echo ""

# Get VPA recommendations
echo "=== VPA Recommendations ==="
kubectl get vpa -n cost-optimization -o custom-columns="NAME:.metadata.name,TARGET:.spec.targetRef.name,CPU_REQUEST:.status.recommendation.containerRecommendations[0].target.cpu,MEMORY_REQUEST:.status.recommendation.containerRecommendations[0].target.memory" 2>/dev/null || echo "No VPA recommendations available yet (allow 10-15 minutes for data collection)"

echo ""
echo "=== Current Resource Usage ==="
kubectl top pods -n cost-optimization 2>/dev/null || echo "Resource usage data not available yet"

echo ""
echo "=== Detailed VPA Status ==="
kubectl describe vpa -n cost-optimization 2>/dev/null || echo "No VPA resources found"
EOF

    chmod +x generate-vpa-recommendations.sh || error_exit "Failed to make VPA report script executable"
    
    log_success "VPA report script created"
}

# Create automated VPA configuration
create_automated_vpa() {
    log_info "Creating automated VPA configuration..."
    
    # Create a more aggressive VPA configuration for automated updates
    cat <<EOF | kubectl apply -f - || error_exit "Failed to create automated VPA configuration"
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: resource-test-app-vpa-auto
  namespace: cost-optimization
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: resource-test-app
  updatePolicy:
    updateMode: "Auto"  # Enable automatic updates
  resourcePolicy:
    containerPolicies:
    - containerName: app
      minAllowed:
        cpu: 50m
        memory: 64Mi
      maxAllowed:
        cpu: 500m  # Reduced from original
        memory: 512Mi  # Reduced from original
      controlledResources: ["cpu", "memory"]
EOF

    log_success "Automated VPA configuration created"
}

# Create cost optimization automation script
create_cost_automation() {
    log_info "Creating cost optimization automation script..."
    
    cat <<EOF > cost-optimization-lambda.py
import boto3
import json
from datetime import datetime, timedelta

def lambda_handler(event, context):
    # Get EKS cluster metrics
    cloudwatch = boto3.client('cloudwatch')
    
    # Query resource utilization metrics
    response = cloudwatch.get_metric_statistics(
        Namespace='ContainerInsights',
        MetricName='pod_cpu_utilization',
        Dimensions=[
            {
                'Name': 'Namespace',
                'Value': 'cost-optimization'
            }
        ],
        StartTime=datetime.utcnow() - timedelta(hours=1),
        EndTime=datetime.utcnow(),
        Period=300,
        Statistics=['Average']
    )
    
    # Analyze utilization and trigger recommendations
    if response['Datapoints']:
        avg_utilization = sum(dp['Average'] for dp in response['Datapoints']) / len(response['Datapoints'])
        
        if avg_utilization < 30:  # Low utilization threshold
            # Send SNS notification
            sns = boto3.client('sns')
            sns.publish(
                TopicArn='${TOPIC_ARN}',
                Message=f'EKS cluster resource utilization is low: {avg_utilization:.2f}%',
                Subject='EKS Cost Optimization Alert'
            )
    
    return {
        'statusCode': 200,
        'body': json.dumps('Cost optimization check completed')
    }
EOF

    log_success "Cost optimization automation script created"
}

# Display deployment summary
show_deployment_summary() {
    log_success "Deployment completed successfully!"
    echo ""
    echo "========================================"
    echo "         DEPLOYMENT SUMMARY"
    echo "========================================"
    echo "Cluster: $CLUSTER_NAME"
    echo "Region: $AWS_REGION"
    echo "Random Suffix: $RANDOM_SUFFIX"
    echo ""
    echo "Resources Created:"
    echo "- Metrics Server (Kubernetes)"
    echo "- Vertical Pod Autoscaler (VPA)"
    echo "- Test Application (cost-optimization namespace)"
    echo "- VPA Policies (Off and Auto modes)"
    echo "- CloudWatch Container Insights"
    echo "- Cost Monitoring Dashboard"
    echo "- Cost Alert System"
    echo ""
    echo "Next Steps:"
    echo "1. Wait 10-15 minutes for VPA to collect metrics"
    echo "2. Run './generate-vpa-recommendations.sh' to view recommendations"
    echo "3. View dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=EKS-Cost-Optimization-${RANDOM_SUFFIX}"
    echo ""
    echo "To test load generation:"
    echo "kubectl run load-generator --image=busybox --restart=Never --rm -it --namespace=cost-optimization -- /bin/sh -c \"while true; do wget -q -O- http://resource-test-app.cost-optimization.svc.cluster.local; done\""
    echo ""
    log_warning "Remember to run './destroy.sh' when you're done to clean up all resources"
}

# Main deployment function
main() {
    echo "========================================"
    echo "  EKS Container Resource Optimization"
    echo "         Deployment Script"
    echo "========================================"
    echo ""
    
    check_prerequisites
    setup_environment
    validate_cluster
    setup_cluster
    deploy_metrics_server
    install_vpa
    deploy_test_application
    create_vpa_config
    install_container_insights
    create_cost_dashboard
    setup_cost_alerts
    create_vpa_report_script
    create_automated_vpa
    create_cost_automation
    show_deployment_summary
}

# Run main function
main "$@"