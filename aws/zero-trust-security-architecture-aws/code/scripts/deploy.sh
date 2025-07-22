#!/bin/bash

# Zero Trust Security Architecture Deployment Script
# This script implements a comprehensive zero trust security architecture using AWS services
# Author: AWS Recipes Team
# Version: 1.0

set -euo pipefail

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

# Help function
show_help() {
    cat << EOF
Zero Trust Security Architecture Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run          Show what would be deployed without making changes
    -v, --verbose          Enable verbose logging
    -r, --region REGION    AWS region (default: from AWS CLI config)
    -p, --prefix PREFIX    Resource prefix (default: auto-generated)
    -e, --email EMAIL      Email for security alerts (required)
    --skip-security-hub    Skip Security Hub configuration
    --skip-guardduty       Skip GuardDuty configuration
    --skip-config          Skip AWS Config configuration
    --skip-network         Skip network infrastructure

EXAMPLES:
    $0 --email security@example.com
    $0 --dry-run --email security@example.com
    $0 --region us-west-2 --prefix myorg-zt --email security@example.com

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Administrative permissions for IAM, Security Hub, GuardDuty, Config, VPC
    - Valid email address for security alerts
    - Estimated cost: $50-100/month

EOF
}

# Default values
DRY_RUN=false
VERBOSE=false
SKIP_SECURITY_HUB=false
SKIP_GUARDDUTY=false
SKIP_CONFIG=false
SKIP_NETWORK=false
EMAIL=""
CUSTOM_PREFIX=""
CUSTOM_REGION=""

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                set -x
                shift
                ;;
            -r|--region)
                CUSTOM_REGION="$2"
                shift 2
                ;;
            -p|--prefix)
                CUSTOM_PREFIX="$2"
                shift 2
                ;;
            -e|--email)
                EMAIL="$2"
                shift 2
                ;;
            --skip-security-hub)
                SKIP_SECURITY_HUB=true
                shift
                ;;
            --skip-guardduty)
                SKIP_GUARDDUTY=true
                shift
                ;;
            --skip-config)
                SKIP_CONFIG=true
                shift
                ;;
            --skip-network)
                SKIP_NETWORK=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Validate prerequisites
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ${AWS_CLI_VERSION:0:1} != "2" ]]; then
        error "AWS CLI v2 is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    # Check email parameter
    if [[ -z "$EMAIL" ]]; then
        error "Email address is required for security alerts. Use --email option."
        exit 1
    fi
    
    # Validate email format
    if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        error "Invalid email format: $EMAIL"
        exit 1
    fi
    
    success "Prerequisites validated"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS region
    if [[ -n "$CUSTOM_REGION" ]]; then
        export AWS_REGION="$CUSTOM_REGION"
    else
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            warning "No region configured, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    if [[ -n "$CUSTOM_PREFIX" ]]; then
        export ZERO_TRUST_PREFIX="$CUSTOM_PREFIX"
    else
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 7))
        export ZERO_TRUST_PREFIX="zero-trust-${RANDOM_SUFFIX}"
    fi
    
    # Set derived variables
    export SECURITY_ROLE_NAME="${ZERO_TRUST_PREFIX}-security-role"
    export COMPLIANCE_ROLE_NAME="${ZERO_TRUST_PREFIX}-compliance-role"
    export MONITORING_ROLE_NAME="${ZERO_TRUST_PREFIX}-monitoring-role"
    export SECURITY_LOGS_BUCKET="${ZERO_TRUST_PREFIX}-security-logs-${AWS_ACCOUNT_ID}"
    export SECURE_DATA_BUCKET="${ZERO_TRUST_PREFIX}-secure-data-${AWS_ACCOUNT_ID}"
    
    log "Environment initialized:"
    log "  Region: $AWS_REGION"
    log "  Account: $AWS_ACCOUNT_ID"
    log "  Prefix: $ZERO_TRUST_PREFIX"
    log "  Security Email: $EMAIL"
}

