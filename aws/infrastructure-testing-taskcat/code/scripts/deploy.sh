#!/bin/bash

# Infrastructure Testing with TaskCat and CloudFormation - Deployment Script
# This script automates the deployment of TaskCat testing infrastructure

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Check if dry run mode is enabled
DRY_RUN=${DRY_RUN:-false}

if [ "$DRY_RUN" = "true" ]; then
    log_warning "Running in DRY RUN mode - no resources will be created"
fi

# Function to execute commands (respects dry run mode)
execute_command() {
    local command="$1"
    local description="$2"
    
    log "$description"
    
    if [ "$DRY_RUN" = "true" ]; then
        echo "DRY RUN: $command"
        return 0
    else
        eval "$command"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    local major_version=$(echo $aws_version | cut -d. -f1)
    if [ "$major_version" -lt "2" ]; then
        log_warning "AWS CLI v2 is recommended. Current version: $aws_version"
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 is not installed. Please install Python 3.7+."
        exit 1
    fi
    
    # Check Python version
    local python_version=$(python3 --version 2>&1 | cut -d' ' -f2)
    local python_major=$(echo $python_version | cut -d. -f1)
    local python_minor=$(echo $python_version | cut -d. -f2)
    if [ "$python_major" -lt "3" ] || ([ "$python_major" -eq "3" ] && [ "$python_minor" -lt "7" ]); then
        log_error "Python 3.7+ is required. Current version: $python_version"
        exit 1
    fi
    
    # Check pip
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        log_error "pip is not installed. Please install pip."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Set AWS region if not already set
    if [ -z "${AWS_REGION:-}" ]; then
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            log_warning "AWS_REGION not set, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export PROJECT_NAME="taskcat-demo-${random_suffix}"
    export S3_BUCKET_NAME="taskcat-artifacts-${random_suffix}"
    
    log "Environment variables set:"
    log "  AWS_REGION: $AWS_REGION"
    log "  AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
    log "  PROJECT_NAME: $PROJECT_NAME"
    log "  S3_BUCKET_NAME: $S3_BUCKET_NAME"
    
    log_success "Environment setup completed"
}

# Function to install TaskCat
install_taskcat() {
    log "Installing TaskCat..."
    
    # Check if TaskCat is already installed
    if command -v taskcat &> /dev/null; then
        local current_version=$(taskcat --version 2>&1 | head -n1)
        log "TaskCat already installed: $current_version"
        return 0
    fi
    
    # Determine pip command
    local pip_cmd="pip3"
    if command -v pip &> /dev/null; then
        pip_cmd="pip"
    fi
    
    execute_command "$pip_cmd install taskcat" "Installing TaskCat framework"
    execute_command "$pip_cmd install taskcat[console]" "Installing TaskCat console enhancements"
    
    if [ "$DRY_RUN" = "false" ]; then
        # Verify installation
        if taskcat --version &> /dev/null; then
            log_success "TaskCat installed successfully: $(taskcat --version 2>&1 | head -n1)"
        else
            log_error "TaskCat installation failed"
            exit 1
        fi
    fi
}

# Function to create S3 bucket for artifacts
create_s3_bucket() {
    log "Creating S3 bucket for TaskCat artifacts..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${S3_BUCKET_NAME}" &> /dev/null; then
        log_warning "S3 bucket ${S3_BUCKET_NAME} already exists"
        return 0
    fi
    
    # Create bucket with appropriate region handling
    if [ "$AWS_REGION" = "us-east-1" ]; then
        execute_command "aws s3 mb s3://${S3_BUCKET_NAME}" "Creating S3 bucket in us-east-1"
    else
        execute_command "aws s3 mb s3://${S3_BUCKET_NAME} --region ${AWS_REGION}" "Creating S3 bucket in ${AWS_REGION}"
    fi
    
    # Enable versioning
    execute_command "aws s3api put-bucket-versioning --bucket ${S3_BUCKET_NAME} --versioning-configuration Status=Enabled" "Enabling S3 bucket versioning"
    
    # Set bucket encryption
    execute_command "aws s3api put-bucket-encryption --bucket ${S3_BUCKET_NAME} --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'" "Enabling S3 bucket encryption"
    
    log_success "S3 bucket created and configured: ${S3_BUCKET_NAME}"
}

# Function to create project directory structure
create_project_structure() {
    log "Creating project directory structure..."
    
    execute_command "mkdir -p ${PROJECT_NAME}/{templates,tests,ci}" "Creating project directories"
    execute_command "cd ${PROJECT_NAME}" "Changing to project directory"
    
    log_success "Project structure created: ${PROJECT_NAME}"
}

