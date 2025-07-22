#!/bin/bash

# CloudFormation Nested Stacks Deployment Script
# This script deploys a complete nested stack infrastructure with network, security, and application layers

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message"
            ;;
        "DEBUG")
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} ${timestamp} - $message"
            fi
            ;;
    esac
}

# Help function
show_help() {
    cat << EOF
CloudFormation Nested Stacks Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -e, --environment ENVIRONMENT    Environment name (development, staging, production) [default: development]
    -p, --project PROJECT           Project name [default: webapp]
    -r, --region REGION             AWS region [default: current AWS CLI region]
    -b, --bucket BUCKET             S3 bucket name for templates [auto-generated if not provided]
    -s, --stack-name STACK          Root stack name [auto-generated if not provided]
    -d, --dry-run                   Show what would be deployed without actually deploying
    -f, --force                     Force deployment even if resources exist
    -v, --verbose                   Enable verbose logging
    -h, --help                      Show this help message

EXAMPLES:
    $0                              # Deploy with defaults
    $0 -e production -p myapp       # Deploy production environment
    $0 -d                          # Dry run to see what would be deployed
    $0 -v                          # Verbose output

EOF
}

# Default values
ENVIRONMENT="development"
PROJECT_NAME="webapp"
AWS_REGION=""
TEMPLATE_BUCKET_NAME=""
ROOT_STACK_NAME=""
DRY_RUN=false
FORCE=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -p|--project)
            PROJECT_NAME="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -b|--bucket)
            TEMPLATE_BUCKET_NAME="$2"
            shift 2
            ;;
        -s|--stack-name)
            ROOT_STACK_NAME="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            DEBUG=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(development|staging|production)$ ]]; then
    log "ERROR" "Invalid environment: $ENVIRONMENT. Must be development, staging, or production"
    exit 1
fi

log "INFO" "Starting CloudFormation nested stacks deployment"
log "INFO" "Environment: $ENVIRONMENT"
log "INFO" "Project: $PROJECT_NAME"

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS credentials not configured or invalid. Please run 'aws configure'"
        exit 1
    fi
    
    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_REGION" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log "ERROR" "AWS region not set. Please set it with 'aws configure' or use -r option"
            exit 1
        fi
    fi
    
    log "INFO" "AWS Account ID: $AWS_ACCOUNT_ID"
    log "INFO" "AWS Region: $AWS_REGION"
    
    # Check required permissions (basic check)
    log "DEBUG" "Checking CloudFormation permissions..."
    if ! aws cloudformation list-stacks --max-items 1 &> /dev/null; then
        log "ERROR" "Insufficient CloudFormation permissions"
        exit 1
    fi
    
    log "DEBUG" "Checking S3 permissions..."
    if ! aws s3 ls &> /dev/null; then
        log "ERROR" "Insufficient S3 permissions"
        exit 1
    fi
    
    log "INFO" "Prerequisites check completed successfully"
}

# Generate unique identifiers
generate_identifiers() {
    log "INFO" "Generating unique identifiers..."
    
    # Generate random suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo $(date +%s | tail -c 8))
    
    # Set default names if not provided
    if [[ -z "$ROOT_STACK_NAME" ]]; then
        ROOT_STACK_NAME="nested-infrastructure-${RANDOM_SUFFIX}"
    fi
    
    if [[ -z "$TEMPLATE_BUCKET_NAME" ]]; then
        TEMPLATE_BUCKET_NAME="cloudformation-templates-${RANDOM_SUFFIX}"
    fi
    
    log "INFO" "Root Stack Name: $ROOT_STACK_NAME"
    log "INFO" "Template Bucket: $TEMPLATE_BUCKET_NAME"
    log "DEBUG" "Random Suffix: $RANDOM_SUFFIX"
}

# Check if resources already exist
check_existing_resources() {
    log "INFO" "Checking for existing resources..."
    
    # Check if stack exists
    if aws cloudformation describe-stacks --stack-name "$ROOT_STACK_NAME" &> /dev/null; then
        if [[ "$FORCE" == "false" ]]; then
            log "ERROR" "Stack '$ROOT_STACK_NAME' already exists. Use --force to update it."
            exit 1
        else
            log "WARN" "Stack '$ROOT_STACK_NAME' exists and will be updated"
        fi
    fi
    
    # Check if bucket exists
    if aws s3 ls "s3://$TEMPLATE_BUCKET_NAME" &> /dev/null; then
        log "WARN" "S3 bucket '$TEMPLATE_BUCKET_NAME' already exists, will reuse it"
    fi
}

