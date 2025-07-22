#!/bin/bash

# Real-Time Streaming Analytics with EMR on EKS and Apache Flink - Deployment Script
# This script deploys a complete streaming analytics platform using EMR on EKS with Flink

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
    exit 1
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check kubectl
    if ! command_exists kubectl; then
        error_exit "kubectl is not installed. Please install kubectl."
    fi
    
    # Check eksctl
    if ! command_exists eksctl; then
        error_exit "eksctl is not installed. Please install eksctl."
    fi
    
    # Check Helm
    if ! command_exists helm; then
        error_exit "Helm is not installed. Please install Helm v3."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error_exit "AWS credentials not configured. Please run 'aws configure'."
    fi
    
    log_success "All prerequisites met"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-west-2"
        log_warning "AWS region not configured, using default: us-west-2"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export CLUSTER_NAME="emr-flink-analytics"
    export EMR_NAMESPACE="emr-flink"
    
    # Generate unique suffix for global resources
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set derived variables
    export BUCKET_NAME="emr-flink-analytics-${RANDOM_SUFFIX}"
    export STREAM_NAME_TRADING="trading-events-${RANDOM_SUFFIX}"
    export STREAM_NAME_MARKET="market-data-${RANDOM_SUFFIX}"
    
    log_success "Environment configured:"
    log_info "  AWS Region: $AWS_REGION"
    log_info "  AWS Account: $AWS_ACCOUNT_ID"
    log_info "  Cluster Name: $CLUSTER_NAME"
    log_info "  S3 Bucket: $BUCKET_NAME"
    
    # Save environment to file for cleanup
    cat > .env << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
CLUSTER_NAME=$CLUSTER_NAME
EMR_NAMESPACE=$EMR_NAMESPACE
RANDOM_SUFFIX=$RANDOM_SUFFIX
BUCKET_NAME=$BUCKET_NAME
STREAM_NAME_TRADING=$STREAM_NAME_TRADING
STREAM_NAME_MARKET=$STREAM_NAME_MARKET
EOF
}

# Create EKS cluster
create_eks_cluster() {
    log_info "Creating EKS cluster (this takes 15-20 minutes)..."
    
    # Check if cluster already exists
    if eksctl get cluster --name $CLUSTER_NAME --region $AWS_REGION >/dev/null 2>&1; then
        log_warning "EKS cluster $CLUSTER_NAME already exists, skipping creation"
        return 0
    fi
    
    cat > cluster-config.yaml << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "1.28"

iam:
  withOIDC: true

managedNodeGroups:
  - name: emr-flink-workers
    instanceType: m5.xlarge
    minSize: 2
    maxSize: 10
    desiredCapacity: 4
    volumeSize: 100
    privateNetworking: true
    iam:
      attachPolicyARNs:
        - arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        - arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        - arn:aws:iam::aws:policy/AmazonS3FullAccess
      withAddonPolicies:
        ebs: true
        cloudWatch: true
    tags:
      Environment: analytics
      Project: flink-streaming

addons:
  - name: aws-ebs-csi-driver
    version: latest
  - name: vpc-cni
    version: latest
EOF
    
    eksctl create cluster -f cluster-config.yaml
    log_success "EKS cluster created successfully"
}

# Setup IAM roles
setup_iam_roles() {
    log_info "Setting up IAM roles for EMR on EKS..."
    
    # Create EMR on EKS service role
    cat > emr-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "emr-containers.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    if ! aws iam get-role --role-name EMRContainersServiceRole >/dev/null 2>&1; then
        aws iam create-role \
            --role-name EMRContainersServiceRole \
            --assume-role-policy-document file://emr-trust-policy.json
        
        aws iam attach-role-policy \
            --role-name EMRContainersServiceRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonEMRContainersServiceRolePolicy
        
        log_success "EMR Containers service role created"
    else
        log_warning "EMR Containers service role already exists"
    fi
    
    # Create job execution role
    OIDC_ISSUER=$(aws eks describe-cluster \
        --name ${CLUSTER_NAME} \
        --query "cluster.identity.oidc.issuer" \
        --output text | sed 's|https://||')
    
    cat > job-execution-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringLike": {
          "${OIDC_ISSUER}:sub": "system:serviceaccount:${EMR_NAMESPACE}:*"
        }
      }
    }
  ]
}
EOF
    
    if ! aws iam get-role --role-name EMRFlinkJobExecutionRole >/dev/null 2>&1; then
        aws iam create-role \
            --role-name EMRFlinkJobExecutionRole \
            --assume-role-policy-document file://job-execution-trust-policy.json
        
        # Attach necessary policies
        aws iam attach-role-policy \
            --role-name EMRFlinkJobExecutionRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
        
        aws iam attach-role-policy \
            --role-name EMRFlinkJobExecutionRole \
            --policy-arn arn:aws:iam::aws:policy/AmazonKinesisFullAccess
        
        aws iam attach-role-policy \
            --role-name EMRFlinkJobExecutionRole \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess
        
        log_success "EMR Flink job execution role created"
    else
        log_warning "EMR Flink job execution role already exists"
    fi
}

