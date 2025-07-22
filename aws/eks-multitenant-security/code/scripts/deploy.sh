#!/bin/bash

# Deploy script for EKS Multi-Tenant Cluster Security with Namespace Isolation
# This script implements secure multi-tenant EKS cluster configuration with proper isolation

set -euo pipefail

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

info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Check if running in dry-run mode
DRY_RUN=${DRY_RUN:-false}
if [ "$DRY_RUN" = "true" ]; then
    warn "Running in DRY-RUN mode - no actual resources will be created"
    KUBECTL_CMD="echo kubectl"
    AWS_CMD="echo aws"
else
    KUBECTL_CMD="kubectl"
    AWS_CMD="aws"
fi

# Default values
CLUSTER_NAME=${CLUSTER_NAME:-"my-multi-tenant-cluster"}
TENANT_A_NAME=${TENANT_A_NAME:-"tenant-alpha"}
TENANT_B_NAME=${TENANT_B_NAME:-"tenant-beta"}
SKIP_PREREQ_CHECK=${SKIP_PREREQ_CHECK:-false}
TEMP_DIR=$(mktemp -d)

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Set trap for cleanup
trap cleanup EXIT

# Function to check prerequisites
check_prerequisites() {
    if [ "$SKIP_PREREQ_CHECK" = "true" ]; then
        warn "Skipping prerequisite checks"
        return 0
    fi

    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if kubectl is installed
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install it first."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' first."
    fi
    
    # Verify AWS region is set
    if [ -z "$(aws configure get region)" ]; then
        error "AWS region not configured. Please set AWS_DEFAULT_REGION or configure region."
    fi
    
    info "Prerequisites check passed"
}

# Function to verify EKS cluster connectivity
verify_cluster_connectivity() {
    log "Verifying EKS cluster connectivity..."
    
    # Check if cluster exists
    if ! aws eks describe-cluster --name "$CLUSTER_NAME" &> /dev/null; then
        error "EKS cluster '$CLUSTER_NAME' not found. Please create the cluster first."
    fi
    
    # Update kubeconfig
    log "Updating kubeconfig for cluster: $CLUSTER_NAME"
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$(aws configure get region)"
    
    # Test kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        error "Cannot connect to EKS cluster. Please check your configuration."
    fi
    
    info "Cluster connectivity verified"
}

# Function to create tenant namespaces
create_tenant_namespaces() {
    log "Creating tenant namespaces..."
    
    # Create namespace for Tenant A
    if ! kubectl get namespace "$TENANT_A_NAME" &> /dev/null; then
        $KUBECTL_CMD create namespace "$TENANT_A_NAME"
        info "Created namespace: $TENANT_A_NAME"
    else
        warn "Namespace $TENANT_A_NAME already exists"
    fi
    
    # Create namespace for Tenant B
    if ! kubectl get namespace "$TENANT_B_NAME" &> /dev/null; then
        $KUBECTL_CMD create namespace "$TENANT_B_NAME"
        info "Created namespace: $TENANT_B_NAME"
    else
        warn "Namespace $TENANT_B_NAME already exists"
    fi
    
    # Add labels for tenant identification
    $KUBECTL_CMD label namespace "$TENANT_A_NAME" \
        tenant=alpha \
        isolation=enabled \
        environment=production \
        --overwrite
    
    $KUBECTL_CMD label namespace "$TENANT_B_NAME" \
        tenant=beta \
        isolation=enabled \
        environment=production \
        --overwrite
    
    info "Tenant namespaces created and labeled successfully"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles for tenant access..."
    
    # Get AWS Account ID
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Create trust policy
    cat > "$TEMP_DIR/tenant-trust-policy.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create IAM role for Tenant A
    if ! aws iam get-role --role-name "${TENANT_A_NAME}-eks-role" &> /dev/null; then
        $AWS_CMD iam create-role \
            --role-name "${TENANT_A_NAME}-eks-role" \
            --assume-role-policy-document "file://$TEMP_DIR/tenant-trust-policy.json"
        info "Created IAM role: ${TENANT_A_NAME}-eks-role"
    else
        warn "IAM role ${TENANT_A_NAME}-eks-role already exists"
    fi
    
    # Create IAM role for Tenant B
    if ! aws iam get-role --role-name "${TENANT_B_NAME}-eks-role" &> /dev/null; then
        $AWS_CMD iam create-role \
            --role-name "${TENANT_B_NAME}-eks-role" \
            --assume-role-policy-document "file://$TEMP_DIR/tenant-trust-policy.json"
        info "Created IAM role: ${TENANT_B_NAME}-eks-role"
    else
        warn "IAM role ${TENANT_B_NAME}-eks-role already exists"
    fi
    
    info "IAM roles created successfully"
}