# Create S3 bucket for templates
create_template_bucket() {
    log "INFO" "Creating S3 bucket for CloudFormation templates..."
    
    if ! aws s3 ls "s3://$TEMPLATE_BUCKET_NAME" &> /dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] Would create S3 bucket: $TEMPLATE_BUCKET_NAME"
            return
        fi
        
        # Create bucket with region-specific command
        if [[ "$AWS_REGION" == "us-east-1" ]]; then
            aws s3 mb "s3://$TEMPLATE_BUCKET_NAME"
        else
            aws s3 mb "s3://$TEMPLATE_BUCKET_NAME" --region "$AWS_REGION"
        fi
        
        # Enable versioning for template history
        aws s3api put-bucket-versioning \
            --bucket "$TEMPLATE_BUCKET_NAME" \
            --versioning-configuration Status=Enabled
        
        log "INFO" "S3 bucket created: $TEMPLATE_BUCKET_NAME"
    else
        log "INFO" "Using existing S3 bucket: $TEMPLATE_BUCKET_NAME"
    fi
}

# Create CloudFormation templates
create_templates() {
    log "INFO" "Creating CloudFormation templates..."
    
    local template_dir="$(dirname "$0")/../templates"
    mkdir -p "$template_dir"
    
    # Network template
    log "DEBUG" "Creating network template..."
    cat > "$template_dir/network-template.yaml" << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Network infrastructure layer with VPC, subnets, and routing'

Parameters:
  Environment:
    Type: String
    Default: development
    AllowedValues: [development, staging, production]
    Description: Environment name
  
  ProjectName:
    Type: String
    Description: Project name for resource tagging
  
  VpcCidr:
    Type: String
    Default: '10.0.0.0/16'
    Description: CIDR block for VPC
    AllowedPattern: '^10\.\d{1,3}\.\d{1,3}\.0/16$'
  
  PublicSubnet1Cidr:
    Type: String
    Default: '10.0.1.0/24'
    Description: CIDR block for public subnet 1
  
  PublicSubnet2Cidr:
    Type: String
    Default: '10.0.2.0/24'
    Description: CIDR block for public subnet 2
  
  PrivateSubnet1Cidr:
    Type: String
    Default: '10.0.10.0/24'
    Description: CIDR block for private subnet 1
  
  PrivateSubnet2Cidr:
    Type: String
    Default: '10.0.20.0/24'
    Description: CIDR block for private subnet 2

Resources:
  # VPC
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref VpcCidr
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-vpc'
        - Key: Environment
          Value: !Ref Environment
        - Key: Project
          Value: !Ref ProjectName

  # Internet Gateway
  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-igw'
        - Key: Environment
          Value: !Ref Environment

  InternetGatewayAttachment:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      InternetGatewayId: !Ref InternetGateway
      VpcId: !Ref VPC

  # Public Subnets
  PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs '']
      CidrBlock: !Ref PublicSubnet1Cidr
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-public-subnet-1'
        - Key: Environment
          Value: !Ref Environment
        - Key: Type
          Value: Public

  PublicSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [1, !GetAZs '']
      CidrBlock: !Ref PublicSubnet2Cidr
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-public-subnet-2'
        - Key: Environment
          Value: !Ref Environment
        - Key: Type
          Value: Public

  # Private Subnets
  PrivateSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [0, !GetAZs '']
      CidrBlock: !Ref PrivateSubnet1Cidr
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-private-subnet-1'
        - Key: Environment
          Value: !Ref Environment
        - Key: Type
          Value: Private

  PrivateSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      AvailabilityZone: !Select [1, !GetAZs '']
      CidrBlock: !Ref PrivateSubnet2Cidr
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-private-subnet-2'
        - Key: Environment
          Value: !Ref Environment
        - Key: Type
          Value: Private

  # NAT Gateways
  NatGateway1EIP:
    Type: AWS::EC2::EIP
    DependsOn: InternetGatewayAttachment
    Properties:
      Domain: vpc
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-nat-eip-1'

  NatGateway2EIP:
    Type: AWS::EC2::EIP
    DependsOn: InternetGatewayAttachment
    Properties:
      Domain: vpc
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-nat-eip-2'

  NatGateway1:
    Type: AWS::EC2::NatGateway
    Properties:
      AllocationId: !GetAtt NatGateway1EIP.AllocationId
      SubnetId: !Ref PublicSubnet1
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-nat-gateway-1'

  NatGateway2:
    Type: AWS::EC2::NatGateway
    Properties:
      AllocationId: !GetAtt NatGateway2EIP.AllocationId
      SubnetId: !Ref PublicSubnet2
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-nat-gateway-2'

  # Route Tables
  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-public-routes'

  DefaultPublicRoute:
    Type: AWS::EC2::Route
    DependsOn: InternetGatewayAttachment
    Properties:
      RouteTableId: !Ref PublicRouteTable
      DestinationCidrBlock: 0.0.0.0/0
      GatewayId: !Ref InternetGateway

  PublicSubnet1RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PublicRouteTable
      SubnetId: !Ref PublicSubnet1

  PublicSubnet2RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PublicRouteTable
      SubnetId: !Ref PublicSubnet2

  PrivateRouteTable1:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-private-routes-1'

  DefaultPrivateRoute1:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref PrivateRouteTable1
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref NatGateway1

  PrivateSubnet1RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PrivateRouteTable1
      SubnetId: !Ref PrivateSubnet1

  PrivateRouteTable2:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-private-routes-2'

  DefaultPrivateRoute2:
    Type: AWS::EC2::Route
    Properties:
      RouteTableId: !Ref PrivateRouteTable2
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref NatGateway2

  PrivateSubnet2RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PrivateRouteTable2
      SubnetId: !Ref PrivateSubnet2

