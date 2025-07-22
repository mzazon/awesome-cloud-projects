#!/bin/bash

# AWS Proton and CDK Infrastructure Automation Deployment Script
# This script deploys the complete infrastructure automation solution using AWS Proton and CDK

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

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Cleaning up resources..."
    if [[ -n "${ENVIRONMENT_NAME:-}" ]]; then
        aws proton delete-environment --name "$ENVIRONMENT_NAME" 2>/dev/null || true
    fi
    if [[ -n "${PROTON_ROLE_NAME:-}" ]]; then
        aws iam detach-role-policy --role-name "$PROTON_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/AWSProtonFullAccess 2>/dev/null || true
        aws iam delete-role --role-name "$PROTON_ROLE_NAME" 2>/dev/null || true
    fi
    if [[ -n "${PROJECT_NAME:-}" ]]; then
        aws s3 rm "s3://${PROJECT_NAME}-templates-${AWS_ACCOUNT_ID}" --recursive 2>/dev/null || true
        aws s3 rb "s3://${PROJECT_NAME}-templates-${AWS_ACCOUNT_ID}" 2>/dev/null || true
    fi
    rm -f proton-service-role-trust-policy.json environment-spec.yaml 2>/dev/null || true
    exit 1
}

# Set trap for cleanup on error
trap cleanup_on_error ERR

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js 16+ first."
        exit 1
    fi
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm first."
        exit 1
    fi
    
    # Check if CDK is installed
    if ! command -v cdk &> /dev/null; then
        warning "AWS CDK is not installed. Installing globally..."
        npm install -g aws-cdk
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check Node.js version
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [[ $NODE_VERSION -lt 16 ]]; then
        error "Node.js version 16+ is required. Current version: $(node --version)"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        export AWS_REGION="us-east-1"
        warning "No AWS region configured. Using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    RANDOM_STRING=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    export PROJECT_NAME="proton-demo-${RANDOM_STRING}"
    export ENV_TEMPLATE_NAME="web-app-env-${RANDOM_STRING}"
    export SVC_TEMPLATE_NAME="web-app-svc-${RANDOM_STRING}"
    export PROTON_ROLE_NAME="ProtonServiceRole-${RANDOM_STRING}"
    export ENVIRONMENT_NAME="dev-env-${RANDOM_STRING}"
    
    log "Project Name: $PROJECT_NAME"
    log "Environment Template: $ENV_TEMPLATE_NAME"
    log "Service Template: $SVC_TEMPLATE_NAME"
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    
    success "Environment variables initialized"
}

# Create project structure
create_project_structure() {
    log "Creating project structure..."
    
    # Create project directory structure
    mkdir -p "$PROJECT_NAME"/{environment-template,service-template,cdk-infra}
    cd "$PROJECT_NAME"
    
    # Initialize CDK project for infrastructure components
    cd cdk-infra
    log "Initializing CDK project..."
    npx cdk init app --language typescript --quiet
    
    # Install additional CDK constructs
    log "Installing CDK dependencies..."
    npm install @aws-cdk/aws-proton-alpha \
        @aws-cdk/aws-ecs-patterns-alpha \
        aws-cdk-lib@^2.0.0 --silent
    
    cd ..
    success "Project structure created and CDK initialized"
}

# Create Proton service role
create_proton_service_role() {
    log "Creating Proton service role..."
    
    # Create trust policy file
    cat > proton-service-role-trust-policy.json << EOF
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
    
    # Check if role already exists
    if aws iam get-role --role-name "$PROTON_ROLE_NAME" &> /dev/null; then
        warning "Proton service role already exists. Skipping creation."
        export PROTON_ROLE_ARN=$(aws iam get-role --role-name "$PROTON_ROLE_NAME" --query 'Role.Arn' --output text)
    else
        # Create Proton service role
        export PROTON_ROLE_ARN=$(aws iam create-role \
            --role-name "$PROTON_ROLE_NAME" \
            --assume-role-policy-document file://proton-service-role-trust-policy.json \
            --query 'Role.Arn' --output text)
        
        # Attach managed policy for Proton
        aws iam attach-role-policy \
            --role-name "$PROTON_ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/AWSProtonFullAccess
        
        # Wait for role to be available
        log "Waiting for IAM role to be ready..."
        sleep 10
    fi
    
    success "Proton service role created: $PROTON_ROLE_ARN"
}

