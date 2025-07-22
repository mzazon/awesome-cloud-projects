#!/bin/bash

# Comprehensive Container Observability Performance Monitoring - Deploy Script
# This script deploys the complete observability infrastructure for EKS and ECS

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
RESOURCE_STATE_FILE="${SCRIPT_DIR}/deployed_resources.json"

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
    log "${RED}Deployment failed. Check ${LOG_FILE} for details.${NC}"
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

# Initialize state tracking
init_state_tracking() {
    echo '{"resources": [], "start_time": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "status": "in_progress"}' > "${RESOURCE_STATE_FILE}"
}

# Add resource to state
add_resource_to_state() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_id="$3"
    
    if [[ -f "${RESOURCE_STATE_FILE}" ]]; then
        local temp_file=$(mktemp)
        jq --arg type "$resource_type" --arg name "$resource_name" --arg id "$resource_id" \
           '.resources += [{"type": $type, "name": $name, "id": $id, "timestamp": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}]' \
           "${RESOURCE_STATE_FILE}" > "$temp_file" && mv "$temp_file" "${RESOURCE_STATE_FILE}"
    fi
}

# Update deployment status
update_deployment_status() {
    local status="$1"
    local temp_file=$(mktemp)
    jq --arg status "$status" \
       '.status = $status | .end_time = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
       "${RESOURCE_STATE_FILE}" > "$temp_file" && mv "$temp_file" "${RESOURCE_STATE_FILE}"
}

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check required tools
    local required_tools=("aws" "kubectl" "eksctl" "helm" "jq" "curl" "zip")
    for tool in "${required_tools[@]}"; do
        if ! command_exists "$tool"; then
            handle_error "Required tool '$tool' is not installed or not in PATH"
        fi
    done
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        handle_error "AWS CLI is not configured. Please run 'aws configure'"
    fi
    
    # Check minimum versions
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local kubectl_version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3 | cut -d'v' -f2)
    local helm_version=$(helm version --short | cut -d' ' -f1 | cut -d'v' -f2)
    
    log_info "Tool versions:"
    log_info "  AWS CLI: $aws_version"
    log_info "  kubectl: $kubectl_version"
    log_info "  Helm: $helm_version"
    
    # Check AWS permissions
    log_info "Checking AWS permissions..."
    if ! aws iam get-user >/dev/null 2>&1 && ! aws sts get-caller-identity >/dev/null 2>&1; then
        handle_error "Insufficient AWS permissions"
    fi
    
    log_success "Prerequisites check completed"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No AWS region configured, using default: us-east-1"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifier
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export EKS_CLUSTER_NAME="observability-eks-${RANDOM_SUFFIX}"
    export ECS_CLUSTER_NAME="observability-ecs-${RANDOM_SUFFIX}"
    export MONITORING_NAMESPACE="monitoring"
    export OPENSEARCH_DOMAIN="container-logs-${RANDOM_SUFFIX}"
    
    log_info "Environment variables set:"
    log_info "  AWS_REGION: ${AWS_REGION}"
    log_info "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log_info "  EKS_CLUSTER_NAME: ${EKS_CLUSTER_NAME}"
    log_info "  ECS_CLUSTER_NAME: ${ECS_CLUSTER_NAME}"
    log_info "  OPENSEARCH_DOMAIN: ${OPENSEARCH_DOMAIN}"
    
    # Save environment variables for cleanup script
    cat > "${SCRIPT_DIR}/deployment_vars.env" << EOF
export AWS_REGION="${AWS_REGION}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}"
export RANDOM_SUFFIX="${RANDOM_SUFFIX}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME}"
export ECS_CLUSTER_NAME="${ECS_CLUSTER_NAME}"
export MONITORING_NAMESPACE="${MONITORING_NAMESPACE}"
export OPENSEARCH_DOMAIN="${OPENSEARCH_DOMAIN}"
EOF
    
    log_success "Environment setup completed"
}

