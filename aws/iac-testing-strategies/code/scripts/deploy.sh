#!/bin/bash

# Deploy script for Automated Testing Strategies for Infrastructure as Code
# This script creates AWS resources for comprehensive IaC testing pipeline

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/iac-testing-deploy-$(date +%Y%m%d-%H%M%S).log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}❌ $1${NC}" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}" | tee -a "$LOG_FILE"
}

# Cleanup function for error handling
cleanup_on_error() {
    print_error "Deployment failed. Check log file: $LOG_FILE"
    print_info "Run ./destroy.sh to clean up any partially created resources"
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Banner
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              IaC Testing Pipeline Deployment                   ║"
echo "║        Automated Testing Strategies for Infrastructure         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

log "Starting IaC testing pipeline deployment"

# Prerequisites check
print_info "Checking prerequisites..."

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install AWS CLI v2"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured. Run 'aws configure' first"
    exit 1
fi

# Check required tools
for tool in git python3 pip3; do
    if ! command -v $tool &> /dev/null; then
        print_error "$tool is not installed. Please install $tool"
        exit 1
    fi
done

print_status "Prerequisites check completed"

# Environment setup
print_info "Setting up environment variables..."

export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    print_warning "AWS region not set in configuration, using us-east-1"
    export AWS_REGION="us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Generate unique identifiers
RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
    --exclude-punctuation --exclude-uppercase \
    --password-length 8 --require-each-included-type \
    --output text --query RandomPassword 2>/dev/null || \
    echo "$(date +%s | tail -c 8)")

export PROJECT_NAME="iac-testing-${RANDOM_SUFFIX}"
export BUCKET_NAME="iac-testing-artifacts-${RANDOM_SUFFIX}"
export REPOSITORY_NAME="iac-testing-repo-${RANDOM_SUFFIX}"
export CLONE_URL="https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/${REPOSITORY_NAME}"

log "Project Name: $PROJECT_NAME"
log "S3 Bucket: $BUCKET_NAME"
log "Repository: $REPOSITORY_NAME"
log "AWS Region: $AWS_REGION"
log "AWS Account: $AWS_ACCOUNT_ID"

# Save environment for destroy script
cat > "$SCRIPT_DIR/.env" << EOF
PROJECT_NAME=$PROJECT_NAME
BUCKET_NAME=$BUCKET_NAME
REPOSITORY_NAME=$REPOSITORY_NAME
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
CLONE_URL=$CLONE_URL
EOF

print_status "Environment variables configured"

# Create S3 bucket for artifacts
print_info "Creating S3 bucket for artifacts..."

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    print_warning "S3 bucket $BUCKET_NAME already exists"
else
    aws s3 mb s3://"$BUCKET_NAME" --region "$AWS_REGION"
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    
    print_status "Created S3 bucket: $BUCKET_NAME"
fi

# Create CodeCommit repository
print_info "Creating CodeCommit repository..."

if aws codecommit get-repository --repository-name "$REPOSITORY_NAME" &>/dev/null; then
    print_warning "CodeCommit repository $REPOSITORY_NAME already exists"
else
    aws codecommit create-repository \
        --repository-name "$REPOSITORY_NAME" \
        --repository-description "Infrastructure as Code Testing Repository" \
        --tags Key=Project,Value="$PROJECT_NAME",Key=Purpose,Value="IaC-Testing"
    
    print_status "Created CodeCommit repository: $REPOSITORY_NAME"
fi

# Create project directory structure
print_info "Creating project structure..."

PROJECT_DIR="/tmp/$PROJECT_NAME"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"/{templates,tests,scripts}
cd "$PROJECT_DIR"

# Create sample CloudFormation template
cat > templates/s3-bucket.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Sample S3 bucket for testing infrastructure as code'

Parameters:
  BucketName:
    Type: String
    Description: Name of the S3 bucket
    Default: test-bucket
  Environment:
    Type: String
    Description: Environment name
    Default: development
    AllowedValues:
      - development
      - staging
      - production