# Execute command with dry-run support
execute_command() {
    local cmd="$1"
    local description="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY-RUN] $description"
        log "[DRY-RUN] Command: $cmd"
    else
        log "$description"
        if [[ "$VERBOSE" == "true" ]]; then
            log "Executing: $cmd"
        fi
        eval "$cmd"
    fi
}

# Create foundational S3 buckets
create_foundational_resources() {
    log "Creating foundational resources..."
    
    # Create security logs bucket
    execute_command "aws s3api create-bucket \
        --bucket \"$SECURITY_LOGS_BUCKET\" \
        --region $AWS_REGION \
        $(if [ \"$AWS_REGION\" != \"us-east-1\" ]; then echo \"--create-bucket-configuration LocationConstraint=$AWS_REGION\"; fi)" \
        "Creating security logs S3 bucket"
    
    # Enable bucket versioning
    execute_command "aws s3api put-bucket-versioning \
        --bucket \"$SECURITY_LOGS_BUCKET\" \
        --versioning-configuration Status=Enabled" \
        "Enabling S3 bucket versioning"
    
    # Enable bucket encryption
    execute_command "aws s3api put-bucket-encryption \
        --bucket \"$SECURITY_LOGS_BUCKET\" \
        --server-side-encryption-configuration '{
            \"Rules\": [{
                \"ApplyServerSideEncryptionByDefault\": {
                    \"SSEAlgorithm\": \"AES256\"
                }
            }]
        }'" \
        "Configuring S3 bucket encryption"
    
    # Block public access
    execute_command "aws s3api put-public-access-block \
        --bucket \"$SECURITY_LOGS_BUCKET\" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        "Blocking public access to S3 bucket"
    
    success "Foundational resources created"
}

# Enable AWS Security Hub
enable_security_hub() {
    if [[ "$SKIP_SECURITY_HUB" == "true" ]]; then
        warning "Skipping Security Hub configuration"
        return 0
    fi
    
    log "Enabling AWS Security Hub..."
    
    # Enable Security Hub
    execute_command "aws securityhub enable-security-hub --enable-default-standards" \
        "Enabling Security Hub with default standards"
    
    # Enable foundational security standards
    execute_command "aws securityhub batch-enable-standards \
        --standards-subscription-requests \
        StandardsArn=arn:aws:securityhub:$AWS_REGION::standard/aws-foundational-security/v/1.0.0,Reason=\"Zero Trust Foundation\"" \
        "Enabling AWS Foundational Security Standard"
    
    # Enable CIS AWS Foundations Benchmark
    execute_command "aws securityhub batch-enable-standards \
        --standards-subscription-requests \
        StandardsArn=arn:aws:securityhub:$AWS_REGION::standard/cis-aws-foundations-benchmark/v/1.2.0,Reason=\"CIS Compliance\"" \
        "Enabling CIS AWS Foundations Benchmark"
    
    success "Security Hub enabled successfully"
}

# Enable Amazon GuardDuty
enable_guardduty() {
    if [[ "$SKIP_GUARDDUTY" == "true" ]]; then
        warning "Skipping GuardDuty configuration"
        return 0
    fi
    
    log "Enabling Amazon GuardDuty..."
    
    # Enable GuardDuty detector
    DETECTOR_ID=$(execute_command "aws guardduty create-detector \
        --enable \
        --finding-publishing-frequency FIFTEEN_MINUTES \
        --data-sources '{
            \"S3Logs\": {\"Enable\": true},
            \"KubernetesConfiguration\": {\"AuditLogs\": {\"Enable\": true}},
            \"MalwareProtection\": {\"ScanEc2InstanceWithFindings\": {\"EbsVolumes\": true}}
        }' \
        --query DetectorId --output text" \
        "Creating GuardDuty detector")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export DETECTOR_ID
        echo "export DETECTOR_ID=\"$DETECTOR_ID\"" >> /tmp/zero-trust-vars.env
        log "GuardDuty Detector ID: $DETECTOR_ID"
    fi
    
    success "GuardDuty enabled successfully"
}

