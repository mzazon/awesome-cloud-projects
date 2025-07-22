#!/bin/bash

# Deploy EKS Service Mesh with AWS App Mesh
# This script deploys a complete microservices architecture with service mesh capabilities

set -euo pipefail

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
cleanup_on_error() {
    log_error "Deployment failed. Check the logs above for details."
    log_info "To clean up partially created resources, run: ./destroy.sh"
    exit 1
}

trap cleanup_on_error ERR

# Validation functions
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    fi
    
    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi
    
    if ! command -v eksctl &> /dev/null; then
        missing_tools+=("eksctl")
    fi
    
    if ! command -v helm &> /dev/null; then
        missing_tools+=("helm")
    fi
    
    if ! command -v docker &> /dev/null; then
        missing_tools+=("docker")
    fi
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_error "Please install missing tools and try again."
        exit 1
    fi
    
    # Check AWS authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS authentication failed. Please configure AWS CLI."
        exit 1
    fi
    
    # Check Docker daemon
    if ! docker ps &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

validate_aws_permissions() {
    log_info "Validating AWS permissions..."
    
    local required_permissions=(
        "eks:*"
        "ec2:*"
        "iam:*"
        "ecr:*"
        "elasticloadbalancing:*"
        "appmesh:*"
        "xray:*"
        "cloudwatch:*"
    )
    
    # Basic validation - check if user can list resources
    if ! aws eks list-clusters &> /dev/null; then
        log_warning "Cannot validate EKS permissions. Continuing with deployment..."
    fi
    
    if ! aws ecr describe-repositories --max-items 1 &> /dev/null; then
        log_warning "Cannot validate ECR permissions. Continuing with deployment..."
    fi
    
    log_success "AWS permissions validation completed"
}

setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export CLUSTER_NAME="demo-mesh-cluster-${RANDOM_SUFFIX}"
    export MESH_NAME="demo-mesh-${RANDOM_SUFFIX}"
    export NAMESPACE="demo"
    export ECR_REPO_PREFIX="demo-microservices-${RANDOM_SUFFIX}"
    
    # Save configuration for cleanup
    cat > .deployment_config << EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
CLUSTER_NAME=${CLUSTER_NAME}
MESH_NAME=${MESH_NAME}
NAMESPACE=${NAMESPACE}
ECR_REPO_PREFIX=${ECR_REPO_PREFIX}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log_success "Environment configured"
    log_info "Cluster Name: ${CLUSTER_NAME}"
    log_info "Mesh Name: ${MESH_NAME}"
    log_info "Region: ${AWS_REGION}"
}

create_ecr_repositories() {
    log_info "Creating ECR repositories..."
    
    local repos=("frontend" "backend" "database")
    
    for repo in "${repos[@]}"; do
        if aws ecr describe-repositories --repository-names "${ECR_REPO_PREFIX}/${repo}" --region "${AWS_REGION}" &> /dev/null; then
            log_warning "ECR repository ${ECR_REPO_PREFIX}/${repo} already exists"
        else
            aws ecr create-repository \
                --repository-name "${ECR_REPO_PREFIX}/${repo}" \
                --region "${AWS_REGION}" \
                --image-scanning-configuration scanOnPush=true \
                --encryption-configuration encryptionType=AES256
            log_success "Created ECR repository: ${ECR_REPO_PREFIX}/${repo}"
        fi
    done
    
    log_success "ECR repositories ready"
}

create_eks_cluster() {
    log_info "Creating EKS cluster (this may take 15-20 minutes)..."
    
    # Check if cluster already exists
    if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" &> /dev/null; then
        log_warning "EKS cluster ${CLUSTER_NAME} already exists"
    else
        eksctl create cluster \
            --name "${CLUSTER_NAME}" \
            --region "${AWS_REGION}" \
            --version 1.28 \
            --nodegroup-name standard-workers \
            --node-type m5.large \
            --nodes 3 \
            --nodes-min 1 \
            --nodes-max 4 \
            --managed \
            --with-oidc \
            --enable-ssm \
            --vpc-cidr 10.0.0.0/16 \
            --tags "Project=ServiceMeshDemo,Environment=Demo"
        
        log_success "EKS cluster created successfully"
    fi
    
    # Update kubeconfig
    aws eks update-kubeconfig \
        --region "${AWS_REGION}" \
        --name "${CLUSTER_NAME}"
    
    # Verify cluster connectivity
    kubectl cluster-info
    log_success "Kubeconfig updated and cluster is accessible"
}