# Create CDK constructs
create_cdk_constructs() {
    log "Creating CDK infrastructure components..."
    
    cd cdk-infra
    
    # Create CDK construct for VPC infrastructure
    cat > lib/vpc-construct.ts << 'EOF'
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';

export interface VpcConstructProps {
  vpcName: string;
  cidrBlock: string;
}

export class VpcConstruct extends Construct {
  public readonly vpc: ec2.Vpc;
  public readonly publicSubnets: ec2.ISubnet[];
  public readonly privateSubnets: ec2.ISubnet[];

  constructor(scope: Construct, id: string, props: VpcConstructProps) {
    super(scope, id);

    this.vpc = new ec2.Vpc(this, 'Vpc', {
      vpcName: props.vpcName,
      ipAddresses: ec2.IpAddresses.cidr(props.cidrBlock),
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        }
      ]
    });

    this.publicSubnets = this.vpc.publicSubnets;
    this.privateSubnets = this.vpc.privateSubnets;

    // Output VPC information for Proton templates
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for Proton services'
    });

    new cdk.CfnOutput(this, 'PublicSubnetIds', {
      value: this.publicSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'Public subnet IDs'
    });

    new cdk.CfnOutput(this, 'PrivateSubnetIds', {
      value: this.privateSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'Private subnet IDs'
    });
  }
}
EOF
    
    # Build and synthesize CDK
    log "Building CDK project..."
    npm run build
    npx cdk synth > /dev/null
    
    cd ..
    success "CDK infrastructure components created"
}

# Create environment template
create_environment_template() {
    log "Creating environment template..."
    
    cd environment-template
    
    # Create the schema file for environment parameters
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
          pattern: "^([0-9]{1,3}\\.){3}[0-9]{1,3}(\\/([0-9]|[1-2][0-9]|3[0-2]))?$"
        environment_name:
          type: string
          description: "Name of the environment"
          minLength: 1
          maxLength: 100
      required:
        - environment_name
EOF
    
    # Create infrastructure template
    cat > infrastructure.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Proton Environment Template - Shared Infrastructure'

Parameters:
  vpc_cidr:
    Type: String
    Description: CIDR block for the VPC
    Default: "10.0.0.0/16"
  environment_name:
    Type: String
    Description: Name of the environment

Resources:
  # VPC for the environment
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref vpc_cidr
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-vpc'

  # Internet Gateway
  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-igw'

  # Attach Internet Gateway to VPC
  AttachGateway:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  # Public Subnet
  PublicSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [0, !Cidr [!Ref vpc_cidr, 4, 8]]
      AvailabilityZone: !Select [0, !GetAZs '']
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-public-subnet'

  # Private Subnet
  PrivateSubnet:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [1, !Cidr [!Ref vpc_cidr, 4, 8]]
      AvailabilityZone: !Select [0, !GetAZs '']
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-private-subnet'

  # Route Table for Public Subnet
  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${environment_name}-public-rt'

  # Route to Internet Gateway
  PublicRoute:
    Type: AWS::EC2::Route
    DependsOn: AttachGateway
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  # Associate Public Subnet with Route Table
  PublicSubnetRouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      SubnetId: !Ref PublicSubnet
      RouteTableId: !Ref PublicRouteTable

  # ECS Cluster
  ECSCluster:
    Type: AWS::ECS::Cluster
    Properties:
      ClusterName: !Sub '${environment_name}-cluster'
      ClusterSettings:
        - Name: containerInsights
          Value: enabled

Outputs:
  VPCId:
    Description: ID of the VPC
    Value: !Ref VPC
  ClusterName:
    Description: Name of the ECS cluster
    Value: !Ref ECSCluster
  PublicSubnetId:
    Description: ID of the public subnet
    Value: !Ref PublicSubnet
  PrivateSubnetId:
    Description: ID of the private subnet
    Value: !Ref PrivateSubnet
EOF
    
    # Create manifest file
    cat > manifest.yaml << 'EOF'
infrastructure:
  templates:
    - file: "infrastructure.yaml"
      engine: "cloudformation"
EOF
    
    cd ..
    success "Environment template created"
}

