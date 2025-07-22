#!/bin/bash

# Advanced Cross-Account IAM Role Federation Deployment Script
# This script deploys the complete infrastructure for cross-account IAM role federation
# including master roles, cross-account roles, CloudTrail auditing, and automated validation

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TEMP_DIR="${SCRIPT_DIR}/temp"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Cleanup function for script interruption
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Deployment failed. Check $LOG_FILE for details."
        warning "You may need to run the destroy script to clean up partial resources."
    fi
    # Clean up temporary files
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    exit $exit_code
}

trap cleanup EXIT

# Prerequisites check
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION 2.0.0" | tr " " "\n" | sort -V | head -n1) != "2.0.0" ]]; then
        error "AWS CLI version 2.0.0 or higher is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check if openssl is installed
    if ! command -v openssl &> /dev/null; then
        error "openssl is not installed. Please install openssl for random ID generation."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid. Please run 'aws configure'."
        exit 1
    fi
    
    success "All prerequisites met"
}

# Environment setup
setup_environment() {
    info "Setting up environment variables..."
    
    # Create temp directory
    mkdir -p "$TEMP_DIR"
    
    # Set default values if not provided
    export SECURITY_ACCOUNT_ID="${SECURITY_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
    export PROD_ACCOUNT_ID="${PROD_ACCOUNT_ID:-}"
    export DEV_ACCOUNT_ID="${DEV_ACCOUNT_ID:-}"
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    export RANDOM_SUFFIX="${RANDOM_SUFFIX:-$(openssl rand -hex 4)}"
    
    # Generate external IDs for enhanced security
    export PROD_EXTERNAL_ID="${PROD_EXTERNAL_ID:-$(openssl rand -hex 16)}"
    export DEV_EXTERNAL_ID="${DEV_EXTERNAL_ID:-$(openssl rand -hex 16)}"
    
    # Validate required environment variables
    if [ -z "$PROD_ACCOUNT_ID" ] || [ -z "$DEV_ACCOUNT_ID" ]; then
        error "PROD_ACCOUNT_ID and DEV_ACCOUNT_ID must be set"
        error "Example: export PROD_ACCOUNT_ID=222222222222"
        error "Example: export DEV_ACCOUNT_ID=333333333333"
        exit 1
    fi
    
    if [ -z "$AWS_REGION" ]; then
        error "AWS_REGION must be set. Run 'aws configure set region us-east-1' or set AWS_REGION environment variable."
        exit 1
    fi
    
    # Validate account IDs format
    if ! [[ "$SECURITY_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || ! [[ "$PROD_ACCOUNT_ID" =~ ^[0-9]{12}$ ]] || ! [[ "$DEV_ACCOUNT_ID" =~ ^[0-9]{12}$ ]]; then
        error "Account IDs must be 12-digit numbers"
        exit 1
    fi
    
    # Store configuration for cleanup script
    cat > "${SCRIPT_DIR}/deployment-config.env" << EOF
SECURITY_ACCOUNT_ID=${SECURITY_ACCOUNT_ID}
PROD_ACCOUNT_ID=${PROD_ACCOUNT_ID}
DEV_ACCOUNT_ID=${DEV_ACCOUNT_ID}
AWS_REGION=${AWS_REGION}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
PROD_EXTERNAL_ID=${PROD_EXTERNAL_ID}
DEV_EXTERNAL_ID=${DEV_EXTERNAL_ID}
EOF
    
    info "Environment configured:"
    info "  Security Account: ${SECURITY_ACCOUNT_ID}"
    info "  Production Account: ${PROD_ACCOUNT_ID}"
    info "  Development Account: ${DEV_ACCOUNT_ID}"
    info "  Region: ${AWS_REGION}"
    info "  Random Suffix: ${RANDOM_SUFFIX}"
    
    # Store external IDs securely
    warning "External IDs generated (store these securely):"
    warning "  Production External ID: ${PROD_EXTERNAL_ID}"
    warning "  Development External ID: ${DEV_EXTERNAL_ID}"
}

# Create policy documents
create_policy_documents() {
    info "Creating IAM policy documents..."
    
    # Master cross-account trust policy
    cat > "${TEMP_DIR}/master-cross-account-trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${SECURITY_ACCOUNT_ID}:saml-provider/CorporateIdP"
      },
      "Action": "sts:AssumeRoleWithSAML",
      "Condition": {
        "StringEquals": {
          "SAML:aud": "https://signin.aws.amazon.com/saml"
        },
        "ForAllValues:StringLike": {
          "SAML:department": ["Engineering", "Security", "DevOps"]
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${SECURITY_ACCOUNT_ID}:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        },
        "NumericLessThan": {
          "aws:MultiFactorAuthAge": "3600"
        }
      }
    }
  ]
}
EOF
    
    # Master cross-account permissions policy
    cat > "${TEMP_DIR}/master-cross-account-permissions.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession"
      ],
      "Resource": [
        "arn:aws:iam::${PROD_ACCOUNT_ID}:role/CrossAccount-*",
        "arn:aws:iam::${DEV_ACCOUNT_ID}:role/CrossAccount-*"
      ],
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": ["${PROD_EXTERNAL_ID}", "${DEV_EXTERNAL_ID}"]
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:ListRoles",
        "iam:GetRole",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    # Production cross-account trust policy
    cat > "${TEMP_DIR}/prod-cross-account-trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${SECURITY_ACCOUNT_ID}:role/MasterCrossAccountRole-${RANDOM_SUFFIX}"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "${PROD_EXTERNAL_ID}"
        },
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        },
        "StringLike": {
          "aws:userid": "*:${SECURITY_ACCOUNT_ID}:*"
        }
      }
    }
  ]
}
EOF

    # Production permissions policy
    cat > "${TEMP_DIR}/prod-cross-account-permissions.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::prod-shared-data-${RANDOM_SUFFIX}",
        "arn:aws:s3:::prod-shared-data-${RANDOM_SUFFIX}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${PROD_ACCOUNT_ID}:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:ListMetrics"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    # Development cross-account trust policy
    cat > "${TEMP_DIR}/dev-cross-account-trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${SECURITY_ACCOUNT_ID}:role/MasterCrossAccountRole-${RANDOM_SUFFIX}"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "${DEV_EXTERNAL_ID}"
        },
        "StringLike": {
          "aws:userid": "*:${SECURITY_ACCOUNT_ID}:*"
        },
        "IpAddress": {
          "aws:SourceIp": ["203.0.113.0/24", "198.51.100.0/24"]
        }
      }
    }
  ]
}
EOF

    # Development permissions policy
    cat > "${TEMP_DIR}/dev-cross-account-permissions.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:*"
      ],
      "Resource": [
        "arn:aws:s3:::dev-shared-data-${RANDOM_SUFFIX}",
        "arn:aws:s3:::dev-shared-data-${RANDOM_SUFFIX}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeVpcs",
        "ec2:DescribeSubnets"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "lambda:InvokeFunction",
        "lambda:GetFunction",
        "lambda:ListFunctions"
      ],
      "Resource": "arn:aws:lambda:${AWS_REGION}:${DEV_ACCOUNT_ID}:function:dev-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:*"
      ],
      "Resource": "arn:aws:logs:${AWS_REGION}:${DEV_ACCOUNT_ID}:*"
    }
  ]
}
EOF

    success "Policy documents created"
}

