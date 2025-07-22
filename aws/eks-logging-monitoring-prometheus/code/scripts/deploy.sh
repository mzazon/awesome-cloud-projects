#!/bin/bash

# Deploy script for EKS Cluster Logging and Monitoring with CloudWatch and Prometheus
# This script automates the deployment of a comprehensive observability stack for Amazon EKS

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check if kubectl is installed
    if ! command_exists kubectl; then
        error "kubectl is not installed. Please install kubectl."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        error "AWS CLI version 2.0.0 or higher is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    log "Prerequisites check passed ✅"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not set. Please set AWS_REGION environment variable or configure default region."
        exit 1
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export CLUSTER_NAME="eks-observability-cluster-${RANDOM_SUFFIX}"
    export NODEGROUP_NAME="eks-observability-nodegroup-${RANDOM_SUFFIX}"
    export PROMETHEUS_WORKSPACE_NAME="eks-prometheus-workspace-${RANDOM_SUFFIX}"
    
    log "Environment variables set:"
    info "  AWS_REGION: $AWS_REGION"
    info "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    info "  CLUSTER_NAME: $CLUSTER_NAME"
    info "  NODEGROUP_NAME: $NODEGROUP_NAME"
    info "  PROMETHEUS_WORKSPACE_NAME: $PROMETHEUS_WORKSPACE_NAME"
    
    # Save environment variables to a file for the destroy script
    cat > /tmp/eks-observability-env.sh << EOF
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export CLUSTER_NAME="$CLUSTER_NAME"
export NODEGROUP_NAME="$NODEGROUP_NAME"
export PROMETHEUS_WORKSPACE_NAME="$PROMETHEUS_WORKSPACE_NAME"
EOF
}

# Function to create VPC and networking
create_vpc() {
    log "Creating VPC and networking infrastructure..."
    
    # Check if VPC already exists
    if [[ -n "$VPC_ID" ]] && aws ec2 describe-vpcs --vpc-ids "$VPC_ID" >/dev/null 2>&1; then
        info "VPC $VPC_ID already exists, skipping creation"
        return 0
    fi
    
    # Create VPC
    export VPC_ID=$(aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --query 'Vpc.VpcId' --output text)
    
    aws ec2 create-tags \
        --resources "$VPC_ID" \
        --tags Key=Name,Value="${CLUSTER_NAME}-vpc" Key=Project,Value="eks-observability"
    
    aws ec2 modify-vpc-attribute \
        --vpc-id "$VPC_ID" \
        --enable-dns-hostnames
    
    # Create subnets
    export SUBNET_1=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone "${AWS_REGION}a" \
        --query 'Subnet.SubnetId' --output text)
    
    export SUBNET_2=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone "${AWS_REGION}b" \
        --query 'Subnet.SubnetId' --output text)
    
    aws ec2 create-tags \
        --resources "$SUBNET_1" "$SUBNET_2" \
        --tags Key=Name,Value="${CLUSTER_NAME}-subnet" Key=Project,Value="eks-observability"
    
    # Create internet gateway
    export IGW_ID=$(aws ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' --output text)
    
    aws ec2 create-tags \
        --resources "$IGW_ID" \
        --tags Key=Name,Value="${CLUSTER_NAME}-igw" Key=Project,Value="eks-observability"
    
    aws ec2 attach-internet-gateway \
        --internet-gateway-id "$IGW_ID" \
        --vpc-id "$VPC_ID"
    
    # Create route table
    export ROUTE_TABLE_ID=$(aws ec2 create-route-table \
        --vpc-id "$VPC_ID" \
        --query 'RouteTable.RouteTableId' --output text)
    
    aws ec2 create-tags \
        --resources "$ROUTE_TABLE_ID" \
        --tags Key=Name,Value="${CLUSTER_NAME}-rt" Key=Project,Value="eks-observability"
    
    aws ec2 create-route \
        --route-table-id "$ROUTE_TABLE_ID" \
        --destination-cidr-block 0.0.0.0/0 \
        --gateway-id "$IGW_ID"
    
    # Associate route table with subnets
    aws ec2 associate-route-table \
        --route-table-id "$ROUTE_TABLE_ID" \
        --subnet-id "$SUBNET_1"
    
    aws ec2 associate-route-table \
        --route-table-id "$ROUTE_TABLE_ID" \
        --subnet-id "$SUBNET_2"
    
    # Enable public IP assignment
    aws ec2 modify-subnet-attribute \
        --subnet-id "$SUBNET_1" \
        --map-public-ip-on-launch
    
    aws ec2 modify-subnet-attribute \
        --subnet-id "$SUBNET_2" \
        --map-public-ip-on-launch
    
    # Save VPC resources to environment file
    cat >> /tmp/eks-observability-env.sh << EOF
export VPC_ID="$VPC_ID"
export SUBNET_1="$SUBNET_1"
export SUBNET_2="$SUBNET_2"
export IGW_ID="$IGW_ID"
export ROUTE_TABLE_ID="$ROUTE_TABLE_ID"
EOF
    
    log "VPC and networking infrastructure created ✅"
    info "  VPC ID: $VPC_ID"
    info "  Subnet IDs: $SUBNET_1, $SUBNET_2"
    info "  Internet Gateway ID: $IGW_ID"
}

