#!/bin/bash

# Deploy script for CloudFormation Guard Infrastructure Policy Validation
# This script sets up Guard rules repository and validation environment

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

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
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI configuration
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or credentials are invalid."
    fi
    
    # Check CloudFormation Guard
    if ! command -v cfn-guard &> /dev/null; then
        error "CloudFormation Guard is not installed. Please install from: https://docs.aws.amazon.com/cfn-guard/latest/ug/setting-up-guard.html"
    fi
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        warn "jq is not installed. Installing via package manager is recommended for JSON processing."
    fi
    
    log "Prerequisites check completed"
}

# Function to set up environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warn "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    # Set resource names
    export BUCKET_NAME="cfn-guard-policies-${RANDOM_SUFFIX}"
    export VALIDATION_ROLE_NAME="CloudFormationGuardValidationRole"
    export STACK_NAME="cfn-guard-demo-stack"
    
    log "Environment configured:"
    log "  AWS Region: $AWS_REGION"
    log "  AWS Account ID: $AWS_ACCOUNT_ID"
    log "  S3 Bucket: $BUCKET_NAME"
}

# Function to create S3 bucket for Guard rules
create_s3_bucket() {
    info "Creating S3 bucket for Guard rules..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
        warn "Bucket $BUCKET_NAME already exists, skipping creation"
        return 0
    fi
    
    # Create S3 bucket
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${BUCKET_NAME}"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$BUCKET_NAME" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$BUCKET_NAME" \
        --server-side-encryption-configuration \
        'Rules=[{ApplyServerSideEncryptionByDefault:{SSEAlgorithm:AES256}}]'
    
    # Block public access
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
    
    log "S3 bucket created and configured: $BUCKET_NAME"
}

# Function to create Guard rules
create_guard_rules() {
    info "Creating Guard rules..."
    
    # Create directory structure
    mkdir -p guard-rules/security
    mkdir -p guard-rules/compliance
    mkdir -p guard-rules/cost-optimization
    
    # Create S3 security rules
    cat > guard-rules/security/s3-security.guard << 'EOF'
# Rule: S3 buckets must have versioning enabled
rule s3_bucket_versioning_enabled {
    AWS::S3::Bucket {
        Properties {
            VersioningConfiguration exists
            VersioningConfiguration {
                Status == "Enabled"
            }
        }
    }
}

# Rule: S3 buckets must have encryption enabled
rule s3_bucket_encryption_enabled {
    AWS::S3::Bucket {
        Properties {
            BucketEncryption exists
            BucketEncryption {
                ServerSideEncryptionConfiguration exists
                ServerSideEncryptionConfiguration[*] {
                    ServerSideEncryptionByDefault exists
                    ServerSideEncryptionByDefault {
                        SSEAlgorithm exists
                    }
                }
            }
        }
    }
}

# Rule: S3 buckets must block public access
rule s3_bucket_public_access_blocked {
    AWS::S3::Bucket {
        Properties {
            PublicAccessBlockConfiguration exists
            PublicAccessBlockConfiguration {
                BlockPublicAcls == true
                BlockPublicPolicy == true
                IgnorePublicAcls == true
                RestrictPublicBuckets == true
            }
        }
    }
}
EOF

    # Create compliance rules
    cat > guard-rules/compliance/resource-compliance.guard << 'EOF'
# Rule: Resources must have required tags
rule resources_must_have_required_tags {
    Resources.*[ Type in ["AWS::S3::Bucket", "AWS::EC2::Instance", "AWS::Lambda::Function"] ] {
        Properties {
            Tags exists
            Tags[*] {
                Key in ["Environment", "Team", "Project", "CostCenter"]
            }
        }
    }
}

# Rule: Resource names must follow naming convention
rule resource_naming_convention {
    AWS::S3::Bucket {
        Properties {
            BucketName exists
            BucketName == /^[a-z0-9][a-z0-9\-]*[a-z0-9]$/
        }
    }
}

# Rule: Lambda functions must have timeout limits
rule lambda_timeout_limit {
    AWS::Lambda::Function {
        Properties {
            Timeout exists
            Timeout <= 300
        }
    }
}
EOF

    # Create cost optimization rules
    cat > guard-rules/cost-optimization/cost-controls.guard << 'EOF'
# Rule: EC2 instances must use approved instance types
rule ec2_approved_instance_types {
    AWS::EC2::Instance {
        Properties {
            InstanceType in ["t3.micro", "t3.small", "t3.medium", "m5.large", "m5.xlarge"]
        }
    }
}

# Rule: RDS instances must have backup retention
rule rds_backup_retention {
    AWS::RDS::DBInstance {
        Properties {
            BackupRetentionPeriod exists
            BackupRetentionPeriod >= 7
            BackupRetentionPeriod <= 35
        }
    }
}
EOF

    # Create IAM security rules
    cat > guard-rules/security/iam-security.guard << 'EOF'
# Rule: IAM roles must have assume role policy
rule iam_role_assume_role_policy {
    AWS::IAM::Role {
        Properties {
            AssumeRolePolicyDocument exists
        }
    }
}

# Rule: IAM policies must not allow full admin access
rule iam_no_admin_policy {
    AWS::IAM::Policy {
        Properties {
            PolicyDocument {
                Statement[*] {
                    Effect == "Allow"
                    Action != "*"
                    Resource != "*"
                }
            }
        }
    }
}
EOF

    log "Guard rules created successfully"
}

