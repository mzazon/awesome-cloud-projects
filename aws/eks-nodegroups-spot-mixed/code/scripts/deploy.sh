#!/bin/bash

# Deploy script for EKS Node Groups with Spot Instances and Mixed Instance Types
# This script creates cost-optimized EKS node groups using EC2 Spot instances and mixed instance types

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Colors for output
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

# Check if dry run mode is enabled
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    log_warning "Running in DRY RUN mode - no resources will be created"
fi

# Function to execute commands with dry run support
execute_cmd() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY RUN: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please configure them first."
        exit 1
    fi
    
    # Check if jq is installed for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. Some JSON parsing may not work optimally."
    fi
    
    log_success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region is not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 6))
    
    # Set cluster and node group names
    export CLUSTER_NAME=${CLUSTER_NAME:-"cost-optimized-eks-${RANDOM_SUFFIX}"}
    export SPOT_NODE_GROUP_NAME=${SPOT_NODE_GROUP_NAME:-"spot-mixed-nodegroup"}
    export ONDEMAND_NODE_GROUP_NAME=${ONDEMAND_NODE_GROUP_NAME:-"ondemand-backup-nodegroup"}
    
    # Set node group configuration
    export NODE_GROUP_ROLE_NAME="EKSNodeGroupRole-${RANDOM_SUFFIX}"
    export CLUSTER_AUTOSCALER_ROLE_NAME="ClusterAutoscalerRole-${RANDOM_SUFFIX}"
    export CLUSTER_AUTOSCALER_POLICY_NAME="ClusterAutoscalerPolicy-${RANDOM_SUFFIX}"
    
    log_success "Environment variables configured"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Cluster Name: $CLUSTER_NAME"
    log "Random Suffix: $RANDOM_SUFFIX"
}

# Check if cluster exists
check_cluster_exists() {
    log "Checking if EKS cluster exists..."
    
    if aws eks describe-cluster --name "$CLUSTER_NAME" &>/dev/null; then
        log_success "EKS cluster '$CLUSTER_NAME' found"
        
        # Get VPC and subnet information
        export VPC_ID=$(aws eks describe-cluster \
            --name "$CLUSTER_NAME" \
            --query cluster.resourcesVpcConfig.vpcId \
            --output text)
        
        export PRIVATE_SUBNET_IDS=$(aws eks describe-cluster \
            --name "$CLUSTER_NAME" \
            --query 'cluster.resourcesVpcConfig.subnetIds' \
            --output text | tr '\t' ' ')
        
        log "VPC ID: $VPC_ID"
        log "Subnet IDs: $PRIVATE_SUBNET_IDS"
        
        # Update kubeconfig
        aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
        log_success "kubeconfig updated for cluster access"
    else
        log_error "EKS cluster '$CLUSTER_NAME' not found. Please create the cluster first or update CLUSTER_NAME environment variable."
        log "Available clusters:"
        aws eks list-clusters --query clusters --output table
        exit 1
    fi
}

# Create IAM role for EKS node groups
create_node_group_role() {
    log "Creating IAM role for EKS node groups..."
    
    # Create trust policy
    cat > /tmp/node-group-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create the node group IAM role
    if aws iam get-role --role-name "$NODE_GROUP_ROLE_NAME" &>/dev/null; then
        log_warning "IAM role '$NODE_GROUP_ROLE_NAME' already exists, skipping creation"
    else
        execute_cmd "aws iam create-role \
            --role-name '$NODE_GROUP_ROLE_NAME' \
            --assume-role-policy-document file:///tmp/node-group-trust-policy.json" \
            "Creating IAM role for node groups"
    fi
    
    # Attach required policies
    local policies=(
        "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
        "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
        "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
    )
    
    for policy in "${policies[@]}"; do
        execute_cmd "aws iam attach-role-policy \
            --role-name '$NODE_GROUP_ROLE_NAME' \
            --policy-arn '$policy'" \
            "Attaching policy: $policy"
    done
    
    # Get role ARN
    export NODE_GROUP_ROLE_ARN=$(aws iam get-role \
        --role-name "$NODE_GROUP_ROLE_NAME" \
        --query Role.Arn --output text)
    
    log_success "Node group IAM role created: $NODE_GROUP_ROLE_ARN"
    
    # Clean up temporary file
    rm -f /tmp/node-group-trust-policy.json
}