# Function to create RBAC resources
create_rbac_resources() {
    log "Creating Kubernetes RBAC resources..."
    
    # Create RBAC configuration for Tenant A
    cat > "$TEMP_DIR/tenant-a-rbac.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${TENANT_A_NAME}
  name: ${TENANT_A_NAME}-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "daemonsets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "networkpolicies"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${TENANT_A_NAME}-binding
  namespace: ${TENANT_A_NAME}
subjects:
- kind: User
  name: ${TENANT_A_NAME}-user
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${TENANT_A_NAME}-role
  apiGroup: rbac.authorization.k8s.io
EOF
    
    # Create RBAC configuration for Tenant B
    cat > "$TEMP_DIR/tenant-b-rbac.yaml" << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${TENANT_B_NAME}
  name: ${TENANT_B_NAME}-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets", "daemonsets", "statefulsets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "networkpolicies"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${TENANT_B_NAME}-binding
  namespace: ${TENANT_B_NAME}
subjects:
- kind: User
  name: ${TENANT_B_NAME}-user
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${TENANT_B_NAME}-role
  apiGroup: rbac.authorization.k8s.io
EOF
    
    # Apply RBAC configurations
    $KUBECTL_CMD apply -f "$TEMP_DIR/tenant-a-rbac.yaml"
    $KUBECTL_CMD apply -f "$TEMP_DIR/tenant-b-rbac.yaml"
    
    info "RBAC resources created successfully"
}

# Function to configure EKS access entries
configure_access_entries() {
    log "Configuring EKS access entries..."
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Create access entry for Tenant A
    if ! aws eks describe-access-entry \
        --cluster-name "$CLUSTER_NAME" \
        --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TENANT_A_NAME}-eks-role" &> /dev/null; then
        $AWS_CMD eks create-access-entry \
            --cluster-name "$CLUSTER_NAME" \
            --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TENANT_A_NAME}-eks-role" \
            --type STANDARD \
            --username "${TENANT_A_NAME}-user"
        info "Created access entry for Tenant A"
    else
        warn "Access entry for Tenant A already exists"
    fi
    
    # Create access entry for Tenant B
    if ! aws eks describe-access-entry \
        --cluster-name "$CLUSTER_NAME" \
        --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TENANT_B_NAME}-eks-role" &> /dev/null; then
        $AWS_CMD eks create-access-entry \
            --cluster-name "$CLUSTER_NAME" \
            --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${TENANT_B_NAME}-eks-role" \
            --type STANDARD \
            --username "${TENANT_B_NAME}-user"
        info "Created access entry for Tenant B"
    else
        warn "Access entry for Tenant B already exists"
    fi
    
    info "Access entries configured successfully"
}

