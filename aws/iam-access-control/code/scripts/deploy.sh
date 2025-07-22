#!/bin/bash

# Deploy script for Fine-Grained Access Control with IAM Policies and Conditions
# This script creates IAM policies, users, roles, and test resources for demonstrating
# advanced IAM condition-based access controls

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

# Error handling function
cleanup_on_error() {
    log_error "Deployment failed. Starting cleanup of partial resources..."
    ./destroy.sh --force 2>/dev/null || true
    exit 1
}

# Set trap for error handling
trap cleanup_on_error ERR

# Check if required tools are installed
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "${AWS_CLI_VERSION}" < "2.0.0" ]]; then
        log_warning "AWS CLI version ${AWS_CLI_VERSION} detected. Version 2.x is recommended."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install jq for JSON processing."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid. Please run 'aws configure'."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [[ -z "${AWS_REGION}" ]]; then
        export AWS_REGION="us-east-1"
        log_warning "No default region found, using us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    
    export PROJECT_NAME="finegrained-access-${RANDOM_SUFFIX}"
    export BUCKET_NAME="${PROJECT_NAME}-test-bucket"
    export LOG_GROUP_NAME="/aws/lambda/${PROJECT_NAME}"
    
    log_success "Environment variables set:"
    log "  AWS_REGION: ${AWS_REGION}"
    log "  AWS_ACCOUNT_ID: ${AWS_ACCOUNT_ID}"
    log "  PROJECT_NAME: ${PROJECT_NAME}"
    log "  BUCKET_NAME: ${BUCKET_NAME}"
    log "  LOG_GROUP_NAME: ${LOG_GROUP_NAME}"
}

# Create foundational resources
create_foundational_resources() {
    log "Creating foundational test resources..."
    
    # Create test S3 bucket
    if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
        log_warning "S3 bucket ${BUCKET_NAME} already exists"
    else
        aws s3 mb "s3://${BUCKET_NAME}" --region "${AWS_REGION}"
        log_success "Created S3 bucket: ${BUCKET_NAME}"
    fi
    
    # Create CloudWatch log group
    if aws logs describe-log-groups --log-group-name-prefix "${LOG_GROUP_NAME}" \
        --query 'logGroups[?logGroupName==`'"${LOG_GROUP_NAME}"'`]' --output text | grep -q "${LOG_GROUP_NAME}"; then
        log_warning "CloudWatch log group ${LOG_GROUP_NAME} already exists"
    else
        aws logs create-log-group --log-group-name "${LOG_GROUP_NAME}" --region "${AWS_REGION}"
        log_success "Created CloudWatch log group: ${LOG_GROUP_NAME}"
    fi
}