# Create spot instance node group
create_spot_node_group() {
    log "Creating spot instance node group with mixed instance types..."
    
    # Check if node group already exists
    if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$SPOT_NODE_GROUP_NAME" &>/dev/null; then
        log_warning "Spot node group '$SPOT_NODE_GROUP_NAME' already exists, skipping creation"
        return 0
    fi
    
    execute_cmd "aws eks create-nodegroup \
        --cluster-name '$CLUSTER_NAME' \
        --nodegroup-name '$SPOT_NODE_GROUP_NAME' \
        --node-role '$NODE_GROUP_ROLE_ARN' \
        --subnets $PRIVATE_SUBNET_IDS \
        --scaling-config minSize=2,maxSize=10,desiredSize=4 \
        --capacity-type SPOT \
        --instance-types m5.large m5a.large c5.large c5a.large m5.xlarge c5.xlarge \
        --ami-type AL2_x86_64 \
        --disk-size 30 \
        --update-config maxUnavailable=1 \
        --labels 'node-type=spot,cost-optimization=enabled' \
        --tags 'Environment=production,NodeType=spot,CostOptimization=enabled'" \
        "Creating spot node group"
    
    log_success "Spot node group creation initiated"
}

# Create on-demand node group
create_ondemand_node_group() {
    log "Creating on-demand backup node group..."
    
    # Check if node group already exists
    if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$ONDEMAND_NODE_GROUP_NAME" &>/dev/null; then
        log_warning "On-demand node group '$ONDEMAND_NODE_GROUP_NAME' already exists, skipping creation"
        return 0
    fi
    
    execute_cmd "aws eks create-nodegroup \
        --cluster-name '$CLUSTER_NAME' \
        --nodegroup-name '$ONDEMAND_NODE_GROUP_NAME' \
        --node-role '$NODE_GROUP_ROLE_ARN' \
        --subnets $PRIVATE_SUBNET_IDS \
        --scaling-config minSize=1,maxSize=3,desiredSize=2 \
        --capacity-type ON_DEMAND \
        --instance-types m5.large c5.large \
        --ami-type AL2_x86_64 \
        --disk-size 30 \
        --update-config maxUnavailable=1 \
        --labels 'node-type=on-demand,workload-type=critical' \
        --tags 'Environment=production,NodeType=on-demand,WorkloadType=critical'" \
        "Creating on-demand node group"
    
    log_success "On-demand node group creation initiated"
}

# Wait for node groups to become active
wait_for_node_groups() {
    log "Waiting for node groups to become active..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping wait for node groups"
        return 0
    fi
    
    # Wait for spot node group
    log "Waiting for spot node group to become active..."
    aws eks wait nodegroup-active \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$SPOT_NODE_GROUP_NAME"
    log_success "Spot node group is now active"
    
    # Wait for on-demand node group
    log "Waiting for on-demand node group to become active..."
    aws eks wait nodegroup-active \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$ONDEMAND_NODE_GROUP_NAME"
    log_success "On-demand node group is now active"
}

# Install AWS Node Termination Handler
install_node_termination_handler() {
    log "Installing AWS Node Termination Handler..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping node termination handler installation"
        return 0
    fi
    
    # Check if already installed
    if kubectl get daemonset aws-node-termination-handler -n kube-system &>/dev/null; then
        log_warning "AWS Node Termination Handler already installed, skipping"
        return 0
    fi
    
    kubectl apply -f https://github.com/aws/aws-node-termination-handler/releases/download/v1.21.0/all-resources.yaml
    
    # Wait for pods to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=aws-node-termination-handler -n kube-system --timeout=300s
    
    log_success "AWS Node Termination Handler installed successfully"
}