# Function to create test cases
create_test_cases() {
    info "Creating test cases for Guard rules..."
    
    # Create test cases for security rules
    cat > guard-rules/security/s3-security-tests.yaml << 'EOF'
---
- name: S3 bucket with all security features - PASS
  input:
    Resources:
      MyBucket:
        Type: AWS::S3::Bucket
        Properties:
          BucketName: secure-bucket-example
          VersioningConfiguration:
            Status: Enabled
          BucketEncryption:
            ServerSideEncryptionConfiguration:
              - ServerSideEncryptionByDefault:
                  SSEAlgorithm: AES256
          PublicAccessBlockConfiguration:
            BlockPublicAcls: true
            BlockPublicPolicy: true
            IgnorePublicAcls: true
            RestrictPublicBuckets: true
  expectations:
    rules:
      s3_bucket_versioning_enabled: PASS
      s3_bucket_encryption_enabled: PASS
      s3_bucket_public_access_blocked: PASS

- name: S3 bucket missing encryption - FAIL
  input:
    Resources:
      MyBucket:
        Type: AWS::S3::Bucket
        Properties:
          BucketName: insecure-bucket-example
          VersioningConfiguration:
            Status: Enabled
          PublicAccessBlockConfiguration:
            BlockPublicAcls: true
            BlockPublicPolicy: true
            IgnorePublicAcls: true
            RestrictPublicBuckets: true
  expectations:
    rules:
      s3_bucket_versioning_enabled: PASS
      s3_bucket_encryption_enabled: FAIL
      s3_bucket_public_access_blocked: PASS
EOF

    log "Test cases created successfully"
}

# Function to upload Guard rules to S3
upload_guard_rules() {
    info "Uploading Guard rules to S3..."
    
    # Upload Guard rules
    aws s3 cp guard-rules/ "s3://${BUCKET_NAME}/guard-rules/" \
        --recursive --include "*.guard"
    
    # Upload test cases
    aws s3 cp guard-rules/ "s3://${BUCKET_NAME}/test-cases/" \
        --recursive --include "*.yaml"
    
    # Create rules manifest
    cat > rules-manifest.json << EOF
{
    "version": "1.0",
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "rules": [
        {
            "category": "security",
            "file": "s3-security.guard",
            "description": "S3 security compliance rules"
        },
        {
            "category": "security",
            "file": "iam-security.guard",
            "description": "IAM security compliance rules"
        },
        {
            "category": "compliance",
            "file": "resource-compliance.guard",
            "description": "Resource tagging and naming compliance"
        },
        {
            "category": "cost-optimization",
            "file": "cost-controls.guard",
            "description": "Cost optimization and resource limits"
        }
    ]
}
EOF
    
    aws s3 cp rules-manifest.json "s3://${BUCKET_NAME}/rules-manifest.json"
    
    log "Guard rules uploaded to S3: s3://${BUCKET_NAME}/guard-rules/"
}