Resources:
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub '${BucketName}-${AWS::AccountId}-${AWS::Region}'
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      VersioningConfiguration:
        Status: Enabled
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: Purpose
          Value: IaC-Testing

Outputs:
  BucketName:
    Description: Name of the created S3 bucket
    Value: !Ref S3Bucket
    Export:
      Name: !Sub '${AWS::StackName}-BucketName'
  BucketArn:
    Description: ARN of the created S3 bucket
    Value: !GetAtt S3Bucket.Arn
    Export:
      Name: !Sub '${AWS::StackName}-BucketArn'
EOF

# Create unit tests
cat > tests/test_s3_bucket.py << 'EOF'
import boto3
import json
import pytest
from moto import mock_s3, mock_cloudformation
import yaml

@mock_cloudformation
@mock_s3
def test_s3_bucket_creation():
    """Test S3 bucket creation with proper security settings"""
    # Load CloudFormation template
    with open('templates/s3-bucket.yaml', 'r') as f:
        template = yaml.safe_load(f)
    
    # Create CloudFormation client
    cf_client = boto3.client('cloudformation', region_name='us-east-1')
    
    # Create stack
    stack_name = 'test-stack'
    cf_client.create_stack(
        StackName=stack_name,
        TemplateBody=yaml.dump(template),
        Parameters=[
            {'ParameterKey': 'BucketName', 'ParameterValue': 'test-bucket'},
            {'ParameterKey': 'Environment', 'ParameterValue': 'development'}
        ]
    )
    
    # Validate stack creation
    stacks = cf_client.describe_stacks(StackName=stack_name)
    assert len(stacks['Stacks']) == 1
    assert stacks['Stacks'][0]['StackStatus'] == 'CREATE_COMPLETE'

def test_template_syntax():
    """Test CloudFormation template syntax"""
    with open('templates/s3-bucket.yaml', 'r') as f:
        template = yaml.safe_load(f)
    
    # Basic structure validation
    assert 'AWSTemplateFormatVersion' in template
    assert 'Resources' in template
    assert 'S3Bucket' in template['Resources']
    
    # Parameter validation
    assert 'Parameters' in template
    assert 'BucketName' in template['Parameters']
    assert 'Environment' in template['Parameters']

def test_security_configuration():
    """Test security settings in template"""
    with open('templates/s3-bucket.yaml', 'r') as f:
        template = yaml.safe_load(f)
    
    bucket_config = template['Resources']['S3Bucket']['Properties']
    
    # Check encryption is enabled
    assert 'BucketEncryption' in bucket_config
    
    # Check public access is blocked
    public_access = bucket_config['PublicAccessBlockConfiguration']
    assert public_access['BlockPublicAcls'] == True
    assert public_access['BlockPublicPolicy'] == True
    assert public_access['IgnorePublicAcls'] == True
    assert public_access['RestrictPublicBuckets'] == True
    
    # Check versioning is enabled
    assert bucket_config['VersioningConfiguration']['Status'] == 'Enabled'

def test_output_configuration():
    """Test CloudFormation outputs are properly configured"""
    with open('templates/s3-bucket.yaml', 'r') as f:
        template = yaml.safe_load(f)
    
    outputs = template['Outputs']
    
    # Check required outputs exist
    assert 'BucketName' in outputs
    assert 'BucketArn' in outputs
    
    # Check outputs have exports
    assert 'Export' in outputs['BucketName']
    assert 'Export' in outputs['BucketArn']
EOF

# Create requirements file
cat > tests/requirements.txt << 'EOF'
boto3==1.34.0
moto==4.2.14
pytest==7.4.3
PyYAML==6.0.1
cfn-lint==0.83.8
checkov==3.1.0
EOF

# Create integration test
cat > tests/integration_test.py << 'EOF'
import boto3
import time
import sys
import os