Outputs:
  VpcId:
    Description: VPC ID
    Value: !Ref VPC
    Export:
      Name: !Sub '${AWS::StackName}-VpcId'
  
  VpcCidr:
    Description: VPC CIDR Block
    Value: !Ref VpcCidr
    Export:
      Name: !Sub '${AWS::StackName}-VpcCidr'
  
  PublicSubnet1Id:
    Description: Public Subnet 1 ID
    Value: !Ref PublicSubnet1
    Export:
      Name: !Sub '${AWS::StackName}-PublicSubnet1Id'
  
  PublicSubnet2Id:
    Description: Public Subnet 2 ID
    Value: !Ref PublicSubnet2
    Export:
      Name: !Sub '${AWS::StackName}-PublicSubnet2Id'
  
  PrivateSubnet1Id:
    Description: Private Subnet 1 ID
    Value: !Ref PrivateSubnet1
    Export:
      Name: !Sub '${AWS::StackName}-PrivateSubnet1Id'
  
  PrivateSubnet2Id:
    Description: Private Subnet 2 ID
    Value: !Ref PrivateSubnet2
    Export:
      Name: !Sub '${AWS::StackName}-PrivateSubnet2Id'
  
  PublicSubnets:
    Description: List of public subnet IDs
    Value: !Join [',', [!Ref PublicSubnet1, !Ref PublicSubnet2]]
    Export:
      Name: !Sub '${AWS::StackName}-PublicSubnets'
  
  PrivateSubnets:
    Description: List of private subnet IDs
    Value: !Join [',', [!Ref PrivateSubnet1, !Ref PrivateSubnet2]]
    Export:
      Name: !Sub '${AWS::StackName}-PrivateSubnets'
EOF

    # Security template
    log "DEBUG" "Creating security template..."
    cat > "$template_dir/security-template.yaml" << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Security layer with IAM roles, security groups, and policies'

Parameters:
  Environment:
    Type: String
    Default: development
    AllowedValues: [development, staging, production]
    Description: Environment name
  
  ProjectName:
    Type: String
    Description: Project name for resource tagging
  
  VpcId:
    Type: String
    Description: VPC ID from network stack
  
  VpcCidr:
    Type: String
    Description: VPC CIDR block for security group rules