# Function to implement network policies
implement_network_policies() {
    log "Implementing network policies for tenant isolation..."
    
    # Create network policy for Tenant A
    cat > "$TEMP_DIR/tenant-a-network-policy.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${TENANT_A_NAME}-isolation
  namespace: ${TENANT_A_NAME}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tenant: alpha
  - from:
    - namespaceSelector:
        matchLabels:
          name: kube-system
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          tenant: alpha
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
  - to: []
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
EOF
    
    # Create network policy for Tenant B
    cat > "$TEMP_DIR/tenant-b-network-policy.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ${TENANT_B_NAME}-isolation
  namespace: ${TENANT_B_NAME}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tenant: beta
  - from:
    - namespaceSelector:
        matchLabels:
          name: kube-system
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          tenant: beta
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
  - to: []
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
EOF
    
    # Apply network policies
    $KUBECTL_CMD apply -f "$TEMP_DIR/tenant-a-network-policy.yaml"
    $KUBECTL_CMD apply -f "$TEMP_DIR/tenant-b-network-policy.yaml"
    
    info "Network policies implemented successfully"
}

# Function to configure resource quotas
configure_resource_quotas() {
    log "Configuring resource quotas and limits..."
    
    # Create resource quota for Tenant A
    cat > "$TEMP_DIR/tenant-a-quota.yaml" << EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${TENANT_A_NAME}-quota
  namespace: ${TENANT_A_NAME}
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "10"
    services: "5"
    secrets: "10"
    configmaps: "10"
    persistentvolumeclaims: "4"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: ${TENANT_A_NAME}-limits
  namespace: ${TENANT_A_NAME}
spec:
  limits:
  - default:
      cpu: 200m
      memory: 256Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
EOF
    
    # Create resource quota for Tenant B
    cat > "$TEMP_DIR/tenant-b-quota.yaml" << EOF
apiVersion: v1
kind: ResourceQuota
metadata:
  name: ${TENANT_B_NAME}-quota
  namespace: ${TENANT_B_NAME}
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "10"
    services: "5"
    secrets: "10"
    configmaps: "10"
    persistentvolumeclaims: "4"
---
apiVersion: v1
kind: LimitRange
metadata:
  name: ${TENANT_B_NAME}-limits
  namespace: ${TENANT_B_NAME}
spec:
  limits:
  - default:
      cpu: 200m
      memory: 256Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
EOF
    
    # Apply resource quotas
    $KUBECTL_CMD apply -f "$TEMP_DIR/tenant-a-quota.yaml"
    $KUBECTL_CMD apply -f "$TEMP_DIR/tenant-b-quota.yaml"
    
    info "Resource quotas and limits configured successfully"
}

# Function to deploy sample applications
deploy_sample_applications() {
    log "Deploying sample applications for testing..."
    
    # Deploy sample application for Tenant A
    cat > "$TEMP_DIR/tenant-a-app.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TENANT_A_NAME}-app
  namespace: ${TENANT_A_NAME}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${TENANT_A_NAME}-app
  template:
    metadata:
      labels:
        app: ${TENANT_A_NAME}-app
    spec:
      containers:
      - name: app
        image: nginx:1.20
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: ${TENANT_A_NAME}-service
  namespace: ${TENANT_A_NAME}
spec:
  selector:
    app: ${TENANT_A_NAME}-app
  ports:
  - port: 80
    targetPort: 80
EOF
    
    # Deploy sample application for Tenant B
    cat > "$TEMP_DIR/tenant-b-app.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TENANT_B_NAME}-app
  namespace: ${TENANT_B_NAME}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${TENANT_B_NAME}-app
  template:
    metadata:
      labels:
        app: ${TENANT_B_NAME}-app
    spec:
      containers:
      - name: app
        image: httpd:2.4
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: ${TENANT_B_NAME}-service
  namespace: ${TENANT_B_NAME}
spec:
  selector:
    app: ${TENANT_B_NAME}-app
  ports:
  - port: 80
    targetPort: 80
EOF
    
    # Apply applications
    $KUBECTL_CMD apply -f "$TEMP_DIR/tenant-a-app.yaml"
    $KUBECTL_CMD apply -f "$TEMP_DIR/tenant-b-app.yaml"
    
    info "Sample applications deployed successfully"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check namespaces
    if kubectl get namespaces --show-labels | grep -q "$TENANT_A_NAME"; then
        info "Tenant A namespace validated"
    else
        warn "Tenant A namespace validation failed"
    fi
    
    if kubectl get namespaces --show-labels | grep -q "$TENANT_B_NAME"; then
        info "Tenant B namespace validated"
    else
        warn "Tenant B namespace validation failed"
    fi
    
    # Check pods
    if kubectl get pods -n "$TENANT_A_NAME" | grep -q Running; then
        info "Tenant A pods are running"
    else
        warn "Tenant A pods not yet running"
    fi
    
    if kubectl get pods -n "$TENANT_B_NAME" | grep -q Running; then
        info "Tenant B pods are running"
    else
        warn "Tenant B pods not yet running"
    fi
    
    # Check RBAC
    if kubectl get role -n "$TENANT_A_NAME" | grep -q "${TENANT_A_NAME}-role"; then
        info "Tenant A RBAC validated"
    else
        warn "Tenant A RBAC validation failed"
    fi
    
    if kubectl get role -n "$TENANT_B_NAME" | grep -q "${TENANT_B_NAME}-role"; then
        info "Tenant B RBAC validated"
    else
        warn "Tenant B RBAC validation failed"
    fi
    
    info "Deployment validation completed"
}