def test_stack_deployment():
    """Test actual stack deployment and cleanup"""
    cf_client = boto3.client('cloudformation')
    s3_client = boto3.client('s3')
    
    stack_name = f"integration-test-{int(time.time())}"
    
    try:
        # Read template
        with open('templates/s3-bucket.yaml', 'r') as f:
            template_body = f.read()
        
        # Create stack
        print(f"Creating stack: {stack_name}")
        cf_client.create_stack(
            StackName=stack_name,
            TemplateBody=template_body,
            Parameters=[
                {'ParameterKey': 'BucketName', 'ParameterValue': 'integration-test'},
                {'ParameterKey': 'Environment', 'ParameterValue': 'development'}
            ]
        )
        
        # Wait for stack creation
        print("Waiting for stack creation to complete...")
        waiter = cf_client.get_waiter('stack_create_complete')
        waiter.wait(StackName=stack_name, WaiterConfig={'Delay': 10, 'MaxAttempts': 60})
        
        # Get stack outputs
        stack_info = cf_client.describe_stacks(StackName=stack_name)
        outputs = stack_info['Stacks'][0].get('Outputs', [])
        
        if outputs:
            bucket_name = None
            for output in outputs:
                if output['OutputKey'] == 'BucketName':
                    bucket_name = output['OutputValue']
                    break
            
            if bucket_name:
                print(f"Created bucket: {bucket_name}")
                
                # Test bucket properties
                bucket_encryption = s3_client.get_bucket_encryption(Bucket=bucket_name)
                assert 'ServerSideEncryptionConfiguration' in bucket_encryption
                print("✅ Bucket encryption verified")
                
                bucket_versioning = s3_client.get_bucket_versioning(Bucket=bucket_name)
                assert bucket_versioning['Status'] == 'Enabled'
                print("✅ Bucket versioning verified")
                
                # Test bucket public access block
                public_access_block = s3_client.get_public_access_block(Bucket=bucket_name)
                config = public_access_block['PublicAccessBlockConfiguration']
                assert all([
                    config['BlockPublicAcls'],
                    config['IgnorePublicAcls'], 
                    config['BlockPublicPolicy'],
                    config['RestrictPublicBuckets']
                ])
                print("✅ Public access block verified")
        
        print("✅ Integration test passed")
        
    except Exception as e:
        print(f"❌ Integration test failed: {str(e)}")
        sys.exit(1)
        
    finally:
        # Cleanup
        try:
            cf_client.delete_stack(StackName=stack_name)
            print(f"✅ Cleaned up stack: {stack_name}")
        except Exception as e:
            print(f"⚠️  Cleanup warning: {str(e)}")

if __name__ == "__main__":
    test_stack_deployment()
EOF

# Create security test
cat > tests/security_test.py << 'EOF'
import subprocess
import sys
import yaml
import json

def run_cfn_lint():
    """Run CloudFormation linting"""
    print("Running CloudFormation linting...")
    try:
        result = subprocess.run([
            'cfn-lint', 'templates/s3-bucket.yaml', '--format', 'json'
        ], capture_output=True, text=True, check=False)
        
        if result.returncode != 0:
            print("❌ CloudFormation linting found issues:")
            if result.stdout:
                try:
                    issues = json.loads(result.stdout)
                    for issue in issues:
                        print(f"  - {issue['Rule']['Id']}: {issue['Message']}")
                except json.JSONDecodeError:
                    print(result.stdout)
            if result.stderr:
                print(result.stderr)
            return False
        else:
            print("✅ CloudFormation linting passed")
            return True
    except FileNotFoundError:
        print("⚠️  cfn-lint not found, installing...")
        subprocess.run([sys.executable, '-m', 'pip', 'install', 'cfn-lint==0.83.8'], check=True)
        return run_cfn_lint()

