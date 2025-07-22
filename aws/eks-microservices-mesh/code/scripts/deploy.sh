#!/bin/bash

# Deploy Microservices on EKS with Service Mesh using AWS App Mesh
# Recipe: microservices-eks-service-mesh-aws-app-mesh
# Description: Automated deployment script for AWS App Mesh service mesh with EKS

set -e  # Exit on any error
set -u  # Exit on undefined variables
set -o pipefail  # Exit on pipe failures

# Colors for output formatting
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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Default configuration
DEFAULT_CLUSTER_NAME="microservices-mesh-cluster"
DEFAULT_APP_MESH_NAME="microservices-mesh"
DEFAULT_NAMESPACE="production"
DEFAULT_ECR_REPO_PREFIX="microservices-demo"
DEFAULT_REGION=""

# Configuration variables
CLUSTER_NAME="${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}"
APP_MESH_NAME="${APP_MESH_NAME:-$DEFAULT_APP_MESH_NAME}"
NAMESPACE="${NAMESPACE:-$DEFAULT_NAMESPACE}"
ECR_REPO_PREFIX="${ECR_REPO_PREFIX:-$DEFAULT_ECR_REPO_PREFIX}"
DRY_RUN="${DRY_RUN:-false}"
SKIP_CLUSTER_CREATION="${SKIP_CLUSTER_CREATION:-false}"
SKIP_CONTAINER_BUILD="${SKIP_CONTAINER_BUILD:-false}"

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Starting cleanup..."
    # Call destroy script if it exists
    if [[ -f "$(dirname "$0")/destroy.sh" ]]; then
        warning "Running cleanup script..."
        bash "$(dirname "$0")/destroy.sh" --force || true
    fi
}

# Set up error trap
trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
Deploy Microservices on EKS with Service Mesh using AWS App Mesh

Usage: $0 [OPTIONS]

Options:
    -h, --help                  Show this help message
    --dry-run                   Show what would be deployed without executing
    --cluster-name NAME         EKS cluster name (default: $DEFAULT_CLUSTER_NAME)
    --mesh-name NAME            App Mesh name (default: $DEFAULT_APP_MESH_NAME)
    --namespace NAME            Kubernetes namespace (default: $DEFAULT_NAMESPACE)
    --ecr-prefix PREFIX         ECR repository prefix (default: $DEFAULT_ECR_REPO_PREFIX)
    --skip-cluster              Skip EKS cluster creation (use existing cluster)
    --skip-containers           Skip container image building
    --region REGION             AWS region (default: from AWS CLI config)

Environment Variables:
    CLUSTER_NAME               EKS cluster name
    APP_MESH_NAME              App Mesh name  
    NAMESPACE                  Kubernetes namespace
    ECR_REPO_PREFIX            ECR repository prefix
    DRY_RUN                    Set to 'true' for dry run mode
    SKIP_CLUSTER_CREATION      Set to 'true' to skip cluster creation
    SKIP_CONTAINER_BUILD       Set to 'true' to skip container building

Examples:
    $0                                    # Deploy with default settings
    $0 --dry-run                          # Show what would be deployed
    $0 --cluster-name my-cluster          # Use custom cluster name
    $0 --skip-cluster --skip-containers   # Use existing cluster and containers

Prerequisites:
    - AWS CLI v2 configured with appropriate permissions
    - kubectl client installed
    - eksctl CLI tool installed (version 0.100.0+)
    - Helm v3 installed
    - Docker installed (if building containers)