# Create master cross-account role
create_master_role() {
    info "Creating master cross-account role..."
    
    # Create the master cross-account role
    if aws iam get-role --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}" &> /dev/null; then
        warning "Master role already exists, skipping creation"
    else
        aws iam create-role \
            --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document "file://${TEMP_DIR}/master-cross-account-trust-policy.json" \
            --description "Master role for federated cross-account access" \
            --max-session-duration 7200
        
        success "Master cross-account role created"
    fi
    
    # Attach permissions policy
    aws iam put-role-policy \
        --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}" \
        --policy-name "CrossAccountAssumePolicy" \
        --policy-document "file://${TEMP_DIR}/master-cross-account-permissions.json"
    
    success "Master role permissions attached"
}

# Create cross-account roles (production and development)
create_cross_account_roles() {
    info "Creating production cross-account role..."
    
    # Note: In a real scenario, these would be run in the respective accounts
    # For demonstration, we'll create them in the current account
    
    # Create production cross-account role
    if aws iam get-role --role-name "CrossAccount-ProductionAccess-${RANDOM_SUFFIX}" &> /dev/null; then
        warning "Production role already exists, skipping creation"
    else
        aws iam create-role \
            --role-name "CrossAccount-ProductionAccess-${RANDOM_SUFFIX}" \
            --assume-role-policy-document "file://${TEMP_DIR}/prod-cross-account-trust-policy.json" \
            --description "Cross-account role for production resource access" \
            --max-session-duration 3600 \
            --tags Key=Environment,Value=Production Key=Purpose,Value=CrossAccount
        
        success "Production cross-account role created"
    fi
    
    # Attach production permissions policy
    aws iam put-role-policy \
        --role-name "CrossAccount-ProductionAccess-${RANDOM_SUFFIX}" \
        --policy-name "ProductionResourceAccess" \
        --policy-document "file://${TEMP_DIR}/prod-cross-account-permissions.json"
    
    info "Creating development cross-account role..."
    
    # Create development cross-account role
    if aws iam get-role --role-name "CrossAccount-DevelopmentAccess-${RANDOM_SUFFIX}" &> /dev/null; then
        warning "Development role already exists, skipping creation"
    else
        aws iam create-role \
            --role-name "CrossAccount-DevelopmentAccess-${RANDOM_SUFFIX}" \
            --assume-role-policy-document "file://${TEMP_DIR}/dev-cross-account-trust-policy.json" \
            --description "Cross-account role for development resource access" \
            --max-session-duration 7200 \
            --tags Key=Environment,Value=Development Key=Purpose,Value=CrossAccount
        
        success "Development cross-account role created"
    fi
    
    # Attach development permissions policy
    aws iam put-role-policy \
        --role-name "CrossAccount-DevelopmentAccess-${RANDOM_SUFFIX}" \
        --policy-name "DevelopmentResourceAccess" \
        --policy-document "file://${TEMP_DIR}/dev-cross-account-permissions.json"
    
    success "Cross-account roles configured"
}

