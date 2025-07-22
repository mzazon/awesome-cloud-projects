#!/bin/bash
set -e

# Infrastructure Automation with AWS Proton and CDK - Deployment Script
# This script deploys the complete AWS Proton infrastructure automation solution

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured or authentication failed"
        error "Please run 'aws configure' or set up AWS credentials"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command_exists aws; then
        error "AWS CLI is not installed"
        error "Please install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
        warn "AWS CLI version $AWS_CLI_VERSION detected. Version 2.0.0+ recommended"
    fi
    
    # Check Node.js
    if ! command_exists node; then
        error "Node.js is not installed"
        error "Please install Node.js 16.x or later: https://nodejs.org/"
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2)
    if [[ $(echo "$NODE_VERSION 16.0.0" | tr " " "\n" | sort -V | head -n1) != "16.0.0" ]]; then
        error "Node.js version $NODE_VERSION detected. Version 16.0.0+ required"
        exit 1
    fi
    
    # Check npm
    if ! command_exists npm; then
        error "npm is not installed"
        error "Please install npm with Node.js"
        exit 1
    fi
    
    # Check Git
    if ! command_exists git; then
        error "Git is not installed"
        error "Please install Git: https://git-scm.com/"
        exit 1
    fi
    
    # Check AWS authentication
    check_aws_auth
    
    log "Prerequisites check completed successfully"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export AWS_REGION=$(aws configure get region)
    
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not configured"
        error "Please set AWS region with 'aws configure set region <region>'"
        exit 1
    fi
    
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export PROTON_SERVICE_ROLE_NAME="ProtonServiceRole-$RANDOM_SUFFIX"
    export TEMPLATE_BUCKET="proton-templates-$RANDOM_SUFFIX"
    
    # Save environment variables for cleanup script
    cat > ../temp_env_vars.sh << EOF
export AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
export AWS_REGION=$AWS_REGION
export RANDOM_SUFFIX=$RANDOM_SUFFIX
export PROTON_SERVICE_ROLE_NAME=$PROTON_SERVICE_ROLE_NAME
export TEMPLATE_BUCKET=$TEMPLATE_BUCKET
EOF
    
    info "Environment variables configured:"
    info "  AWS Account ID: $AWS_ACCOUNT_ID"
    info "  AWS Region: $AWS_REGION"
    info "  Random Suffix: $RANDOM_SUFFIX"
    info "  Proton Service Role: $PROTON_SERVICE_ROLE_NAME"
    info "  Template Bucket: $TEMPLATE_BUCKET"
}

# Function to install and bootstrap CDK
setup_cdk() {
    log "Setting up AWS CDK..."
    
    # Install CDK globally if not present
    if ! command_exists cdk; then
        log "Installing AWS CDK globally..."
        npm install -g aws-cdk
    fi
    
    # Check CDK version
    CDK_VERSION=$(cdk --version 2>&1 | cut -d' ' -f1)
    info "CDK version: $CDK_VERSION"
    
    # Bootstrap CDK
    log "Bootstrapping CDK..."
    if ! cdk bootstrap aws://${AWS_ACCOUNT_ID}/${AWS_REGION}; then
        error "CDK bootstrap failed"
        exit 1
    fi
    
    log "CDK setup completed successfully"
}

# Function to create S3 bucket for templates
create_template_bucket() {
    log "Creating S3 bucket for template bundles..."
    
    # Check if bucket already exists
    if aws s3api head-bucket --bucket "$TEMPLATE_BUCKET" 2>/dev/null; then
        warn "Bucket $TEMPLATE_BUCKET already exists, skipping creation"
        return 0
    fi
    
    # Create bucket with proper region handling
    if [[ "$AWS_REGION" == "us-east-1" ]]; then
        aws s3api create-bucket --bucket "$TEMPLATE_BUCKET"
    else
        aws s3api create-bucket --bucket "$TEMPLATE_BUCKET" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$TEMPLATE_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$TEMPLATE_BUCKET" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    log "S3 bucket created successfully: $TEMPLATE_BUCKET"
}