# Create foundational resources
create_foundational_resources() {
    log_info "Creating foundational resources..."
    
    # Create CloudWatch log groups
    local log_groups=(
        "/aws/eks/${EKS_CLUSTER_NAME}/application"
        "/aws/ecs/${ECS_CLUSTER_NAME}/application"
        "/aws/containerinsights/${EKS_CLUSTER_NAME}/application"
    )
    
    for log_group in "${log_groups[@]}"; do
        if ! aws logs describe-log-groups --log-group-name-prefix "$log_group" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group"; then
            aws logs create-log-group \
                --log-group-name "$log_group" \
                --retention-in-days 30 || handle_error "Failed to create log group: $log_group"
            add_resource_to_state "log_group" "$log_group" "$log_group"
            log_success "Created log group: $log_group"
        else
            log_info "Log group already exists: $log_group"
        fi
    done
    
    # Create SNS topic for alerts
    local sns_topic="container-observability-alerts"
    if ! aws sns get-topic-attributes --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${sns_topic}" >/dev/null 2>&1; then
        aws sns create-topic --name "$sns_topic" || handle_error "Failed to create SNS topic"
        add_resource_to_state "sns_topic" "$sns_topic" "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${sns_topic}"
        log_success "Created SNS topic: $sns_topic"
    else
        log_info "SNS topic already exists: $sns_topic"
    fi
    
    export SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${sns_topic}"
    
    log_success "Foundational resources created"
}