# Function to create CloudFormation templates
create_templates() {
    log "Creating CloudFormation templates..."
    
    # Create basic VPC template
    cat > templates/vpc-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Sample VPC template for TaskCat testing'

Parameters:
  VpcCidr:
    Type: String
    Default: '10.0.0.0/16'
    Description: 'CIDR block for VPC'
  
  EnvironmentName:
    Type: String
    Default: 'TaskCatDemo'
    Description: 'Environment name for resource tagging'
  
  CreateNatGateway:
    Type: String
    Default: 'true'
    AllowedValues: ['true', 'false']
    Description: 'Create NAT Gateway for private subnets'

Conditions:
  CreateNatGatewayCondition: !Equals [!Ref CreateNatGateway, 'true']

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref VpcCidr
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-VPC'
        - Key: Environment
          Value: !Ref EnvironmentName

  InternetGateway:
    Type: AWS::EC2::InternetGateway
    Properties:
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-IGW'

  AttachGateway:
    Type: AWS::EC2::VPCGatewayAttachment
    Properties:
      VpcId: !Ref VPC
      InternetGatewayId: !Ref InternetGateway

  PublicSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [0, !Cidr [!Ref VpcCidr, 4, 8]]
      AvailabilityZone: !Select [0, !GetAZs '']
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-Public-Subnet-1'

  PublicSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [1, !Cidr [!Ref VpcCidr, 4, 8]]
      AvailabilityZone: !Select [1, !GetAZs '']
      MapPublicIpOnLaunch: true
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-Public-Subnet-2'

  PrivateSubnet1:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [2, !Cidr [!Ref VpcCidr, 4, 8]]
      AvailabilityZone: !Select [0, !GetAZs '']
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-Private-Subnet-1'

  PrivateSubnet2:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: !Select [3, !Cidr [!Ref VpcCidr, 4, 8]]
      AvailabilityZone: !Select [1, !GetAZs '']
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-Private-Subnet-2'

  PublicRouteTable:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-Public-Routes'

  DefaultPublicRoute:
    Type: AWS::EC2::Route
    DependsOn: AttachGateway
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

  NatGateway1EIP:
    Type: AWS::EC2::EIP
    Condition: CreateNatGatewayCondition
    DependsOn: AttachGateway
    Properties:
      Domain: vpc

  NatGateway1:
    Type: AWS::EC2::NatGateway
    Condition: CreateNatGatewayCondition
    Properties:
      AllocationId: !GetAtt NatGateway1EIP.AllocationId
      SubnetId: !Ref PublicSubnet1
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-NAT-Gateway-1'

  PrivateRouteTable1:
    Type: AWS::EC2::RouteTable
    Properties:
      VpcId: !Ref VPC
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-Private-Routes-1'

  DefaultPrivateRoute1:
    Type: AWS::EC2::Route
    Condition: CreateNatGatewayCondition
    Properties:
      RouteTableId: !Ref PrivateRouteTable1
      DestinationCidrBlock: 0.0.0.0/0
      NatGatewayId: !Ref NatGateway1

  PrivateSubnet1RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PrivateRouteTable1
      SubnetId: !Ref PrivateSubnet1

  PrivateSubnet2RouteTableAssociation:
    Type: AWS::EC2::SubnetRouteTableAssociation
    Properties:
      RouteTableId: !Ref PrivateRouteTable1
      SubnetId: !Ref PrivateSubnet2

Outputs:
  VPCId:
    Description: 'VPC ID'
    Value: !Ref VPC
    Export:
      Name: !Sub '${EnvironmentName}-VPC-ID'
  
  PublicSubnets:
    Description: 'Public subnet IDs'
    Value: !Join [',', [!Ref PublicSubnet1, !Ref PublicSubnet2]]
    Export:
      Name: !Sub '${EnvironmentName}-Public-Subnets'
  
  PrivateSubnets:
    Description: 'Private subnet IDs'
    Value: !Join [',', [!Ref PrivateSubnet1, !Ref PrivateSubnet2]]
    Export:
      Name: !Sub '${EnvironmentName}-Private-Subnets'
EOF

    # Create advanced template with dynamic parameters
    cat > templates/advanced-vpc-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Advanced VPC template with dynamic parameters for TaskCat'

Parameters:
  VpcCidr:
    Type: String
    Default: '10.0.0.0/16'
    Description: 'CIDR block for VPC'
  
  EnvironmentName:
    Type: String
    Description: 'Environment name for resource tagging'
  
  KeyPairName:
    Type: AWS::EC2::KeyPair::KeyName
    Description: 'EC2 Key Pair for instances'
  
  S3BucketName:
    Type: String
    Description: 'S3 bucket name for application artifacts'
  
  DatabasePassword:
    Type: String
    NoEcho: true
    MinLength: 8
    MaxLength: 41
    Description: 'Database password'

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: !Ref VpcCidr
      EnableDnsHostnames: true
      EnableDnsSupport: true
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-VPC'
        - Key: Environment
          Value: !Ref EnvironmentName
  
  ApplicationS3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref S3BucketName
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-App-Bucket'
        - Key: Environment
          Value: !Ref EnvironmentName
  
  TestSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: 'Security group for testing'
      VpcId: !Ref VPC
      SecurityGroupIngress:
        - IpProtocol: tcp
          FromPort: 80
          ToPort: 80
          CidrIp: 0.0.0.0/0
        - IpProtocol: tcp
          FromPort: 443
          ToPort: 443
          CidrIp: 0.0.0.0/0
      Tags:
        - Key: Name
          Value: !Sub '${EnvironmentName}-Test-SG'

Outputs:
  VPCId:
    Description: 'VPC ID'
    Value: !Ref VPC
    Export:
      Name: !Sub '${EnvironmentName}-VPC-ID'
  
  S3BucketName:
    Description: 'S3 Bucket Name'
    Value: !Ref ApplicationS3Bucket
    Export:
      Name: !Sub '${EnvironmentName}-S3-Bucket'
  
  SecurityGroupId:
    Description: 'Security Group ID'
    Value: !Ref TestSecurityGroup
    Export:
      Name: !Sub '${EnvironmentName}-Security-Group'
EOF

    log_success "CloudFormation templates created"
}