# Function to create IAM roles
create_iam_roles() {
    log "Creating IAM roles..."
    
    # Create EKS cluster service role
    if ! aws iam get-role --role-name "${CLUSTER_NAME}-service-role" >/dev/null 2>&1; then
        cat > /tmp/eks-cluster-role-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
        
        export CLUSTER_ROLE_ARN=$(aws iam create-role \
            --role-name "${CLUSTER_NAME}-service-role" \
            --assume-role-policy-document file:///tmp/eks-cluster-role-trust-policy.json \
            --query 'Role.Arn' --output text)
        
        aws iam attach-role-policy \
            --role-name "${CLUSTER_NAME}-service-role" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
        
        info "EKS cluster service role created: $CLUSTER_ROLE_ARN"
    else
        export CLUSTER_ROLE_ARN=$(aws iam get-role --role-name "${CLUSTER_NAME}-service-role" --query 'Role.Arn' --output text)
        info "EKS cluster service role already exists: $CLUSTER_ROLE_ARN"
    fi
    
    # Create node group role
    if ! aws iam get-role --role-name "${CLUSTER_NAME}-node-role" >/dev/null 2>&1; then
        cat > /tmp/node-group-role-trust-policy.json << EOF
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
        
        export NODE_ROLE_ARN=$(aws iam create-role \
            --role-name "${CLUSTER_NAME}-node-role" \
            --assume-role-policy-document file:///tmp/node-group-role-trust-policy.json \
            --query 'Role.Arn' --output text)
        
        # Attach required policies
        aws iam attach-role-policy \
            --role-name "${CLUSTER_NAME}-node-role" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
        
        aws iam attach-role-policy \
            --role-name "${CLUSTER_NAME}-node-role" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
        
        aws iam attach-role-policy \
            --role-name "${CLUSTER_NAME}-node-role" \
            --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
        
        info "Node group role created: $NODE_ROLE_ARN"
    else
        export NODE_ROLE_ARN=$(aws iam get-role --role-name "${CLUSTER_NAME}-node-role" --query 'Role.Arn' --output text)
        info "Node group role already exists: $NODE_ROLE_ARN"
    fi
    
    # Save IAM role ARNs to environment file
    cat >> /tmp/eks-observability-env.sh << EOF
export CLUSTER_ROLE_ARN="$CLUSTER_ROLE_ARN"
export NODE_ROLE_ARN="$NODE_ROLE_ARN"
EOF
    
    log "IAM roles created ✅"
}