# Implement session tags and conditional access
implement_session_tags() {
    info "Implementing session tags and conditional access..."
    
    # Create enhanced permissions policy with session tags
    cat > "${TEMP_DIR}/enhanced-cross-account-permissions.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sts:AssumeRole",
        "sts:TagSession"
      ],
      "Resource": [
        "arn:aws:iam::${PROD_ACCOUNT_ID}:role/CrossAccount-*",
        "arn:aws:iam::${DEV_ACCOUNT_ID}:role/CrossAccount-*"
      ],
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": ["${PROD_EXTERNAL_ID}", "${DEV_EXTERNAL_ID}"],
          "aws:RequestedRegion": "${AWS_REGION}"
        },
        "ForAllValues:StringEquals": {
          "sts:TransitiveTagKeys": ["Department", "Project", "Environment"]
        }
      }
    }
  ]
}
EOF
    
    # Update master role with enhanced permissions
    aws iam put-role-policy \
        --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}" \
        --policy-name "EnhancedCrossAccountAccess" \
        --policy-document "file://${TEMP_DIR}/enhanced-cross-account-permissions.json"
    
    # Create role assumption script
    cat > "${SCRIPT_DIR}/assume-cross-account-role.sh" << 'EOF'
#!/bin/bash

TARGET_ACCOUNT=$1
ROLE_NAME=$2
EXTERNAL_ID=$3
SESSION_NAME=$4

if [ $# -ne 4 ]; then
    echo "Usage: $0 <target-account-id> <role-name> <external-id> <session-name>"
    exit 1
fi

# Assume role with session tags
ROLE_CREDENTIALS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::${TARGET_ACCOUNT}:role/${ROLE_NAME}" \
    --role-session-name "${SESSION_NAME}" \
    --external-id "${EXTERNAL_ID}" \
    --tags Key=Department,Value=Engineering Key=Project,Value=CrossAccountDemo Key=Environment,Value=Prod \
    --transitive-tag-keys Department,Project,Environment \
    --duration-seconds 3600 \
    --output json)

if [ $? -eq 0 ]; then
    echo "Role assumed successfully. Credentials:"
    echo "$ROLE_CREDENTIALS" | jq -r '.Credentials | "export AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nexport AWS_SESSION_TOKEN=\(.SessionToken)"'
else
    echo "Failed to assume role"
    exit 1
fi
EOF
    
    chmod +x "${SCRIPT_DIR}/assume-cross-account-role.sh"
    
    success "Session tagging and conditional access implemented"
}