install_app_mesh_controller() {
    log_info "Installing AWS App Mesh Controller..."
    
    # Add EKS Helm repository
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    
    # Install App Mesh CRDs
    kubectl apply -k \
        "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"
    
    # Create namespace for App Mesh system
    kubectl create namespace appmesh-system --dry-run=client -o yaml | kubectl apply -f -
    
    # Create IAM role for App Mesh controller
    if ! eksctl get iamserviceaccount --cluster="${CLUSTER_NAME}" --namespace=appmesh-system --name=appmesh-controller &> /dev/null; then
        eksctl create iamserviceaccount \
            --cluster="${CLUSTER_NAME}" \
            --namespace=appmesh-system \
            --name=appmesh-controller \
            --attach-policy-arn=arn:aws:iam::aws:policy/AWSCloudMapFullAccess \
            --attach-policy-arn=arn:aws:iam::aws:policy/AWSAppMeshFullAccess \
            --override-existing-serviceaccounts \
            --approve
    fi
    
    # Install App Mesh controller
    if ! helm list -n appmesh-system | grep -q appmesh-controller; then
        helm install appmesh-controller eks/appmesh-controller \
            --namespace appmesh-system \
            --set region="${AWS_REGION}" \
            --set serviceAccount.create=false \
            --set serviceAccount.name=appmesh-controller \
            --wait --timeout=300s
    fi
    
    # Wait for controller to be ready
    kubectl wait --for=condition=available \
        --timeout=300s \
        deployment/appmesh-controller \
        -n appmesh-system
    
    log_success "App Mesh controller installed successfully"
}

setup_service_mesh() {
    log_info "Setting up service mesh..."
    
    # Create application namespace
    kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
    
    # Label namespace for App Mesh injection
    kubectl label namespace "${NAMESPACE}" \
        mesh="${MESH_NAME}" \
        appmesh.k8s.aws/sidecarInjectorWebhook=enabled \
        --overwrite
    
    # Create App Mesh mesh resource
    cat <<EOF | kubectl apply -f -
apiVersion: appmesh.k8s.aws/v1beta2
kind: Mesh
metadata:
  name: ${MESH_NAME}
  namespace: ${NAMESPACE}
spec:
  namespaceSelector:
    matchLabels:
      mesh: ${MESH_NAME}
  egressFilter:
    type: ALLOW_ALL
EOF
    
    # Wait for mesh to be active
    sleep 10
    kubectl wait --for=condition=MeshActive \
        --timeout=300s \
        mesh/"${MESH_NAME}" \
        -n "${NAMESPACE}" || true
    
    log_success "Service mesh created successfully"
}