# Function to create IAM service role
create_proton_service_role() {
    log "Creating IAM service role for AWS Proton..."
    
    # Check if role already exists
    if aws iam get-role --role-name "$PROTON_SERVICE_ROLE_NAME" 2>/dev/null; then
        warn "Role $PROTON_SERVICE_ROLE_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create trust policy
    cat > proton-service-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "proton.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create role
    aws iam create-role \
        --role-name "$PROTON_SERVICE_ROLE_NAME" \
        --assume-role-policy-document file://proton-service-trust-policy.json
    
    # Attach policy
    aws iam attach-role-policy \
        --role-name "$PROTON_SERVICE_ROLE_NAME" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSProtonServiceRole
    
    # Clean up temporary file
    rm -f proton-service-trust-policy.json
    
    log "IAM service role created successfully: $PROTON_SERVICE_ROLE_NAME"
}

# Function to create environment template
create_environment_template() {
    log "Creating environment template..."
    
    # Create directory structure
    mkdir -p environment-template/v1/infrastructure
    cd environment-template/v1
    
    # Create environment template schema
    cat > schema.yaml << 'EOF'
schema:
  format:
    openapi: "3.0.0"
  environment_input_type: "EnvironmentInput"
  types:
    EnvironmentInput:
      type: object
      description: "Input properties for the environment"
      properties:
        vpc_cidr:
          type: string
          description: "CIDR block for the VPC"
          default: "10.0.0.0/16"
          pattern: '^(\d{1,3}\.){3}\d{1,3}/\d{1,2}$'
        environment_name:
          type: string
          description: "Name for the environment"
          minLength: 1
          maxLength: 100
          pattern: '^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$'
      required:
        - environment_name
EOF
    
    # Create CloudFormation template for environment
    cat > infrastructure/cloudformation.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'VPC with ECS Cluster for Proton Environment'

Parameters:
  vpc_cidr:
    Type: String
    Default: '10.0.0.0/16'
    Description: 'CIDR block for VPC'
  environment_name:
    Type: String
    Description: 'Name for the environment'

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref vpc_cidr
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-vpc'

  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-igw'

  InternetGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      InternetGatewayId: !Ref InternetGateway
      VpcId: !Ref VPC

  PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs '']
      CidrBlock: !Select [0, !Cidr [!Ref vpc_cidr, 4, 8]]
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-public-subnet-1'

  PublicSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [1, !GetAZs '']
      CidrBlock: !Select [1, !Cidr [!Ref vpc_cidr, 4, 8]]
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-public-subnet-2'

  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-public-routes'

  DefaultPublicRoute:
    Type: AWS::EC2::Route
    DependsOn: InternetGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  PublicSubnet1RouteTableAssociation:
    Type: AWS::EC2::RouteTableAssociation
    Properties:
      RouteTableId: !Ref PublicRouteTable
      SubnetId: !Ref PublicSubnet1

  PublicSubnet2RouteTableAssociation:
    Type: AWS::EC2::RouteTableAssociation
    Properties:
      RouteTableId: !Ref PublicRouteTable
      SubnetId: !Ref PublicSubnet2

  ECSCluster:
    Type: AWS::ECS::Cluster
    Properties:
      ClusterName: !Sub '${environment_name}-cluster'
      CapacityProviders:
        - FARGATE
        - FARGATE_SPOT
      DefaultCapacityProviderStrategy:
        - CapacityProvider: FARGATE
          Weight: 1

Outputs:
  VpcId:
    Description: 'VPC ID'
    Value: !Ref VPC
  
  PublicSubnet1Id:
    Description: 'Public Subnet 1 ID'
    Value: !Ref PublicSubnet1
  
  PublicSubnet2Id:
    Description: 'Public Subnet 2 ID'
    Value: !Ref PublicSubnet2
  
  ECSClusterName:
    Description: 'ECS Cluster Name'
    Value: !Ref ECSCluster
  
  ECSClusterArn:
    Description: 'ECS Cluster ARN'
    Value: !GetAtt ECSCluster.Arn
EOF
    
    # Create manifest file
    cat > infrastructure/manifest.yaml << 'EOF'
infrastructure:
  templates:
    - file: "cloudformation.yaml"
      engine: "cloudformation"
      template_language: "yaml"