# Create IAM policies with conditions
create_iam_policies() {
    log "Creating IAM policies with advanced conditions..."
    
    # Create time-based access policy
    cat > business-hours-policy.json << EOF
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
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ],
            "Condition": {
                "DateGreaterThan": {
                    "aws:CurrentTime": "09:00Z"
                },
                "DateLessThan": {
                    "aws:CurrentTime": "17:00Z"
                }
            }
        }
    ]
}
EOF
    
    aws iam create-policy \
        --policy-name "${PROJECT_NAME}-business-hours-policy" \
        --policy-document file://business-hours-policy.json \
        --description "S3 access restricted to business hours (9 AM - 5 PM UTC)" \
        --no-cli-pager
    
    log_success "Created time-based access policy"
    
    # Create IP-based access control policy
    cat > ip-restriction-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            ],
            "Resource": "arn:aws:logs:*:${AWS_ACCOUNT_ID}:log-group:/aws/lambda/${PROJECT_NAME}*",
            "Condition": {
                "IpAddress": {
                    "aws:SourceIp": [
                        "203.0.113.0/24",
                        "198.51.100.0/24"
                    ]
                }
            }
        },
        {
            "Effect": "Deny",
            "Action": "*",
            "Resource": "*",
            "Condition": {
                "Bool": {
                    "aws:ViaAWSService": "false"
                },
                "NotIpAddress": {
                    "aws:SourceIp": [
                        "203.0.113.0/24",
                        "198.51.100.0/24"
                    ]
                }
            }
        }
    ]
}
EOF
    
    aws iam create-policy \
        --policy-name "${PROJECT_NAME}-ip-restriction-policy" \
        --policy-document file://ip-restriction-policy.json \
        --description "CloudWatch Logs access from specific IP ranges only" \
        --no-cli-pager
    
    log_success "Created IP-based access control policy"
    
    # Create tag-based access control policy
    cat > tag-based-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
            "Condition": {
                "StringEquals": {
                    "aws:PrincipalTag/Department": "\${s3:ExistingObjectTag/Department}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/shared/*"
        },
        {
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}",
            "Condition": {
                "StringLike": {
                    "s3:prefix": [
                        "shared/*",
                        "\${aws:PrincipalTag/Department}/*"
                    ]
                }
            }
        }
    ]
}
EOF
    
    aws iam create-policy \
        --policy-name "${PROJECT_NAME}-tag-based-policy" \
        --policy-document file://tag-based-policy.json \
        --description "S3 access based on user and resource tags (ABAC)" \
        --no-cli-pager
    
    log_success "Created tag-based access control policy"
    
    # Create MFA required policy
    cat > mfa-required-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:PutObjectAcl"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
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
    
    aws iam create-policy \
        --policy-name "${PROJECT_NAME}-mfa-required-policy" \
        --policy-document file://mfa-required-policy.json \
        --description "S3 write operations require MFA authentication" \
        --no-cli-pager
    
    log_success "Created MFA-required policy"
    
    # Create session-based access control policy
    cat > session-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:${AWS_ACCOUNT_ID}:log-group:/aws/lambda/${PROJECT_NAME}*",
            "Condition": {
                "StringEquals": {
                    "aws:userid": "\${aws:userid}"
                },
                "StringLike": {
                    "aws:rolename": "${PROJECT_NAME}*"
                },
                "NumericLessThan": {
                    "aws:TokenIssueTime": "\${aws:CurrentTime}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": "sts:GetSessionToken",
            "Resource": "*",
            "Condition": {
                "NumericLessThan": {
                    "aws:RequestedDuration": "3600"
                }
            }
        }
    ]
}
EOF
    
    aws iam create-policy \
        --policy-name "${PROJECT_NAME}-session-policy" \
        --policy-document file://session-policy.json \
        --description "Session-based access control with duration limits" \
        --no-cli-pager
    
    log_success "Created session-based access control policy"
}

# Create test IAM principals
create_test_principals() {
    log "Creating test IAM users and roles..."
    
    # Create test user
    if aws iam get-user --user-name "${PROJECT_NAME}-test-user" &>/dev/null; then
        log_warning "Test user ${PROJECT_NAME}-test-user already exists"
    else
        aws iam create-user --user-name "${PROJECT_NAME}-test-user" --no-cli-pager
        log_success "Created test user: ${PROJECT_NAME}-test-user"
    fi
    
    # Tag the test user
    aws iam tag-user \
        --user-name "${PROJECT_NAME}-test-user" \
        --tags Key=Department,Value=Engineering Key=Project,Value="${PROJECT_NAME}" \
        --no-cli-pager
    
    log_success "Tagged test user with Department=Engineering"
    
    # Create trust policy for test role
    cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:user/${PROJECT_NAME}-test-user"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "aws:RequestedRegion": "${AWS_REGION}"
                },
                "IpAddress": {
                    "aws:SourceIp": [
                        "203.0.113.0/24",
                        "198.51.100.0/24"
                    ]
                }
            }
        }
    ]
}
EOF
    
    # Create test role
    if aws iam get-role --role-name "${PROJECT_NAME}-test-role" &>/dev/null; then
        log_warning "Test role ${PROJECT_NAME}-test-role already exists"
    else
        aws iam create-role \
            --role-name "${PROJECT_NAME}-test-role" \
            --assume-role-policy-document file://trust-policy.json \
            --description "Test role with conditional access controls" \
            --no-cli-pager
        log_success "Created test role: ${PROJECT_NAME}-test-role"
    fi
    
    # Tag the test role
    aws iam tag-role \
        --role-name "${PROJECT_NAME}-test-role" \
        --tags Key=Department,Value=Engineering Key=Environment,Value=Test \
        --no-cli-pager
    
    log_success "Tagged test role with Department=Engineering"
}