build_and_push_images() {
    log_info "Building and pushing container images..."
    
    # Get ECR login token
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin \
        "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    # Create temporary directory for application code
    TEMP_DIR=$(mktemp -d)
    
    # Build frontend image
    log_info "Building frontend image..."
    mkdir -p "${TEMP_DIR}/frontend"
    cat > "${TEMP_DIR}/frontend/app.py" << 'EOF'
from flask import Flask, requests
import os
import time
import logging

logging.basicConfig(level=logging.INFO)
app = Flask(__name__)

@app.route('/')
def home():
    try:
        backend_url = os.getenv('BACKEND_URL', 'http://backend:8080')
        response = requests.get(f'{backend_url}/api/data', timeout=10)
        return f'Frontend received: {response.text} (timestamp: {time.time()})'
    except Exception as e:
        app.logger.error(f'Error connecting to backend: {str(e)}')
        return f'Error connecting to backend: {str(e)}'

@app.route('/health')
def health():
    return 'OK'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF
    
    cat > "${TEMP_DIR}/frontend/requirements.txt" << 'EOF'
Flask==2.3.3
requests==2.31.0
gunicorn==21.2.0
EOF
    
    cat > "${TEMP_DIR}/frontend/Dockerfile" << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
EOF
    
    cd "${TEMP_DIR}/frontend"
    docker build -t "${ECR_REPO_PREFIX}/frontend:latest" .
    docker tag "${ECR_REPO_PREFIX}/frontend:latest" \
        "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/frontend:latest"
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/frontend:latest"
    
    # Build backend image
    log_info "Building backend image..."
    mkdir -p "${TEMP_DIR}/backend"
    cat > "${TEMP_DIR}/backend/app.py" << 'EOF'
from flask import Flask, requests
import os
import time
import logging

logging.basicConfig(level=logging.INFO)
app = Flask(__name__)

@app.route('/api/data')
def get_data():
    try:
        db_url = os.getenv('DATABASE_URL', 'http://database:5432')
        response = requests.get(f'{db_url}/query', timeout=10)
        version = os.getenv('VERSION', 'v1')
        return f'Backend {version} data: {response.text} (timestamp: {time.time()})'
    except Exception as e:
        app.logger.error(f'Backend error: {str(e)}')
        return f'Backend error: {str(e)}'

@app.route('/health')
def health():
    return 'OK'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF
    
    cat > "${TEMP_DIR}/backend/requirements.txt" << 'EOF'
Flask==2.3.3
requests==2.31.0
gunicorn==21.2.0
EOF
    
    cat > "${TEMP_DIR}/backend/Dockerfile" << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
EOF
    
    cd "${TEMP_DIR}/backend"
    docker build -t "${ECR_REPO_PREFIX}/backend:latest" .
    docker tag "${ECR_REPO_PREFIX}/backend:latest" \
        "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/backend:latest"
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/backend:latest"
    
    # Build database image
    log_info "Building database image..."
    mkdir -p "${TEMP_DIR}/database"
    cat > "${TEMP_DIR}/database/app.py" << 'EOF'
from flask import Flask
import json
import time
import logging

logging.basicConfig(level=logging.INFO)
app = Flask(__name__)

@app.route('/query')
def query_data():
    data = {
        'records': [
            {'id': 1, 'name': 'Product A', 'price': 29.99},
            {'id': 2, 'name': 'Product B', 'price': 39.99},
            {'id': 3, 'name': 'Product C', 'price': 19.99}
        ],
        'query_time': time.time()
    }
    return json.dumps(data)

@app.route('/health')
def health():
    return 'OK'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5432, debug=False)
EOF
    
    cat > "${TEMP_DIR}/database/requirements.txt" << 'EOF'
Flask==2.3.3
gunicorn==21.2.0
EOF
    
    cat > "${TEMP_DIR}/database/Dockerfile" << 'EOF'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5432
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5432/health || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:5432", "--workers", "2", "app:app"]
EOF
    
    cd "${TEMP_DIR}/database"
    docker build -t "${ECR_REPO_PREFIX}/database:latest" .
    docker tag "${ECR_REPO_PREFIX}/database:latest" \
        "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/database:latest"
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/database:latest"
    
    # Cleanup temporary directory
    rm -rf "${TEMP_DIR}"
    
    log_success "Container images built and pushed successfully"
}

deploy_virtual_nodes() {
    log_info "Deploying virtual nodes..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualNode
metadata:
  name: frontend-virtual-node
  namespace: ${NAMESPACE}
spec:
  awsName: frontend-virtual-node
  podSelector:
    matchLabels:
      app: frontend
  listeners:
    - portMapping:
        port: 8080
        protocol: http
      healthCheck:
        healthyThreshold: 2
        intervalMillis: 5000
        path: /health
        port: 8080
        protocol: http
        timeoutMillis: 2000
        unhealthyThreshold: 2
  backends:
    - virtualService:
        virtualServiceRef:
          name: backend-virtual-service
  serviceDiscovery:
    dns:
      hostname: frontend.${NAMESPACE}.svc.cluster.local
---
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualNode
metadata:
  name: backend-virtual-node
  namespace: ${NAMESPACE}
spec:
  awsName: backend-virtual-node
  podSelector:
    matchLabels:
      app: backend
      version: v1
  listeners:
    - portMapping:
        port: 8080
        protocol: http
      healthCheck:
        healthyThreshold: 2
        intervalMillis: 5000
        path: /health
        port: 8080
        protocol: http
        timeoutMillis: 2000
        unhealthyThreshold: 2
  backends:
    - virtualService:
        virtualServiceRef:
          name: database-virtual-service
  serviceDiscovery:
    dns:
      hostname: backend.${NAMESPACE}.svc.cluster.local
---
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualNode
metadata:
  name: backend-v2-virtual-node
  namespace: ${NAMESPACE}
spec:
  awsName: backend-v2-virtual-node
  podSelector:
    matchLabels:
      app: backend
      version: v2
  listeners:
    - portMapping:
        port: 8080
        protocol: http
      healthCheck:
        healthyThreshold: 2
        intervalMillis: 5000
        path: /health
        port: 8080
        protocol: http
        timeoutMillis: 2000
        unhealthyThreshold: 2
  backends:
    - virtualService:
        virtualServiceRef:
          name: database-virtual-service
  serviceDiscovery:
    dns:
      hostname: backend.${NAMESPACE}.svc.cluster.local
---
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualNode
metadata:
  name: database-virtual-node
  namespace: ${NAMESPACE}
spec:
  awsName: database-virtual-node
  podSelector:
    matchLabels:
      app: database
  listeners:
    - portMapping:
        port: 5432
        protocol: http
      healthCheck:
        healthyThreshold: 2
        intervalMillis: 5000
        path: /health
        port: 5432
        protocol: http
        timeoutMillis: 2000
        unhealthyThreshold: 2
  serviceDiscovery:
    dns:
      hostname: database.${NAMESPACE}.svc.cluster.local
EOF
    
    log_success "Virtual nodes created successfully"
}

