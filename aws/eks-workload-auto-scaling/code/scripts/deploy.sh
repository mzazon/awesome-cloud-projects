#!/bin/bash

# Deploy script for EKS Auto-Scaling Recipe
# Implements Auto Scaling for EKS Workloads with HPA and Cluster Autoscaler

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Default configuration
CLUSTER_NAME="eks-autoscaling-demo"
NODEGROUP_NAME="autoscaling-nodes"
SERVICE_ACCOUNT_NAME="cluster-autoscaler"
NAMESPACE="kube-system"
DRY_RUN=false
SKIP_APPS=false
SKIP_MONITORING=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-apps)
            SKIP_APPS=true
            shift
            ;;
        --skip-monitoring)
            SKIP_MONITORING=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --cluster-name NAME    Set cluster name (default: eks-autoscaling-demo)"
            echo "  --dry-run             Show what would be done without executing"
            echo "  --skip-apps           Skip demo application deployment"
            echo "  --skip-monitoring     Skip monitoring stack deployment"
            echo "  --help                Show this help message"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running in dry-run mode
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN MODE: No actual changes will be made"
        return 0
    fi
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it first."
    fi
    
    # Check eksctl
    if ! command -v eksctl &> /dev/null; then
        error "eksctl is not installed. Please install it first."
    fi
    
    # Check helm
    if ! command -v helm &> /dev/null; then
        error "Helm is not installed. Please install it first."
    fi
    
    # Check if git is available (needed for VPA)
    if ! command -v git &> /dev/null; then
        error "Git is not installed. Please install it first."
    fi
    
    # Check AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        fi
    fi
    
    log "Prerequisites check completed successfully"
}

# Set environment variables
set_environment() {
    log "Setting up environment variables..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set cluster and resource names
    export CLUSTER_FULL_NAME="${CLUSTER_NAME}-${RANDOM_SUFFIX}"
    
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    info "AWS Region: $AWS_REGION"
    info "Cluster Name: $CLUSTER_FULL_NAME"
    info "Random Suffix: $RANDOM_SUFFIX"
}

# Create EKS cluster
create_eks_cluster() {
    log "Creating EKS cluster configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create EKS cluster with configuration"
        return 0
    fi
    
    # Check if cluster already exists
    if aws eks describe-cluster --name "$CLUSTER_FULL_NAME" &> /dev/null; then
        warn "Cluster $CLUSTER_FULL_NAME already exists. Skipping creation."
        return 0
    fi
    
    # Create cluster configuration file
    cat > cluster-config.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_FULL_NAME}
  region: ${AWS_REGION}
  version: "1.28"

managedNodeGroups:
  - name: general-purpose
    instanceTypes: ["m5.large", "m5.xlarge"]
    desiredCapacity: 2
    minSize: 1
    maxSize: 10
    volumeSize: 20
    ssh:
      allow: false
    labels:
      workload-type: "general"
    tags:
      k8s.io/cluster-autoscaler/enabled: "true"
      k8s.io/cluster-autoscaler/${CLUSTER_FULL_NAME}: "owned"
  
  - name: compute-optimized
    instanceTypes: ["c5.large", "c5.xlarge"]
    desiredCapacity: 1
    minSize: 0
    maxSize: 5
    volumeSize: 20
    ssh:
      allow: false
    labels:
      workload-type: "compute"
    tags:
      k8s.io/cluster-autoscaler/enabled: "true"
      k8s.io/cluster-autoscaler/${CLUSTER_FULL_NAME}: "owned"

addons:
  - name: vpc-cni
    version: latest
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
  - name: aws-ebs-csi-driver
    version: latest

iam:
  withOIDC: true
  serviceAccounts:
    - metadata:
        name: ${SERVICE_ACCOUNT_NAME}
        namespace: ${NAMESPACE}
      wellKnownPolicies:
        autoScaler: true
EOF
    
    log "Creating EKS cluster (this may take 15-20 minutes)..."
    if ! eksctl create cluster -f cluster-config.yaml; then
        error "Failed to create EKS cluster"
    fi
    
    log "EKS cluster created successfully"
}