Resources:
  # Application Load Balancer Security Group
  ALBSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupName: !Sub '${ProjectName}-${Environment}-alb-sg'
      GroupDescription: Security group for Application Load Balancer
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
          Description: Allow HTTP traffic from internet
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0
          Description: Allow HTTPS traffic from internet
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-alb-sg'
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: LoadBalancer

  # Application Security Group
  ApplicationSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupName: !Sub '${ProjectName}-${Environment}-app-sg'
      GroupDescription: Security group for application instances
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          SourceSecurityGroupId: !Ref ALBSecurityGroup
          Description: Allow HTTP traffic from ALB
        - IpProtocol: tcp
          FromPort: 22
          ToPort: 22
          SourceSecurityGroupId: !Ref BastionSecurityGroup
          Description: Allow SSH from bastion host
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-app-sg'
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Application

  # Bastion Host Security Group
  BastionSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupName: !Sub '${ProjectName}-${Environment}-bastion-sg'
      GroupDescription: Security group for bastion host
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 22
          ToPort: 22
          CidrIp: 0.0.0.0/0
          Description: Allow SSH access from internet
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-bastion-sg'
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Bastion

  # Database Security Group
  DatabaseSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupName: !Sub '${ProjectName}-${Environment}-db-sg'
      GroupDescription: Security group for database
      VpcId: !Ref VpcId
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 3306
          ToPort: 3306
          SourceSecurityGroupId: !Ref ApplicationSecurityGroup
          Description: Allow MySQL access from application
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-db-sg'
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Database

  # IAM Role for EC2 instances
  EC2InstanceRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${ProjectName}-${Environment}-ec2-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: ec2.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
        - arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
      Policies:
        - PolicyName: S3AccessPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - s3:GetObject
                  - s3:PutObject
                Resource: !Sub 'arn:aws:s3:::${ProjectName}-${Environment}-*/*'
              - Effect: Allow
                Action:
                  - s3:ListBucket
                Resource: !Sub 'arn:aws:s3:::${ProjectName}-${Environment}-*'
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Compute

  # Instance Profile for EC2 role
  EC2InstanceProfile:
    Type: AWS::IAM::InstanceProfile
    Properties:
      InstanceProfileName: !Sub '${ProjectName}-${Environment}-ec2-profile'
      Roles:
        - !Ref EC2InstanceRole

  # IAM Role for RDS Enhanced Monitoring
  RDSEnhancedMonitoringRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: !Sub '${ProjectName}-${Environment}-rds-monitoring-role'
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: monitoring.rds.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Database

Outputs:
  ALBSecurityGroupId:
    Description: Application Load Balancer Security Group ID
    Value: !Ref ALBSecurityGroup
    Export:
      Name: !Sub '${AWS::StackName}-ALBSecurityGroupId'
  
  ApplicationSecurityGroupId:
    Description: Application Security Group ID
    Value: !Ref ApplicationSecurityGroup
    Export:
      Name: !Sub '${AWS::StackName}-ApplicationSecurityGroupId'
  
  BastionSecurityGroupId:
    Description: Bastion Security Group ID
    Value: !Ref BastionSecurityGroup
    Export:
      Name: !Sub '${AWS::StackName}-BastionSecurityGroupId'
  
  DatabaseSecurityGroupId:
    Description: Database Security Group ID
    Value: !Ref DatabaseSecurityGroup
    Export:
      Name: !Sub '${AWS::StackName}-DatabaseSecurityGroupId'
  
  EC2InstanceRoleArn:
    Description: EC2 Instance Role ARN
    Value: !GetAtt EC2InstanceRole.Arn
    Export:
      Name: !Sub '${AWS::StackName}-EC2InstanceRoleArn'
  
  EC2InstanceProfileArn:
    Description: EC2 Instance Profile ARN
    Value: !GetAtt EC2InstanceProfile.Arn
    Export:
      Name: !Sub '${AWS::StackName}-EC2InstanceProfileArn'
  
  RDSMonitoringRoleArn:
    Description: RDS Enhanced Monitoring Role ARN
    Value: !GetAtt RDSEnhancedMonitoringRole.Arn
    Export:
      Name: !Sub '${AWS::StackName}-RDSMonitoringRoleArn'
EOF

    # Application template
    log "DEBUG" "Creating application template..."
    cat > "$template_dir/application-template.yaml" << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Application layer with load balancer, auto scaling, and database'

Parameters:
  Environment:
    Type: String
    Default: development
    AllowedValues: [development, staging, production]
    Description: Environment name
  
  ProjectName:
    Type: String
    Description: Project name for resource tagging
  
  VpcId:
    Type: String
    Description: VPC ID from network stack
  
  PublicSubnets:
    Type: CommaDelimitedList
    Description: List of public subnet IDs for load balancer
  
  PrivateSubnets:
    Type: CommaDelimitedList
    Description: List of private subnet IDs for application
  
  ALBSecurityGroupId:
    Type: String
    Description: Security group ID for Application Load Balancer
  
  ApplicationSecurityGroupId:
    Type: String
    Description: Security group ID for application instances
  
  DatabaseSecurityGroupId:
    Type: String
    Description: Security group ID for database
  
  EC2InstanceProfileArn:
    Type: String
    Description: EC2 instance profile ARN
  
  RDSMonitoringRoleArn:
    Type: String
    Description: RDS monitoring role ARN

Mappings:
  EnvironmentConfig:
    development:
      InstanceType: t3.micro
      MinSize: 1
      MaxSize: 2
      DesiredCapacity: 1
      DBInstanceClass: db.t3.micro
      DBAllocatedStorage: 20
    staging:
      InstanceType: t3.small
      MinSize: 2
      MaxSize: 4
      DesiredCapacity: 2
      DBInstanceClass: db.t3.small
      DBAllocatedStorage: 50
    production:
      InstanceType: t3.medium
      MinSize: 2
      MaxSize: 6
      DesiredCapacity: 3
      DBInstanceClass: db.t3.medium
      DBAllocatedStorage: 100