# Configure node taints for spot instances
configure_spot_node_taints() {
    log "Configuring node taints for spot instances..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping node taint configuration"
        return 0
    fi
    
    # Wait for nodes to be ready
    sleep 30
    
    # Get spot instance node names
    SPOT_NODES=$(kubectl get nodes -l node-type=spot --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null || echo "")
    
    if [ -z "$SPOT_NODES" ]; then
        log_warning "No spot nodes found yet, they may still be joining the cluster"
        return 0
    fi
    
    # Apply taints to spot nodes
    for node in $SPOT_NODES; do
        kubectl taint nodes "$node" node-type=spot:NoSchedule --overwrite
        log_success "Tainted spot node: $node"
    done
    
    # Verify taints were applied
    kubectl get nodes -l node-type=spot -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
}

# Create pod disruption budget
create_pod_disruption_budget() {
    log "Creating pod disruption budget for spot workloads..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping pod disruption budget creation"
        return 0
    fi
    
    # Create pod disruption budget
    cat > /tmp/spot-pdb.yaml << EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: spot-workload-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      workload-type: spot-tolerant
EOF
    
    kubectl apply -f /tmp/spot-pdb.yaml
    
    log_success "Pod disruption budget created for spot workloads"
    
    # Clean up temporary file
    rm -f /tmp/spot-pdb.yaml
}

# Deploy test application
deploy_test_application() {
    log "Deploying test application with spot tolerance..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping test application deployment"
        return 0
    fi
    
    # Create test application
    cat > /tmp/spot-demo-app.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spot-demo-app
spec:
  replicas: 6
  selector:
    matchLabels:
      app: spot-demo-app
      workload-type: spot-tolerant
  template:
    metadata:
      labels:
        app: spot-demo-app
        workload-type: spot-tolerant
    spec:
      tolerations:
      - key: node-type
        operator: Equal
        value: spot
        effect: NoSchedule
      nodeSelector:
        node-type: spot
      containers:
      - name: nginx
        image: nginx:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: spot-demo-service
spec:
  selector:
    app: spot-demo-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
  type: ClusterIP
EOF
    
    kubectl apply -f /tmp/spot-demo-app.yaml
    
    log_success "Spot-tolerant demo application deployed"
    
    # Clean up temporary file
    rm -f /tmp/spot-demo-app.yaml
}

# Create IAM role for cluster autoscaler
create_cluster_autoscaler_role() {
    log "Creating IAM role and policy for cluster autoscaler..."
    
    # Create cluster autoscaler policy
    cat > /tmp/cluster-autoscaler-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Create IAM policy
    if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/$CLUSTER_AUTOSCALER_POLICY_NAME" &>/dev/null; then
        log_warning "Cluster autoscaler policy already exists, skipping creation"
    else
        execute_cmd "aws iam create-policy \
            --policy-name '$CLUSTER_AUTOSCALER_POLICY_NAME' \
            --policy-document file:///tmp/cluster-autoscaler-policy.json" \
            "Creating cluster autoscaler IAM policy"
    fi
    
    log_success "Cluster autoscaler IAM policy created"
    
    # Clean up temporary file
    rm -f /tmp/cluster-autoscaler-policy.json
}

# Install cluster autoscaler
install_cluster_autoscaler() {
    log "Installing and configuring cluster autoscaler..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping cluster autoscaler installation"
        return 0
    fi
    
    # Create service account
    if kubectl get serviceaccount cluster-autoscaler -n kube-system &>/dev/null; then
        log_warning "Cluster autoscaler service account already exists, skipping creation"
    else
        kubectl create serviceaccount cluster-autoscaler --namespace kube-system
    fi
    
    # Annotate service account (Note: This requires OIDC provider setup)
    kubectl annotate serviceaccount cluster-autoscaler \
        --namespace kube-system \
        eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/$CLUSTER_AUTOSCALER_ROLE_NAME \
        --overwrite
    
    # Deploy cluster autoscaler
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
    
    # Patch deployment with correct cluster name
    kubectl patch deployment cluster-autoscaler \
        --namespace kube-system \
        --patch "{\"spec\":{\"template\":{\"spec\":{\"containers\":[{\"name\":\"cluster-autoscaler\",\"command\":[\"./cluster-autoscaler\",\"--v=4\",\"--stderrthreshold=info\",\"--cloud-provider=aws\",\"--skip-nodes-with-local-storage=false\",\"--expander=least-waste\",\"--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/$CLUSTER_NAME\"]}]}}}}"
    
    log_success "Cluster autoscaler deployed and configured"
}