# Function to create EKS cluster
create_eks_cluster() {
    log "Creating EKS cluster..."
    
    # Check if cluster already exists
    if aws eks describe-cluster --name "$CLUSTER_NAME" >/dev/null 2>&1; then
        info "EKS cluster $CLUSTER_NAME already exists, skipping creation"
        CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.status' --output text)
        if [[ "$CLUSTER_STATUS" != "ACTIVE" ]]; then
            info "Waiting for cluster to become active..."
            aws eks wait cluster-active --name "$CLUSTER_NAME" --timeout 1200
        fi
    else
        # Create cluster
        aws eks create-cluster \
            --name "$CLUSTER_NAME" \
            --version 1.28 \
            --role-arn "$CLUSTER_ROLE_ARN" \
            --resources-vpc-config subnetIds="$SUBNET_1,$SUBNET_2" \
            --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' \
            --tags Project=eks-observability
        
        info "Waiting for EKS cluster to become active..."
        aws eks wait cluster-active --name "$CLUSTER_NAME" --timeout 1200
    fi
    
    # Update kubeconfig
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    
    log "EKS cluster created and configured ✅"
}

# Function to create node group
create_node_group() {
    log "Creating EKS node group..."
    
    # Check if node group already exists
    if aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" >/dev/null 2>&1; then
        info "Node group $NODEGROUP_NAME already exists, skipping creation"
        NODEGROUP_STATUS=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --query 'nodegroup.status' --output text)
        if [[ "$NODEGROUP_STATUS" != "ACTIVE" ]]; then
            info "Waiting for node group to become active..."
            aws eks wait nodegroup-active --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --timeout 1200
        fi
    else
        # Create node group
        aws eks create-nodegroup \
            --cluster-name "$CLUSTER_NAME" \
            --nodegroup-name "$NODEGROUP_NAME" \
            --node-role "$NODE_ROLE_ARN" \
            --subnets "$SUBNET_1" "$SUBNET_2" \
            --instance-types t3.medium \
            --scaling-config minSize=2,maxSize=4,desiredSize=2 \
            --ami-type AL2_x86_64 \
            --tags Project=eks-observability
        
        info "Waiting for node group to become active..."
        aws eks wait nodegroup-active --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --timeout 1200
    fi
    
    log "EKS node group created and ready ✅"
}

# Function to create IAM OIDC provider
create_oidc_provider() {
    log "Creating IAM OIDC provider..."
    
    # Get the OIDC issuer URL
    OIDC_ISSUER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.identity.oidc.issuer' --output text)
    OIDC_PROVIDER=$(echo "$OIDC_ISSUER" | sed 's|https://||')
    
    # Check if OIDC provider already exists
    if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}" >/dev/null 2>&1; then
        info "OIDC provider already exists"
    else
        # Get the certificate thumbprint
        THUMBPRINT=$(echo | openssl s_client -servername "$OIDC_PROVIDER" -connect "${OIDC_PROVIDER}:443" 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | sed 's/SHA1 Fingerprint=//g' | sed 's/://g')
        
        # Create OIDC provider
        aws iam create-open-id-connect-provider \
            --url "$OIDC_ISSUER" \
            --client-id-list sts.amazonaws.com \
            --thumbprint-list "$THUMBPRINT" \
            --tags Key=Project,Value=eks-observability
        
        info "OIDC provider created"
    fi
    
    # Save OIDC provider info to environment file
    cat >> /tmp/eks-observability-env.sh << EOF
export OIDC_ISSUER="$OIDC_ISSUER"
export OIDC_PROVIDER="$OIDC_PROVIDER"
EOF
    
    log "OIDC provider configured ✅"
}