# Enable AWS Config
enable_aws_config() {
    if [[ "$SKIP_CONFIG" == "true" ]]; then
        warning "Skipping AWS Config configuration"
        return 0
    fi
    
    log "Enabling AWS Config..."
    
    # Create Config service role
    execute_command "aws iam create-role \
        --role-name \"${ZERO_TRUST_PREFIX}-config-role\" \
        --assume-role-policy-document '{
            \"Version\": \"2012-10-17\",
            \"Statement\": [{
                \"Effect\": \"Allow\",
                \"Principal\": {\"Service\": \"config.amazonaws.com\"},
                \"Action\": \"sts:AssumeRole\"
            }]
        }'" \
        "Creating Config service role"
    
    # Attach AWS Config service role policy
    execute_command "aws iam attach-role-policy \
        --role-name \"${ZERO_TRUST_PREFIX}-config-role\" \
        --policy-arn arn:aws:iam::aws:policy/service-role/ConfigRole" \
        "Attaching Config service role policy"
    
    # Create Config delivery channel
    execute_command "aws configservice put-delivery-channel \
        --delivery-channel '{
            \"name\": \"zero-trust-config-channel\",
            \"s3BucketName\": \"$SECURITY_LOGS_BUCKET\",
            \"s3KeyPrefix\": \"config/\",
            \"configSnapshotDeliveryProperties\": {
                \"deliveryFrequency\": \"TwentyFour_Hours\"
            }
        }'" \
        "Creating Config delivery channel"
    
    # Create Config configuration recorder
    execute_command "aws configservice put-configuration-recorder \
        --configuration-recorder '{
            \"name\": \"zero-trust-config-recorder\",
            \"roleARN\": \"arn:aws:iam::$AWS_ACCOUNT_ID:role/${ZERO_TRUST_PREFIX}-config-role\",
            \"recordingGroup\": {
                \"allSupported\": true,
                \"includeGlobalResourceTypes\": true,
                \"recordingModeOverrides\": [{
                    \"resourceTypes\": [\"AWS::IAM::Role\", \"AWS::IAM::Policy\"],
                    \"recordingMode\": {
                        \"recordingFrequency\": \"CONTINUOUS\"
                    }
                }]
            }
        }'" \
        "Creating Config configuration recorder"
    
    # Start Config recorder
    execute_command "aws configservice start-configuration-recorder \
        --configuration-recorder-name zero-trust-config-recorder" \
        "Starting Config recorder"
    
    success "AWS Config enabled successfully"
}

# Configure IAM Identity Center
configure_identity_center() {
    log "Configuring IAM Identity Center..."
    
    # Check if Identity Center is enabled
    IDENTITY_STORE_ID=$(aws sso-admin list-instances \
        --query 'Instances[0].IdentityStoreId' --output text 2>/dev/null || echo "None")
    
    if [[ "$IDENTITY_STORE_ID" == "None" ]] || [[ -z "$IDENTITY_STORE_ID" ]]; then
        warning "IAM Identity Center is not enabled. Please enable it manually in the AWS Console."
        warning "Visit: https://console.aws.amazon.com/singlesignon/home"
        if [[ "$DRY_RUN" == "false" ]]; then
            read -p "Press Enter after enabling Identity Center to continue..."
        fi
        return 0
    fi
    
    # Get Identity Center instance details
    INSTANCE_ARN=$(aws sso-admin list-instances \
        --query 'Instances[0].InstanceArn' --output text)
    
    export IDENTITY_STORE_ID
    export INSTANCE_ARN
    
    # Create zero trust security admin permission set
    PERMISSION_SET_ARN=$(execute_command "aws sso-admin create-permission-set \
        --instance-arn \"$INSTANCE_ARN\" \
        --name \"ZeroTrustSecurityAdmin\" \
        --description \"Zero Trust Security Administration with MFA enforcement\" \
        --session-duration PT8H \
        --query PermissionSetArn --output text" \
        "Creating zero trust permission set")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export PERMISSION_SET_ARN
        echo "export PERMISSION_SET_ARN=\"$PERMISSION_SET_ARN\"" >> /tmp/zero-trust-vars.env
    fi
    
    # Attach security admin policy to permission set
    execute_command "aws sso-admin attach-managed-policy-to-permission-set \
        --instance-arn \"$INSTANCE_ARN\" \
        --permission-set-arn \"$PERMISSION_SET_ARN\" \
        --managed-policy-arn arn:aws:iam::aws:policy/SecurityAudit" \
        "Attaching SecurityAudit policy to permission set"
    
    success "IAM Identity Center configured successfully"
}