# Function to create TaskCat configuration
create_taskcat_config() {
    log "Creating TaskCat configuration..."
    
    cat > .taskcat.yml << EOF
project:
  name: ${PROJECT_NAME}
  owner: 'taskcat-demo@example.com'
  regions:
    - us-east-1
    - us-west-2
    - eu-west-1

tests:
  vpc-basic-test:
    template: templates/vpc-template.yaml
    parameters:
      VpcCidr: '10.0.0.0/16'
      EnvironmentName: 'TaskCatBasic'
      CreateNatGateway: 'true'
  
  vpc-no-nat-test:
    template: templates/vpc-template.yaml
    parameters:
      VpcCidr: '10.1.0.0/16'
      EnvironmentName: 'TaskCatNoNat'
      CreateNatGateway: 'false'
  
  vpc-custom-cidr-test:
    template: templates/vpc-template.yaml
    parameters:
      VpcCidr: '172.16.0.0/16'
      EnvironmentName: 'TaskCatCustom'
      CreateNatGateway: 'true'

  vpc-dynamic-test:
    template: templates/advanced-vpc-template.yaml
    parameters:
      VpcCidr: '10.2.0.0/16'
      EnvironmentName: \$[taskcat_project_name]
      KeyPairName: \$[taskcat_getkeypair]
      S3BucketName: \$[taskcat_autobucket]
      DatabasePassword: \$[taskcat_genpass_16A]

  vpc-regional-test:
    template: templates/advanced-vpc-template.yaml
    parameters:
      VpcCidr: '10.3.0.0/16'
      EnvironmentName: \$[taskcat_project_name]-\$[taskcat_current_region]
      KeyPairName: \$[taskcat_getkeypair]
      S3BucketName: \$[taskcat_autobucket]
      DatabasePassword: \$[taskcat_genpass_32S]
EOF

    log_success "TaskCat configuration created"
}