# Register templates with Proton
register_proton_templates() {
    log "Registering templates with AWS Proton..."
    
    cd environment-template
    
    # Create template bundle
    tar -czf environment-template.tar.gz schema.yaml infrastructure.yaml manifest.yaml
    
    # Create S3 bucket for templates
    log "Creating S3 bucket for templates..."
    if aws s3api head-bucket --bucket "${PROJECT_NAME}-templates-${AWS_ACCOUNT_ID}" 2>/dev/null; then
        warning "S3 bucket already exists. Skipping creation."
    else
        aws s3 mb "s3://${PROJECT_NAME}-templates-${AWS_ACCOUNT_ID}"
    fi
    
    # Upload template bundle
    aws s3 cp environment-template.tar.gz "s3://${PROJECT_NAME}-templates-${AWS_ACCOUNT_ID}/"
    
    # Check if template already exists
    if aws proton get-environment-template --name "$ENV_TEMPLATE_NAME" &> /dev/null; then
        warning "Environment template already exists. Skipping creation."
    else
        # Register the environment template
        aws proton create-environment-template \
            --name "$ENV_TEMPLATE_NAME" \
            --display-name "Web Application Environment" \
            --description "Shared infrastructure for web applications"
    fi
    
    # Create template version
    log "Creating environment template version..."
    aws proton create-environment-template-version \
        --template-name "$ENV_TEMPLATE_NAME" \
        --description "Initial version of web application environment template" \
        --source "s3={bucket=${PROJECT_NAME}-templates-${AWS_ACCOUNT_ID},key=environment-template.tar.gz}" \
        2>/dev/null || warning "Template version may already exist"
    
    # Wait for template version to be ready
    log "Waiting for environment template version to be ready..."
    aws proton wait environment-template-version-registered \
        --template-name "$ENV_TEMPLATE_NAME" \
        --major-version "1" \
        --minor-version "0" || true
    
    # Publish template
    log "Publishing environment template..."
    aws proton update-environment-template-version \
        --template-name "$ENV_TEMPLATE_NAME" \
        --major-version "1" \
        --minor-version "0" \
        --status PUBLISHED || warning "Template may already be published"
    
    cd ..
    success "Environment template registered and published"
}

# Deploy environment
deploy_environment() {
    log "Deploying test environment..."
    
    # Create environment specification
    cat > environment-spec.yaml << EOF
vpc_cidr: "10.0.0.0/16"
environment_name: "dev-environment"
EOF
    
    # Check if environment already exists
    if aws proton get-environment --name "$ENVIRONMENT_NAME" &> /dev/null; then
        warning "Environment already exists. Skipping creation."
    else
        # Create environment
        aws proton create-environment \
            --name "$ENVIRONMENT_NAME" \
            --template-name "$ENV_TEMPLATE_NAME" \
            --template-major-version "1" \
            --proton-service-role-arn "$PROTON_ROLE_ARN" \
            --spec file://environment-spec.yaml
        
        log "Environment deployment initiated. This may take several minutes..."
        
        # Wait for environment to be ready (with timeout)
        local timeout=1800  # 30 minutes
        local elapsed=0
        local interval=30
        
        while [[ $elapsed -lt $timeout ]]; do
            local status=$(aws proton get-environment --name "$ENVIRONMENT_NAME" --query 'environment.deploymentStatus' --output text)
            
            if [[ "$status" == "SUCCEEDED" ]]; then
                success "Environment deployment completed successfully"
                break
            elif [[ "$status" == "FAILED" ]]; then
                error "Environment deployment failed"
                return 1
            else
                log "Environment deployment status: $status (elapsed: ${elapsed}s)"
                sleep $interval
                elapsed=$((elapsed + interval))
            fi
        done
        
        if [[ $elapsed -ge $timeout ]]; then
            warning "Environment deployment timed out after ${timeout}s"
        fi
    fi
    
    success "Environment deployment initiated: $ENVIRONMENT_NAME"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    # List environment templates
    echo "Environment Templates:"
    aws proton list-environment-templates \
        --query 'templates[*].{Name:name,Status:status}' \
        --output table
    
    # Check template versions
    echo "Environment Template Versions:"
    aws proton list-environment-template-versions \
        --template-name "$ENV_TEMPLATE_NAME" \
        --query 'templateVersions[*].{Version:majorVersion+"."+minorVersion,Status:status}' \
        --output table
    
    # Show environment status
    echo "Environment Status:"
    aws proton get-environment \
        --name "$ENVIRONMENT_NAME" \
        --query 'environment.{Name:name,Status:deploymentStatus,Template:templateName}' \
        --output table
    
    success "Deployment validation completed"
}

# Main deployment function
main() {
    log "Starting AWS Proton and CDK Infrastructure Automation deployment..."
    
    check_prerequisites
    initialize_environment
    create_project_structure
    create_proton_service_role
    create_cdk_constructs
    create_environment_template
    register_proton_templates
    deploy_environment
    validate_deployment
    
    success "Deployment completed successfully!"
    log "Project created in directory: $PROJECT_NAME"
    log "Environment Template: $ENV_TEMPLATE_NAME"
    log "Environment Name: $ENVIRONMENT_NAME"
    log "Proton Service Role: $PROTON_ROLE_ARN"
    
    echo ""
    echo "Next steps:"
    echo "1. Access the AWS Proton console to view your templates"
    echo "2. Create service templates to deploy applications"
    echo "3. Use the self-service interface to deploy services"
    echo "4. Run './destroy.sh' to clean up resources when done"
}

# Run main function
main "$@"