# Install metrics server
install_metrics_server() {
    log "Installing Metrics Server..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would install Metrics Server"
        return 0
    fi
    
    # Deploy Metrics Server
    if ! kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml; then
        error "Failed to deploy Metrics Server"
    fi
    
    # Wait for metrics server to be ready
    log "Waiting for Metrics Server to be ready..."
    if ! kubectl wait --for=condition=ready pod -l k8s-app=metrics-server -n kube-system --timeout=300s; then
        error "Metrics Server failed to become ready"
    fi
    
    # Verify metrics server is working
    info "Verifying Metrics Server..."
    sleep 30  # Give metrics server time to collect data
    if kubectl top nodes &> /dev/null; then
        log "Metrics Server installed and verified successfully"
    else
        warn "Metrics Server installed but may still be collecting initial data"
    fi
}

# Deploy cluster autoscaler
deploy_cluster_autoscaler() {
    log "Deploying Cluster Autoscaler..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would deploy Cluster Autoscaler"
        return 0
    fi
    
    # Download cluster autoscaler configuration
    if ! curl -o cluster-autoscaler-autodiscover.yaml \
        https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml; then
        error "Failed to download Cluster Autoscaler configuration"
    fi
    
    # Update the cluster autoscaler configuration
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/<YOUR CLUSTER NAME>/${CLUSTER_FULL_NAME}/g" cluster-autoscaler-autodiscover.yaml
    else
        sed -i "s/<YOUR CLUSTER NAME>/${CLUSTER_FULL_NAME}/g" cluster-autoscaler-autodiscover.yaml
    fi
    
    # Apply the cluster autoscaler
    if ! kubectl apply -f cluster-autoscaler-autodiscover.yaml; then
        error "Failed to apply Cluster Autoscaler configuration"
    fi
    
    # Get the service account role ARN
    local role_arn=$(aws iam list-roles --query "Roles[?contains(RoleName, 'eksctl-${CLUSTER_FULL_NAME}-addon-iamserviceaccount-kube-system-cluster-autoscaler')].Arn" --output text)
    
    if [[ -n "$role_arn" ]]; then
        # Add cluster autoscaler annotations
        if ! kubectl annotate serviceaccount cluster-autoscaler \
            -n kube-system \
            eks.amazonaws.com/role-arn="$role_arn" --overwrite; then
            error "Failed to annotate service account"
        fi
        
        # Restart cluster autoscaler to pick up new annotation
        kubectl scale deployment cluster-autoscaler --replicas=0 -n kube-system
        sleep 10
        kubectl scale deployment cluster-autoscaler --replicas=1 -n kube-system
    else
        warn "Could not find Cluster Autoscaler service account role. Manual annotation may be required."
    fi
    
    log "Cluster Autoscaler deployed successfully"
}

# Install KEDA
install_keda() {
    log "Installing KEDA..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would install KEDA"
        return 0
    fi
    
    # Add KEDA Helm repository
    if ! helm repo add kedacore https://kedacore.github.io/charts; then
        error "Failed to add KEDA Helm repository"
    fi
    
    if ! helm repo update; then
        error "Failed to update Helm repositories"
    fi
    
    # Install KEDA
    if ! helm install keda kedacore/keda \
        --namespace keda-system \
        --create-namespace \
        --set prometheus.metricServer.enabled=true \
        --set prometheus.operator.enabled=true; then
        error "Failed to install KEDA"
    fi
    
    # Wait for KEDA to be ready
    log "Waiting for KEDA to be ready..."
    if ! kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keda -n keda-system --timeout=300s; then
        error "KEDA failed to become ready"
    fi
    
    log "KEDA installed successfully"
}