Resources:
  # Application Load Balancer
  ApplicationLoadBalancer:
    Type: AWS::ElasticLoadBalancingV2::LoadBalancer
    Properties:
      Name: !Sub '${ProjectName}-${Environment}-alb'
      Scheme: internet-facing
      Type: application
      Subnets: !Ref PublicSubnets
      SecurityGroups:
        - !Ref ALBSecurityGroupId
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-alb'
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: LoadBalancer

  # Target Group
  ApplicationTargetGroup:
    Type: AWS::ElasticLoadBalancingV2::TargetGroup
    Properties:
      Name: !Sub '${ProjectName}-${Environment}-tg'
      Port: 80
      Protocol: HTTP
      VpcId: !Ref VpcId
      HealthCheckPath: /health
      HealthCheckProtocol: HTTP
      HealthCheckIntervalSeconds: 30
      HealthCheckTimeoutSeconds: 5
      HealthyThresholdCount: 2
      UnhealthyThresholdCount: 3
      TargetGroupAttributes:
        - Key: deregistration_delay.timeout_seconds
          Value: '300'
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-tg'
        - Key: Environment
          Value: !Ref Environment

  # Load Balancer Listener
  ApplicationListener:
    Type: AWS::ElasticLoadBalancingV2::Listener
    Properties:
      DefaultActions:
        - Type: forward
          TargetGroupArn: !Ref ApplicationTargetGroup
      LoadBalancerArn: !Ref ApplicationLoadBalancer
      Port: 80
      Protocol: HTTP

  # Launch Template
  ApplicationLaunchTemplate:
    Type: AWS::EC2::LaunchTemplate
    Properties:
      LaunchTemplateName: !Sub '${ProjectName}-${Environment}-template'
      LaunchTemplateData:
        ImageId: !Sub '{{resolve:ssm:/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2}}'
        InstanceType: !FindInMap [EnvironmentConfig, !Ref Environment, InstanceType]
        IamInstanceProfile:
          Arn: !Ref EC2InstanceProfileArn
        SecurityGroupIds:
          - !Ref ApplicationSecurityGroupId
        UserData:
          Fn::Base64: !Sub |
            #!/bin/bash
            yum update -y
            yum install -y httpd
            systemctl start httpd
            systemctl enable httpd
            
            # Create simple health check endpoint
            echo '<html><body><h1>Application Running</h1><p>Environment: ${Environment}</p></body></html>' > /var/www/html/index.html
            echo 'OK' > /var/www/html/health
        TagSpecifications:
          - ResourceType: instance
            Tags:
              - Key: Name
                Value: !Sub '${ProjectName}-${Environment}-instance'
              - Key: Environment
                Value: !Ref Environment
              - Key: Component
                Value: Application

  # Auto Scaling Group
  ApplicationAutoScalingGroup:
    Type: AWS::AutoScaling::AutoScalingGroup
    Properties:
      AutoScalingGroupName: !Sub '${ProjectName}-${Environment}-asg'
      VPCZoneIdentifier: !Ref PrivateSubnets
      LaunchTemplate:
        LaunchTemplateId: !Ref ApplicationLaunchTemplate
        Version: !GetAtt ApplicationLaunchTemplate.LatestVersionNumber
      MinSize: !FindInMap [EnvironmentConfig, !Ref Environment, MinSize]
      MaxSize: !FindInMap [EnvironmentConfig, !Ref Environment, MaxSize]
      DesiredCapacity: !FindInMap [EnvironmentConfig, !Ref Environment, DesiredCapacity]
      TargetGroupARNs:
        - !Ref ApplicationTargetGroup
      HealthCheckType: ELB
      HealthCheckGracePeriod: 300
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-asg'
          PropagateAtLaunch: false
        - Key: Environment
          Value: !Ref Environment
          PropagateAtLaunch: true
        - Key: Component
          Value: Application
          PropagateAtLaunch: true

  # Database Subnet Group
  DatabaseSubnetGroup:
    Type: AWS::RDS::DBSubnetGroup
    Properties:
      DBSubnetGroupName: !Sub '${ProjectName}-${Environment}-db-subnet-group'
      DBSubnetGroupDescription: Subnet group for RDS database
      SubnetIds: !Ref PrivateSubnets
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-db-subnet-group'
        - Key: Environment
          Value: !Ref Environment

  # Database Secret
  DatabaseSecret:
    Type: AWS::SecretsManager::Secret
    Properties:
      Name: !Sub '${ProjectName}-${Environment}-db-secret'
      Description: Database credentials
      GenerateSecretString:
        SecretStringTemplate: '{"username": "admin"}'
        GenerateStringKey: 'password'
        PasswordLength: 16
        ExcludeCharacters: '"@/\'
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Database

  # RDS Database Instance
  DatabaseInstance:
    Type: AWS::RDS::DBInstance
    DeletionPolicy: Delete
    Properties:
      DBInstanceIdentifier: !Sub '${ProjectName}-${Environment}-db'
      DBInstanceClass: !FindInMap [EnvironmentConfig, !Ref Environment, DBInstanceClass]
      Engine: mysql
      EngineVersion: '8.0.35'
      MasterUsername: admin
      MasterUserPassword: !Sub '{{resolve:secretsmanager:${DatabaseSecret}:SecretString:password}}'
      AllocatedStorage: !FindInMap [EnvironmentConfig, !Ref Environment, DBAllocatedStorage]
      StorageType: gp2
      StorageEncrypted: true
      VPCSecurityGroups:
        - !Ref DatabaseSecurityGroupId
      DBSubnetGroupName: !Ref DatabaseSubnetGroup
      BackupRetentionPeriod: 7
      MultiAZ: !If [IsProduction, true, false]
      MonitoringInterval: 60
      MonitoringRoleArn: !Ref RDSMonitoringRoleArn
      EnablePerformanceInsights: true
      DeletionProtection: !If [IsProduction, true, false]
      Tags:
        - Key: Name
          Value: !Sub '${ProjectName}-${Environment}-db'
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Database