# Create EKS cluster
create_eks_cluster() {
    log_info "Creating EKS cluster with enhanced observability..."
    
    # Check if cluster already exists
    if aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" >/dev/null 2>&1; then
        log_info "EKS cluster already exists: ${EKS_CLUSTER_NAME}"
        return 0
    fi
    
    # Create EKS cluster configuration
    cat > "${SCRIPT_DIR}/eks-observability-config.yaml" << EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${EKS_CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "1.28"

cloudWatch:
  clusterLogging:
    enable:
      - api
      - audit
      - authenticator
      - controllerManager
      - scheduler
    logRetentionInDays: 30

managedNodeGroups:
  - name: observability-nodes
    instanceType: t3.large
    minSize: 3
    maxSize: 6
    desiredCapacity: 3
    volumeSize: 50
    privateNetworking: true
    labels:
      role: observability
    tags:
      Environment: observability
      Monitoring: enabled
    iam:
      withAddonPolicies:
        autoScaler: true
        cloudWatch: true
        xray: true

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
        name: cloudwatch-agent
        namespace: amazon-cloudwatch
      wellKnownPolicies:
        cloudWatch: true
    - metadata:
        name: fluent-bit
        namespace: amazon-cloudwatch
      wellKnownPolicies:
        cloudWatch: true
    - metadata:
        name: aws-for-fluent-bit
        namespace: amazon-cloudwatch
      wellKnownPolicies:
        cloudWatch: true
EOF
    
    # Create the EKS cluster
    log_info "Creating EKS cluster (this may take 15-20 minutes)..."
    eksctl create cluster -f "${SCRIPT_DIR}/eks-observability-config.yaml" || handle_error "Failed to create EKS cluster"
    
    add_resource_to_state "eks_cluster" "${EKS_CLUSTER_NAME}" "${EKS_CLUSTER_NAME}"
    log_success "EKS cluster created: ${EKS_CLUSTER_NAME}"
}

# Deploy Container Insights
deploy_container_insights() {
    log_info "Deploying Container Insights..."
    
    # Download and configure Container Insights
    curl -O https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml || handle_error "Failed to download Container Insights manifest"
    
    # Replace placeholders
    sed -i.bak "s/{{cluster_name}}/${EKS_CLUSTER_NAME}/g" cwagent-fluent-bit-quickstart.yaml
    sed -i.bak "s/{{region_name}}/${AWS_REGION}/g" cwagent-fluent-bit-quickstart.yaml
    
    # Apply Container Insights
    kubectl apply -f cwagent-fluent-bit-quickstart.yaml || handle_error "Failed to apply Container Insights"
    
    # Wait for pods to be ready
    kubectl wait --for=condition=Ready pods --all -n amazon-cloudwatch --timeout=300s || handle_error "Container Insights pods not ready"
    
    log_success "Container Insights deployed"
}

# Install monitoring stack
install_monitoring_stack() {
    log_info "Installing Prometheus and Grafana monitoring stack..."
    
    # Add Helm repositories
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo add grafana https://grafana.github.io/helm-charts
    helm repo update
    
    # Create monitoring namespace
    kubectl create namespace ${MONITORING_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Prometheus values file
    cat > "${SCRIPT_DIR}/prometheus-values.yaml" << EOF
server:
  global:
    scrape_interval: 15s
    evaluation_interval: 15s
  persistentVolume:
    enabled: true
    size: 50Gi
  retention: "30d"
  
alertmanager:
  enabled: true
  persistentVolume:
    enabled: true
    size: 10Gi
    
nodeExporter:
  enabled: true
  
kubeStateMetrics:
  enabled: true
EOF
    
    # Install Prometheus
    helm upgrade --install prometheus prometheus-community/prometheus \
        --namespace ${MONITORING_NAMESPACE} \
        --values "${SCRIPT_DIR}/prometheus-values.yaml" \
        --wait || handle_error "Failed to install Prometheus"
    
    # Create Grafana values file
    cat > "${SCRIPT_DIR}/grafana-values.yaml" << EOF
adminPassword: "observability123!"

persistence:
  enabled: true
  size: 10Gi
  
service:
  type: LoadBalancer
  
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
    - name: Prometheus
      type: prometheus
      url: http://prometheus-server:80
      access: proxy
      isDefault: true
    - name: CloudWatch
      type: cloudwatch
      jsonData:
        authType: arn
        defaultRegion: ${AWS_REGION}
      secureJsonData:
        accessKey: ''
        secretKey: ''
EOF
    
    # Install Grafana
    helm upgrade --install grafana grafana/grafana \
        --namespace ${MONITORING_NAMESPACE} \
        --values "${SCRIPT_DIR}/grafana-values.yaml" \
        --wait || handle_error "Failed to install Grafana"
    
    log_success "Monitoring stack installed"
}

# Deploy ADOT collector
deploy_adot_collector() {
    log_info "Deploying AWS Distro for OpenTelemetry (ADOT) collector..."
    
    # Install ADOT operator
    kubectl apply -f https://github.com/aws-observability/aws-otel-operator/releases/latest/download/opentelemetry-operator.yaml || handle_error "Failed to install ADOT operator"
    
    # Wait for operator to be ready
    kubectl wait --for=condition=Available deployment/opentelemetry-operator-controller-manager -n opentelemetry-operator-system --timeout=300s || handle_error "ADOT operator not ready"
    
    # Create service account for ADOT collector
    eksctl create iamserviceaccount \
        --cluster=${EKS_CLUSTER_NAME} \
        --namespace=${MONITORING_NAMESPACE} \
        --name=adot-collector \
        --attach-policy-arn=arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
        --attach-policy-arn=arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess \
        --override-existing-serviceaccounts \
        --approve || handle_error "Failed to create ADOT service account"
    
    # Create ADOT collector configuration
    cat > "${SCRIPT_DIR}/adot-collector-config.yaml" << EOF
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: adot-container-collector
  namespace: ${MONITORING_NAMESPACE}
spec:
  mode: daemonset
  serviceAccount: adot-collector
  config: |
    receivers:
      awscontainerinsightreceiver:
        collection_interval: 60s
        container_orchestrator: eks
        add_service_as_attribute: true
        prefer_full_pod_name: false
        add_full_pod_name_metric_label: false
    
    processors:
      batch:
        timeout: 60s
      
      resourcedetection:
        detectors: [env, eks]
        timeout: 2s
        override: false
    
    exporters:
      awscloudwatchmetrics:
        region: ${AWS_REGION}
        namespace: AWS/ContainerInsights/Enhanced
        dimension_rollup_option: NoDimensionRollup
      
      awsxray:
        region: ${AWS_REGION}
    
    service:
      pipelines:
        metrics:
          receivers: [awscontainerinsightreceiver]
          processors: [resourcedetection, batch]
          exporters: [awscloudwatchmetrics]
        
        traces:
          receivers: [awsxray]
          processors: [resourcedetection, batch]
          exporters: [awsxray]
EOF
    
    # Deploy ADOT collector
    kubectl apply -f "${SCRIPT_DIR}/adot-collector-config.yaml" || handle_error "Failed to deploy ADOT collector"
    
    log_success "ADOT collector deployed"
}

# Create ECS cluster
create_ecs_cluster() {
    log_info "Creating ECS cluster with enhanced monitoring..."
    
    # Check if cluster already exists
    if aws ecs describe-clusters --clusters "${ECS_CLUSTER_NAME}" --query 'clusters[0].clusterName' --output text 2>/dev/null | grep -q "${ECS_CLUSTER_NAME}"; then
        log_info "ECS cluster already exists: ${ECS_CLUSTER_NAME}"
        return 0
    fi
    
    # Create ECS cluster
    aws ecs create-cluster \
        --cluster-name ${ECS_CLUSTER_NAME} \
        --capacity-providers EC2 FARGATE \
        --default-capacity-provider-strategy \
        capacityProvider=FARGATE,weight=1 \
        --settings name=containerInsights,value=enabled \
        --tags key=Environment,value=observability key=Monitoring,value=enabled || handle_error "Failed to create ECS cluster"
    
    add_resource_to_state "ecs_cluster" "${ECS_CLUSTER_NAME}" "${ECS_CLUSTER_NAME}"
    log_success "ECS cluster created: ${ECS_CLUSTER_NAME}"
}

# Create ECS task execution role
create_ecs_task_role() {
    log_info "Creating ECS task execution role..."
    
    local role_name="ecsTaskExecutionRole-${RANDOM_SUFFIX}"
    
    # Check if role already exists
    if aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
        log_info "ECS task execution role already exists: $role_name"
        export ECS_TASK_EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_name}"
        return 0
    fi
    
    # Create assume role policy
    cat > "${SCRIPT_DIR}/ecs-task-execution-role.json" << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document file://"${SCRIPT_DIR}/ecs-task-execution-role.json" || handle_error "Failed to create ECS task execution role"
    
    # Attach policies
    local policies=(
        "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
        "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
        "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
    )
    
    for policy in "${policies[@]}"; do
        aws iam attach-role-policy \
            --role-name "$role_name" \
            --policy-arn "$policy" || handle_error "Failed to attach policy: $policy"
    done
    
    export ECS_TASK_EXECUTION_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${role_name}"
    add_resource_to_state "iam_role" "$role_name" "$ECS_TASK_EXECUTION_ROLE_ARN"
    
    log_success "ECS task execution role created: $role_name"
}

# Deploy sample applications
deploy_sample_applications() {
    log_info "Deploying sample applications with observability..."
    
    # Deploy EKS sample application
    cat > "${SCRIPT_DIR}/eks-sample-app.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: observability-demo-app
  namespace: default
  labels:
    app: observability-demo
spec:
  replicas: 3
  selector:
    matchLabels:
      app: observability-demo
  template:
    metadata:
      labels:
        app: observability-demo
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: app
        image: nginx:1.21-alpine
        ports:
        - containerPort: 80
        - containerPort: 8080
          name: metrics
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
        env:
        - name: AWS_XRAY_TRACING_NAME
          value: "observability-demo"
        - name: AWS_XRAY_DAEMON_ADDRESS
          value: "xray-daemon:2000"
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
      - name: xray-sidecar
        image: amazon/aws-xray-daemon:latest
        command:
        - /xray
        - -o
        - -b
        - 0.0.0.0:2000
        ports:
        - containerPort: 2000
          protocol: UDP
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: observability-demo-service
  labels:
    app: observability-demo
spec:
  selector:
    app: observability-demo
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: metrics
    port: 8080
    targetPort: 8080
  type: LoadBalancer
EOF
    
    kubectl apply -f "${SCRIPT_DIR}/eks-sample-app.yaml" || handle_error "Failed to deploy EKS sample application"
    
    # Deploy ECS sample application
    cat > "${SCRIPT_DIR}/ecs-task-definition.json" << EOF
{
    "family": "observability-demo-task",
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "512",
    "memory": "1024",
    "executionRoleArn": "${ECS_TASK_EXECUTION_ROLE_ARN}",
    "taskRoleArn": "${ECS_TASK_EXECUTION_ROLE_ARN}",
    "containerDefinitions": [
        {
            "name": "app",
            "image": "nginx:latest",
            "essential": true,
            "portMappings": [
                {
                    "containerPort": 80,
                    "protocol": "tcp"
                }
            ],
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/aws/ecs/${ECS_CLUSTER_NAME}/application",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "app"
                }
            },
            "environment": [
                {
                    "name": "AWS_XRAY_TRACING_NAME",
                    "value": "ecs-observability-demo"
                }
            ]
        },
        {
            "name": "aws-otel-collector",
            "image": "public.ecr.aws/aws-observability/aws-otel-collector:latest",
            "essential": false,
            "logConfiguration": {
                "logDriver": "awslogs",
                "options": {
                    "awslogs-group": "/aws/ecs/${ECS_CLUSTER_NAME}/application",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "otel-collector"
                }
            },
            "environment": [
                {
                    "name": "AWS_REGION",
                    "value": "${AWS_REGION}"
                }
            ]
        }
    ]
}
EOF
    
    # Register ECS task definition
    aws ecs register-task-definition \
        --cli-input-json file://"${SCRIPT_DIR}/ecs-task-definition.json" || handle_error "Failed to register ECS task definition"
    
    # Get network configuration
    local default_vpc=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' --output text)
    
    local default_subnet=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${default_vpc}" \
        --query 'Subnets[0].SubnetId' --output text)
    
    local default_sg=$(aws ec2 describe-security-groups \
        --filters "Name=vpc-id,Values=${default_vpc}" \
        "Name=group-name,Values=default" \
        --query 'SecurityGroups[0].GroupId' --output text)
    
    # Create ECS service
    aws ecs create-service \
        --cluster ${ECS_CLUSTER_NAME} \
        --service-name observability-demo-service \
        --task-definition observability-demo-task \
        --desired-count 2 \
        --launch-type FARGATE \
        --network-configuration "awsvpcConfiguration={subnets=[${default_subnet}],securityGroups=[${default_sg}],assignPublicIp=ENABLED}" || handle_error "Failed to create ECS service"
    
    log_success "Sample applications deployed"
}