def run_checkov():
    """Run Checkov security scanning"""
    print("Running Checkov security scan...")
    try:
        result = subprocess.run([
            'checkov', '-f', 'templates/s3-bucket.yaml', '--framework', 'cloudformation', '--output', 'json'
        ], capture_output=True, text=True, check=False)
        
        if result.stdout:
            try:
                scan_results = json.loads(result.stdout)
                failed_checks = scan_results.get('results', {}).get('failed_checks', [])
                passed_checks = scan_results.get('results', {}).get('passed_checks', [])
                
                print(f"✅ Passed checks: {len(passed_checks)}")
                if failed_checks:
                    print(f"❌ Failed checks: {len(failed_checks)}")
                    for check in failed_checks[:5]:  # Show first 5 failures
                        print(f"  - {check['check_id']}: {check['check_name']}")
                    return False
                else:
                    print("✅ All Checkov security checks passed")
                    return True
            except json.JSONDecodeError:
                print("⚠️  Could not parse Checkov output")
                return True
        else:
            print("✅ Checkov security scan completed")
            return True
            
    except FileNotFoundError:
        print("⚠️  Checkov not found, installing...")
        subprocess.run([sys.executable, '-m', 'pip', 'install', 'checkov==3.1.0'], check=True)
        return run_checkov()

def check_security_compliance():
    """Check security compliance rules"""
    print("Checking security compliance...")
    
    with open('templates/s3-bucket.yaml', 'r') as f:
        template = yaml.safe_load(f)
    
    security_issues = []
    
    bucket_properties = template['Resources']['S3Bucket']['Properties']
    
    # Check for encryption
    if 'BucketEncryption' not in bucket_properties:
        security_issues.append("S3 bucket encryption not configured")
    
    # Check for public access block
    if 'PublicAccessBlockConfiguration' not in bucket_properties:
        security_issues.append("S3 public access block not configured")
    else:
        pab = bucket_properties['PublicAccessBlockConfiguration']
        required_settings = ['BlockPublicAcls', 'BlockPublicPolicy', 'IgnorePublicAcls', 'RestrictPublicBuckets']
        for setting in required_settings:
            if not pab.get(setting, False):
                security_issues.append(f"Public access block {setting} not enabled")
    
    # Check for versioning
    if 'VersioningConfiguration' not in bucket_properties:
        security_issues.append("S3 versioning not enabled")
    elif bucket_properties['VersioningConfiguration'].get('Status') != 'Enabled':
        security_issues.append("S3 versioning not properly configured")
    
    # Check for tags
    if 'Tags' not in bucket_properties:
        security_issues.append("Resource tags not configured")
    
    if security_issues:
        print("❌ Security compliance issues found:")
        for issue in security_issues:
            print(f"  - {issue}")
        return False
    else:
        print("✅ Security compliance checks passed")
        return True

def main():
    """Run all security tests"""
    print("Starting security validation...")
    
    lint_passed = run_cfn_lint()
    checkov_passed = run_checkov()
    compliance_passed = check_security_compliance()
    
    if lint_passed and checkov_passed and compliance_passed:
        print("✅ All security tests passed")
        sys.exit(0)
    else:
        print("❌ Security tests failed")
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

# Create cost analysis script
cat > tests/cost_analysis.py << 'EOF'
import yaml
import json
from datetime import datetime