# Function to deploy CloudWatch Container Insights
deploy_cloudwatch_insights() {
    log "Deploying CloudWatch Container Insights..."
    
    # Create namespace
    kubectl create namespace amazon-cloudwatch --dry-run=client -o yaml | kubectl apply -f -
    
    # Create service account
    cat > /tmp/cloudwatch-agent-service-account.yaml << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: cloudwatch-agent
  namespace: amazon-cloudwatch
EOF
    
    kubectl apply -f /tmp/cloudwatch-agent-service-account.yaml
    
    # Create IAM role for CloudWatch agent with OIDC
    if ! aws iam get-role --role-name "${CLUSTER_NAME}-cloudwatch-agent-role" >/dev/null 2>&1; then
        cat > /tmp/cloudwatch-agent-role-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
        }
      }
    }
  ]
}
EOF
        
        export CLOUDWATCH_AGENT_ROLE_ARN=$(aws iam create-role \
            --role-name "${CLUSTER_NAME}-cloudwatch-agent-role" \
            --assume-role-policy-document file:///tmp/cloudwatch-agent-role-trust-policy.json \
            --query 'Role.Arn' --output text)
        
        aws iam attach-role-policy \
            --role-name "${CLUSTER_NAME}-cloudwatch-agent-role" \
            --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
        
        info "CloudWatch agent role created: $CLOUDWATCH_AGENT_ROLE_ARN"
    else
        export CLOUDWATCH_AGENT_ROLE_ARN=$(aws iam get-role --role-name "${CLUSTER_NAME}-cloudwatch-agent-role" --query 'Role.Arn' --output text)
        info "CloudWatch agent role already exists: $CLOUDWATCH_AGENT_ROLE_ARN"
    fi
    
    # Annotate service account
    kubectl annotate serviceaccount cloudwatch-agent \
        -n amazon-cloudwatch \
        eks.amazonaws.com/role-arn="$CLOUDWATCH_AGENT_ROLE_ARN" \
        --overwrite
    
    # Save CloudWatch agent role ARN to environment file
    cat >> /tmp/eks-observability-env.sh << EOF
export CLOUDWATCH_AGENT_ROLE_ARN="$CLOUDWATCH_AGENT_ROLE_ARN"
EOF
    
    log "CloudWatch Container Insights setup completed ✅"
}