EOF
    
    cd ../..
    log "Environment template created successfully"
}

# Function to create service template
create_service_template() {
    log "Creating service template..."
    
    # Create directory structure
    mkdir -p service-template/v1/instance_infrastructure
    cd service-template/v1
    
    # Create service template schema
    cat > schema.yaml << 'EOF'
schema:
  format:
    openapi: "3.0.0"
  service_input_type: "ServiceInput"
  types:
    ServiceInput:
      type: object
      description: "Input properties for the service"
      properties:
        image:
          type: string
          description: "Docker image to deploy"
          default: "nginx:latest"
        port:
          type: number
          description: "Container port"
          default: 80
          minimum: 1
          maximum: 65535
        environment:
          type: string
          description: "Environment name"
          default: "production"
          enum: ["development", "staging", "production"]
        memory:
          type: number
          description: "Memory allocation in MiB"
          default: 512
          minimum: 256
          maximum: 8192
        cpu:
          type: number
          description: "CPU allocation"
          default: 256
          minimum: 256
          maximum: 4096
        desired_count:
          type: number
          description: "Desired number of tasks"
          default: 2
          minimum: 1
          maximum: 10
        min_capacity:
          type: number
          description: "Minimum number of tasks"
          default: 1
          minimum: 1
        max_capacity:
          type: number
          description: "Maximum number of tasks"
          default: 5
          minimum: 2
        health_check_path:
          type: string
          description: "Health check path"
          default: "/"
      required:
        - image
        - port
EOF
    
    # Create CloudFormation template for service
    cat > instance_infrastructure/cloudformation.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Fargate Web Service for Proton'

Parameters:
  image:
    Type: String
    Default: 'nginx:latest'
    Description: 'Docker image to deploy'
  port:
    Type: Number
    Default: 80
    Description: 'Container port'
  environment:
    Type: String
    Default: 'production'
    Description: 'Environment name'
    AllowedValues: ['development', 'staging', 'production']
  memory:
    Type: Number
    Default: 512
    Description: 'Memory allocation in MiB'
  cpu:
    Type: Number
    Default: 256
    Description: 'CPU allocation'
  desired_count:
    Type: Number
    Default: 2
    Description: 'Desired number of tasks'
  min_capacity:
    Type: Number
    Default: 1
    Description: 'Minimum number of tasks'
  max_capacity:
    Type: Number
    Default: 5
    Description: 'Maximum number of tasks'
  health_check_path:
    Type: String
    Default: '/'
    Description: 'Health check path'

Resources:
  TaskDefinition:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: !Sub '{{service.name}}-{{service_instance.name}}'
      Cpu: !Ref cpu
      Memory: !Ref memory
      NetworkMode: awsvpc
      RequiresCompatibilities:
        - FARGATE
      ExecutionRoleArn: !GetAtt TaskExecutionRole.Arn
      TaskRoleArn: !GetAtt TaskRole.Arn
      ContainerDefinitions:
        - Name: !Sub '{{service.name}}-container'
          Image: !Ref image
          PortMappings:
            - ContainerPort: !Ref port
          Environment:
            - Name: NODE_ENV
              Value: !Ref environment
            - Name: SERVICE_NAME
              Value: '{{service.name}}'
          LogConfiguration:
            LogDriver: awslogs
            Options:
              awslogs-group: !Ref LogGroup
              awslogs-region: !Ref 'AWS::Region'
              awslogs-stream-prefix: '{{service.name}}'
          Essential: true

  TaskExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Statement:
          - Effect: Allow
            Principal:
              Service: ecs-tasks.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy

  TaskRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Statement:
          - Effect: Allow
            Principal:
              Service: ecs-tasks.amazonaws.com
            Action: sts:AssumeRole

  LogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub '/aws/ecs/{{service.name}}-{{service_instance.name}}'
      RetentionInDays: 7

  LoadBalancer:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Name: !Sub '{{service.name}}-{{service_instance.name}}-alb'
      Scheme: internet-facing
      Type: application
      Subnets:
        - '{{environment.outputs.PublicSubnet1Id}}'
        - '{{environment.outputs.PublicSubnet2Id}}'
      SecurityGroups:
        - !Ref LoadBalancerSecurityGroup

  LoadBalancerSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for ALB
      VpcId: '{{environment.outputs.VpcId}}'
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0

  TaskSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for ECS tasks
      VpcId: '{{environment.outputs.VpcId}}'
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: !Ref port
          ToPort: !Ref port
          SourceSecurityGroupId: !Ref LoadBalancerSecurityGroup

  TargetGroup:
    Type: AWS::ElasticLoadBalancingV2::TargetGroup
    Properties:
      Name: !Sub '{{service.name}}-{{service_instance.name}}-tg'
      Port: !Ref port
      Protocol: HTTP
      VpcId: '{{environment.outputs.VpcId}}'
      TargetType: ip
      HealthCheckPath: !Ref health_check_path
      HealthCheckProtocol: HTTP
      HealthyThresholdCount: 2
      UnhealthyThresholdCount: 3
      HealthCheckTimeoutSeconds: 5
      HealthCheckIntervalSeconds: 30

  Listener:
    Type: AWS::ElasticLoadBalancingV2::Listener
    Properties:
      DefaultActions:
        - Type: forward
          TargetGroupArn: !Ref TargetGroup
      LoadBalancerArn: !Ref LoadBalancer
      Port: 80
      Protocol: HTTP

  Service:
    Type: AWS::ECS::Service
    DependsOn: Listener
    Properties:
      ServiceName: !Sub '{{service.name}}-{{service_instance.name}}'
      Cluster: '{{environment.outputs.ECSClusterName}}'
      TaskDefinition: !Ref TaskDefinition
      DesiredCount: !Ref desired_count
      LaunchType: FARGATE
      NetworkConfiguration:
        AwsvpcConfiguration:
          SecurityGroups:
            - !Ref TaskSecurityGroup
          Subnets:
            - '{{environment.outputs.PublicSubnet1Id}}'
            - '{{environment.outputs.PublicSubnet2Id}}'
          AssignPublicIp: ENABLED
      LoadBalancers:
        - ContainerName: !Sub '{{service.name}}-container'
          ContainerPort: !Ref port
          TargetGroupArn: !Ref TargetGroup

  ServiceAutoScalingTarget:
    Type: AWS::ApplicationAutoScaling::ScalableTarget
    Properties:
      MaxCapacity: !Ref max_capacity
      MinCapacity: !Ref min_capacity
      ResourceId: !Sub 'service/{{environment.outputs.ECSClusterName}}/{{service.name}}-{{service_instance.name}}'
      RoleARN: !Sub 'arn:aws:iam::${AWS::AccountId}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService'
      ScalableDimension: ecs:service:DesiredCount
      ServiceNamespace: ecs

  ServiceAutoScalingPolicy:
    Type: AWS::ApplicationAutoScaling::ScalingPolicy
    Properties:
      PolicyName: !Sub '{{service.name}}-{{service_instance.name}}-cpu-scaling'
      PolicyType: TargetTrackingScaling
      ScalingTargetId: !Ref ServiceAutoScalingTarget
      TargetTrackingScalingPolicyConfiguration:
        PredefinedMetricSpecification:
          PredefinedMetricType: ECSServiceAverageCPUUtilization
        TargetValue: 70.0

Outputs:
  LoadBalancerDNS:
    Description: 'Load Balancer DNS name'
    Value: !GetAtt LoadBalancer.DNSName
  
  ServiceArn:
    Description: 'ECS Service ARN'
    Value: !Ref Service
EOF
    
    # Create manifest file
    cat > instance_infrastructure/manifest.yaml << 'EOF'
infrastructure:
  templates:
    - file: "cloudformation.yaml"
      engine: "cloudformation"
      template_language: "yaml"
EOF
    
    cd ../..
    log "Service template created successfully"
}