deploy_virtual_services() {
    log_info "Deploying virtual services and routers..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualService
metadata:
  name: frontend-virtual-service
  namespace: ${NAMESPACE}
spec:
  awsName: frontend-virtual-service
  provider:
    virtualNode:
      virtualNodeRef:
        name: frontend-virtual-node
---
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualService
metadata:
  name: backend-virtual-service
  namespace: ${NAMESPACE}
spec:
  awsName: backend-virtual-service
  provider:
    virtualRouter:
      virtualRouterRef:
        name: backend-virtual-router
---
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualService
metadata:
  name: database-virtual-service
  namespace: ${NAMESPACE}
spec:
  awsName: database-virtual-service
  provider:
    virtualNode:
      virtualNodeRef:
        name: database-virtual-node
---
apiVersion: appmesh.k8s.aws/v1beta2
kind: VirtualRouter
metadata:
  name: backend-virtual-router
  namespace: ${NAMESPACE}
spec:
  awsName: backend-virtual-router
  listeners:
    - portMapping:
        port: 8080
        protocol: http
  routes:
    - name: backend-route
      httpRoute:
        match:
          prefix: /
        action:
          weightedTargets:
            - virtualNodeRef:
                name: backend-virtual-node
              weight: 90
            - virtualNodeRef:
                name: backend-v2-virtual-node
              weight: 10
        retryPolicy:
          maxRetries: 3
          perRetryTimeout:
            unit: s
            value: 15
          httpRetryEvents:
            - server-error
            - gateway-error
          tcpRetryEvents:
            - connection-error
EOF
    
    log_success "Virtual services and routers created successfully"
}

deploy_microservices() {
    log_info "Deploying microservices..."
    
    # Deploy frontend service
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ${NAMESPACE}
  labels:
    app: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend
        image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/frontend:latest
        ports:
        - containerPort: 8080
        env:
        - name: BACKEND_URL
          value: "http://backend:8080"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: ${NAMESPACE}
spec:
  selector:
    app: frontend
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF
    
    # Deploy backend service v1
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: ${NAMESPACE}
  labels:
    app: backend
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
      version: v1
  template:
    metadata:
      labels:
        app: backend
        version: v1
    spec:
      containers:
      - name: backend
        image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/backend:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          value: "http://database:5432"
        - name: VERSION
          value: "v1"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-v2
  namespace: ${NAMESPACE}
  labels:
    app: backend
    version: v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend
      version: v2
  template:
    metadata:
      labels:
        app: backend
        version: v2
    spec:
      containers:
      - name: backend
        image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/backend:latest
        ports:
        - containerPort: 8080
        env:
        - name: DATABASE_URL
          value: "http://database:5432"
        - name: VERSION
          value: "v2"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: ${NAMESPACE}
spec:
  selector:
    app: backend
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF
    
    # Deploy database service
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database
  namespace: ${NAMESPACE}
  labels:
    app: database
spec:
  replicas: 1
  selector:
    matchLabels:
      app: database
  template:
    metadata:
      labels:
        app: database
    spec:
      containers:
      - name: database
        image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/database:latest
        ports:
        - containerPort: 5432
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /health
            port: 5432
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 5432
          initialDelaySeconds: 15
          periodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: database
  namespace: ${NAMESPACE}
spec:
  selector:
    app: database
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF
    
    log_success "Microservices deployed successfully"
}