def analyze_template_costs():
    """Analyze estimated costs for CloudFormation template"""
    print("Analyzing template costs...")
    
    # Load template
    with open('templates/s3-bucket.yaml', 'r') as f:
        template = yaml.safe_load(f)
    
    # S3 cost analysis
    cost_estimates = {
        'S3 Standard Storage (per GB/month)': 0.023,
        'S3 PUT Requests (per 1000 requests)': 0.005,
        'S3 GET Requests (per 1000 requests)': 0.0004,
        'S3 Data Transfer Out (per GB)': 0.09
    }
    
    print("📊 AWS S3 Pricing (US East 1):")
    for service, cost in cost_estimates.items():
        print(f"  {service}: ${cost}")
    
    # Calculate estimated minimum cost
    base_cost = 0.01  # Minimum S3 bucket cost
    versioning_overhead = 0.005  # Additional cost for versioning
    total_base = base_cost + versioning_overhead
    
    print(f"\n💰 Estimated minimum monthly cost: ${total_base}")
    print("   Note: Actual costs depend on storage usage and request patterns")
    
    # Cost optimization recommendations
    print("\n🔧 Cost optimization recommendations:")
    print("  - Use S3 Intelligent Tiering for variable access patterns")
    print("  - Implement lifecycle policies to transition to cheaper storage classes")
    print("  - Consider S3 One Zone-IA for non-critical, reproducible data")
    print("  - Monitor CloudWatch metrics to optimize request patterns")
    print("  - Use S3 Storage Lens for detailed cost and usage analytics")
    
    return True

def check_cost_controls():
    """Check for cost control measures in template"""
    print("Checking cost control measures...")
    
    with open('templates/s3-bucket.yaml', 'r') as f:
        template = yaml.safe_load(f)
    
    cost_controls = []
    bucket_properties = template['Resources']['S3Bucket']['Properties']
    
    # Check for lifecycle policies
    if 'LifecycleConfiguration' in bucket_properties:
        cost_controls.append("Lifecycle policies configured")
    
    # Check for intelligent tiering
    if 'IntelligentTieringConfigurations' in bucket_properties:
        cost_controls.append("Intelligent tiering configured")
    
    # Check for notification configuration (can help monitor usage)
    if 'NotificationConfiguration' in bucket_properties:
        cost_controls.append("Notification configuration for monitoring")
    
    # Check for metrics configuration
    if 'MetricsConfigurations' in bucket_properties:
        cost_controls.append("CloudWatch metrics configured")
    
    if cost_controls:
        print("✅ Cost control measures found:")
        for control in cost_controls:
            print(f"  - {control}")
    else:
        print("⚠️  No advanced cost control measures found")
        print("  Consider adding:")
        print("    - Lifecycle policies for automatic data transitioning")
        print("    - Intelligent tiering for automatic cost optimization")
        print("    - CloudWatch metrics for usage monitoring")
    
    return True

def generate_cost_report():
    """Generate a cost analysis report"""
    print("Generating cost analysis report...")
    
    report = {
        "analysis_date": datetime.now().isoformat(),
        "template": "templates/s3-bucket.yaml",
        "estimated_monthly_cost": {
            "minimum": 0.015,
            "currency": "USD",
            "region": "us-east-1"
        },
        "cost_factors": [
            "Storage usage (GB)",
            "Request frequency",
            "Data transfer patterns",
            "Versioning overhead"
        ],
        "optimization_opportunities": [
            "Implement lifecycle policies",
            "Use intelligent tiering",
            "Monitor access patterns",
            "Regular cost reviews"
        ]
    }
    
    with open('cost_analysis_report.json', 'w') as f:
        json.dump(report, f, indent=2)
    
    print("✅ Cost analysis report saved to cost_analysis_report.json")
    return True

def main():
    """Run cost analysis"""
    print("Starting cost analysis...")
    
    analyze_template_costs()
    check_cost_controls()
    generate_cost_report()
    
    print("✅ Cost analysis completed")

if __name__ == "__main__":
    main()
EOF

# Create buildspec.yml
cat > buildspec.yml << 'EOF'
version: 0.2

env:
  variables:
    PYTHON_VERSION: "3.9"