# Function to create validation scripts
create_validation_scripts() {
    log "Creating validation scripts..."
    
    execute_command "mkdir -p tests/validation" "Creating validation directory"
    
    cat > tests/validation/test_vpc_resources.py << 'EOF'
#!/usr/bin/env python3
"""
TaskCat test validation script for VPC resources
"""

import boto3
import sys
import json

def test_vpc_resources(stack_name, region):
    """Test VPC resources in the stack"""
    try:
        cf = boto3.client('cloudformation', region_name=region)
        ec2 = boto3.client('ec2', region_name=region)
        
        # Get stack resources
        resources = cf.describe_stack_resources(StackName=stack_name)
        
        vpc_id = None
        subnets = []
        
        # Find VPC and subnets
        for resource in resources['StackResources']:
            if resource['ResourceType'] == 'AWS::EC2::VPC':
                vpc_id = resource['PhysicalResourceId']
            elif resource['ResourceType'] == 'AWS::EC2::Subnet':
                subnets.append(resource['PhysicalResourceId'])
        
        # Validate VPC
        if vpc_id:
            vpc_response = ec2.describe_vpcs(VpcIds=[vpc_id])
            vpc = vpc_response['Vpcs'][0]
            
            # Check VPC state
            if vpc['State'] != 'available':
                print(f"❌ VPC {vpc_id} is not in available state")
                return False
            
            # Check DNS support
            if not vpc.get('EnableDnsSupport', False):
                print(f"❌ VPC {vpc_id} does not have DNS support enabled")
                return False
            
            print(f"✅ VPC {vpc_id} validation passed")
        
        # Validate subnets
        if subnets:
            subnet_response = ec2.describe_subnets(SubnetIds=subnets)
            for subnet in subnet_response['Subnets']:
                if subnet['State'] != 'available':
                    print(f"❌ Subnet {subnet['SubnetId']} is not available")
                    return False
            
            print(f"✅ All {len(subnets)} subnets validation passed")
        
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {str(e)}")
        return False

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python test_vpc_resources.py <stack_name> <region>")
        sys.exit(1)
    
    stack_name = sys.argv[1]
    region = sys.argv[2]
    
    success = test_vpc_resources(stack_name, region)
    sys.exit(0 if success else 1)
EOF

    execute_command "chmod +x tests/validation/test_vpc_resources.py" "Making validation script executable"
    
    log_success "Validation scripts created"
}

# Function to run TaskCat validation
run_taskcat_validation() {
    log "Running TaskCat validation..."
    
    if [ "$DRY_RUN" = "false" ]; then
        # Lint CloudFormation templates
        log "Linting CloudFormation templates..."
        taskcat lint
        
        # Upload templates to S3
        log "Uploading templates to S3..."
        taskcat upload --project-root .
        
        # Run dry-run validation
        log "Running TaskCat dry-run validation..."
        taskcat test run --dry-run
        
        log_success "TaskCat validation completed successfully"
    else
        log "DRY RUN: Would run TaskCat validation"
    fi
}

# Function to run TaskCat tests
run_taskcat_tests() {
    log "Running TaskCat tests..."
    
    if [ "$DRY_RUN" = "false" ]; then
        # Create output directory
        mkdir -p ./taskcat_outputs
        
        # Run tests
        log "Executing TaskCat tests across all configured regions..."
        taskcat test run --output-directory ./taskcat_outputs
        
        # Generate reports
        log "Generating test reports..."
        if [ -d "./taskcat_outputs" ]; then
            find ./taskcat_outputs -name "*.html" -o -name "*.json" | head -5 | while read file; do
                log "Generated report: $(basename $file)"
            done
        fi
        
        log_success "TaskCat tests completed"
    else
        log "DRY RUN: Would run TaskCat tests"
    fi
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary"
    log "=================="
    log "Project Name: $PROJECT_NAME"
    log "S3 Bucket: $S3_BUCKET_NAME"
    log "AWS Region: $AWS_REGION"
    log "AWS Account: $AWS_ACCOUNT_ID"
    
    if [ "$DRY_RUN" = "false" ]; then
        log ""
        log "Next Steps:"
        log "1. Review test results in ./taskcat_outputs/"
        log "2. Open HTML reports in your browser"
        log "3. Run ./destroy.sh to clean up resources when finished"
        log ""
        log "To run additional tests:"
        log "  taskcat test run --output-directory ./taskcat_outputs"
        log ""
        log "To clean up test stacks:"
        log "  taskcat test clean --project-root ."
    fi
    
    log_success "TaskCat infrastructure testing deployment completed!"
}

# Main execution function
main() {
    log "Starting TaskCat Infrastructure Testing Deployment"
    log "=================================================="
    
    # Check if help is requested
    if [[ "$*" == *"--help"* ]] || [[ "$*" == *"-h"* ]]; then
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --dry-run          Run in dry-run mode (no resources created)"
        echo ""
        echo "Environment Variables:"
        echo "  DRY_RUN            Set to 'true' for dry-run mode"
        echo "  AWS_REGION         AWS region to use (default: from AWS CLI config)"
        echo ""
        exit 0
    fi
    
    # Parse command line arguments
    for arg in "$@"; do
        case $arg in
            --dry-run)
                DRY_RUN=true
                ;;
        esac
    done
    
    # Execute deployment steps
    check_prerequisites
    setup_environment
    install_taskcat
    create_s3_bucket
    create_project_structure
    create_templates
    create_taskcat_config
    create_validation_scripts
    run_taskcat_validation
    run_taskcat_tests
    display_summary
}

# Trap errors and cleanup
trap 'log_error "Deployment failed on line $LINENO. Check the logs above for details."' ERR

# Run main function
main "$@"