# Function to create sample templates
create_sample_templates() {
    info "Creating sample CloudFormation templates..."
    
    # Create compliant template
    cat > compliant-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Compliant S3 bucket template for Guard validation'

Resources:
  SecureDataBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub 'secure-data-bucket-${AWS::AccountId}-${AWS::Region}'
      VersioningConfiguration:
        Status: Enabled
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
        - Key: Environment
          Value: Production
        - Key: Team
          Value: DataEngineering
        - Key: Project
          Value: DataLake
        - Key: CostCenter
          Value: CC-1001

Outputs:
  BucketName:
    Description: 'Name of the created S3 bucket'
    Value: !Ref SecureDataBucket
EOF

    # Create non-compliant template
    cat > non-compliant-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Non-compliant S3 bucket template for Guard validation'

Resources:
  InsecureDataBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: 'UPPERCASE-BUCKET-NAME'
      # Missing: VersioningConfiguration
      # Missing: BucketEncryption
      # Missing: PublicAccessBlockConfiguration
      # Missing: Required tags
EOF

    # Upload templates to S3
    aws s3 cp compliant-template.yaml "s3://${BUCKET_NAME}/templates/"
    aws s3 cp non-compliant-template.yaml "s3://${BUCKET_NAME}/templates/"
    
    log "Sample templates created and uploaded"
}

# Function to set up local validation environment
setup_local_validation() {
    info "Setting up local validation environment..."
    
    # Download rules from S3
    mkdir -p local-validation
    aws s3 cp "s3://${BUCKET_NAME}/guard-rules/" \
        local-validation/rules/ --recursive
    
    aws s3 cp "s3://${BUCKET_NAME}/test-cases/" \
        local-validation/tests/ --recursive
    
    # Create validation script
    cat > validate-template.sh << 'EOF'
#!/bin/bash

TEMPLATE_FILE=$1
RULES_DIR="local-validation/rules"

if [ -z "$TEMPLATE_FILE" ]; then
    echo "Usage: $0 <template-file>"
    exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

echo "Validating template: $TEMPLATE_FILE"
echo "=================================="

# Validate against all rule files
VALIDATION_FAILED=false

for rule_file in $(find $RULES_DIR -name "*.guard"); do
    echo "Checking against: $(basename $rule_file)"
    if ! cfn-guard validate --data $TEMPLATE_FILE --rules $rule_file --show-summary; then
        VALIDATION_FAILED=true
    fi
    echo ""
done

if [ "$VALIDATION_FAILED" = true ]; then
    echo "❌ Template validation failed"
    exit 1
else
    echo "✅ Template validation passed"
    exit 0
fi
EOF
    
    chmod +x validate-template.sh
    
    log "Local validation environment configured"
}

# Function to create CI/CD integration script
create_cicd_script() {
    info "Creating CI/CD integration script..."
    
    cat > ci-cd-validation.sh << 'EOF'
#!/bin/bash

# CI/CD Pipeline Guard Validation Script
set -e

TEMPLATE_FILE=$1
BUCKET_NAME=$2
RULES_PREFIX="guard-rules"

if [ -z "$TEMPLATE_FILE" ] || [ -z "$BUCKET_NAME" ]; then
    echo "Usage: $0 <template-file> <s3-bucket-name>"
    exit 1
fi

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

echo "Starting CI/CD validation for: $TEMPLATE_FILE"
echo "=============================================="

# Download latest rules from S3
mkdir -p /tmp/guard-rules
aws s3 cp s3://${BUCKET_NAME}/${RULES_PREFIX}/ /tmp/guard-rules/ --recursive

# Validate template against all rules
VALIDATION_FAILED=false
VALIDATION_RESULTS=""

for rule_file in $(find /tmp/guard-rules -name "*.guard"); do
    echo "Validating against: $(basename $rule_file)"
    
    if cfn-guard validate --data $TEMPLATE_FILE --rules $rule_file --show-summary; then
        echo "✅ Validation passed for: $(basename $rule_file)"
        VALIDATION_RESULTS="${VALIDATION_RESULTS}✅ $(basename $rule_file): PASS\n"
    else
        echo "❌ Validation failed for: $(basename $rule_file)"
        VALIDATION_RESULTS="${VALIDATION_RESULTS}❌ $(basename $rule_file): FAIL\n"
        VALIDATION_FAILED=true
    fi
    echo ""
done

# Generate comprehensive compliance report
if [ -f "/tmp/guard-rules/security/s3-security.guard" ]; then
    cfn-guard validate \
        --data $TEMPLATE_FILE \
        --rules /tmp/guard-rules/security/s3-security.guard \
        --output-format json --show-summary > compliance-report.json
    
    # Upload report to S3 with timestamp
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    aws s3 cp compliance-report.json \
        s3://${BUCKET_NAME}/reports/${TIMESTAMP}-compliance-report.json
fi

# Clean up temporary files
rm -rf /tmp/guard-rules

if [ "$VALIDATION_FAILED" = true ]; then
    echo "❌ CI/CD validation failed - deployment blocked"
    exit 1
else
    echo "✅ CI/CD validation passed - deployment approved"
    exit 0
fi
EOF
    
    chmod +x ci-cd-validation.sh
    
    log "CI/CD integration script created"
}