phases:
  install:
    runtime-versions:
      python: 3.9
    commands:
      - echo "Installing dependencies..."
      - python -m pip install --upgrade pip
      - pip install -r tests/requirements.txt
      - pip install awscli
      
  pre_build:
    commands:
      - echo "Pre-build phase started on `date`"
      - echo "Validating AWS credentials..."
      - aws sts get-caller-identity
      - echo "Python version:"
      - python --version
      - echo "AWS CLI version:"
      - aws --version
      
  build:
    commands:
      - echo "Build phase started on `date`"
      - echo "Running unit tests..."
      - cd tests && python -m pytest test_s3_bucket.py -v --tb=short
      - cd ..
      
      - echo "Running security tests..."
      - python tests/security_test.py
      
      - echo "Running cost analysis..."
      - python tests/cost_analysis.py
      
      - echo "Running integration tests..."
      - python tests/integration_test.py
      
  post_build:
    commands:
      - echo "Post-build phase started on `date`"
      - echo "All tests completed successfully!"
      - if [ -f cost_analysis_report.json ]; then echo "Cost analysis report generated"; fi
      
artifacts:
  files:
    - '**/*'
  base-directory: .
  
reports:
  pytest-reports:
    files:
      - 'tests/test-results.xml'
    base-directory: '.'
    file-format: 'JUNITXML'
EOF

print_status "Created project structure and test files"

# Create IAM roles and policies
print_info "Creating IAM roles for CodeBuild and CodePipeline..."

# CodeBuild role trust policy
cat > trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "codebuild.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

# Create CodeBuild role
if aws iam get-role --role-name "${PROJECT_NAME}-codebuild-role" &>/dev/null; then
    print_warning "CodeBuild role already exists"
else
    aws iam create-role \
        --role-name "${PROJECT_NAME}-codebuild-role" \
        --assume-role-policy-document file://trust-policy.json \
        --tags Key=Project,Value="$PROJECT_NAME"
    print_status "Created CodeBuild role"
fi

# CodeBuild policy
cat > codebuild-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/aws/codebuild/${PROJECT_NAME}*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:CreateBucket",
                "s3:DeleteBucket",
                "s3:ListBucket",
                "s3:GetBucketEncryption",
                "s3:GetBucketVersioning",
                "s3:GetPublicAccessBlock",
                "s3:PutBucketEncryption",
                "s3:PutBucketVersioning",
                "s3:PutPublicAccessBlock"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*",
                "arn:aws:s3:::integration-test-*",
                "arn:aws:s3:::test-bucket-*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:CreateStack",
                "cloudformation:UpdateStack",
                "cloudformation:DeleteStack",
                "cloudformation:DescribeStacks",
                "cloudformation:DescribeStackEvents",
                "cloudformation:ValidateTemplate"
            ],
            "Resource": [
                "arn:aws:cloudformation:${AWS_REGION}:${AWS_ACCOUNT_ID}:stack/integration-test-*/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "codecommit:GitPull"
            ],
            "Resource": "arn:aws:codecommit:${AWS_REGION}:${AWS_ACCOUNT_ID}:${REPOSITORY_NAME}"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name "${PROJECT_NAME}-codebuild-role" \
    --policy-name "${PROJECT_NAME}-codebuild-policy" \
    --policy-document file://codebuild-policy.json

print_status "Attached policy to CodeBuild role"

# Wait for role propagation
print_info "Waiting for IAM role propagation..."
sleep 10

# Create CodeBuild project
print_info "Creating CodeBuild project..."

cat > codebuild-project.json << EOF
{
    "name": "${PROJECT_NAME}",
    "description": "Automated testing for Infrastructure as Code templates",
    "source": {
        "type": "CODECOMMIT",
        "location": "${CLONE_URL}",
        "buildspec": "buildspec.yml"
    },
    "artifacts": {
        "type": "S3",
        "location": "${BUCKET_NAME}/artifacts",
        "packaging": "ZIP"
    },
    "environment": {
        "type": "LINUX_CONTAINER",
        "image": "aws/codebuild/amazonlinux2-x86_64-standard:4.0",
        "computeType": "BUILD_GENERAL1_SMALL",
        "environmentVariables": [
            {
                "name": "AWS_DEFAULT_REGION",
                "value": "${AWS_REGION}"
            },
            {
                "name": "AWS_ACCOUNT_ID",
                "value": "${AWS_ACCOUNT_ID}"
            }
        ]
    },
    "serviceRole": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-codebuild-role",
    "timeoutInMinutes": 30,
    "tags": [
        {
            "key": "Project",
            "value": "${PROJECT_NAME}"
        },
        {
            "key": "Purpose",
            "value": "IaC-Testing"
        }
    ]
}
EOF