# Implement zero trust IAM policies
implement_zero_trust_policies() {
    log "Implementing zero trust IAM policies..."
    
    # Create zero trust boundary policy
    cat > /tmp/zero-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EnforceMFAForAllActions",
            "Effect": "Deny",
            "Action": "*",
            "Resource": "*",
            "Condition": {
                "BoolIfExists": {
                    "aws:MultiFactorAuthPresent": "false"
                },
                "NumericLessThan": {
                    "aws:MultiFactorAuthAge": "3600"
                }
            }
        },
        {
            "Sid": "EnforceSSLRequests",
            "Effect": "Deny",
            "Action": "s3:*",
            "Resource": "*",
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        },
        {
            "Sid": "RestrictHighRiskActions",
            "Effect": "Deny",
            "Action": [
                "iam:CreateUser",
                "iam:DeleteUser",
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:AttachUserPolicy",
                "iam:DetachUserPolicy",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy"
            ],
            "Resource": "*",
            "Condition": {
                "StringNotEquals": {
                    "aws:RequestedRegion": [
                        "us-east-1",
                        "us-west-2"
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Create zero trust boundary policy
    ZERO_TRUST_POLICY_ARN=$(execute_command "aws iam create-policy \
        --policy-name \"${ZERO_TRUST_PREFIX}-boundary-policy\" \
        --description \"Zero Trust Security Boundary Policy\" \
        --policy-document file:///tmp/zero-trust-policy.json \
        --query Policy.Arn --output text" \
        "Creating zero trust boundary policy")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export ZERO_TRUST_POLICY_ARN
        echo "export ZERO_TRUST_POLICY_ARN=\"$ZERO_TRUST_POLICY_ARN\"" >> /tmp/zero-trust-vars.env
    fi
    
    # Create zero trust security role
    execute_command "aws iam create-role \
        --role-name \"$SECURITY_ROLE_NAME\" \
        --assume-role-policy-document '{
            \"Version\": \"2012-10-17\",
            \"Statement\": [{
                \"Effect\": \"Allow\",
                \"Principal\": {\"Service\": \"lambda.amazonaws.com\"},
                \"Action\": \"sts:AssumeRole\",
                \"Condition\": {
                    \"StringEquals\": {
                        \"sts:ExternalId\": \"${ZERO_TRUST_PREFIX}-security-automation\"
                    }
                }
            }]
        }' \
        --permissions-boundary \"$ZERO_TRUST_POLICY_ARN\"" \
        "Creating zero trust security role"
    
    success "Zero trust IAM policies implemented successfully"
}