Conditions:
  IsProduction: !Equals [!Ref Environment, production]

Outputs:
  LoadBalancerDNS:
    Description: Application Load Balancer DNS name
    Value: !GetAtt ApplicationLoadBalancer.DNSName
    Export:
      Name: !Sub '${AWS::StackName}-LoadBalancerDNS'
  
  LoadBalancerArn:
    Description: Application Load Balancer ARN
    Value: !Ref ApplicationLoadBalancer
    Export:
      Name: !Sub '${AWS::StackName}-LoadBalancerArn'
  
  AutoScalingGroupName:
    Description: Auto Scaling Group name
    Value: !Ref ApplicationAutoScalingGroup
    Export:
      Name: !Sub '${AWS::StackName}-AutoScalingGroupName'
  
  DatabaseEndpoint:
    Description: RDS database endpoint
    Value: !GetAtt DatabaseInstance.Endpoint.Address
    Export:
      Name: !Sub '${AWS::StackName}-DatabaseEndpoint'
  
  DatabasePort:
    Description: RDS database port
    Value: !GetAtt DatabaseInstance.Endpoint.Port
    Export:
      Name: !Sub '${AWS::StackName}-DatabasePort'
  
  DatabaseSecretArn:
    Description: Database secret ARN
    Value: !Ref DatabaseSecret
    Export:
      Name: !Sub '${AWS::StackName}-DatabaseSecretArn'
EOF

    # Root template
    log "DEBUG" "Creating root template..."
    cat > "$template_dir/root-stack-template.yaml" << EOF
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Root stack for nested infrastructure deployment'

Parameters:
  Environment:
    Type: String
    Default: development
    AllowedValues: [development, staging, production]
    Description: Environment name
  
  ProjectName:
    Type: String
    Default: webapp
    Description: Project name for resource tagging
  
  TemplateBucketName:
    Type: String
    Description: S3 bucket containing nested stack templates
  
  VpcCidr:
    Type: String
    Default: '10.0.0.0/16'
    Description: CIDR block for VPC
    AllowedPattern: '^10\.\d{1,3}\.\d{1,3}\.0/16$'