install_load_balancer_controller() {
    log_info "Installing AWS Load Balancer Controller..."
    
    # Download IAM policy
    curl -o iam_policy.json \
        https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json
    
    # Create IAM policy
    if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" &> /dev/null; then
        aws iam create-policy \
            --policy-name AWSLoadBalancerControllerIAMPolicy \
            --policy-document file://iam_policy.json
    fi
    
    # Create IAM role for Load Balancer Controller
    if ! eksctl get iamserviceaccount --cluster="${CLUSTER_NAME}" --namespace=kube-system --name=aws-load-balancer-controller &> /dev/null; then
        eksctl create iamserviceaccount \
            --cluster="${CLUSTER_NAME}" \
            --namespace=kube-system \
            --name=aws-load-balancer-controller \
            --role-name "AmazonEKSLoadBalancerControllerRole-${RANDOM_SUFFIX}" \
            --attach-policy-arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" \
            --approve
    fi
    
    # Install AWS Load Balancer Controller
    if ! helm list -n kube-system | grep -q aws-load-balancer-controller; then
        helm install aws-load-balancer-controller \
            eks/aws-load-balancer-controller \
            -n kube-system \
            --set clusterName="${CLUSTER_NAME}" \
            --set serviceAccount.create=false \
            --set serviceAccount.name=aws-load-balancer-controller \
            --wait --timeout=300s
    fi
    
    # Create ingress for frontend service
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
  namespace: ${NAMESPACE}
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 8080
EOF
    
    # Clean up temporary files
    rm -f iam_policy.json
    
    log_success "AWS Load Balancer Controller installed successfully"
}

enable_observability() {
    log_info "Enabling distributed tracing and monitoring..."
    
    # Enable X-Ray tracing for App Mesh
    kubectl patch mesh "${MESH_NAME}" -n "${NAMESPACE}" \
        --type='merge' \
        -p='{"spec":{"meshSpec":{"tracing":{"xray":{}}}}}'
    
    # Create X-Ray daemon DaemonSet
    cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: xray-daemon
  namespace: ${NAMESPACE}
  labels:
    app: xray-daemon
spec:
  selector:
    matchLabels:
      app: xray-daemon
  template:
    metadata:
      labels:
        app: xray-daemon
    spec:
      containers:
      - name: xray-daemon
        image: amazon/aws-xray-daemon:latest
        ports:
        - containerPort: 2000
          protocol: UDP
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
        env:
        - name: AWS_REGION
          value: ${AWS_REGION}
---
apiVersion: v1
kind: Service
metadata:
  name: xray-service
  namespace: ${NAMESPACE}
spec:
  selector:
    app: xray-daemon
  ports:
  - port: 2000
    protocol: UDP
  type: ClusterIP
EOF
    
    # Update virtual nodes to enable access logging
    kubectl patch virtualnode frontend-virtual-node -n "${NAMESPACE}" \
        --type='merge' \
        -p='{"spec":{"logging":{"accessLog":{"file":{"path":"/dev/stdout"}}}}}'
    
    kubectl patch virtualnode backend-virtual-node -n "${NAMESPACE}" \
        --type='merge' \
        -p='{"spec":{"logging":{"accessLog":{"file":{"path":"/dev/stdout"}}}}}'
    
    kubectl patch virtualnode backend-v2-virtual-node -n "${NAMESPACE}" \
        --type='merge' \
        -p='{"spec":{"logging":{"accessLog":{"file":{"path":"/dev/stdout"}}}}}'
    
    kubectl patch virtualnode database-virtual-node -n "${NAMESPACE}" \
        --type='merge' \
        -p='{"spec":{"logging":{"accessLog":{"file":{"path":"/dev/stdout"}}}}}'
    
    log_success "Distributed tracing and monitoring enabled"
}