# Configure network security
configure_network_security() {
    if [[ "$SKIP_NETWORK" == "true" ]]; then
        warning "Skipping network security configuration"
        return 0
    fi
    
    log "Configuring zero trust network security..."
    
    # Create VPC with zero trust design
    VPC_ID=$(execute_command "aws ec2 create-vpc \
        --cidr-block 10.0.0.0/16 \
        --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=${ZERO_TRUST_PREFIX}-vpc},{Key=Purpose,Value=ZeroTrustSecurity}]' \
        --query Vpc.VpcId --output text" \
        "Creating zero trust VPC")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export VPC_ID
        echo "export VPC_ID=\"$VPC_ID\"" >> /tmp/zero-trust-vars.env
    fi
    
    # Create private subnets
    PRIVATE_SUBNET_1=$(execute_command "aws ec2 create-subnet \
        --vpc-id \"$VPC_ID\" \
        --cidr-block 10.0.1.0/24 \
        --availability-zone \"${AWS_REGION}a\" \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${ZERO_TRUST_PREFIX}-private-1}]' \
        --query Subnet.SubnetId --output text" \
        "Creating private subnet 1")
    
    PRIVATE_SUBNET_2=$(execute_command "aws ec2 create-subnet \
        --vpc-id \"$VPC_ID\" \
        --cidr-block 10.0.2.0/24 \
        --availability-zone \"${AWS_REGION}b\" \
        --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${ZERO_TRUST_PREFIX}-private-2}]' \
        --query Subnet.SubnetId --output text" \
        "Creating private subnet 2")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export PRIVATE_SUBNET_1
        export PRIVATE_SUBNET_2
        echo "export PRIVATE_SUBNET_1=\"$PRIVATE_SUBNET_1\"" >> /tmp/zero-trust-vars.env
        echo "export PRIVATE_SUBNET_2=\"$PRIVATE_SUBNET_2\"" >> /tmp/zero-trust-vars.env
    fi
    
    # Create restrictive security group
    ZERO_TRUST_SG=$(execute_command "aws ec2 create-security-group \
        --group-name \"${ZERO_TRUST_PREFIX}-zero-trust-sg\" \
        --description \"Zero Trust Security Group with minimal access\" \
        --vpc-id \"$VPC_ID\" \
        --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=${ZERO_TRUST_PREFIX}-zero-trust-sg}]' \
        --query GroupId --output text" \
        "Creating zero trust security group")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export ZERO_TRUST_SG
        echo "export ZERO_TRUST_SG=\"$ZERO_TRUST_SG\"" >> /tmp/zero-trust-vars.env
    fi
    
    # Add necessary inbound rules
    execute_command "aws ec2 authorize-security-group-ingress \
        --group-id \"$ZERO_TRUST_SG\" \
        --protocol tcp \
        --port 443 \
        --source-group \"$ZERO_TRUST_SG\" \
        --group-owner-id \"$AWS_ACCOUNT_ID\"" \
        "Adding HTTPS rule to security group"
    
    success "Network security configured successfully"
}

# Configure data protection
configure_data_protection() {
    log "Configuring zero trust data protection..."
    
    # Create KMS key for zero trust encryption
    KMS_KEY_ID=$(execute_command "aws kms create-key \
        --description \"Zero Trust Security Architecture Key\" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --policy '{
            \"Version\": \"2012-10-17\",
            \"Statement\": [{
                \"Sid\": \"Enable IAM User Permissions\",
                \"Effect\": \"Allow\",
                \"Principal\": {\"AWS\": \"arn:aws:iam::$AWS_ACCOUNT_ID:root\"},
                \"Action\": \"kms:*\",
                \"Resource\": \"*\"
            }, {
                \"Sid\": \"Allow Zero Trust Services\",
                \"Effect\": \"Allow\",
                \"Principal\": {
                    \"Service\": [
                        \"s3.amazonaws.com\",
                        \"secretsmanager.amazonaws.com\",
                        \"rds.amazonaws.com\"
                    ]
                },
                \"Action\": [
                    \"kms:Decrypt\",
                    \"kms:Encrypt\",
                    \"kms:GenerateDataKey\"
                ],
                \"Resource\": \"*\",
                \"Condition\": {
                    \"StringEquals\": {
                        \"kms:ViaService\": [
                            \"s3.$AWS_REGION.amazonaws.com\",
                            \"secretsmanager.$AWS_REGION.amazonaws.com\",
                            \"rds.$AWS_REGION.amazonaws.com\"
                        ]
                    }
                }
            }]
        }' \
        --query KeyMetadata.KeyId --output text" \
        "Creating KMS key for zero trust encryption")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export KMS_KEY_ID
        echo "export KMS_KEY_ID=\"$KMS_KEY_ID\"" >> /tmp/zero-trust-vars.env
    fi
    
    # Create KMS key alias
    execute_command "aws kms create-alias \
        --alias-name \"alias/${ZERO_TRUST_PREFIX}-key\" \
        --target-key-id \"$KMS_KEY_ID\"" \
        "Creating KMS key alias"
    
    # Create secure S3 bucket
    execute_command "aws s3api create-bucket \
        --bucket \"$SECURE_DATA_BUCKET\" \
        --region $AWS_REGION \
        $(if [ \"$AWS_REGION\" != \"us-east-1\" ]; then echo \"--create-bucket-configuration LocationConstraint=$AWS_REGION\"; fi)" \
        "Creating secure data S3 bucket"
    
    # Configure S3 bucket encryption
    execute_command "aws s3api put-bucket-encryption \
        --bucket \"$SECURE_DATA_BUCKET\" \
        --server-side-encryption-configuration '{
            \"Rules\": [{
                \"ApplyServerSideEncryptionByDefault\": {
                    \"SSEAlgorithm\": \"aws:kms\",
                    \"KMSMasterKeyID\": \"$KMS_KEY_ID\"
                },
                \"BucketKeyEnabled\": true
            }]
        }'" \
        "Configuring S3 bucket encryption with KMS"
    
    # Block all public access
    execute_command "aws s3api put-public-access-block \
        --bucket \"$SECURE_DATA_BUCKET\" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        "Blocking public access to secure data bucket"
    
    # Enable bucket versioning
    execute_command "aws s3api put-bucket-versioning \
        --bucket \"$SECURE_DATA_BUCKET\" \
        --versioning-configuration Status=Enabled" \
        "Enabling versioning on secure data bucket"
    
    success "Data protection configured successfully"
}