# Function to create and upload template bundles
create_template_bundles() {
    log "Creating and uploading template bundles..."
    
    # Create environment template bundle
    cd environment-template
    tar -czf environment-template-v1.tar.gz v1/
    aws s3 cp environment-template-v1.tar.gz s3://$TEMPLATE_BUCKET/
    cd ..
    
    # Create service template bundle
    cd service-template
    tar -czf service-template-v1.tar.gz v1/
    aws s3 cp service-template-v1.tar.gz s3://$TEMPLATE_BUCKET/
    cd ..
    
    log "Template bundles uploaded successfully"
}

# Function to register templates with Proton
register_templates() {
    log "Registering templates with AWS Proton..."
    
    local proton_service_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROTON_SERVICE_ROLE_NAME}"
    
    # Register environment template
    if ! aws proton get-environment-template --name "vpc-ecs-environment" 2>/dev/null; then
        aws proton create-environment-template \
            --name "vpc-ecs-environment" \
            --display-name "VPC with ECS Cluster" \
            --description "Standard VPC environment with ECS cluster for containerized applications"
        log "Environment template registered"
    else
        warn "Environment template already exists"
    fi
    
    # Create environment template version
    if ! aws proton get-environment-template-version \
        --template-name "vpc-ecs-environment" \
        --major-version "1" --minor-version "0" 2>/dev/null; then
        
        aws proton create-environment-template-version \
            --template-name "vpc-ecs-environment" \
            --description "Initial version with VPC and ECS cluster" \
            --source s3="{bucket=${TEMPLATE_BUCKET},key=environment-template-v1.tar.gz}"
        
        log "Waiting for environment template version to be registered..."
        aws proton wait environment-template-version-registered \
            --template-name "vpc-ecs-environment" \
            --major-version "1" --minor-version "0"
        
        aws proton update-environment-template-version \
            --template-name "vpc-ecs-environment" \
            --major-version "1" --minor-version "0" \
            --status "PUBLISHED"
        
        log "Environment template version published"
    else
        warn "Environment template version already exists"
    fi
    
    # Register service template
    if ! aws proton get-service-template --name "fargate-web-service" 2>/dev/null; then
        aws proton create-service-template \
            --name "fargate-web-service" \
            --display-name "Fargate Web Service" \
            --description "Web service running on Fargate with load balancer"
        log "Service template registered"
    else
        warn "Service template already exists"
    fi
    
    # Create service template version
    if ! aws proton get-service-template-version \
        --template-name "fargate-web-service" \
        --major-version "1" --minor-version "0" 2>/dev/null; then
        
        aws proton create-service-template-version \
            --template-name "fargate-web-service" \
            --description "Initial version with Fargate and ALB" \
            --source s3="{bucket=${TEMPLATE_BUCKET},key=service-template-v1.tar.gz}" \
            --compatible-environment-templates templateName="vpc-ecs-environment",majorVersion="1"
        
        log "Waiting for service template version to be registered..."
        aws proton wait service-template-version-registered \
            --template-name "fargate-web-service" \
            --major-version "1" --minor-version "0"
        
        aws proton update-service-template-version \
            --template-name "fargate-web-service" \
            --major-version "1" --minor-version "0" \
            --status "PUBLISHED"
        
        log "Service template version published"
    else
        warn "Service template version already exists"
    fi
    
    log "Templates registered successfully with AWS Proton"
}