# Function to deploy Fluent Bit
deploy_fluent_bit() {
    log "Deploying Fluent Bit for log collection..."
    
    # Create Fluent Bit configuration
    cat > /tmp/fluent-bit-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: amazon-cloudwatch
data:
  fluent-bit.conf: |
    [SERVICE]
        Flush                     5
        Grace                     30
        Log_Level                 info
        Daemon                    off
        Parsers_File              parsers.conf
        HTTP_Server               On
        HTTP_Listen               0.0.0.0
        HTTP_Port                 2020
        storage.path              /var/fluent-bit/state/flb-storage/
        storage.sync              normal
        storage.checksum          off
        storage.backlog.mem_limit 5M
    
    [INPUT]
        Name                tail
        Tag                 application.*
        Exclude_Path        /var/log/containers/cloudwatch-agent*, /var/log/containers/fluent-bit*, /var/log/containers/aws-node*, /var/log/containers/kube-proxy*
        Path                /var/log/containers/*.log
        multiline.parser    docker, cri
        DB                  /var/fluent-bit/state/flb_container.db
        Mem_Buf_Limit       50MB
        Skip_Long_Lines     On
        Refresh_Interval    10
        Rotate_Wait         30
        storage.type        filesystem
        Read_from_Head      Off
    
    [FILTER]
        Name                kubernetes
        Match               application.*
        Kube_URL            https://kubernetes.default.svc:443
        Kube_Tag_Prefix     application.var.log.containers.
        Merge_Log           On
        Merge_Log_Key       log_processed
        K8S-Logging.Parser  On
        K8S-Logging.Exclude Off
        Labels              Off
        Annotations         Off
        Use_Kubelet         On
        Kubelet_Port        10250
        Buffer_Size         0
    
    [OUTPUT]
        Name                cloudwatch_logs
        Match               application.*
        region              ${AWS_REGION}
        log_group_name      /aws/containerinsights/${CLUSTER_NAME}/application
        log_stream_prefix   \${kubernetes_namespace_name}-
        auto_create_group   On
        extra_user_agent    container-insights
  
  parsers.conf: |
    [PARSER]
        Name                docker
        Format              json
        Time_Key            time
        Time_Format         %Y-%m-%dT%H:%M:%S.%L
        Time_Keep           On

    [PARSER]
        Name                cri
        Format              regex
        Regex               ^(?<time>[^ ]+) (?<stream>stdout|stderr) (?<logtag>[^ ]*) (?<message>.*)$
        Time_Key            time
        Time_Format         %Y-%m-%dT%H:%M:%S.%L%z
EOF
    
    kubectl apply -f /tmp/fluent-bit-config.yaml
    
    # Deploy Fluent Bit DaemonSet
    cat > /tmp/fluent-bit-daemonset.yaml << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluent-bit
  namespace: amazon-cloudwatch
spec:
  selector:
    matchLabels:
      name: fluent-bit
  template:
    metadata:
      labels:
        name: fluent-bit
    spec:
      serviceAccountName: cloudwatch-agent
      containers:
      - name: fluent-bit
        image: amazon/aws-for-fluent-bit:stable
        imagePullPolicy: Always
        env:
        - name: AWS_REGION
          value: "${AWS_REGION}"
        - name: CLUSTER_NAME
          value: "${CLUSTER_NAME}"
        - name: HTTP_SERVER
          value: "On"
        - name: HTTP_PORT
          value: "2020"
        - name: READ_FROM_HEAD
          value: "Off"
        - name: HOST_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: HOSTNAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: metadata.name
        resources:
          limits:
            memory: 200Mi
          requests:
            cpu: 500m
            memory: 100Mi
        volumeMounts:
        - name: fluentbitstate
          mountPath: /var/fluent-bit/state
        - name: varlog
          mountPath: /var/log
          readOnly: true
        - name: varlibdockercontainers
          mountPath: /var/lib/docker/containers
          readOnly: true
        - name: fluent-bit-config
          mountPath: /fluent-bit/etc/
        - name: runlogjournal
          mountPath: /run/log/journal
          readOnly: true
        - name: dmesg
          mountPath: /var/log/dmesg
          readOnly: true
      terminationGracePeriodSeconds: 10
      volumes:
      - name: fluentbitstate
        hostPath:
          path: /var/fluent-bit/state
      - name: varlog
        hostPath:
          path: /var/log
      - name: varlibdockercontainers
        hostPath:
          path: /var/lib/docker/containers
      - name: fluent-bit-config
        configMap:
          name: fluent-bit-config
      - name: runlogjournal
        hostPath:
          path: /run/log/journal
      - name: dmesg
        hostPath:
          path: /var/log/dmesg
      tolerations:
      - key: node-role.kubernetes.io/master
        operator: Exists
        effect: NoSchedule
      - operator: "Exists"
        effect: "NoExecute"
      - operator: "Exists"
        effect: "NoSchedule"
EOF
    
    kubectl apply -f /tmp/fluent-bit-daemonset.yaml
    
    log "Fluent Bit deployed successfully ✅"
}

# Function to deploy CloudWatch agent
deploy_cloudwatch_agent() {
    log "Deploying CloudWatch agent..."
    
    # Create CloudWatch agent configuration
    cat > /tmp/cwagent-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: cwagentconfig
  namespace: amazon-cloudwatch
data:
  cwagentconfig.json: |
    {
      "metrics": {
        "namespace": "ContainerInsights",
        "metrics_collected": {
          "cpu": {
            "measurement": [
              "cpu_usage_idle",
              "cpu_usage_iowait",
              "cpu_usage_user",
              "cpu_usage_system"
            ],
            "metrics_collection_interval": 60,
            "resources": ["*"],
            "totalcpu": false
          },
          "disk": {
            "measurement": ["used_percent"],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          },
          "diskio": {
            "measurement": [
              "io_time",
              "read_bytes",
              "write_bytes",
              "reads",
              "writes"
            ],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          },
          "mem": {
            "measurement": ["mem_used_percent"],
            "metrics_collection_interval": 60
          },
          "netstat": {
            "measurement": ["tcp_established", "tcp_time_wait"],
            "metrics_collection_interval": 60
          },
          "swap": {
            "measurement": ["swap_used_percent"],
            "metrics_collection_interval": 60
          }
        }
      }
    }
EOF
    
    kubectl apply -f /tmp/cwagent-config.yaml
    
    # Deploy CloudWatch agent DaemonSet
    cat > /tmp/cwagent-daemonset.yaml << EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: cloudwatch-agent
  namespace: amazon-cloudwatch
spec:
  selector:
    matchLabels:
      name: cloudwatch-agent
  template:
    metadata:
      labels:
        name: cloudwatch-agent
    spec:
      serviceAccountName: cloudwatch-agent
      containers:
      - name: cloudwatch-agent
        image: amazon/cloudwatch-agent:1.300026.2b361
        ports:
        - containerPort: 8125
          hostPort: 8125
          protocol: UDP
        resources:
          limits:
            cpu: 200m
            memory: 200Mi
          requests:
            cpu: 200m
            memory: 200Mi
        env:
        - name: HOST_IP
          valueFrom:
            fieldRef:
              fieldPath: status.hostIP
        - name: HOST_NAME
          valueFrom:
            fieldRef:
              fieldPath: spec.nodeName
        - name: K8S_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        volumeMounts:
        - name: cwagentconfig
          mountPath: /etc/cwagentconfig
        - name: rootfs
          mountPath: /rootfs
          readOnly: true
        - name: dockersock
          mountPath: /var/run/docker.sock
          readOnly: true
        - name: varlibdocker
          mountPath: /var/lib/docker
          readOnly: true
        - name: containerdsock
          mountPath: /run/containerd/containerd.sock
          readOnly: true
        - name: sys
          mountPath: /sys
          readOnly: true
        - name: devdisk
          mountPath: /dev/disk
          readOnly: true
      volumes:
      - name: cwagentconfig
        configMap:
          name: cwagentconfig
      - name: rootfs
        hostPath:
          path: /
      - name: dockersock
        hostPath:
          path: /var/run/docker.sock
      - name: varlibdocker
        hostPath:
          path: /var/lib/docker
      - name: containerdsock
        hostPath:
          path: /run/containerd/containerd.sock
      - name: sys
        hostPath:
          path: /sys
      - name: devdisk
        hostPath:
          path: /dev/disk/
      terminationGracePeriodSeconds: 60
      tolerations:
      - operator: "Exists"
        effect: "NoSchedule"
      - operator: "Exists"
        effect: "NoExecute"
EOF
    
    kubectl apply -f /tmp/cwagent-daemonset.yaml
    
    log "CloudWatch agent deployed successfully ✅"
}

# Function to create Prometheus workspace
create_prometheus_workspace() {
    log "Creating Amazon Managed Service for Prometheus workspace..."
    
    # Check if workspace already exists
    if EXISTING_WORKSPACE=$(aws amp list-workspaces --query "workspaces[?alias=='${PROMETHEUS_WORKSPACE_NAME}'].workspaceId" --output text 2>/dev/null) && [[ -n "$EXISTING_WORKSPACE" ]]; then
        export PROMETHEUS_WORKSPACE_ID="$EXISTING_WORKSPACE"
        info "Prometheus workspace already exists: $PROMETHEUS_WORKSPACE_ID"
    else
        # Create workspace
        export PROMETHEUS_WORKSPACE_ID=$(aws amp create-workspace \
            --alias "$PROMETHEUS_WORKSPACE_NAME" \
            --tags Project=eks-observability \
            --query 'workspaceId' --output text)
        
        info "Waiting for Prometheus workspace to become active..."
        while true; do
            WORKSPACE_STATUS=$(aws amp describe-workspace --workspace-id "$PROMETHEUS_WORKSPACE_ID" --query 'workspace.status' --output text)
            if [[ "$WORKSPACE_STATUS" == "ACTIVE" ]]; then
                break
            fi
            info "Workspace status: $WORKSPACE_STATUS - waiting 30 seconds..."
            sleep 30
        done
    fi
    
    # Save Prometheus workspace ID to environment file
    cat >> /tmp/eks-observability-env.sh << EOF
export PROMETHEUS_WORKSPACE_ID="$PROMETHEUS_WORKSPACE_ID"
EOF
    
    log "Prometheus workspace ready: $PROMETHEUS_WORKSPACE_ID ✅"
}

# Function to create CloudWatch dashboard
create_cloudwatch_dashboard() {
    log "Creating CloudWatch dashboard..."
    
    # Create dashboard JSON
    cat > /tmp/cloudwatch-dashboard.json << EOF
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
          [ "ContainerInsights", "cluster_node_count", "ClusterName", "${CLUSTER_NAME}" ],
          [ ".", "cluster_node_running_count", ".", "." ],
          [ ".", "cluster_node_failed_count", ".", "." ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "EKS Cluster Node Status",
        "period": 300
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
          [ "ContainerInsights", "cluster_running_count", "ClusterName", "${CLUSTER_NAME}" ],
          [ ".", "cluster_pending_count", ".", "." ],
          [ ".", "cluster_failed_count", ".", "." ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "EKS Cluster Pod Status",
        "period": 300
      }
    },
    {
      "type": "metric",
      "x": 0,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          [ "ContainerInsights", "node_cpu_utilization", "ClusterName", "${CLUSTER_NAME}" ],
          [ ".", "node_memory_utilization", ".", "." ],
          [ ".", "node_filesystem_utilization", ".", "." ]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "${AWS_REGION}",
        "title": "Node Resource Utilization",
        "period": 300
      }
    },
    {
      "type": "log",
      "x": 12,
      "y": 6,
      "width": 12,
      "height": 6,
      "properties": {
        "query": "SOURCE '/aws/eks/${CLUSTER_NAME}/cluster' | fields @timestamp, @message\\n| filter @message like /ERROR/\\n| sort @timestamp desc\\n| limit 20",
        "region": "${AWS_REGION}",
        "title": "EKS Control Plane Errors",
        "view": "table"
      }
    }
  ]
}
EOF
    
    aws cloudwatch put-dashboard \
        --dashboard-name "${CLUSTER_NAME}-observability" \
        --dashboard-body file:///tmp/cloudwatch-dashboard.json
    
    log "CloudWatch dashboard created ✅"
}

# Function to deploy sample application
deploy_sample_application() {
    log "Deploying sample application with Prometheus metrics..."
    
    cat > /tmp/sample-app-with-metrics.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-app
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-app
  template:
    metadata:
      labels:
        app: sample-app
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: sample-app
        image: nginx:1.21
        ports:
        - containerPort: 80
        - containerPort: 8080
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 200m
            memory: 256Mi
        env:
        - name: PROMETHEUS_ENABLED
          value: "true"
---
apiVersion: v1
kind: Service
metadata:
  name: sample-app-service
  namespace: default
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
spec:
  selector:
    app: sample-app
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: metrics
    port: 8080
    targetPort: 8080
  type: ClusterIP
EOF
    
    kubectl apply -f /tmp/sample-app-with-metrics.yaml
    
    log "Sample application deployed ✅"
}

# Function to create CloudWatch alarms
create_cloudwatch_alarms() {
    log "Creating CloudWatch alarms..."
    
    # Create CPU utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CLUSTER_NAME}-high-cpu-utilization" \
        --alarm-description "High CPU utilization in EKS cluster" \
        --metric-name node_cpu_utilization \
        --namespace ContainerInsights \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
        --treat-missing-data notBreaching \
        --tags Key=Project,Value=eks-observability
    
    # Create memory utilization alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CLUSTER_NAME}-high-memory-utilization" \
        --alarm-description "High memory utilization in EKS cluster" \
        --metric-name node_memory_utilization \
        --namespace ContainerInsights \
        --statistic Average \
        --period 300 \
        --threshold 80 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
        --treat-missing-data notBreaching \
        --tags Key=Project,Value=eks-observability
    
    # Create failed pods alarm
    aws cloudwatch put-metric-alarm \
        --alarm-name "${CLUSTER_NAME}-high-pod-failures" \
        --alarm-description "High number of failed pods in EKS cluster" \
        --metric-name cluster_failed_count \
        --namespace ContainerInsights \
        --statistic Average \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 1 \
        --dimensions Name=ClusterName,Value="${CLUSTER_NAME}" \
        --treat-missing-data notBreaching \
        --tags Key=Project,Value=eks-observability
    
    log "CloudWatch alarms created ✅"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    rm -f /tmp/eks-cluster-role-trust-policy.json
    rm -f /tmp/node-group-role-trust-policy.json
    rm -f /tmp/cloudwatch-agent-role-trust-policy.json
    rm -f /tmp/cloudwatch-agent-service-account.yaml
    rm -f /tmp/fluent-bit-config.yaml
    rm -f /tmp/fluent-bit-daemonset.yaml
    rm -f /tmp/cwagent-config.yaml
    rm -f /tmp/cwagent-daemonset.yaml
    rm -f /tmp/cloudwatch-dashboard.json
    rm -f /tmp/sample-app-with-metrics.yaml
    
    log "Temporary files cleaned up ✅"
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check cluster status
    CLUSTER_STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --query 'cluster.status' --output text)
    if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
        info "✅ EKS cluster is active"
    else
        warn "❌ EKS cluster status: $CLUSTER_STATUS"
    fi
    
    # Check node group status
    NODEGROUP_STATUS=$(aws eks describe-nodegroup --cluster-name "$CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --query 'nodegroup.status' --output text)
    if [[ "$NODEGROUP_STATUS" == "ACTIVE" ]]; then
        info "✅ EKS node group is active"
    else
        warn "❌ EKS node group status: $NODEGROUP_STATUS"
    fi
    
    # Check pods in amazon-cloudwatch namespace
    CLOUDWATCH_PODS=$(kubectl get pods -n amazon-cloudwatch --no-headers 2>/dev/null | wc -l)
    if [[ "$CLOUDWATCH_PODS" -gt 0 ]]; then
        info "✅ CloudWatch pods deployed: $CLOUDWATCH_PODS"
    else
        warn "❌ No CloudWatch pods found"
    fi
    
    # Check Prometheus workspace
    WORKSPACE_STATUS=$(aws amp describe-workspace --workspace-id "$PROMETHEUS_WORKSPACE_ID" --query 'workspace.status' --output text)
    if [[ "$WORKSPACE_STATUS" == "ACTIVE" ]]; then
        info "✅ Prometheus workspace is active"
    else
        warn "❌ Prometheus workspace status: $WORKSPACE_STATUS"
    fi
    
    log "Deployment validation completed ✅"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    echo "=================="
    info "EKS Cluster: $CLUSTER_NAME"
    info "AWS Region: $AWS_REGION"
    info "VPC ID: $VPC_ID"
    info "Prometheus Workspace: $PROMETHEUS_WORKSPACE_ID"
    info "CloudWatch Dashboard: ${CLUSTER_NAME}-observability"
    echo ""
    info "Access your resources:"
    info "  - kubectl get nodes"
    info "  - kubectl get pods -A"
    info "  - aws cloudwatch get-dashboard --dashboard-name ${CLUSTER_NAME}-observability"
    info "  - aws amp describe-workspace --workspace-id ${PROMETHEUS_WORKSPACE_ID}"
    echo ""
    info "Environment variables saved to: /tmp/eks-observability-env.sh"
    warn "Important: Save the environment file before running destroy.sh!"
    echo ""
    warn "Remember to run destroy.sh to clean up resources when finished!"
}

# Main deployment function
main() {
    log "Starting EKS Cluster Logging and Monitoring deployment..."
    
    # Check if this is a dry run
    if [[ "$1" == "--dry-run" ]]; then
        info "Running in dry-run mode - no resources will be created"
        return 0
    fi
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    create_vpc
    create_iam_roles
    create_eks_cluster
    create_node_group
    create_oidc_provider
    deploy_cloudwatch_insights
    deploy_fluent_bit
    deploy_cloudwatch_agent
    create_prometheus_workspace
    create_cloudwatch_dashboard
    deploy_sample_application
    create_cloudwatch_alarms
    cleanup_temp_files
    validate_deployment
    display_summary
    
    log "Deployment completed successfully! 🎉"
}

# Trap to clean up on exit
trap cleanup_temp_files EXIT

# Execute main function with all arguments
main "$@"