Estimated deployment time: 30-45 minutes
Estimated cost: \$150-200 for 4 hours of testing

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            --mesh-name)
                APP_MESH_NAME="$2"
                shift 2
                ;;
            --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            --ecr-prefix)
                ECR_REPO_PREFIX="$2"
                shift 2
                ;;
            --skip-cluster)
                SKIP_CLUSTER_CREATION=true
                shift
                ;;
            --skip-containers)
                SKIP_CONTAINER_BUILD=true
                shift
                ;;
            --region)
                AWS_REGION="$2"
                shift 2
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    if ! command -v aws &> /dev/null; then
        missing_tools+=(aws-cli)
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=(kubectl)
    fi
    
    if ! command -v eksctl &> /dev/null; then
        missing_tools+=(eksctl)
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=(helm)
    fi
    
    if [[ "$SKIP_CONTAINER_BUILD" != "true" ]] && ! command -v docker &> /dev/null; then
        missing_tools+=(docker)
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
        error "Please install the missing tools and try again."
        exit 1
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid"
        error "Please run 'aws configure' and try again."
        exit 1
    fi
    
    # Check Docker daemon (if building containers)
    if [[ "$SKIP_CONTAINER_BUILD" != "true" ]] && ! docker info &> /dev/null; then
        error "Docker daemon is not running"
        error "Please start Docker and try again."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please set it using --region or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    log "Environment configured:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  Cluster Name: $CLUSTER_NAME"
    log "  App Mesh Name: $APP_MESH_NAME"
    log "  Namespace: $NAMESPACE"
    log "  ECR Repository Prefix: $ECR_REPO_PREFIX"
    log "  Random Suffix: $RANDOM_SUFFIX"
}

# Create ECR repositories
create_ecr_repositories() {
    log "Creating ECR repositories..."
    
    local services=("service-a" "service-b" "service-c")
    
    for service in "${services[@]}"; do
        local repo_name="${ECR_REPO_PREFIX}-${service}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would create ECR repository: $repo_name"
            continue
        fi
        
        if aws ecr describe-repositories --repository-names "$repo_name" --region "$AWS_REGION" &> /dev/null; then
            warning "ECR repository $repo_name already exists, skipping creation"
        else
            aws ecr create-repository \
                --repository-name "$repo_name" \
                --region "$AWS_REGION" > /dev/null
            success "Created ECR repository: $repo_name"
        fi
    done
}

# Create EKS cluster
create_eks_cluster() {
    if [[ "$SKIP_CLUSTER_CREATION" == "true" ]]; then
        log "Skipping EKS cluster creation as requested"
        return 0
    fi
    
    log "Creating EKS cluster with App Mesh support..."
    
    # Check if cluster already exists
    if eksctl get cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" &> /dev/null; then
        warning "EKS cluster $CLUSTER_NAME already exists, skipping creation"
        # Update kubeconfig
        aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
        return 0
    fi
    
    # Create cluster configuration file
    local cluster_config=$(mktemp)
    cat > "$cluster_config" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "1.28"

managedNodeGroups:
  - name: microservices-nodes
    instanceType: t3.medium
    minSize: 3
    maxSize: 6
    desiredCapacity: 3
    volumeSize: 20
    ssh:
      allow: false
    iam:
      withAddonPolicies:
        imageBuilder: true
        autoScaler: true
        cloudWatch: true
        appMesh: true

addons:
  - name: aws-ebs-csi-driver
  - name: coredns
  - name: kube-proxy
  - name: vpc-cni
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create EKS cluster with configuration:"
        cat "$cluster_config"
        rm -f "$cluster_config"
        return 0
    fi
    
    # Create the EKS cluster
    eksctl create cluster -f "$cluster_config"
    rm -f "$cluster_config"
    
    success "EKS cluster created successfully"
}

# Install App Mesh controller
install_app_mesh_controller() {
    log "Installing App Mesh controller and CRDs..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would install App Mesh controller"
        return 0
    fi
    
    # Add EKS charts repository
    helm repo add eks https://aws.github.io/eks-charts || true
    helm repo update
    
    # Install App Mesh CRDs
    kubectl apply -k \
        "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"
    
    # Create namespace for App Mesh controller
    kubectl create namespace appmesh-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Create service account for App Mesh controller
    eksctl create iamserviceaccount \
        --cluster="$CLUSTER_NAME" \
        --namespace=appmesh-system \
        --name=appmesh-controller \
        --attach-policy-arn=arn:aws:iam::aws:policy/AWSCloudMapFullAccess \
        --attach-policy-arn=arn:aws:iam::aws:policy/AWSAppMeshFullAccess \
        --override-existing-serviceaccounts \
        --approve
    
    # Install App Mesh controller
    helm upgrade --install appmesh-controller eks/appmesh-controller \
        --namespace appmesh-system \
        --set region="$AWS_REGION" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=appmesh-controller
    
    # Wait for controller to be ready
    kubectl wait --for=condition=available --timeout=300s \
        deployment/appmesh-controller -n appmesh-system
    
    success "App Mesh controller installed successfully"
}