# Function to deploy test environment
deploy_test_environment() {
    log "Deploying test environment..."
    
    local proton_service_role_arn="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROTON_SERVICE_ROLE_NAME}"
    
    # Create environment spec
    cat > dev-environment-spec.json << 'EOF'
{
  "vpc_cidr": "10.0.0.0/16",
  "environment_name": "development"
}
EOF
    
    # Create environment if it doesn't exist
    if ! aws proton get-environment --name "dev-environment" 2>/dev/null; then
        aws proton create-environment \
            --name "dev-environment" \
            --template-name "vpc-ecs-environment" \
            --template-major-version "1" \
            --spec file://dev-environment-spec.json \
            --proton-service-role-arn "$proton_service_role_arn"
        
        log "Waiting for environment to be deployed..."
        aws proton wait environment-deployed --name "dev-environment"
        log "Test environment deployed successfully"
    else
        warn "Test environment already exists"
    fi
    
    # Clean up temporary file
    rm -f dev-environment-spec.json
}

# Function to deploy test service
deploy_test_service() {
    log "Deploying test service..."
    
    # Create service spec
    cat > test-service-spec.json << 'EOF'
{
  "image": "nginx:latest",
  "port": 80,
  "environment": "development",
  "memory": 512,
  "cpu": 256,
  "desired_count": 1,
  "min_capacity": 1,
  "max_capacity": 3,
  "health_check_path": "/"
}
EOF
    
    # Create service if it doesn't exist
    if ! aws proton get-service --name "test-web-service" 2>/dev/null; then
        aws proton create-service \
            --name "test-web-service" \
            --template-name "fargate-web-service" \
            --template-major-version "1" \
            --spec file://test-service-spec.json
        log "Test service created"
    else
        warn "Test service already exists"
    fi
    
    # Create service instance if it doesn't exist
    if ! aws proton get-service-instance \
        --service-name "test-web-service" \
        --name "dev-instance" 2>/dev/null; then
        
        aws proton create-service-instance \
            --service-name "test-web-service" \
            --name "dev-instance" \
            --environment-name "dev-environment" \
            --spec file://test-service-spec.json
        
        log "Waiting for service instance to be deployed..."
        aws proton wait service-instance-deployed \
            --service-name "test-web-service" \
            --name "dev-instance"
        
        log "Test service instance deployed successfully"
    else
        warn "Test service instance already exists"
    fi
    
    # Clean up temporary file
    rm -f test-service-spec.json
}