Resources:
  # Network Infrastructure Stack
  NetworkStack:
    Type: AWS::CloudFormation::Stack
    Properties:
      TemplateURL: !Sub 'https://\${TemplateBucketName}.s3.\${AWS::Region}.amazonaws.com/network-template.yaml'
      Parameters:
        Environment: !Ref Environment
        ProjectName: !Ref ProjectName
        VpcCidr: !Ref VpcCidr
        PublicSubnet1Cidr: !Select [0, !Cidr [!Ref VpcCidr, 4, 8]]
        PublicSubnet2Cidr: !Select [1, !Cidr [!Ref VpcCidr, 4, 8]]
        PrivateSubnet1Cidr: !Select [2, !Cidr [!Ref VpcCidr, 4, 8]]
        PrivateSubnet2Cidr: !Select [3, !Cidr [!Ref VpcCidr, 4, 8]]
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Network
        - Key: StackType
          Value: Nested

  # Security Infrastructure Stack
  SecurityStack:
    Type: AWS::CloudFormation::Stack
    DependsOn: NetworkStack
    Properties:
      TemplateURL: !Sub 'https://\${TemplateBucketName}.s3.\${AWS::Region}.amazonaws.com/security-template.yaml'
      Parameters:
        Environment: !Ref Environment
        ProjectName: !Ref ProjectName
        VpcId: !GetAtt NetworkStack.Outputs.VpcId
        VpcCidr: !GetAtt NetworkStack.Outputs.VpcCidr
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Security
        - Key: StackType
          Value: Nested

  # Application Infrastructure Stack
  ApplicationStack:
    Type: AWS::CloudFormation::Stack
    DependsOn: [NetworkStack, SecurityStack]
    Properties:
      TemplateURL: !Sub 'https://\${TemplateBucketName}.s3.\${AWS::Region}.amazonaws.com/application-template.yaml'
      Parameters:
        Environment: !Ref Environment
        ProjectName: !Ref ProjectName
        VpcId: !GetAtt NetworkStack.Outputs.VpcId
        PublicSubnets: !GetAtt NetworkStack.Outputs.PublicSubnets
        PrivateSubnets: !GetAtt NetworkStack.Outputs.PrivateSubnets
        ALBSecurityGroupId: !GetAtt SecurityStack.Outputs.ALBSecurityGroupId
        ApplicationSecurityGroupId: !GetAtt SecurityStack.Outputs.ApplicationSecurityGroupId
        DatabaseSecurityGroupId: !GetAtt SecurityStack.Outputs.DatabaseSecurityGroupId
        EC2InstanceProfileArn: !GetAtt SecurityStack.Outputs.EC2InstanceProfileArn
        RDSMonitoringRoleArn: !GetAtt SecurityStack.Outputs.RDSMonitoringRoleArn
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: Component
          Value: Application
        - Key: StackType
          Value: Nested

Outputs:
  NetworkStackId:
    Description: Network stack ID
    Value: !Ref NetworkStack
    Export:
      Name: !Sub '\${AWS::StackName}-NetworkStackId'
  
  SecurityStackId:
    Description: Security stack ID
    Value: !Ref SecurityStack
    Export:
      Name: !Sub '\${AWS::StackName}-SecurityStackId'
  
  ApplicationStackId:
    Description: Application stack ID
    Value: !Ref ApplicationStack
    Export:
      Name: !Sub '\${AWS::StackName}-ApplicationStackId'
  
  VpcId:
    Description: VPC ID
    Value: !GetAtt NetworkStack.Outputs.VpcId
    Export:
      Name: !Sub '\${AWS::StackName}-VpcId'
  
  ApplicationURL:
    Description: Application URL
    Value: !Sub 'http://\${ApplicationStack.Outputs.LoadBalancerDNS}'
    Export:
      Name: !Sub '\${AWS::StackName}-ApplicationURL'
  
  DatabaseEndpoint:
    Description: Database endpoint
    Value: !GetAtt ApplicationStack.Outputs.DatabaseEndpoint
    Export:
      Name: !Sub '\${AWS::StackName}-DatabaseEndpoint'
EOF

    log "INFO" "CloudFormation templates created successfully"
}

# Upload templates to S3
upload_templates() {
    log "INFO" "Uploading CloudFormation templates to S3..."
    
    local template_dir="$(dirname "$0")/../templates"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would upload templates to s3://$TEMPLATE_BUCKET_NAME/"
        return
    fi
    
    # Upload individual templates
    aws s3 cp "$template_dir/network-template.yaml" "s3://$TEMPLATE_BUCKET_NAME/"
    aws s3 cp "$template_dir/security-template.yaml" "s3://$TEMPLATE_BUCKET_NAME/"
    aws s3 cp "$template_dir/application-template.yaml" "s3://$TEMPLATE_BUCKET_NAME/"
    
    log "INFO" "Templates uploaded successfully"
}