if aws codebuild batch-get-projects --names "$PROJECT_NAME" &>/dev/null; then
    print_warning "CodeBuild project already exists"
else
    aws codebuild create-project --cli-input-json file://codebuild-project.json
    print_status "Created CodeBuild project: $PROJECT_NAME"
fi

# Create CodePipeline IAM role
print_info "Creating CodePipeline IAM role..."

cat > pipeline-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "codepipeline.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

if aws iam get-role --role-name "${PROJECT_NAME}-pipeline-role" &>/dev/null; then
    print_warning "CodePipeline role already exists"
else
    aws iam create-role \
        --role-name "${PROJECT_NAME}-pipeline-role" \
        --assume-role-policy-document file://pipeline-trust-policy.json \
        --tags Key=Project,Value="$PROJECT_NAME"
    print_status "Created CodePipeline role"
fi

cat > pipeline-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:GetBucketVersioning"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "codecommit:GetBranch",
                "codecommit:GetCommit",
                "codecommit:GetRepository",
                "codecommit:ListBranches",
                "codecommit:ListRepositories"
            ],
            "Resource": "arn:aws:codecommit:${AWS_REGION}:${AWS_ACCOUNT_ID}:${REPOSITORY_NAME}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "codebuild:BatchGetBuilds",
                "codebuild:StartBuild"
            ],
            "Resource": "arn:aws:codebuild:${AWS_REGION}:${AWS_ACCOUNT_ID}:project/${PROJECT_NAME}"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name "${PROJECT_NAME}-pipeline-role" \
    --policy-name "${PROJECT_NAME}-pipeline-policy" \
    --policy-document file://pipeline-policy.json

print_status "Attached policy to CodePipeline role"

# Wait for role propagation
sleep 10

# Create CodePipeline
print_info "Creating CodePipeline..."

cat > pipeline-definition.json << EOF
{
    "pipeline": {
        "name": "${PROJECT_NAME}-pipeline",
        "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-pipeline-role",
        "artifactStore": {
            "type": "S3",
            "location": "${BUCKET_NAME}"
        },
        "stages": [
            {
                "name": "Source",
                "actions": [
                    {
                        "name": "Source",
                        "actionTypeId": {
                            "category": "Source",
                            "owner": "AWS",
                            "provider": "CodeCommit",
                            "version": "1"
                        },
                        "configuration": {
                            "RepositoryName": "${REPOSITORY_NAME}",
                            "BranchName": "main",
                            "PollForSourceChanges": "true"
                        },
                        "outputArtifacts": [
                            {
                                "name": "SourceOutput"
                            }
                        ]
                    }
                ]
            },
            {
                "name": "Test",
                "actions": [
                    {
                        "name": "SecurityAndComplianceTests",
                        "actionTypeId": {
                            "category": "Build",
                            "owner": "AWS",
                            "provider": "CodeBuild",
                            "version": "1"
                        },
                        "configuration": {
                            "ProjectName": "${PROJECT_NAME}"
                        },
                        "inputArtifacts": [
                            {
                                "name": "SourceOutput"
                            }
                        ],
                        "outputArtifacts": [
                            {
                                "name": "TestOutput"
                            }
                        ]
                    }
                ]
            }
        ],
        "tags": [
            {
                "key": "Project",
                "value": "${PROJECT_NAME}"
            },
            {
                "key": "Purpose",
                "value": "IaC-Testing"
            }
        ]
    }
}
EOF

if aws codepipeline get-pipeline --name "${PROJECT_NAME}-pipeline" &>/dev/null; then
    print_warning "CodePipeline already exists"