# Function to display deployment information
display_deployment_info() {
    log "Deployment completed successfully!"
    
    echo ""
    echo "=== Deployment Summary ==="
    echo "Cluster Name: $CLUSTER_NAME"
    echo "Tenant A Namespace: $TENANT_A_NAME"
    echo "Tenant B Namespace: $TENANT_B_NAME"
    echo ""
    echo "=== Next Steps ==="
    echo "1. Verify isolation by running: kubectl auth can-i get pods --as=${TENANT_A_NAME}-user -n ${TENANT_B_NAME}"
    echo "2. Test network policies between tenant pods"
    echo "3. Monitor resource usage with: kubectl describe quota -n ${TENANT_A_NAME}"
    echo "4. Review network policies: kubectl get networkpolicy -n ${TENANT_A_NAME}"
    echo ""
    echo "=== Cleanup ==="
    echo "To remove all resources, run: ./destroy.sh"
    echo ""
}

# Main execution
main() {
    log "Starting EKS Multi-Tenant Cluster Security deployment..."
    
    check_prerequisites
    verify_cluster_connectivity
    create_tenant_namespaces
    create_iam_roles
    create_rbac_resources
    configure_access_entries
    implement_network_policies
    configure_resource_quotas
    deploy_sample_applications
    
    # Wait for pods to be ready
    log "Waiting for pods to be ready..."
    sleep 30
    
    validate_deployment
    display_deployment_info
    
    info "Deployment completed successfully!"
}

# Print usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -c, --cluster-name NAME     EKS cluster name (default: my-multi-tenant-cluster)
    -a, --tenant-a NAME         Tenant A name (default: tenant-alpha)
    -b, --tenant-b NAME         Tenant B name (default: tenant-beta)
    -d, --dry-run              Run in dry-run mode (no actual changes)
    -s, --skip-prereq          Skip prerequisite checks
    -h, --help                 Show this help message

Environment Variables:
    CLUSTER_NAME               EKS cluster name
    TENANT_A_NAME              Tenant A namespace name
    TENANT_B_NAME              Tenant B namespace name
    DRY_RUN                    Set to 'true' for dry-run mode
    SKIP_PREREQ_CHECK          Set to 'true' to skip prerequisite checks

Examples:
    $0
    $0 --cluster-name my-cluster --tenant-a alpha --tenant-b beta
    DRY_RUN=true $0
    CLUSTER_NAME=prod-cluster $0 --skip-prereq
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -a|--tenant-a)
            TENANT_A_NAME="$2"
            shift 2
            ;;
        -b|--tenant-b)
            TENANT_B_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--skip-prereq)
            SKIP_PREREQ_CHECK=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Run main function
main "$@"