# Deploy the nested stack
deploy_stack() {
    log "INFO" "Deploying CloudFormation nested stack..."
    
    local template_dir="$(dirname "$0")/../templates"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would deploy stack: $ROOT_STACK_NAME"
        log "INFO" "[DRY-RUN] Template: $template_dir/root-stack-template.yaml"
        log "INFO" "[DRY-RUN] Environment: $ENVIRONMENT"
        log "INFO" "[DRY-RUN] Project: $PROJECT_NAME"
        log "INFO" "[DRY-RUN] Bucket: $TEMPLATE_BUCKET_NAME"
        return
    fi
    
    # Check if stack exists to determine create vs update
    local stack_operation="create-stack"
    if aws cloudformation describe-stacks --stack-name "$ROOT_STACK_NAME" &> /dev/null; then
        stack_operation="update-stack"
        log "INFO" "Stack exists, performing update..."
    else
        log "INFO" "Creating new stack..."
    fi
    
    # Deploy the stack
    aws cloudformation $stack_operation \
        --stack-name "$ROOT_STACK_NAME" \
        --template-body "file://$template_dir/root-stack-template.yaml" \
        --parameters ParameterKey=Environment,ParameterValue="$ENVIRONMENT" \
                    ParameterKey=ProjectName,ParameterValue="$PROJECT_NAME" \
                    ParameterKey=TemplateBucketName,ParameterValue="$TEMPLATE_BUCKET_NAME" \
        --capabilities CAPABILITY_NAMED_IAM \
        --tags Key=Environment,Value="$ENVIRONMENT" \
               Key=Project,Value="$PROJECT_NAME" \
               Key=ManagedBy,Value=CloudFormation
    
    log "INFO" "Stack deployment initiated..."
    
    # Wait for stack operation to complete
    local wait_operation="stack-create-complete"
    if [[ "$stack_operation" == "update-stack" ]]; then
        wait_operation="stack-update-complete"
    fi
    
    log "INFO" "Waiting for stack operation to complete (this may take 10-15 minutes)..."
    if aws cloudformation wait $wait_operation --stack-name "$ROOT_STACK_NAME"; then
        log "INFO" "Stack deployment completed successfully!"
    else
        log "ERROR" "Stack deployment failed"
        exit 1
    fi
}

# Verify deployment
verify_deployment() {
    log "INFO" "Verifying deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would verify deployment"
        return
    fi
    
    # Check stack status
    local stack_status=$(aws cloudformation describe-stacks \
        --stack-name "$ROOT_STACK_NAME" \
        --query 'Stacks[0].StackStatus' --output text)
    
    log "INFO" "Root stack status: $stack_status"
    
    # Get stack outputs
    log "INFO" "Stack outputs:"
    aws cloudformation describe-stacks \
        --stack-name "$ROOT_STACK_NAME" \
        --query 'Stacks[0].Outputs[].{OutputKey:OutputKey,OutputValue:OutputValue}' \
        --output table
    
    # Test application URL if available
    local app_url=$(aws cloudformation describe-stacks \
        --stack-name "$ROOT_STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApplicationURL`].OutputValue' \
        --output text)
    
    if [[ -n "$app_url" && "$app_url" != "None" ]]; then
        log "INFO" "Testing application accessibility at: $app_url"
        if curl -f -s "$app_url/health" > /dev/null; then
            log "INFO" "✅ Application is accessible and healthy"
        else
            log "WARN" "Application may not be ready yet (this is normal immediately after deployment)"
        fi
    fi
}

# Generate deployment summary
generate_summary() {
    log "INFO" "Generating deployment summary..."
    
    local summary_file="$(dirname "$0")/../deployment-summary.json"
    
    cat > "$summary_file" << EOF
{
  "deployment": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "environment": "$ENVIRONMENT",
    "projectName": "$PROJECT_NAME",
    "region": "$AWS_REGION",
    "accountId": "$AWS_ACCOUNT_ID",
    "stackName": "$ROOT_STACK_NAME",
    "templateBucket": "$TEMPLATE_BUCKET_NAME",
    "dryRun": $DRY_RUN
  }
}
EOF
    
    log "INFO" "Deployment summary saved to: $summary_file"
}

# Main execution
main() {
    log "INFO" "=== CloudFormation Nested Stacks Deployment Started ==="
    
    check_prerequisites
    generate_identifiers
    check_existing_resources
    create_template_bucket
    create_templates
    upload_templates
    deploy_stack
    verify_deployment
    generate_summary
    
    log "INFO" "=== Deployment Completed Successfully ==="
    log "INFO" "Stack Name: $ROOT_STACK_NAME"
    log "INFO" "Environment: $ENVIRONMENT"
    log "INFO" "Region: $AWS_REGION"
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log "INFO" "To access your application, check the ApplicationURL output above"
        log "INFO" "To clean up resources, run: ./destroy.sh --stack-name $ROOT_STACK_NAME"
    fi
}

# Run main function
main "$@"