# Deploy sample applications
deploy_sample_applications() {
    if [[ "$SKIP_APPS" == "true" ]]; then
        log "Skipping sample applications deployment"
        return 0
    fi
    
    log "Deploying sample applications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would deploy sample applications"
        return 0
    fi
    
    # Create namespace for applications
    kubectl create namespace demo-apps --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy CPU-intensive application
    cat > cpu-app.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-demo
  namespace: demo-apps
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cpu-demo
  template:
    metadata:
      labels:
        app: cpu-demo
    spec:
      containers:
      - name: cpu-demo
        image: k8s.gcr.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: cpu-demo-service
  namespace: demo-apps
spec:
  selector:
    app: cpu-demo
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: cpu-demo-hpa
  namespace: demo-apps
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: cpu-demo
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
      - type: Percent
        value: 100
        periodSeconds: 60
EOF
    
    if ! kubectl apply -f cpu-app.yaml; then
        error "Failed to deploy CPU-intensive application"
    fi
    
    # Deploy memory-intensive application
    cat > memory-app.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: memory-demo
  namespace: demo-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: memory-demo
  template:
    metadata:
      labels:
        app: memory-demo
    spec:
      containers:
      - name: memory-demo
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 256Mi
          limits:
            cpu: 200m
            memory: 512Mi
---
apiVersion: v1
kind: Service
metadata:
  name: memory-demo-service
  namespace: demo-apps
spec:
  selector:
    app: memory-demo
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: memory-demo-hpa
  namespace: demo-apps
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: memory-demo
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
    scaleUp:
      stabilizationWindowSeconds: 30
EOF
    
    if ! kubectl apply -f memory-app.yaml; then
        error "Failed to deploy memory-intensive application"
    fi
    
    # Deploy custom metrics application
    cat > custom-metrics-app.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: custom-metrics-demo
  namespace: demo-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: custom-metrics-demo
  template:
    metadata:
      labels:
        app: custom-metrics-demo
    spec:
      containers:
      - name: custom-metrics-demo
        image: nginx:1.21
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 300m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: custom-metrics-demo-service
  namespace: demo-apps
spec:
  selector:
    app: custom-metrics-demo
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: custom-metrics-scaler
  namespace: demo-apps
spec:
  scaleTargetRef:
    name: custom-metrics-demo
  minReplicaCount: 1
  maxReplicaCount: 15
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus-server.monitoring.svc.cluster.local:80
      metricName: http_requests_per_second
      threshold: '30'
      query: rate(http_requests_total[1m])
EOF
    
    if ! kubectl apply -f custom-metrics-app.yaml; then
        error "Failed to deploy custom metrics application"
    fi
    
    # Create Pod Disruption Budgets
    cat > pod-disruption-budgets.yaml << EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: cpu-demo-pdb
  namespace: demo-apps
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: cpu-demo
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: memory-demo-pdb
  namespace: demo-apps
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: memory-demo
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: custom-metrics-demo-pdb
  namespace: demo-apps
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: custom-metrics-demo
EOF
    
    if ! kubectl apply -f pod-disruption-budgets.yaml; then
        error "Failed to deploy Pod Disruption Budgets"
    fi
    
    log "Sample applications deployed successfully"
}

# Configure cluster autoscaler advanced settings
configure_cluster_autoscaler() {
    log "Configuring Cluster Autoscaler with advanced settings..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would configure Cluster Autoscaler advanced settings"
        return 0
    fi
    
    # Update cluster autoscaler with advanced configuration
    if ! kubectl patch deployment cluster-autoscaler \
        -n kube-system \
        -p '{"spec":{"template":{"spec":{"containers":[{"name":"cluster-autoscaler","command":["./cluster-autoscaler","--v=4","--stderrthreshold=info","--cloud-provider=aws","--skip-nodes-with-local-storage=false","--expander=least-waste","--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/'"${CLUSTER_FULL_NAME}"'","--balance-similar-node-groups","--skip-nodes-with-system-pods=false","--scale-down-delay-after-add=10m","--scale-down-unneeded-time=10m","--scale-down-delay-after-delete=10s","--scale-down-utilization-threshold=0.5"]}]}}}}'; then
        error "Failed to update Cluster Autoscaler configuration"
    fi
    
    # Add resource limits to cluster autoscaler
    if ! kubectl patch deployment cluster-autoscaler \
        -n kube-system \
        -p '{"spec":{"template":{"spec":{"containers":[{"name":"cluster-autoscaler","resources":{"limits":{"cpu":"100m","memory":"300Mi"},"requests":{"cpu":"100m","memory":"300Mi"}}}]}}}}'; then
        error "Failed to set Cluster Autoscaler resource limits"
    fi
    
    log "Cluster Autoscaler configured with advanced settings"
}