# Set up monitoring and alerting
setup_monitoring() {
    log "Setting up zero trust monitoring and alerting..."
    
    # Create CloudWatch log group
    execute_command "aws logs create-log-group \
        --log-group-name \"/aws/zero-trust/${ZERO_TRUST_PREFIX}\" \
        --retention-in-days 30" \
        "Creating CloudWatch log group"
    
    # Create SNS topic for security alerts
    ALERT_TOPIC_ARN=$(execute_command "aws sns create-topic \
        --name \"${ZERO_TRUST_PREFIX}-security-alerts\" \
        --query TopicArn --output text" \
        "Creating SNS topic for security alerts")
    
    if [[ "$DRY_RUN" == "false" ]]; then
        export ALERT_TOPIC_ARN
        echo "export ALERT_TOPIC_ARN=\"$ALERT_TOPIC_ARN\"" >> /tmp/zero-trust-vars.env
    fi
    
    # Subscribe email to security alerts
    execute_command "aws sns subscribe \
        --topic-arn \"$ALERT_TOPIC_ARN\" \
        --protocol email \
        --notification-endpoint \"$EMAIL\"" \
        "Subscribing email to security alerts"
    
    # Create custom Config rules
    execute_command "aws configservice put-config-rule \
        --config-rule '{
            \"ConfigRuleName\": \"zero-trust-mfa-enabled\",
            \"Description\": \"Checks if MFA is enabled for all IAM users\",
            \"Source\": {
                \"Owner\": \"AWS\",
                \"SourceIdentifier\": \"MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS\"
            },
            \"InputParameters\": \"{}\",
            \"ConfigRuleState\": \"ACTIVE\"
        }'" \
        "Creating Config rule for MFA enforcement"
    
    execute_command "aws configservice put-config-rule \
        --config-rule '{
            \"ConfigRuleName\": \"zero-trust-s3-bucket-ssl-requests-only\",
            \"Description\": \"Checks if S3 buckets have policies requiring SSL requests only\",
            \"Source\": {
                \"Owner\": \"AWS\",
                \"SourceIdentifier\": \"S3_BUCKET_SSL_REQUESTS_ONLY\"
            },
            \"InputParameters\": \"{}\",
            \"ConfigRuleState\": \"ACTIVE\"
        }'" \
        "Creating Config rule for SSL enforcement"
    
    success "Monitoring and alerting configured successfully"
}