wait_for_deployment() {
    log_info "Waiting for all pods to be ready..."
    
    # Wait for all deployments to be ready
    kubectl wait --for=condition=available \
        --timeout=600s \
        deployment --all -n "${NAMESPACE}"
    
    # Wait for all pods to be ready with sidecars
    log_info "Waiting for Envoy sidecar injection..."
    sleep 30
    
    # Verify sidecar injection
    local pods_ready=false
    local attempts=0
    local max_attempts=30
    
    while [ "$pods_ready" = false ] && [ $attempts -lt $max_attempts ]; do
        log_info "Checking pod readiness (attempt $((attempts + 1))/${max_attempts})..."
        
        if kubectl get pods -n "${NAMESPACE}" --no-headers | awk '{print $2}' | grep -q "1/2\|0/2"; then
            log_info "Some pods still starting or missing sidecars, waiting..."
            sleep 20
            ((attempts++))
        else
            pods_ready=true
        fi
    done
    
    if [ "$pods_ready" = false ]; then
        log_warning "Timeout waiting for all pods to be ready. Continuing with deployment verification..."
    fi
    
    log_success "Deployment completed"
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Show cluster information
    log_info "Cluster Information:"
    kubectl cluster-info
    
    # Show mesh resources
    log_info "App Mesh Resources:"
    kubectl get mesh,virtualnode,virtualservice,virtualrouter -n "${NAMESPACE}" -o wide
    
    # Show pod status
    log_info "Pod Status:"
    kubectl get pods -n "${NAMESPACE}" -o wide
    
    # Show services
    log_info "Services:"
    kubectl get services -n "${NAMESPACE}"
    
    # Get load balancer URL
    log_info "Getting Application Load Balancer URL..."
    local attempts=0
    local max_attempts=20
    local alb_url=""
    
    while [ -z "$alb_url" ] && [ $attempts -lt $max_attempts ]; do
        alb_url=$(kubectl get ingress frontend-ingress -n "${NAMESPACE}" \
            -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
        
        if [ -z "$alb_url" ]; then
            log_info "Waiting for load balancer to be ready (attempt $((attempts + 1))/${max_attempts})..."
            sleep 30
            ((attempts++))
        fi
    done
    
    if [ -n "$alb_url" ]; then
        log_success "Application URL: http://${alb_url}"
        echo "ALB_URL=${alb_url}" >> .deployment_config
        
        # Test application
        log_info "Testing application connectivity..."
        sleep 60  # Wait for load balancer to be fully ready
        
        if curl -f -s "http://${alb_url}/health" > /dev/null; then
            log_success "Application is responding to health checks"
            
            # Test full application flow
            log_info "Testing full application flow..."
            response=$(curl -s "http://${alb_url}" || echo "Connection failed")
            log_info "Application response: ${response}"
        else
            log_warning "Application health check failed. This may resolve in a few minutes."
        fi
    else
        log_warning "Load balancer URL not available yet. Check ingress status with: kubectl get ingress -n ${NAMESPACE}"
    fi
    
    log_success "Deployment verification completed"
}

main() {
    log_info "Starting EKS Service Mesh with AWS App Mesh deployment..."
    
    # Check if deployment already exists
    if [ -f .deployment_config ]; then
        log_warning "Found existing deployment configuration."
        read -p "Do you want to continue with a fresh deployment? This may create duplicate resources. (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled."
            exit 0
        fi
    fi
    
    check_prerequisites
    validate_aws_permissions
    setup_environment
    create_ecr_repositories
    create_eks_cluster
    install_app_mesh_controller
    setup_service_mesh
    build_and_push_images
    deploy_virtual_nodes
    deploy_virtual_services
    deploy_microservices
    install_load_balancer_controller
    enable_observability
    wait_for_deployment
    verify_deployment
    
    log_success "🎉 EKS Service Mesh with AWS App Mesh deployed successfully!"
    log_info ""
    log_info "Next Steps:"
    log_info "1. Access your application using the Load Balancer URL shown above"
    log_info "2. Monitor traces in AWS X-Ray console"
    log_info "3. View service mesh metrics in CloudWatch"
    log_info "4. Experiment with traffic routing and canary deployments"
    log_info ""
    log_info "To clean up resources, run: ./destroy.sh"
    log_info "Configuration saved in: .deployment_config"
}

# Run main function
main "$@"