# Function to validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # Check environment status
    local env_status=$(aws proton get-environment --name "dev-environment" --query 'environment.deploymentStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    if [[ "$env_status" == "SUCCEEDED" ]]; then
        log "✅ Environment deployed successfully"
    else
        error "Environment deployment failed with status: $env_status"
        return 1
    fi
    
    # Check service instance status
    local service_status=$(aws proton get-service-instance \
        --service-name "test-web-service" \
        --name "dev-instance" \
        --query 'serviceInstance.deploymentStatus' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$service_status" == "SUCCEEDED" ]]; then
        log "✅ Service instance deployed successfully"
        
        # Get load balancer DNS
        local lb_dns=$(aws proton get-service-instance \
            --service-name "test-web-service" \
            --name "dev-instance" \
            --query 'serviceInstance.outputs[?key==`LoadBalancerDNS`].valueString' --output text 2>/dev/null || echo "")
        
        if [[ -n "$lb_dns" ]]; then
            log "🌐 Load Balancer DNS: http://$lb_dns"
            info "You can test the service by visiting: http://$lb_dns"
        fi
    else
        error "Service instance deployment failed with status: $service_status"
        return 1
    fi
    
    log "Deployment validation completed successfully"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    rm -rf environment-template service-template
    rm -f *.json *.tar.gz
    log "Temporary files cleaned up"
}

# Function to display summary
display_summary() {
    log "Deployment Summary:"
    info "✅ AWS Proton infrastructure automation platform deployed successfully"
    info "✅ Environment template: vpc-ecs-environment (v1.0)"
    info "✅ Service template: fargate-web-service (v1.0)"
    info "✅ Test environment: dev-environment"
    info "✅ Test service: test-web-service with dev-instance"
    info ""
    info "Next steps:"
    info "1. Visit the AWS Proton console to explore your templates"
    info "2. Create additional environments for staging/production"
    info "3. Deploy more services using the fargate-web-service template"
    info "4. Customize templates for your specific use cases"
    info ""
    info "To clean up resources, run: ./destroy.sh"
}

# Main execution
main() {
    log "Starting AWS Proton CDK infrastructure automation deployment..."
    
    # Check if running in scripts directory
    if [[ ! -f "deploy.sh" ]]; then
        error "This script must be run from the scripts directory"
        exit 1
    fi
    
    # Create temp directory for work
    mkdir -p ../temp
    cd ../temp
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    setup_cdk
    create_template_bucket
    create_proton_service_role
    create_environment_template
    create_service_template
    create_template_bundles
    register_templates
    deploy_test_environment
    deploy_test_service
    validate_deployment
    cleanup_temp_files
    
    cd ../scripts
    display_summary
    
    log "Deployment completed successfully! 🎉"
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"