# Create resource-based policies
create_resource_policies() {
    log "Creating resource-based policies..."
    
    # Create S3 bucket policy with advanced conditions
    cat > bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-test-role"
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-server-side-encryption": "AES256"
                },
                "StringLike": {
                    "s3:x-amz-meta-project": "${PROJECT_NAME}*"
                }
            }
        },
        {
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF
    
    # Apply bucket policy
    aws s3api put-bucket-policy \
        --bucket "${BUCKET_NAME}" \
        --policy file://bucket-policy.json
    
    log_success "Applied resource-based policy to S3 bucket"
}

# Attach policies to test principals
attach_policies() {
    log "Attaching policies to test principals..."
    
    # Attach tag-based policy to test user
    aws iam attach-user-policy \
        --user-name "${PROJECT_NAME}-test-user" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-tag-based-policy" \
        --no-cli-pager
    
    log_success "Attached tag-based policy to test user"
    
    # Attach business hours policy to test role
    aws iam attach-role-policy \
        --role-name "${PROJECT_NAME}-test-role" \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-business-hours-policy" \
        --no-cli-pager
    
    log_success "Attached business hours policy to test role"
}

# Create test resources
create_test_resources() {
    log "Creating test objects with appropriate tags..."
    
    # Create test content
    echo "Test content for engineering department - $(date)" > test-file.txt
    
    # Upload test object with tags and encryption
    aws s3api put-object \
        --bucket "${BUCKET_NAME}" \
        --key "Engineering/test-file.txt" \
        --body test-file.txt \
        --tagging "Department=Engineering&Project=${PROJECT_NAME}" \
        --server-side-encryption AES256 \
        --metadata "project=${PROJECT_NAME}-test" \
        --no-cli-pager > /dev/null
    
    log_success "Created test object with appropriate tags and encryption"
    
    # Create shared directory test object
    echo "Shared content accessible to all departments - $(date)" > shared-file.txt
    
    aws s3api put-object \
        --bucket "${BUCKET_NAME}" \
        --key "shared/shared-file.txt" \
        --body shared-file.txt \
        --tagging "Department=Shared&Project=${PROJECT_NAME}" \
        --server-side-encryption AES256 \
        --metadata "project=${PROJECT_NAME}-shared" \
        --no-cli-pager > /dev/null
    
    log_success "Created shared test object"
    
    # Clean up local files
    rm -f test-file.txt shared-file.txt
}