# Configure monitoring and alerts
configure_monitoring() {
    log "Configuring cost monitoring and alerts..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping monitoring configuration"
        return 0
    fi
    
    # Create CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "/aws/eks/${CLUSTER_NAME}/spot-interruptions" | grep -q "logGroups"; then
        log_warning "CloudWatch log group already exists, skipping creation"
    else
        execute_cmd "aws logs create-log-group \
            --log-group-name '/aws/eks/${CLUSTER_NAME}/spot-interruptions' \
            --region '$AWS_REGION'" \
            "Creating CloudWatch log group for spot interruptions"
    fi
    
    log_success "Cost monitoring configured"
    log_warning "Note: CloudWatch alarms require an existing SNS topic for notifications"
}

# Validation function
validate_deployment() {
    log "Validating deployment..."
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "DRY RUN: Skipping deployment validation"
        return 0
    fi
    
    # Check node group status
    local spot_status=$(aws eks describe-nodegroup \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$SPOT_NODE_GROUP_NAME" \
        --query 'nodegroup.status' --output text)
    
    local ondemand_status=$(aws eks describe-nodegroup \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "$ONDEMAND_NODE_GROUP_NAME" \
        --query 'nodegroup.status' --output text)
    
    if [ "$spot_status" = "ACTIVE" ] && [ "$ondemand_status" = "ACTIVE" ]; then
        log_success "Both node groups are active"
    else
        log_error "Node groups are not active. Spot: $spot_status, On-demand: $ondemand_status"
        return 1
    fi
    
    # Check nodes are ready
    local ready_nodes=$(kubectl get nodes --no-headers | grep -c Ready || echo 0)
    if [ "$ready_nodes" -gt 0 ]; then
        log_success "Found $ready_nodes ready nodes"
    else
        log_error "No ready nodes found"
        return 1
    fi
    
    # Check if demo app is running
    local running_pods=$(kubectl get pods -l app=spot-demo-app --no-headers | grep -c Running || echo 0)
    if [ "$running_pods" -gt 0 ]; then
        log_success "Demo application is running with $running_pods pods"
    else
        log_warning "Demo application pods are not running yet"
    fi
    
    log_success "Deployment validation completed"
}

# Main deployment function
main() {
    log "Starting EKS Node Groups with Spot Instances deployment..."
    
    # Check for help flag
    if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
        cat << EOF
Usage: $0 [OPTIONS]

Deploy EKS node groups with spot instances and mixed instance types.

Options:
  --help, -h          Show this help message
  --dry-run           Run in dry-run mode (no resources created)
  --cluster-name      Specify EKS cluster name (default: auto-generated)
  --region            Specify AWS region (default: from AWS config)

Environment Variables:
  DRY_RUN             Set to 'true' for dry-run mode
  CLUSTER_NAME        EKS cluster name
  AWS_REGION          AWS region

Examples:
  $0                              # Deploy with default settings
  $0 --dry-run                    # Dry run mode
  $0 --cluster-name my-cluster    # Use specific cluster
  DRY_RUN=true $0                 # Environment variable dry run

EOF
        exit 0
    fi
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    check_cluster_exists
    create_node_group_role
    create_spot_node_group
    create_ondemand_node_group
    wait_for_node_groups
    install_node_termination_handler
    configure_spot_node_taints
    create_pod_disruption_budget
    deploy_test_application
    create_cluster_autoscaler_role
    install_cluster_autoscaler
    configure_monitoring
    validate_deployment
    
    log_success "EKS Node Groups with Spot Instances deployment completed successfully!"
    log "Cluster Name: $CLUSTER_NAME"
    log "Spot Node Group: $SPOT_NODE_GROUP_NAME"
    log "On-Demand Node Group: $ONDEMAND_NODE_GROUP_NAME"
    log ""
    log "Next steps:"
    log "1. Check node status: kubectl get nodes"
    log "2. Check pod distribution: kubectl get pods -o wide"
    log "3. Monitor costs in AWS Cost Explorer"
    log "4. Set up SNS topic for interruption alerts"
}

# Run main function with all arguments
main "$@"