# Set up monitoring
setup_monitoring() {
    if [[ "$SKIP_MONITORING" == "true" ]]; then
        log "Skipping monitoring setup"
        return 0
    fi
    
    log "Setting up monitoring stack..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would set up monitoring stack"
        return 0
    fi
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Add Prometheus Helm repository
    if ! helm repo add prometheus-community https://prometheus-community.github.io/helm-charts; then
        error "Failed to add Prometheus Helm repository"
    fi
    
    if ! helm repo update; then
        error "Failed to update Helm repositories"
    fi
    
    # Install Prometheus
    if ! helm install prometheus prometheus-community/prometheus \
        --namespace monitoring \
        --set server.persistentVolume.size=20Gi \
        --set server.retention=7d \
        --set alertmanager.persistentVolume.size=10Gi; then
        error "Failed to install Prometheus"
    fi
    
    # Install Grafana
    if ! helm repo add grafana https://grafana.github.io/helm-charts; then
        error "Failed to add Grafana Helm repository"
    fi
    
    if ! helm install grafana grafana/grafana \
        --namespace monitoring \
        --set persistence.enabled=true \
        --set persistence.size=10Gi \
        --set adminPassword=admin123; then
        error "Failed to install Grafana"
    fi
    
    # Wait for monitoring stack to be ready
    log "Waiting for monitoring stack to be ready..."
    if ! kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s; then
        error "Prometheus failed to become ready"
    fi
    
    if ! kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=grafana -n monitoring --timeout=300s; then
        error "Grafana failed to become ready"
    fi
    
    log "Monitoring stack deployed successfully"
}

# Create load testing configuration
create_load_testing() {
    if [[ "$SKIP_APPS" == "true" ]]; then
        log "Skipping load testing configuration"
        return 0
    fi
    
    log "Creating load testing configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN: Would create load testing configuration"
        return 0
    fi
    
    cat > load-test.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: load-generator
  namespace: demo-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: load-generator
  template:
    metadata:
      labels:
        app: load-generator
    spec:
      containers:
      - name: load-generator
        image: busybox:1.35
        command:
        - /bin/sh
        - -c
        - |
          while true; do
            echo "Starting load test..."
            for i in \$(seq 1 1000); do
              wget -q -O- http://cpu-demo-service.demo-apps.svc.cluster.local/ &
              wget -q -O- http://memory-demo-service.demo-apps.svc.cluster.local/ &
              wget -q -O- http://custom-metrics-demo-service.demo-apps.svc.cluster.local/ &
            done
            wait
            echo "Load test completed, sleeping for 30 seconds..."
            sleep 30
          done
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
EOF
    
    if ! kubectl apply -f load-test.yaml; then
        error "Failed to create load testing configuration"
    fi
    
    log "Load testing configuration created successfully"
}

# Display deployment summary
show_deployment_summary() {
    log "Deployment Summary"
    echo "=================================="
    info "Cluster Name: $CLUSTER_FULL_NAME"
    info "AWS Region: $AWS_REGION"
    info "AWS Account ID: $AWS_ACCOUNT_ID"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "DRY RUN MODE: No actual resources were created"
        return 0
    fi
    
    # Get cluster info
    info "Cluster Status:"
    kubectl get nodes -o wide
    echo ""
    
    # Get HPA status
    if [[ "$SKIP_APPS" != "true" ]]; then
        info "HPA Status:"
        kubectl get hpa -n demo-apps
        echo ""
    fi
    
    # Get cluster autoscaler status
    info "Cluster Autoscaler Status:"
    kubectl get pods -n kube-system -l app=cluster-autoscaler
    echo ""
    
    # Get KEDA status
    info "KEDA Status:"
    kubectl get pods -n keda-system -l app.kubernetes.io/name=keda
    echo ""
    
    if [[ "$SKIP_MONITORING" != "true" ]]; then
        info "Monitoring Status:"
        kubectl get pods -n monitoring
        echo ""
    fi
    
    echo "=================================="
    log "Deployment completed successfully!"
    echo ""
    info "Next steps:"
    echo "1. Monitor HPA scaling: kubectl get hpa -n demo-apps -w"
    echo "2. Monitor cluster autoscaler: kubectl logs -n kube-system -l app=cluster-autoscaler -f"
    echo "3. Check node scaling: kubectl get nodes -w"
    echo "4. Access Grafana: kubectl port-forward -n monitoring svc/grafana 3000:80"
    echo "5. Grafana login: admin/admin123"
    echo ""
    warn "Remember to clean up resources when done to avoid ongoing charges!"
}

# Main execution
main() {
    log "Starting EKS Auto-Scaling deployment..."
    
    check_prerequisites
    set_environment
    create_eks_cluster
    install_metrics_server
    deploy_cluster_autoscaler
    install_keda
    deploy_sample_applications
    configure_cluster_autoscaler
    setup_monitoring
    create_load_testing
    show_deployment_summary
    
    log "Deployment process completed successfully!"
}

# Trap to handle script interruption
trap 'error "Script interrupted by user"' INT TERM

# Run main function
main "$@"