# Setup EMR virtual cluster
setup_emr_cluster() {
    log_info "Setting up EMR virtual cluster and Flink operator..."
    
    # Create namespace and service account
    kubectl create namespace ${EMR_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    kubectl create serviceaccount emr-containers-sa-flink-operator \
        -n ${EMR_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Annotate service account with IAM role
    kubectl annotate serviceaccount emr-containers-sa-flink-operator \
        -n ${EMR_NAMESPACE} \
        eks.amazonaws.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/EMRFlinkJobExecutionRole \
        --overwrite
    
    # Enable EMR on EKS namespace
    eksctl create iamidentitymapping \
        --cluster ${CLUSTER_NAME} \
        --namespace ${EMR_NAMESPACE} \
        --service-name emr-containers || true
    
    # Create EMR virtual cluster
    VIRTUAL_CLUSTER_ID=$(aws emr-containers list-virtual-clusters \
        --query "virtualClusters[?name=='flink-analytics-cluster' && state=='RUNNING'].id" \
        --output text)
    
    if [ -z "$VIRTUAL_CLUSTER_ID" ]; then
        VIRTUAL_CLUSTER_ID=$(aws emr-containers create-virtual-cluster \
            --name "flink-analytics-cluster" \
            --container-provider '{
              "id": "'${CLUSTER_NAME}'",
              "type": "EKS",
              "info": {
                "eksInfo": {
                  "namespace": "'${EMR_NAMESPACE}'"
                }
              }
            }' \
            --query 'id' --output text)
        
        log_success "Virtual Cluster created with ID: ${VIRTUAL_CLUSTER_ID}"
    else
        log_warning "Virtual cluster already exists with ID: ${VIRTUAL_CLUSTER_ID}"
    fi
    
    # Save virtual cluster ID
    echo "VIRTUAL_CLUSTER_ID=$VIRTUAL_CLUSTER_ID" >> .env
    
    # Install Flink Kubernetes operator using Helm
    helm repo add flink-operator-repo \
        https://downloads.apache.org/flink/flink-kubernetes-operator-1.7.0/ || true
    helm repo update
    
    if ! helm list -n ${EMR_NAMESPACE} | grep -q flink-kubernetes-operator; then
        helm install flink-kubernetes-operator \
            flink-operator-repo/flink-kubernetes-operator \
            --namespace ${EMR_NAMESPACE} \
            --set image.repository=public.ecr.aws/emr-on-eks/flink/flink-kubernetes-operator \
            --set image.tag=1.7.0-emr-7.0.0
        
        log_success "Flink operator installed"
    else
        log_warning "Flink operator already installed"
    fi
}

# Create supporting infrastructure
create_supporting_infrastructure() {
    log_info "Creating supporting infrastructure..."
    
    # Create S3 bucket
    if ! aws s3 ls s3://${BUCKET_NAME} >/dev/null 2>&1; then
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION}
        log_success "S3 bucket created: ${BUCKET_NAME}"
    else
        log_warning "S3 bucket already exists: ${BUCKET_NAME}"
    fi
    
    # Configure S3 bucket lifecycle policy
    cat > lifecycle-policy.json << EOF
{
  "Rules": [
    {
      "ID": "FlinkCheckpointLifecycle",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "checkpoints/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ]
    }
  ]
}
EOF
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket ${BUCKET_NAME} \
        --lifecycle-configuration file://lifecycle-policy.json
    
    # Create Kinesis data streams
    if ! aws kinesis describe-stream --stream-name ${STREAM_NAME_TRADING} >/dev/null 2>&1; then
        aws kinesis create-stream \
            --stream-name ${STREAM_NAME_TRADING} \
            --shard-count 4
        log_success "Kinesis stream created: ${STREAM_NAME_TRADING}"
    else
        log_warning "Kinesis stream already exists: ${STREAM_NAME_TRADING}"
    fi
    
    if ! aws kinesis describe-stream --stream-name ${STREAM_NAME_MARKET} >/dev/null 2>&1; then
        aws kinesis create-stream \
            --stream-name ${STREAM_NAME_MARKET} \
            --shard-count 2
        log_success "Kinesis stream created: ${STREAM_NAME_MARKET}"
    else
        log_warning "Kinesis stream already exists: ${STREAM_NAME_MARKET}"
    fi
    
    # Wait for streams to become active
    log_info "Waiting for Kinesis streams to become active..."
    aws kinesis wait stream-exists --stream-name ${STREAM_NAME_TRADING}
    aws kinesis wait stream-exists --stream-name ${STREAM_NAME_MARKET}
    log_success "Kinesis streams are active"
}

# Deploy Flink applications
deploy_flink_applications() {
    log_info "Deploying Flink applications..."
    
    # Create fraud detection job
    cat > fraud-detection-job.yaml << EOF
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: fraud-detection
  namespace: ${EMR_NAMESPACE}
spec:
  image: public.ecr.aws/emr-on-eks/flink/flink:1.17.1-emr-7.0.0
  flinkVersion: v1_17
  flinkConfiguration:
    taskmanager.numberOfTaskSlots: "4"
    state.backend: rocksdb
    state.checkpoints.dir: s3://${BUCKET_NAME}/checkpoints/fraud-detection
    state.checkpoint-storage: filesystem
    execution.checkpointing.interval: 60s
    execution.checkpointing.mode: EXACTLY_ONCE
    restart-strategy: exponential-delay
    restart-strategy.exponential-delay.initial-backoff: 10s
    restart-strategy.exponential-delay.max-backoff: 2min
    restart-strategy.exponential-delay.backoff-multiplier: 2.0
    restart-strategy.exponential-delay.reset-backoff-threshold: 10min
    high-availability: org.apache.flink.kubernetes.highavailability.KubernetesHaServicesFactory
    high-availability.storageDir: s3://${BUCKET_NAME}/ha/fraud-detection
  serviceAccount: emr-containers-sa-flink-operator
  jobManager:
    resource:
      memory: 2048m
      cpu: 1
    replicas: 1
  taskManager:
    resource:
      memory: 4096m
      cpu: 2
    replicas: 3
  job:
    jarURI: local:///opt/flink/examples/streaming/StateMachineExample.jar
    parallelism: 6
    upgradeMode: stateless
    args:
      - "--input"
      - "kinesis"
      - "--aws.region"
      - "${AWS_REGION}"
      - "--kinesis.stream.name"
      - "${STREAM_NAME_TRADING}"
      - "--output"
      - "s3://${BUCKET_NAME}/fraud-alerts/"
  podTemplate:
    spec:
      containers:
        - name: flink-main-container
          env:
            - name: AWS_REGION
              value: ${AWS_REGION}
            - name: ENABLE_NATIVE_S3_FILESYSTEM
              value: "true"
          volumeMounts:
            - name: flink-logs
              mountPath: /opt/flink/log
      volumes:
        - name: flink-logs
          emptyDir: {}
EOF
    
    kubectl apply -f fraud-detection-job.yaml
    log_success "Fraud detection Flink job deployed"
    
    # Create risk analytics job
    cat > risk-analytics-job.yaml << EOF
apiVersion: flink.apache.org/v1beta1
kind: FlinkDeployment
metadata:
  name: risk-analytics
  namespace: ${EMR_NAMESPACE}
spec:
  image: public.ecr.aws/emr-on-eks/flink/flink:1.17.1-emr-7.0.0
  flinkVersion: v1_17
  flinkConfiguration:
    taskmanager.numberOfTaskSlots: "2"
    state.backend: rocksdb
    state.checkpoints.dir: s3://${BUCKET_NAME}/checkpoints/risk-analytics
    state.checkpoint-storage: filesystem
    execution.checkpointing.interval: 30s
    execution.checkpointing.mode: EXACTLY_ONCE
    restart-strategy: exponential-delay
    high-availability: org.apache.flink.kubernetes.highavailability.KubernetesHaServicesFactory
    high-availability.storageDir: s3://${BUCKET_NAME}/ha/risk-analytics
    metrics.reporter.prom.class: org.apache.flink.metrics.prometheus.PrometheusReporter
    metrics.reporter.prom.host: localhost
    metrics.reporter.prom.port: 9249
  serviceAccount: emr-containers-sa-flink-operator
  jobManager:
    resource:
      memory: 1536m
      cpu: 1
    replicas: 1
  taskManager:
    resource:
      memory: 2048m
      cpu: 1
    replicas: 2
  job:
    jarURI: local:///opt/flink/examples/streaming/WindowJoin.jar
    parallelism: 4
    upgradeMode: stateless
    args:
      - "--input"
      - "kinesis"
      - "--aws.region"
      - "${AWS_REGION}"
      - "--kinesis.stream.name"
      - "${STREAM_NAME_MARKET}"
  podTemplate:
    spec:
      containers:
        - name: flink-main-container
          env:
            - name: AWS_REGION
              value: ${AWS_REGION}
            - name: ENABLE_NATIVE_S3_FILESYSTEM
              value: "true"
          ports:
            - name: metrics
              containerPort: 9249
              protocol: TCP
EOF
    
    kubectl apply -f risk-analytics-job.yaml
    log_success "Risk analytics Flink job deployed"
}

# Setup monitoring
setup_monitoring() {
    log_info "Setting up monitoring with Prometheus and Grafana..."
    
    # Add Prometheus community Helm repository
    helm repo add prometheus-community \
        https://prometheus-community.github.io/helm-charts || true
    helm repo add grafana https://grafana.github.io/helm-charts || true
    helm repo update
    
    # Install Prometheus
    if ! helm list -n monitoring | grep -q prometheus; then
        helm install prometheus prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --create-namespace \
            --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
            --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false
        
        log_success "Prometheus installed"
    else
        log_warning "Prometheus already installed"
    fi
    
    # Create service monitor for Flink metrics
    cat > flink-service-monitor.yaml << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: flink-metrics
  namespace: monitoring
  labels:
    app: flink
spec:
  selector:
    matchLabels:
      app: flink
  namespaceSelector:
    matchNames:
      - ${EMR_NAMESPACE}
  endpoints:
    - port: metrics
      interval: 15s
      path: /metrics
EOF
    
    kubectl apply -f flink-service-monitor.yaml
    log_success "Flink service monitor configured"
}

# Deploy data generator
deploy_data_generator() {
    log_info "Deploying data generator for testing..."
    
    cat > data-generator.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: trading-data-generator
  namespace: ${EMR_NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: data-generator
  template:
    metadata:
      labels:
        app: data-generator
    spec:
      containers:
      - name: generator
        image: amazon/aws-cli:latest
        command: ["/bin/bash"]
        args:
          - -c
          - |
            while true; do
              TIMESTAMP=\$(date +%s)
              USER_ID=\$((RANDOM % 10000))
              AMOUNT=\$((RANDOM % 10000))
              TRANSACTION='{"timestamp":'"\$TIMESTAMP"',"user_id":'"\$USER_ID"',"amount":'"\$AMOUNT"',"type":"trade"}'
              
              aws kinesis put-record \
                --stream-name ${STREAM_NAME_TRADING} \
                --partition-key \$USER_ID \
                --data "\$TRANSACTION" \
                --region ${AWS_REGION}
              
              echo "Sent: \$TRANSACTION"
              sleep 1
            done
        env:
        - name: AWS_DEFAULT_REGION
          value: ${AWS_REGION}
EOF
    
    kubectl apply -f data-generator.yaml
    log_success "Data generator deployed"
}

# Wait for deployments
wait_for_deployments() {
    log_info "Waiting for Flink deployments to be ready..."
    
    # Wait for Flink operator to be ready
    kubectl wait --for=condition=available deployment/flink-kubernetes-operator \
        -n ${EMR_NAMESPACE} --timeout=300s
    
    # Wait for Flink deployments
    kubectl wait --for=condition=Ready flinkdeployment/fraud-detection \
        -n ${EMR_NAMESPACE} --timeout=600s || true
    kubectl wait --for=condition=Ready flinkdeployment/risk-analytics \
        -n ${EMR_NAMESPACE} --timeout=600s || true
    
    log_success "Deployments are ready"
}

# Display deployment information
display_info() {
    log_success "Deployment completed successfully!"
    echo
    log_info "Deployment Summary:"
    log_info "  EKS Cluster: $CLUSTER_NAME"
    log_info "  EMR Namespace: $EMR_NAMESPACE"
    log_info "  S3 Bucket: $BUCKET_NAME"
    log_info "  Trading Stream: $STREAM_NAME_TRADING"
    log_info "  Market Stream: $STREAM_NAME_MARKET"
    echo
    log_info "Next Steps:"
    log_info "  1. Check Flink jobs: kubectl get flinkdeployments -n $EMR_NAMESPACE"
    log_info "  2. Access Flink UI: kubectl port-forward -n $EMR_NAMESPACE service/fraud-detection-rest 8081:8081"
    log_info "  3. Access Grafana: kubectl port-forward -n monitoring service/prometheus-grafana 3000:80"
    log_info "  4. Monitor logs: kubectl logs -n $EMR_NAMESPACE -l app=fraud-detection -f"
    echo
    log_info "To clean up resources, run: ./destroy.sh"
}

# Main deployment function
main() {
    log_info "Starting EMR on EKS with Flink deployment..."
    
    check_prerequisites
    setup_environment
    create_eks_cluster
    setup_iam_roles
    setup_emr_cluster
    create_supporting_infrastructure
    deploy_flink_applications
    setup_monitoring
    deploy_data_generator
    wait_for_deployments
    display_info
    
    log_success "Deployment script completed successfully!"
}

# Trap errors and cleanup
trap 'log_error "Deployment failed. Check logs and run destroy.sh to clean up."; exit 1' ERR

# Run main function
main "$@"