# Function to run validation tests
run_validation_tests() {
    info "Running validation tests..."
    
    # Test compliant template
    log "Testing compliant template..."
    ./validate-template.sh compliant-template.yaml || warn "Compliant template validation had issues"
    
    # Test non-compliant template (expect failure)
    log "Testing non-compliant template (expecting failures)..."
    ./validate-template.sh non-compliant-template.yaml && warn "Non-compliant template unexpectedly passed" || log "Non-compliant template correctly failed validation"
    
    # Run unit tests for Guard rules
    if [ -f "local-validation/rules/security/s3-security.guard" ] && [ -f "local-validation/tests/security/s3-security-tests.yaml" ]; then
        log "Running unit tests for Guard rules..."
        cfn-guard test --rules-file local-validation/rules/security/s3-security.guard \
            --test-data local-validation/tests/security/s3-security-tests.yaml || warn "Unit tests had issues"
    fi
    
    log "Validation tests completed"
}

# Function to save environment configuration
save_environment_config() {
    info "Saving environment configuration..."
    
    cat > .env-config << EOF
# CloudFormation Guard Environment Configuration
# Generated on: $(date)
export AWS_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$AWS_ACCOUNT_ID"
export BUCKET_NAME="$BUCKET_NAME"
export VALIDATION_ROLE_NAME="$VALIDATION_ROLE_NAME"
export STACK_NAME="$STACK_NAME"

# To load this configuration, run: source .env-config
EOF
    
    log "Environment configuration saved to .env-config"
    log "To reload configuration later, run: source .env-config"
}

# Main deployment function
main() {
    log "Starting CloudFormation Guard deployment..."
    
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_guard_rules
    create_test_cases
    upload_guard_rules
    create_sample_templates
    setup_local_validation
    create_cicd_script
    run_validation_tests
    save_environment_config
    
    log "Deployment completed successfully!"
    log ""
    log "📋 Deployment Summary:"
    log "  S3 Bucket: $BUCKET_NAME"
    log "  Guard Rules: s3://${BUCKET_NAME}/guard-rules/"
    log "  Sample Templates: s3://${BUCKET_NAME}/templates/"
    log "  Local Validation: ./validate-template.sh <template-file>"
    log "  CI/CD Validation: ./ci-cd-validation.sh <template-file> $BUCKET_NAME"
    log ""
    log "🔍 Next Steps:"
    log "  1. Test validation with: ./validate-template.sh compliant-template.yaml"
    log "  2. Review Guard rules in: local-validation/rules/"
    log "  3. Customize rules for your organization"
    log "  4. Integrate ci-cd-validation.sh into your CI/CD pipeline"
    log ""
    log "📚 Documentation:"
    log "  CloudFormation Guard: https://docs.aws.amazon.com/cfn-guard/latest/ug/"
    log "  Environment config saved to: .env-config"
}

# Handle script interruption
trap 'error "Deployment interrupted"' INT TERM

# Run main function
main "$@"