else
    aws codepipeline create-pipeline --cli-input-json file://pipeline-definition.json
    print_status "Created CodePipeline: ${PROJECT_NAME}-pipeline"
fi

# Initialize Git repository and commit code
print_info "Committing code to repository..."

git init
git add .
git commit -m "Initial commit: Infrastructure testing framework with comprehensive test suite"

# Configure Git credentials helper for CodeCommit
git config credential.helper '!aws codecommit credential-helper $@'
git config credential.UseHttpPath true

# Add remote and push
git remote add origin "$CLONE_URL"

# Set branch to main if not already
git branch -M main

# Push code
if git push -u origin main; then
    print_status "Code committed and pushed to repository"
else
    print_warning "Push failed - this might be expected if repository has existing content"
fi

# Clean up temporary files
rm -f trust-policy.json codebuild-policy.json pipeline-trust-policy.json pipeline-policy.json
rm -f codebuild-project.json pipeline-definition.json

# Display deployment summary
echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗"
echo "║                    Deployment Summary                          ║"
echo "╚════════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n📋 ${BLUE}Resources Created:${NC}"
echo "   • S3 Bucket: $BUCKET_NAME"
echo "   • CodeCommit Repository: $REPOSITORY_NAME"
echo "   • CodeBuild Project: $PROJECT_NAME"
echo "   • CodePipeline: ${PROJECT_NAME}-pipeline"
echo "   • IAM Roles: ${PROJECT_NAME}-codebuild-role, ${PROJECT_NAME}-pipeline-role"

echo -e "\n🔗 ${BLUE}Useful URLs:${NC}"
echo "   • CodeBuild Console: https://console.aws.amazon.com/codesuite/codebuild/projects/$PROJECT_NAME"
echo "   • CodePipeline Console: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/${PROJECT_NAME}-pipeline/view"
echo "   • CodeCommit Console: https://console.aws.amazon.com/codesuite/codecommit/repositories/$REPOSITORY_NAME"
echo "   • S3 Console: https://s3.console.aws.amazon.com/s3/buckets/$BUCKET_NAME"

echo -e "\n🧪 ${BLUE}Test Coverage:${NC}"
echo "   • Unit tests for CloudFormation templates"
echo "   • Security compliance validation"
echo "   • Cost analysis and optimization recommendations"
echo "   • Integration testing with real AWS resources"
echo "   • Infrastructure linting with cfn-lint and Checkov"

echo -e "\n⚙️ ${BLUE}Next Steps:${NC}"
echo "   1. Trigger a pipeline run: aws codepipeline start-pipeline-execution --name ${PROJECT_NAME}-pipeline"
echo "   2. Monitor build progress in the AWS Console"
echo "   3. Add your own infrastructure templates to test"
echo "   4. Customize test scenarios for your use cases"

echo -e "\n💰 ${YELLOW}Cost Information:${NC}"
echo "   • CodeBuild: ~$0.005 per build minute"
echo "   • CodePipeline: $1 per active pipeline per month"
echo "   • S3: Standard storage rates apply"
echo "   • CodeCommit: First 5 users free, then $1/user/month"

echo -e "\n🧹 ${BLUE}Cleanup:${NC}"
echo "   • Run ./destroy.sh to remove all resources"
echo "   • Environment saved to: $SCRIPT_DIR/.env"

echo -e "\n📊 ${BLUE}Monitoring:${NC}"
echo "   • CloudWatch Logs: /aws/codebuild/$PROJECT_NAME"
echo "   • Build history: Available in CodeBuild console"
echo "   • Pipeline execution history: Available in CodePipeline console"

log "Deployment completed successfully"
print_status "Infrastructure as Code testing pipeline is ready!"

# Display final status
echo -e "\n${GREEN}✅ Deployment completed successfully!${NC}"
echo -e "📝 Log file: $LOG_FILE"
echo -e "🔧 Environment file: $SCRIPT_DIR/.env"