# Configure CloudWatch alarms
configure_cloudwatch_alarms() {
    log_info "Configuring CloudWatch alarms and anomaly detection..."
    
    # Create CloudWatch alarms
    local alarms=(
        "EKS-High-CPU-Utilization:pod_cpu_utilization:AWS/ContainerInsights:ClusterName=${EKS_CLUSTER_NAME}:80"
        "EKS-High-Memory-Utilization:pod_memory_utilization:AWS/ContainerInsights:ClusterName=${EKS_CLUSTER_NAME}:80"
        "ECS-Service-Unhealthy-Tasks:RunningTaskCount:AWS/ECS:ServiceName=observability-demo-service,ClusterName=${ECS_CLUSTER_NAME}:1"
    )
    
    for alarm_config in "${alarms[@]}"; do
        IFS=':' read -r alarm_name metric_name namespace dimensions threshold <<< "$alarm_config"
        
        local comparison_operator="GreaterThanThreshold"
        if [[ "$metric_name" == "RunningTaskCount" ]]; then
            comparison_operator="LessThanThreshold"
        fi
        
        aws cloudwatch put-metric-alarm \
            --alarm-name "$alarm_name" \
            --alarm-description "Alarm for $metric_name" \
            --metric-name "$metric_name" \
            --namespace "$namespace" \
            --statistic Average \
            --period 300 \
            --threshold "$threshold" \
            --comparison-operator "$comparison_operator" \
            --dimensions Name=ClusterName,Value="${EKS_CLUSTER_NAME}" \
            --evaluation-periods 2 \
            --alarm-actions "${SNS_TOPIC_ARN}" || handle_error "Failed to create alarm: $alarm_name"
    done
    
    # Enable anomaly detection
    aws cloudwatch put-anomaly-detector \
        --namespace "AWS/ContainerInsights" \
        --metric-name "pod_cpu_utilization" \
        --dimensions Name=ClusterName,Value="${EKS_CLUSTER_NAME}" \
        --stat Average || handle_error "Failed to create anomaly detector"
    
    log_success "CloudWatch alarms configured"
}