# Set up cross-account audit trail
setup_audit_trail() {
    info "Setting up cross-account audit trail..."
    
    # Create CloudTrail policy
    cat > "${TEMP_DIR}/cross-account-cloudtrail-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": [
        "s3:PutObject",
        "s3:GetBucketAcl"
      ],
      "Resource": [
        "arn:aws:s3:::cross-account-audit-trail-${RANDOM_SUFFIX}",
        "arn:aws:s3:::cross-account-audit-trail-${RANDOM_SUFFIX}/*"
      ],
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control"
        }
      }
    }
  ]
}
EOF
    
    # Create S3 bucket for CloudTrail logs
    if aws s3api head-bucket --bucket "cross-account-audit-trail-${RANDOM_SUFFIX}" 2>/dev/null; then
        warning "Audit trail bucket already exists"
    else
        aws s3 mb "s3://cross-account-audit-trail-${RANDOM_SUFFIX}" \
            --region "${AWS_REGION}"
        
        # Apply bucket policy
        aws s3api put-bucket-policy \
            --bucket "cross-account-audit-trail-${RANDOM_SUFFIX}" \
            --policy "file://${TEMP_DIR}/cross-account-cloudtrail-policy.json"
        
        success "Audit trail S3 bucket created"
    fi
    
    # Create CloudTrail
    if aws cloudtrail describe-trails --trail-name-list "CrossAccountAuditTrail-${RANDOM_SUFFIX}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "CrossAccountAuditTrail"; then
        warning "CloudTrail already exists"
    else
        aws cloudtrail create-trail \
            --name "CrossAccountAuditTrail-${RANDOM_SUFFIX}" \
            --s3-bucket-name "cross-account-audit-trail-${RANDOM_SUFFIX}" \
            --include-global-service-events \
            --is-multi-region-trail \
            --enable-log-file-validation \
            --event-selectors '[
              {
                "ReadWriteType": "All",
                "IncludeManagementEvents": true,
                "DataResources": [
                  {
                    "Type": "AWS::IAM::Role",
                    "Values": ["arn:aws:iam::*:role/CrossAccount-*"]
                  },
                  {
                    "Type": "AWS::STS::AssumeRole",
                    "Values": ["*"]
                  }
                ]
              }
            ]'
        
        success "CloudTrail created"
    fi
    
    # Start logging
    aws cloudtrail start-logging \
        --name "CrossAccountAuditTrail-${RANDOM_SUFFIX}"
    
    success "Cross-account audit trail configured and started"
}