# Run validation tests
run_validation_tests() {
    log "Running validation tests..."
    
    # Test policy simulator with time conditions (business hours)
    BUSINESS_HOURS_TEST=$(aws iam simulate-principal-policy \
        --policy-source-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${PROJECT_NAME}-test-role" \
        --action-names "s3:GetObject" \
        --resource-arns "arn:aws:s3:::${BUCKET_NAME}/test-file.txt" \
        --context-entries ContextKeyName=aws:CurrentTime,ContextKeyValues="14:00:00Z",ContextKeyType=date \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>/dev/null || echo "failed")
    
    if [[ "${BUSINESS_HOURS_TEST}" == "allowed" ]]; then
        log_success "Time-based policy validation: PASSED"
    else
        log_warning "Time-based policy validation: ${BUSINESS_HOURS_TEST}"
    fi
    
    # Test IP-based policy with allowed IP
    IP_TEST=$(aws iam simulate-principal-policy \
        --policy-source-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-ip-restriction-policy" \
        --action-names "logs:PutLogEvents" \
        --resource-arns "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}" \
        --context-entries ContextKeyName=aws:SourceIp,ContextKeyValues="203.0.113.100",ContextKeyType=ip \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>/dev/null || echo "failed")
    
    if [[ "${IP_TEST}" == "allowed" ]]; then
        log_success "IP-based policy validation: PASSED"
    else
        log_warning "IP-based policy validation: ${IP_TEST}"
    fi
    
    # Test MFA policy without MFA (should deny)
    MFA_TEST=$(aws iam simulate-principal-policy \
        --policy-source-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-mfa-required-policy" \
        --action-names "s3:PutObject" \
        --resource-arns "arn:aws:s3:::${BUCKET_NAME}/test-file.txt" \
        --context-entries ContextKeyName=aws:MultiFactorAuthPresent,ContextKeyValues="false",ContextKeyType=boolean \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>/dev/null || echo "failed")
    
    if [[ "${MFA_TEST}" == "implicitDeny" ]]; then
        log_success "MFA policy validation: PASSED (correctly denied without MFA)"
    else
        log_warning "MFA policy validation: ${MFA_TEST}"
    fi
    
    # Verify bucket policy is applied
    if aws s3api get-bucket-policy --bucket "${BUCKET_NAME}" --output text > /dev/null 2>&1; then
        log_success "Resource-based policy validation: PASSED"
    else
        log_warning "Resource-based policy validation: FAILED"
    fi
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    cat > deployment-info.json << EOF
{
    "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "project_name": "${PROJECT_NAME}",
    "aws_region": "${AWS_REGION}",
    "aws_account_id": "${AWS_ACCOUNT_ID}",
    "resources": {
        "s3_bucket": "${BUCKET_NAME}",
        "log_group": "${LOG_GROUP_NAME}",
        "iam_user": "${PROJECT_NAME}-test-user",
        "iam_role": "${PROJECT_NAME}-test-role",
        "policies": [
            "${PROJECT_NAME}-business-hours-policy",
            "${PROJECT_NAME}-ip-restriction-policy",
            "${PROJECT_NAME}-tag-based-policy",
            "${PROJECT_NAME}-mfa-required-policy",
            "${PROJECT_NAME}-session-policy"
        ]
    },
    "policy_arns": {
        "business_hours": "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-business-hours-policy",
        "ip_restriction": "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-ip-restriction-policy",
        "tag_based": "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-tag-based-policy",
        "mfa_required": "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-mfa-required-policy",
        "session_policy": "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${PROJECT_NAME}-session-policy"
    }
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Main deployment function
main() {
    log "Starting Fine-Grained Access Control IAM deployment..."
    log "======================================================="
    
    check_prerequisites
    setup_environment
    create_foundational_resources
    create_iam_policies
    create_test_principals
    create_resource_policies
    attach_policies
    create_test_resources
    run_validation_tests
    save_deployment_info
    
    log "======================================================="
    log_success "Deployment completed successfully!"
    log ""
    log "Resources created:"
    log "  S3 Bucket: ${BUCKET_NAME}"
    log "  CloudWatch Log Group: ${LOG_GROUP_NAME}"
    log "  IAM User: ${PROJECT_NAME}-test-user"
    log "  IAM Role: ${PROJECT_NAME}-test-role"
    log "  IAM Policies: 5 conditional access policies"
    log ""
    log "Next steps:"
    log "  1. Review the created policies in the AWS IAM console"
    log "  2. Test the policies using the AWS Policy Simulator"
    log "  3. Use 'aws iam simulate-principal-policy' for additional testing"
    log "  4. When finished, run './destroy.sh' to clean up resources"
    log ""
    log "⚠️  Important: These resources may incur small charges. Clean up when done testing."
}

# Cleanup function for temporary files
cleanup_temp_files() {
    rm -f business-hours-policy.json
    rm -f ip-restriction-policy.json
    rm -f tag-based-policy.json
    rm -f mfa-required-policy.json
    rm -f session-policy.json
    rm -f trust-policy.json
    rm -f bucket-policy.json
}

# Set trap for cleanup
trap cleanup_temp_files EXIT

# Run main function
main "$@"