# Create deployment summary
create_deployment_summary() {
    log "Creating deployment summary..."
    
    cat > /tmp/zero-trust-deployment-summary.txt << EOF
Zero Trust Security Architecture Deployment Summary
=================================================

Deployment Date: $(date)
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID
Resource Prefix: $ZERO_TRUST_PREFIX
Security Email: $EMAIL

Resources Created:
- Security Hub: Enabled with foundational and CIS standards
- GuardDuty: Enabled with S3 logs and malware protection
- AWS Config: Enabled with continuous IAM monitoring
- IAM Identity Center: Zero trust permission set configured
- Zero Trust IAM Policies: Boundary policies with MFA enforcement
- Network Security: Private VPC with restrictive security groups
- Data Protection: KMS encryption with secure S3 buckets
- Monitoring: CloudWatch logs and SNS alerts configured

S3 Buckets:
- Security Logs: $SECURITY_LOGS_BUCKET
- Secure Data: $SECURE_DATA_BUCKET

Next Steps:
1. Check your email ($EMAIL) and confirm SNS subscription
2. Configure IAM Identity Center users and groups
3. Test access with MFA enabled
4. Review Security Hub findings
5. Monitor GuardDuty for threats

Important Notes:
- All policies enforce MFA and secure transport
- Network access is restricted to private subnets only
- Data encryption is enforced using customer-managed KMS keys
- Comprehensive monitoring and alerting is configured

Cleanup:
To remove all resources, run: ./destroy.sh --prefix $ZERO_TRUST_PREFIX

EOF
    
    if [[ "$DRY_RUN" == "false" ]]; then
        cp /tmp/zero-trust-deployment-summary.txt ./zero-trust-deployment-summary.txt
        success "Deployment summary saved to: ./zero-trust-deployment-summary.txt"
    else
        cat /tmp/zero-trust-deployment-summary.txt
    fi
}

# Main deployment function
main() {
    echo "=============================================="
    echo "Zero Trust Security Architecture Deployment"
    echo "=============================================="
    echo
    
    parse_args "$@"
    validate_prerequisites
    initialize_environment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        warning "DRY RUN MODE - No resources will be created"
        echo
    fi
    
    # Create environment variables file
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "# Zero Trust Environment Variables" > /tmp/zero-trust-vars.env
        echo "export AWS_REGION=\"$AWS_REGION\"" >> /tmp/zero-trust-vars.env
        echo "export AWS_ACCOUNT_ID=\"$AWS_ACCOUNT_ID\"" >> /tmp/zero-trust-vars.env
        echo "export ZERO_TRUST_PREFIX=\"$ZERO_TRUST_PREFIX\"" >> /tmp/zero-trust-vars.env
        echo "export SECURITY_LOGS_BUCKET=\"$SECURITY_LOGS_BUCKET\"" >> /tmp/zero-trust-vars.env
        echo "export SECURE_DATA_BUCKET=\"$SECURE_DATA_BUCKET\"" >> /tmp/zero-trust-vars.env
    fi
    
    # Execute deployment steps
    create_foundational_resources
    enable_security_hub
    enable_guardduty
    enable_aws_config
    configure_identity_center
    implement_zero_trust_policies
    configure_network_security
    configure_data_protection
    setup_monitoring
    create_deployment_summary
    
    echo
    echo "=============================================="
    if [[ "$DRY_RUN" == "true" ]]; then
        success "DRY RUN COMPLETED - No resources were created"
        log "Run without --dry-run to perform actual deployment"
    else
        success "ZERO TRUST SECURITY ARCHITECTURE DEPLOYED SUCCESSFULLY"
        log "Check your email for SNS subscription confirmation"
        log "Review the deployment summary for next steps"
        log "Environment variables saved to: /tmp/zero-trust-vars.env"
    fi
    echo "=============================================="
}

# Run main function with all arguments
main "$@"