# Create App Mesh and namespace
create_app_mesh_namespace() {
    log "Creating App Mesh and production namespace..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create App Mesh and namespace"
        return 0
    fi
    
    # Create production namespace
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespace for App Mesh injection
    kubectl label namespace "$NAMESPACE" \
        mesh="$APP_MESH_NAME" \
        appmesh.k8s.aws/sidecarInjectorWebhook=enabled \
        --overwrite
    
    # Create App Mesh resource
    local mesh_config=$(mktemp)
    cat > "$mesh_config" << EOF
apiVersion: appmesh.k8s.aws/v1beta2
kind: Mesh
metadata:
  name: ${APP_MESH_NAME}
spec:
  namespaceSelector:
    matchLabels:
      mesh: ${APP_MESH_NAME}
EOF
    
    kubectl apply -f "$mesh_config"
    rm -f "$mesh_config"
    
    success "App Mesh and namespace created successfully"
}

# Build and push container images
build_push_containers() {
    if [[ "$SKIP_CONTAINER_BUILD" == "true" ]]; then
        log "Skipping container image building as requested"
        return 0
    fi
    
    log "Building and pushing sample microservices..."
    
    # Create temporary directory for microservices code
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"
    
    # Create service A
    cat > service-a.py << 'EOF'
from flask import Flask, jsonify
import requests
import os

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({"service": "A", "message": "Hello from Service A"})

@app.route('/call-b')
def call_b():
    try:
        response = requests.get('http://service-b:5000/')
        return jsonify({"service": "A", "called": "B", "response": response.json()})
    except Exception as e:
        return jsonify({"service": "A", "error": str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
    
    cat > Dockerfile-service-a << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY service-a.py .
RUN pip install flask requests
EXPOSE 5000
CMD ["python", "service-a.py"]
EOF
    
    # Create service B
    cat > service-b.py << 'EOF'
from flask import Flask, jsonify
import requests
import os

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({"service": "B", "message": "Hello from Service B"})

@app.route('/call-c')
def call_c():
    try:
        response = requests.get('http://service-c:5000/')
        return jsonify({"service": "B", "called": "C", "response": response.json()})
    except Exception as e:
        return jsonify({"service": "B", "error": str(e)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
    
    cat > Dockerfile-service-b << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY service-b.py .
RUN pip install flask requests
EXPOSE 5000
CMD ["python", "service-b.py"]
EOF
    
    # Create service C
    cat > service-c.py << 'EOF'
from flask import Flask, jsonify
import time

app = Flask(__name__)

@app.route('/')
def hello():
    return jsonify({"service": "C", "message": "Hello from Service C", "timestamp": time.time()})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
    
    cat > Dockerfile-service-c << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY service-c.py .
RUN pip install flask
EXPOSE 5000
CMD ["python", "service-c.py"]
EOF
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would build and push container images"
        cd - > /dev/null
        rm -rf "$temp_dir"
        return 0
    fi
    
    # Login to ECR
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin \
        "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    # Build and push each service
    local services=("a" "b" "c")
    for service in "${services[@]}"; do
        local image_name="${ECR_REPO_PREFIX}-service-${service}"
        local image_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${image_name}:latest"
        
        log "Building service $service..."
        docker build -t "$image_name:latest" -f "Dockerfile-service-${service}" .
        docker tag "$image_name:latest" "$image_uri"
        docker push "$image_uri"
        
        success "Built and pushed service $service"
    done
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    success "Container images built and pushed successfully"
}

# Deploy virtual nodes and services
deploy_virtual_nodes() {
    log "Deploying Virtual Nodes and Virtual Services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would deploy virtual nodes and services"
        return 0
    fi
    
    local temp_dir=$(mktemp -d)
    
    # Create Virtual Nodes
    local services=("a" "b" "c")
    for service in "${services[@]}"; do
        local virtual_node_file="$temp_dir/virtual-node-service-${service}.yaml"
        
        # Determine backends
        local backends=""
        if [[ "$service" == "a" ]]; then
            backends="    backends:
      - virtualService:
          virtualServiceRef:
            name: service-b"
        elif [[ "$service" == "b" ]]; then
            backends="    backends:
      - virtualService:
          virtualServiceRef:
            name: service-c"
        fi
        
        cat > "$virtual_node_file" << EOF
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualNode
metadata:
  name: service-${service}
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: service-${service}
  listeners:
    - portMapping:
        port: 5000
        protocol: http
      healthCheck:
        protocol: http
        path: '/'
        healthyThreshold: 2
        unhealthyThreshold: 2
        timeoutMillis: 2000
        intervalMillis: 5000
${backends}
  serviceDiscovery:
    dns:
      hostname: service-${service}.${NAMESPACE}.svc.cluster.local
EOF
        kubectl apply -f "$virtual_node_file"
    done
    
    # Create Virtual Services
    for service in "${services[@]}"; do
        local virtual_service_file="$temp_dir/virtual-service-${service}.yaml"
        
        cat > "$virtual_service_file" << EOF
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualService
metadata:
  name: service-${service}
  namespace: ${NAMESPACE}
spec:
  awsName: service-${service}.${NAMESPACE}.svc.cluster.local
  provider:
    virtualNode:
      virtualNodeRef:
        name: service-${service}
EOF
        kubectl apply -f "$virtual_service_file"
    done
    
    rm -rf "$temp_dir"
    success "Virtual nodes and services deployed successfully"
}

# Deploy microservices
deploy_microservices() {
    log "Deploying microservices with App Mesh integration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would deploy microservices"
        return 0
    fi
    
    local temp_dir=$(mktemp -d)
    local services=("a" "b" "c")
    
    for service in "${services[@]}"; do
        local deployment_file="$temp_dir/service-${service}-deployment.yaml"
        local image_uri="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}-service-${service}:latest"
        
        cat > "$deployment_file" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: service-${service}
  namespace: ${NAMESPACE}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: service-${service}
  template:
    metadata:
      labels:
        app: service-${service}
    spec:
      containers:
      - name: service-${service}
        image: ${image_uri}
        ports:
        - containerPort: 5000
        env:
        - name: SERVICE_NAME
          value: "service-${service}"
---
apiVersion: v1
kind: Service
metadata:
  name: service-${service}
  namespace: ${NAMESPACE}
spec:
  selector:
    app: service-${service}
  ports:
  - port: 5000
    targetPort: 5000
EOF
        kubectl apply -f "$deployment_file"
    done
    
    # Wait for deployments to be ready
    for service in "${services[@]}"; do
        log "Waiting for service-${service} deployment to be ready..."
        kubectl wait --for=condition=available --timeout=300s \
            deployment/service-${service} -n "$NAMESPACE"
    done
    
    rm -rf "$temp_dir"
    success "Microservices deployed successfully"
}

# Install AWS Load Balancer Controller
install_load_balancer_controller() {
    log "Installing AWS Load Balancer Controller..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would install AWS Load Balancer Controller"
        return 0
    fi
    
    # Check if already installed
    if kubectl get deployment aws-load-balancer-controller -n kube-system &> /dev/null; then
        warning "AWS Load Balancer Controller already installed, skipping"
        return 0
    fi
    
    # Download IAM policy
    local policy_file=$(mktemp)
    curl -s -o "$policy_file" \
        https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.4.4/docs/install/iam_policy.json
    
    # Create IAM policy
    local policy_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"
    if ! aws iam get-policy --policy-arn "$policy_arn" &> /dev/null; then
        aws iam create-policy \
            --policy-name AWSLoadBalancerControllerIAMPolicy \
            --policy-document "file://$policy_file"
    fi
    
    rm -f "$policy_file"
    
    # Create service account
    eksctl create iamserviceaccount \
        --cluster="$CLUSTER_NAME" \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --attach-policy-arn="$policy_arn" \
        --override-existing-serviceaccounts \
        --approve
    
    # Install controller using Helm
    helm repo add eks https://aws.github.io/eks-charts || true
    helm repo update
    
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName="$CLUSTER_NAME" \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller
    
    # Wait for controller to be ready
    kubectl wait --for=condition=available --timeout=300s \
        deployment/aws-load-balancer-controller -n kube-system
    
    success "AWS Load Balancer Controller installed successfully"
}

# Create ingress
create_ingress() {
    log "Creating Application Load Balancer Ingress..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would create ingress"
        return 0
    fi
    
    local ingress_file=$(mktemp)
    cat > "$ingress_file" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: service-a-ingress
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: service-a
            port:
              number: 5000
EOF
    
    kubectl apply -f "$ingress_file"
    rm -f "$ingress_file"
    
    success "Application Load Balancer configured successfully"
}

# Configure observability
configure_observability() {
    log "Configuring CloudWatch observability..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would configure CloudWatch Container Insights"
        return 0
    fi
    
    # Enable CloudWatch Container Insights
    local cwagent_file=$(mktemp)
    curl -s -o "$cwagent_file" \
        https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml
    
    # Replace cluster name and region
    sed -i.bak "s/{{cluster_name}}/${CLUSTER_NAME}/g" "$cwagent_file"
    sed -i.bak "s/{{region_name}}/${AWS_REGION}/g" "$cwagent_file"
    
    kubectl apply -f "$cwagent_file"
    rm -f "$cwagent_file" "${cwagent_file}.bak"
    
    success "CloudWatch Container Insights configured successfully"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Check App Mesh resources
    log "Checking App Mesh resources..."
    kubectl get virtualnodes -n "$NAMESPACE" -o wide
    kubectl get virtualservices -n "$NAMESPACE" -o wide
    kubectl get mesh
    
    # Check pod status
    log "Checking pod status..."
    kubectl get pods -n "$NAMESPACE" -o wide
    
    # Check ingress
    log "Checking ingress status..."
    kubectl get ingress -n "$NAMESPACE"
    
    # Get load balancer URL
    local lb_url=""
    local attempts=0
    while [[ -z "$lb_url" && $attempts -lt 60 ]]; do
        lb_url=$(kubectl get ingress service-a-ingress -n "$NAMESPACE" \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
        if [[ -z "$lb_url" ]]; then
            log "Waiting for Load Balancer to be ready... (attempt $((attempts+1))/60)"
            sleep 10
            ((attempts++))
        fi
    done
    
    if [[ -n "$lb_url" ]]; then
        success "Load Balancer URL: http://$lb_url"
        log "You can test the service with: curl http://$lb_url/"
    else
        warning "Load Balancer URL not yet available. Check status with: kubectl get ingress -n $NAMESPACE"
    fi
    
    success "Deployment validation completed"
}

# Print deployment summary
print_summary() {
    log "Deployment Summary"
    echo "=================="
    echo "Cluster Name:        $CLUSTER_NAME"
    echo "App Mesh Name:       $APP_MESH_NAME"
    echo "Namespace:           $NAMESPACE"
    echo "AWS Region:          $AWS_REGION"
    echo "ECR Repository:      ${ECR_REPO_PREFIX}-*"
    echo ""
    echo "Next Steps:"
    echo "1. Check service status: kubectl get pods -n $NAMESPACE"
    echo "2. View App Mesh resources: kubectl get virtualnodes,virtualservices -n $NAMESPACE"
    echo "3. Get Load Balancer URL: kubectl get ingress -n $NAMESPACE"
    echo "4. Test the application: curl http://\$(kubectl get ingress service-a-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/"
    echo ""
    echo "To clean up resources, run: $(dirname "$0")/destroy.sh"
    echo ""
    warning "Remember to clean up resources to avoid ongoing charges!"
}

# Main deployment function
main() {
    log "Starting deployment of Microservices on EKS with AWS App Mesh"
    
    parse_args "$@"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No actual resources will be created"
    fi
    
    check_prerequisites
    setup_environment
    create_ecr_repositories
    create_eks_cluster
    install_app_mesh_controller
    create_app_mesh_namespace
    build_push_containers
    deploy_virtual_nodes
    deploy_microservices
    install_load_balancer_controller
    create_ingress
    configure_observability
    validate_deployment
    print_summary
    
    success "Deployment completed successfully!"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "This was a dry run. No resources were actually created."
        log "Run without --dry-run to perform the actual deployment."
    fi
}

# Run main function with all arguments
main "$@"