# Create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log_info "Creating CloudWatch dashboard..."
    
    cat > "${SCRIPT_DIR}/container-observability-dashboard.json" << EOF
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/ContainerInsights", "pod_cpu_utilization", "ClusterName", "${EKS_CLUSTER_NAME}" ],
                    [ ".", "pod_memory_utilization", ".", "." ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "EKS Pod Resource Utilization",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0,
                        "max": 100
                    }
                }
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/ECS", "CPUUtilization", "ServiceName", "observability-demo-service", "ClusterName", "${ECS_CLUSTER_NAME}" ],
                    [ ".", "MemoryUtilization", ".", ".", ".", "." ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "${AWS_REGION}",
                "title": "ECS Service Resource Utilization",
                "period": 300
            }
        }
    ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "Container-Observability-${RANDOM_SUFFIX}" \
        --dashboard-body file://"${SCRIPT_DIR}/container-observability-dashboard.json" || handle_error "Failed to create dashboard"
    
    log_success "CloudWatch dashboard created"
}

# Main deployment function
main() {
    log_info "Starting comprehensive container observability deployment..."
    log_info "Deployment started at: $(date)"
    
    # Initialize state tracking
    init_state_tracking
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_eks_cluster
    deploy_container_insights
    install_monitoring_stack
    deploy_adot_collector
    create_ecs_cluster
    create_ecs_task_role
    deploy_sample_applications
    configure_cloudwatch_alarms
    create_cloudwatch_dashboard
    
    # Update deployment status
    update_deployment_status "completed"
    
    log_success "Comprehensive container observability deployment completed successfully!"
    log_info "Deployment completed at: $(date)"
    
    # Display access information
    echo ""
    log_info "Access Information:"
    log_info "===================="
    log_info "EKS Cluster: ${EKS_CLUSTER_NAME}"
    log_info "ECS Cluster: ${ECS_CLUSTER_NAME}"
    log_info "CloudWatch Dashboard: Container-Observability-${RANDOM_SUFFIX}"
    log_info "Monitoring Namespace: ${MONITORING_NAMESPACE}"
    
    # Get Grafana URL
    local grafana_url=$(kubectl get svc -n ${MONITORING_NAMESPACE} grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending")
    log_info "Grafana URL: http://${grafana_url} (admin/observability123!)"
    
    log_info "Environment variables saved to: ${SCRIPT_DIR}/deployment_vars.env"
    log_info "Deployment log available at: ${LOG_FILE}"
    log_info "Resource state saved to: ${RESOURCE_STATE_FILE}"
    
    echo ""
    log_success "Deployment completed successfully! 🎉"
}

# Trap to handle script interruption
trap 'handle_error "Script interrupted"' INT TERM

# Clear log file
> "${LOG_FILE}"

# Run main function
main "$@"