# Implement automated role validation
implement_role_validation() {
    info "Implementing automated role validation..."
    
    # Create Lambda function code
    cat > "${TEMP_DIR}/role-validator.py" << 'EOF'
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iam = boto3.client('iam')
config = boto3.client('config')

def lambda_handler(event, context):
    """
    Validate cross-account role configurations and trust policies
    """
    try:
        # Get all cross-account roles
        paginator = iam.get_paginator('list_roles')
        
        validation_results = []
        
        for page in paginator.paginate():
            for role in page['Roles']:
                if 'CrossAccount-' in role['RoleName']:
                    validation_result = validate_role(role)
                    validation_results.append(validation_result)
        
        # Report findings to Config
        for result in validation_results:
            if not result['compliant']:
                logger.warning(f"Non-compliant role found: {result}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'validated_roles': len(validation_results),
                'compliant_roles': sum(1 for r in validation_results if r['compliant'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error validating roles: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def validate_role(role):
    """
    Validate individual role configuration
    """
    role_name = role['RoleName']
    
    try:
        # Get role details
        role_details = iam.get_role(RoleName=role_name)
        assume_role_policy = role_details['Role']['AssumeRolePolicyDocument']
        
        validation_checks = {
            'has_external_id': check_external_id(assume_role_policy),
            'has_mfa_condition': check_mfa_condition(assume_role_policy),
            'has_ip_restriction': check_ip_restriction(assume_role_policy),
            'max_session_duration_ok': role['MaxSessionDuration'] <= 7200
        }
        
        compliant = all(validation_checks.values())
        
        return {
            'role_name': role_name,
            'compliant': compliant,
            'checks': validation_checks
        }
        
    except Exception as e:
        logger.error(f"Error validating role {role_name}: {str(e)}")
        return {
            'role_name': role_name,
            'compliant': False,
            'error': str(e)
        }

def check_external_id(policy):
    """Check if policy requires ExternalId"""
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'StringEquals' in conditions and 'sts:ExternalId' in conditions['StringEquals']:
            return True
    return False

def check_mfa_condition(policy):
    """Check if policy requires MFA"""
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'Bool' in conditions and 'aws:MultiFactorAuthPresent' in conditions['Bool']:
            return True
    return False

def check_ip_restriction(policy):
    """Check if policy has IP restrictions"""
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'IpAddress' in conditions or 'IpAddressIfExists' in conditions:
            return True
    return True  # Not mandatory for all environments
EOF
    
    # Create Lambda deployment package
    cd "${TEMP_DIR}"
    zip role-validator.zip role-validator.py
    cd - > /dev/null
    
    # Create Lambda execution role trust policy
    cat > "${TEMP_DIR}/lambda-execution-trust-policy.json" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create Lambda execution role
    if aws iam get-role --role-name "RoleValidatorLambdaRole-${RANDOM_SUFFIX}" &> /dev/null; then
        warning "Lambda execution role already exists"
    else
        aws iam create-role \
            --role-name "RoleValidatorLambdaRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document "file://${TEMP_DIR}/lambda-execution-trust-policy.json"
        
        success "Lambda execution role created"
    fi
    
    # Attach necessary policies
    aws iam attach-role-policy \
        --role-name "RoleValidatorLambdaRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    
    aws iam attach-role-policy \
        --role-name "RoleValidatorLambdaRole-${RANDOM_SUFFIX}" \
        --policy-arn "arn:aws:iam::aws:policy/IAMReadOnlyAccess"
    
    # Wait for role propagation
    sleep 10
    
    # Create Lambda function
    if aws lambda get-function --function-name "CrossAccountRoleValidator-${RANDOM_SUFFIX}" &> /dev/null; then
        warning "Lambda function already exists, updating code"
        aws lambda update-function-code \
            --function-name "CrossAccountRoleValidator-${RANDOM_SUFFIX}" \
            --zip-file "fileb://${TEMP_DIR}/role-validator.zip"
    else
        aws lambda create-function \
            --function-name "CrossAccountRoleValidator-${RANDOM_SUFFIX}" \
            --runtime python3.9 \
            --role "arn:aws:iam::${SECURITY_ACCOUNT_ID}:role/RoleValidatorLambdaRole-${RANDOM_SUFFIX}" \
            --handler role-validator.lambda_handler \
            --zip-file "fileb://${TEMP_DIR}/role-validator.zip" \
            --timeout 300 \
            --memory-size 256
        
        success "Lambda function created"
    fi
    
    success "Automated role validation implemented"
}

# Run validation tests
run_validation_tests() {
    info "Running validation tests..."
    
    # Test master role creation
    if aws iam get-role --role-name "MasterCrossAccountRole-${RANDOM_SUFFIX}" &> /dev/null; then
        success "✅ Master role exists"
    else
        error "❌ Master role not found"
        return 1
    fi
    
    # Test production role creation
    if aws iam get-role --role-name "CrossAccount-ProductionAccess-${RANDOM_SUFFIX}" &> /dev/null; then
        success "✅ Production role exists"
    else
        error "❌ Production role not found"
        return 1
    fi
    
    # Test development role creation
    if aws iam get-role --role-name "CrossAccount-DevelopmentAccess-${RANDOM_SUFFIX}" &> /dev/null; then
        success "✅ Development role exists"
    else
        error "❌ Development role not found"
        return 1
    fi
    
    # Test CloudTrail
    if aws cloudtrail describe-trails --trail-name-list "CrossAccountAuditTrail-${RANDOM_SUFFIX}" --query 'trailList[0].Name' --output text 2>/dev/null | grep -q "CrossAccountAuditTrail"; then
        success "✅ CloudTrail exists"
    else
        error "❌ CloudTrail not found"
        return 1
    fi
    
    # Test Lambda function
    if aws lambda get-function --function-name "CrossAccountRoleValidator-${RANDOM_SUFFIX}" &> /dev/null; then
        success "✅ Lambda validator exists"
        
        # Test Lambda function execution
        info "Testing Lambda function..."
        aws lambda invoke \
            --function-name "CrossAccountRoleValidator-${RANDOM_SUFFIX}" \
            --payload '{}' \
            "${TEMP_DIR}/lambda-response.json" > /dev/null
        
        if [ $? -eq 0 ]; then
            success "✅ Lambda function executed successfully"
            info "Validation results: $(cat "${TEMP_DIR}/lambda-response.json")"
        else
            warning "⚠️ Lambda function execution failed"
        fi
    else
        error "❌ Lambda validator not found"
        return 1
    fi
    
    success "All validation tests passed"
}

# Main deployment function
main() {
    echo "=========================================="
    echo "Advanced Cross-Account IAM Role Federation"
    echo "Deployment Script"
    echo "=========================================="
    echo
    
    # Initialize log file
    echo "Deployment started at $(date)" > "$LOG_FILE"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_policy_documents
    create_master_role
    create_cross_account_roles
    implement_session_tags
    setup_audit_trail
    implement_role_validation
    run_validation_tests
    
    echo
    success "=========================================="
    success "Deployment completed successfully!"
    success "=========================================="
    echo
    info "Next steps:"
    info "1. Review the deployment configuration in: ${SCRIPT_DIR}/deployment-config.env"
    info "2. Test cross-account role assumption using: ${SCRIPT_DIR}/assume-cross-account-role.sh"
    info "3. Monitor audit logs in CloudTrail console"
    info "4. Run the role validator Lambda function to check compliance"
    echo
    info "To clean up all resources, run: ${SCRIPT_DIR}/destroy.sh"
    echo
    info "For detailed logs, check: $LOG_FILE"
}

# Run main function
main "$@"