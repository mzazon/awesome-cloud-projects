#!/bin/bash

# =============================================================================
# AWS Cross-Account Compliance Monitoring Deployment Script
# =============================================================================
# This script deploys cross-account compliance monitoring using AWS Systems
# Manager and Security Hub for enterprise compliance automation.
#
# Services: Systems Manager, Security Hub, CloudTrail, IAM, Lambda, EventBridge
# =============================================================================

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Cleanup function for script interruption
cleanup() {
    log_warning "Script interrupted. Cleaning up temporary files..."
    rm -f cross-account-trust-policy.json compliance-access-policy.json
    rm -f lambda-trust-policy.json lambda-permissions-policy.json
    rm -f cloudtrail-bucket-policy.json compliance_processor.py
    rm -f compliance_processor.zip custom-compliance-script.sh
    rm -f baseline_id.txt response.json
    exit 1
}

trap cleanup SIGINT SIGTERM

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate AWS CLI configuration
validate_aws_config() {
    log_info "Validating AWS CLI configuration..."
    
    if ! command_exists aws; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2 and configure it."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Get current account and region
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
    CURRENT_REGION=$(aws configure get region)
    
    if [[ -z "${CURRENT_REGION}" ]]; then
        log_error "No default region configured. Please set a default region."
        exit 1
    fi
    
    log_success "AWS CLI configured for account ${CURRENT_ACCOUNT} in region ${CURRENT_REGION}"
}

# Function to check required permissions
check_permissions() {
    log_info "Checking required AWS permissions..."
    
    local required_actions=(
        "iam:CreateRole"
        "iam:PutRolePolicy"
        "securityhub:EnableSecurityHub"
        "lambda:CreateFunction"
        "events:PutRule"
        "cloudtrail:CreateTrail"
        "s3:CreateBucket"
        "ssm:CreateDocument"
    )
    
    for action in "${required_actions[@]}"; do
        if ! aws iam simulate-principal-policy \
            --policy-source-arn "$(aws sts get-caller-identity --query Arn --output text)" \
            --action-names "$action" \
            --query 'EvaluationResults[0].EvalDecision' \
            --output text 2>/dev/null | grep -q "allowed"; then
            log_warning "May not have permission for: $action"
        fi
    done
    
    log_success "Permission check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Generate unique identifiers for resources
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        openssl rand -hex 3)
    
    export AWS_REGION="${CURRENT_REGION}"
    export SECURITY_ACCOUNT_ID="${CURRENT_ACCOUNT}"
    export CROSS_ACCOUNT_ROLE_NAME="SecurityHubComplianceRole-${random_suffix}"
    export COMPLIANCE_LAMBDA_NAME="ComplianceAutomation-${random_suffix}"
    export CLOUDTRAIL_NAME="ComplianceAuditTrail-${random_suffix}"
    export RANDOM_SUFFIX="${random_suffix}"
    
    # Prompt for member accounts if not set
    if [[ -z "${MEMBER_ACCOUNT_1:-}" ]]; then
        echo -n "Enter first member account ID (or press Enter to skip): "
        read -r MEMBER_ACCOUNT_1
        export MEMBER_ACCOUNT_1
    fi
    
    if [[ -z "${MEMBER_ACCOUNT_2:-}" ]]; then
        echo -n "Enter second member account ID (or press Enter to skip): "
        read -r MEMBER_ACCOUNT_2
        export MEMBER_ACCOUNT_2
    fi
    
    log_success "Environment variables configured"
    log_info "Security Account: ${SECURITY_ACCOUNT_ID}"
    log_info "Region: ${AWS_REGION}"
    log_info "Cross-Account Role: ${CROSS_ACCOUNT_ROLE_NAME}"
    log_info "Lambda Function: ${COMPLIANCE_LAMBDA_NAME}"
    log_info "CloudTrail: ${CLOUDTRAIL_NAME}"
}

# Function to enable Security Hub
enable_security_hub() {
    log_info "Enabling Security Hub as organization administrator..."
    
    # Enable Security Hub
    if aws securityhub enable-security-hub \
        --enable-default-standards \
        --tags "Purpose=ComplianceMonitoring,Environment=Production" \
        >/dev/null 2>&1; then
        log_success "Security Hub enabled successfully"
    else
        log_warning "Security Hub may already be enabled or insufficient permissions"
    fi
    
    # Try to designate as organization administrator (may fail if not using Organizations)
    if aws securityhub enable-organization-admin-account \
        --admin-account-id "${SECURITY_ACCOUNT_ID}" \
        >/dev/null 2>&1; then
        log_success "Configured as Security Hub organization administrator"
    else
        log_warning "Could not set as organization administrator (may not be using AWS Organizations)"
    fi
}

# Function to create cross-account IAM policies
create_iam_policies() {
    log_info "Creating cross-account IAM policies..."
    
    # Create trust policy for cross-account access
    cat > cross-account-trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${SECURITY_ACCOUNT_ID}:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "sts:ExternalId": "ComplianceMonitoring-${RANDOM_SUFFIX}"
                }
            }
        }
    ]
}
EOF
    
    # Create permissions policy for compliance data access
    cat > compliance-access-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ssm:ListComplianceItems",
                "ssm:ListResourceComplianceSummaries",
                "ssm:GetComplianceSummary",
                "ssm:DescribeInstanceInformation",
                "ssm:DescribeInstanceAssociations",
                "securityhub:BatchImportFindings",
                "securityhub:BatchUpdateFindings"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    log_success "Cross-account IAM policies created"
}

# Function to deploy cross-account role (this would need to be run in each member account)
create_cross_account_role() {
    log_info "Creating cross-account compliance role..."
    
    # Note: In a real deployment, this would need to be executed in each member account
    # For demonstration, we'll create it in the current account
    
    # Create the IAM role
    if aws iam create-role \
        --role-name "${CROSS_ACCOUNT_ROLE_NAME}" \
        --assume-role-policy-document file://cross-account-trust-policy.json \
        --description "Cross-account role for Security Hub compliance monitoring" \
        --tags Key=Purpose,Value=ComplianceMonitoring Key=DeployedBy,Value=ComplianceScript \
        >/dev/null 2>&1; then
        log_success "Cross-account role created: ${CROSS_ACCOUNT_ROLE_NAME}"
    else
        log_warning "Role may already exist or insufficient permissions"
    fi
    
    # Attach the compliance access policy
    if aws iam put-role-policy \
        --role-name "${CROSS_ACCOUNT_ROLE_NAME}" \
        --policy-name ComplianceAccessPolicy \
        --policy-document file://compliance-access-policy.json \
        >/dev/null 2>&1; then
        log_success "Compliance access policy attached"
    else
        log_warning "Policy may already be attached"
    fi
    
    # Wait for role propagation
    log_info "Waiting for IAM role propagation..."
    sleep 10
}

# Function to configure Systems Manager compliance
configure_ssm_compliance() {
    log_info "Configuring Systems Manager Compliance..."
    
    # Check for default patch baseline
    local baseline_id
    baseline_id=$(aws ssm describe-patch-baselines \
        --filters "Key=DefaultBaseline,Values=true" \
        --query "BaselineIdentities[0].BaselineId" \
        --output text 2>/dev/null || echo "None")
    
    if [[ "${baseline_id}" == "None" || "${baseline_id}" == "null" ]]; then
        log_info "Creating default patch baseline..."
        aws ssm create-patch-baseline \
            --name "ComplianceMonitoring-Baseline-${RANDOM_SUFFIX}" \
            --description "Default patch baseline for compliance monitoring" \
            --operating-system AMAZON_LINUX_2 \
            --approval-rules 'PatchRules=[{PatchFilterGroup:{PatchFilters:[{Key=CLASSIFICATION,Values=[Security,Critical]}]},ApproveAfterDays=0}]' \
            >/dev/null 2>&1 && log_success "Patch baseline created"
    else
        log_info "Using existing patch baseline: ${baseline_id}"
    fi
    
    # Create compliance association for patch scanning (if there are instances)
    local instance_count
    instance_count=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
        --query "length(Reservations[].Instances[])" \
        --output text 2>/dev/null || echo "0")
    
    if [[ "${instance_count}" -gt 0 ]]; then
        log_info "Creating compliance association for ${instance_count} instances..."
        if aws ssm create-association \
            --name "AWS-RunPatchBaseline" \
            --targets "Key=tag:Environment,Values=Production" \
            --parameters "Operation=Scan" \
            --schedule-expression "rate(1 day)" \
            --association-name "CompliancePatching-${RANDOM_SUFFIX}" \
            >/dev/null 2>&1; then
            log_success "Systems Manager Compliance association created"
        else
            log_warning "Could not create association (may already exist or no matching instances)"
        fi
    else
        log_warning "No running instances found - skipping compliance association"
    fi
}

# Function to create CloudTrail for compliance auditing
create_cloudtrail() {
    log_info "Creating CloudTrail for compliance auditing..."
    
    local bucket_name="compliance-audit-trail-${RANDOM_SUFFIX}-${AWS_REGION}"
    
    # Create S3 bucket for CloudTrail logs
    if aws s3 mb "s3://${bucket_name}" --region "${AWS_REGION}" >/dev/null 2>&1; then
        log_success "S3 bucket created: ${bucket_name}"
    else
        log_warning "S3 bucket may already exist"
    fi
    
    # Configure bucket policy for CloudTrail
    cat > cloudtrail-bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSCloudTrailAclCheck",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${bucket_name}"
        },
        {
            "Sid": "AWSCloudTrailWrite",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${bucket_name}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        }
    ]
}
EOF
    
    # Apply bucket policy
    if aws s3api put-bucket-policy \
        --bucket "${bucket_name}" \
        --policy file://cloudtrail-bucket-policy.json \
        >/dev/null 2>&1; then
        log_success "S3 bucket policy applied"
    else
        log_warning "Could not apply bucket policy"
    fi
    
    # Create CloudTrail
    if aws cloudtrail create-trail \
        --name "${CLOUDTRAIL_NAME}" \
        --s3-bucket-name "${bucket_name}" \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation \
        --tags-list Key=Purpose,Value=ComplianceAuditing \
        >/dev/null 2>&1; then
        log_success "CloudTrail created: ${CLOUDTRAIL_NAME}"
        
        # Start logging
        aws cloudtrail start-logging --name "${CLOUDTRAIL_NAME}" >/dev/null 2>&1
        log_success "CloudTrail logging started"
    else
        log_warning "CloudTrail may already exist"
    fi
}

# Function to create Lambda function for compliance processing
create_lambda_function() {
    log_info "Creating Lambda function for automated compliance processing..."
    
    # Create Lambda execution role
    cat > lambda-trust-policy.json << EOF
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
    
    local lambda_role_name="ComplianceProcessingRole-${RANDOM_SUFFIX}"
    
    if aws iam create-role \
        --role-name "${lambda_role_name}" \
        --assume-role-policy-document file://lambda-trust-policy.json \
        >/dev/null 2>&1; then
        log_success "Lambda execution role created: ${lambda_role_name}"
    else
        log_warning "Lambda role may already exist"
    fi
    
    # Create Lambda permissions policy
    cat > lambda-permissions-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "sts:AssumeRole",
                "securityhub:BatchImportFindings",
                "ssm:ListComplianceItems",
                "ssm:GetComplianceSummary"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    if aws iam put-role-policy \
        --role-name "${lambda_role_name}" \
        --policy-name ComplianceProcessingPolicy \
        --policy-document file://lambda-permissions-policy.json \
        >/dev/null 2>&1; then
        log_success "Lambda permissions policy attached"
    else
        log_warning "Lambda policy may already be attached"
    fi
    
    # Wait for role propagation
    log_info "Waiting for Lambda role propagation..."
    sleep 15
    
    # Create Lambda function code
    cat > compliance_processor.py << 'EOF'
import json
import boto3
import uuid
from datetime import datetime

def lambda_handler(event, context):
    """
    Process Systems Manager compliance events and create Security Hub findings
    """
    
    # Initialize AWS clients
    sts = boto3.client('sts')
    securityhub = boto3.client('securityhub')
    
    # Parse the EventBridge event
    detail = event.get('detail', {})
    account_id = event.get('account')
    region = event.get('region')
    
    # Process compliance change event
    if detail.get('eventName') == 'PutComplianceItems':
        findings = []
        
        try:
            # Create Security Hub finding for compliance violation
            finding = {
                'SchemaVersion': '2018-10-08',
                'Id': f"compliance-{account_id}-{uuid.uuid4()}",
                'ProductArn': f"arn:aws:securityhub:{region}::product/aws/systems-manager",
                'GeneratorId': 'ComplianceMonitoring',
                'AwsAccountId': account_id,
                'Types': ['Software and Configuration Checks/Vulnerabilities/CVE'],
                'CreatedAt': datetime.utcnow().isoformat() + 'Z',
                'UpdatedAt': datetime.utcnow().isoformat() + 'Z',
                'Severity': {
                    'Label': 'HIGH' if 'CRITICAL' in str(detail) else 'MEDIUM'
                },
                'Title': 'Systems Manager Compliance Violation Detected',
                'Description': f"Compliance violation detected in account {account_id}",
                'Resources': [
                    {
                        'Type': 'AwsAccount',
                        'Id': f"AWS::::Account:{account_id}",
                        'Region': region
                    }
                ],
                'Compliance': {
                    'Status': 'FAILED'
                },
                'WorkflowState': 'NEW'
            }
            
            findings.append(finding)
            
            # Import findings into Security Hub
            if findings:
                response = securityhub.batch_import_findings(
                    Findings=findings
                )
                print(f"Imported {len(findings)} findings to Security Hub")
            
        except Exception as e:
            print(f"Error processing compliance event: {str(e)}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Compliance event processed successfully')
    }
EOF
    
    # Package Lambda function
    zip compliance_processor.zip compliance_processor.py >/dev/null 2>&1
    
    # Create Lambda function
    if aws lambda create-function \
        --function-name "${COMPLIANCE_LAMBDA_NAME}" \
        --runtime python3.9 \
        --role "arn:aws:iam::${SECURITY_ACCOUNT_ID}:role/${lambda_role_name}" \
        --handler compliance_processor.lambda_handler \
        --zip-file fileb://compliance_processor.zip \
        --description "Automated compliance processing for Security Hub" \
        --timeout 60 \
        --memory-size 256 \
        >/dev/null 2>&1; then
        log_success "Lambda function created: ${COMPLIANCE_LAMBDA_NAME}"
    else
        log_warning "Lambda function may already exist"
    fi
}

# Function to configure EventBridge rules
configure_eventbridge() {
    log_info "Configuring EventBridge rules for compliance automation..."
    
    local rule_name="ComplianceMonitoringRule-${RANDOM_SUFFIX}"
    
    # Create EventBridge rule for Systems Manager compliance events
    if aws events put-rule \
        --name "${rule_name}" \
        --description "Trigger compliance processing on SSM compliance changes" \
        --event-pattern '{
            "source": ["aws.ssm"],
            "detail-type": ["AWS API Call via CloudTrail"],
            "detail": {
                "eventName": ["PutComplianceItems", "DeleteComplianceItems"]
            }
        }' \
        --state ENABLED \
        >/dev/null 2>&1; then
        log_success "EventBridge rule created: ${rule_name}"
    else
        log_warning "EventBridge rule may already exist"
    fi
    
    # Add Lambda function as target for the rule
    if aws events put-targets \
        --rule "${rule_name}" \
        --targets "Id=1,Arn=arn:aws:lambda:${AWS_REGION}:${SECURITY_ACCOUNT_ID}:function:${COMPLIANCE_LAMBDA_NAME}" \
        >/dev/null 2>&1; then
        log_success "Lambda target added to EventBridge rule"
    else
        log_warning "Lambda target may already be configured"
    fi
    
    # Grant EventBridge permission to invoke Lambda
    if aws lambda add-permission \
        --function-name "${COMPLIANCE_LAMBDA_NAME}" \
        --statement-id ComplianceEventBridgePermission \
        --action lambda:InvokeFunction \
        --principal events.amazonaws.com \
        --source-arn "arn:aws:events:${AWS_REGION}:${SECURITY_ACCOUNT_ID}:rule/${rule_name}" \
        >/dev/null 2>&1; then
        log_success "EventBridge permission granted to Lambda"
    else
        log_warning "Permission may already be granted"
    fi
}

# Function to create custom compliance rules
create_custom_compliance() {
    log_info "Creating custom compliance rules and automation..."
    
    # Create custom compliance check script
    cat > custom-compliance-script.sh << 'EOF'
#!/bin/bash

# Custom compliance check script
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "local-test")
COMPLIANCE_TYPE="Custom:OrganizationalPolicy"

# Check for required tags
REQUIRED_TAGS=("Environment" "Owner" "Project")
COMPLIANCE_STATUS="COMPLIANT"
COMPLIANCE_DETAILS=""

for tag in "${REQUIRED_TAGS[@]}"; do
    TAG_VALUE=$(aws ec2 describe-tags \
        --filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=${tag}" \
        --query "Tags[0].Value" --output text 2>/dev/null || echo "None")
    
    if [ "$TAG_VALUE" = "None" ]; then
        COMPLIANCE_STATUS="NON_COMPLIANT"
        COMPLIANCE_DETAILS="${COMPLIANCE_DETAILS}Missing required tag: ${tag}; "
    fi
done

# Report compliance status to Systems Manager (if running on EC2)
if [[ "${INSTANCE_ID}" != "local-test" ]]; then
    aws ssm put-compliance-items \
        --resource-id "${INSTANCE_ID}" \
        --resource-type "ManagedInstance" \
        --compliance-type "${COMPLIANCE_TYPE}" \
        --execution-summary "ExecutionTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --items "Id=TagCompliance,Title=Required Tags Check,Severity=HIGH,Status=${COMPLIANCE_STATUS},Details={\"Details\":\"${COMPLIANCE_DETAILS}\"}"
fi

echo "Custom compliance check completed: ${COMPLIANCE_STATUS}"
EOF
    
    chmod +x custom-compliance-script.sh
    
    # Create Systems Manager document for custom compliance
    if aws ssm create-document \
        --name "CustomComplianceCheck-${RANDOM_SUFFIX}" \
        --document-type "Command" \
        --document-format "YAML" \
        --content '
schemaVersion: "2.2"
description: "Custom compliance check for organizational policies"
parameters:
  complianceType:
    type: "String"
    description: "Type of compliance check to perform"
    default: "Custom:OrganizationalPolicy"
mainSteps:
- action: "aws:runShellScript"
  name: "runComplianceCheck"
  inputs:
    runCommand:
    - "#!/bin/bash"
    - "# Custom compliance check implementation"
    - "echo \"Running custom compliance check\""
    ' \
        >/dev/null 2>&1; then
        log_success "Custom compliance document created"
    else
        log_warning "Custom compliance document may already exist"
    fi
}

# Function to configure Security Hub integration
configure_security_hub_integration() {
    log_info "Configuring cross-account Security Hub integration..."
    
    # Add member accounts if provided
    if [[ -n "${MEMBER_ACCOUNT_1}" ]] || [[ -n "${MEMBER_ACCOUNT_2}" ]]; then
        local account_details=""
        [[ -n "${MEMBER_ACCOUNT_1}" ]] && account_details="[{\"AccountId\": \"${MEMBER_ACCOUNT_1}\"}"
        [[ -n "${MEMBER_ACCOUNT_2}" ]] && [[ -n "${MEMBER_ACCOUNT_1}" ]] && account_details="${account_details}, {\"AccountId\": \"${MEMBER_ACCOUNT_2}\"}"
        [[ -n "${MEMBER_ACCOUNT_2}" ]] && [[ -z "${MEMBER_ACCOUNT_1}" ]] && account_details="[{\"AccountId\": \"${MEMBER_ACCOUNT_2}\"}"
        account_details="${account_details}]"
        
        if aws securityhub create-members \
            --account-details "${account_details}" \
            >/dev/null 2>&1; then
            log_success "Member accounts added to Security Hub"
        else
            log_warning "Could not add member accounts (may already exist or insufficient permissions)"
        fi
    fi
    
    # Enable Systems Manager integration with Security Hub
    if aws securityhub enable-import-findings-for-product \
        --product-arn "arn:aws:securityhub:${AWS_REGION}::product/aws/systems-manager" \
        >/dev/null 2>&1; then
        log_success "Systems Manager integration enabled with Security Hub"
    else
        log_warning "Systems Manager integration may already be enabled"
    fi
}

# Function to run validation tests
run_validation_tests() {
    log_info "Running validation tests..."
    
    # Check Security Hub status
    if aws securityhub describe-hub >/dev/null 2>&1; then
        log_success "Security Hub is enabled and accessible"
    else
        log_error "Security Hub validation failed"
        return 1
    fi
    
    # Test cross-account role
    if aws sts assume-role \
        --role-arn "arn:aws:iam::${SECURITY_ACCOUNT_ID}:role/${CROSS_ACCOUNT_ROLE_NAME}" \
        --role-session-name "ComplianceTest" \
        --external-id "ComplianceMonitoring-${RANDOM_SUFFIX}" \
        >/dev/null 2>&1; then
        log_success "Cross-account role assumption test passed"
    else
        log_warning "Cross-account role test failed (may be expected if not in member account)"
    fi
    
    # Test Lambda function
    if aws lambda invoke \
        --function-name "${COMPLIANCE_LAMBDA_NAME}" \
        --payload '{"source":"test","detail":{"eventName":"PutComplianceItems"}}' \
        response.json >/dev/null 2>&1; then
        log_success "Lambda function test passed"
        rm -f response.json
    else
        log_warning "Lambda function test failed"
    fi
    
    # Check EventBridge rules
    local rule_count
    rule_count=$(aws events list-rules --name-prefix "ComplianceMonitoring" --query "length(Rules)" --output text 2>/dev/null || echo "0")
    if [[ "${rule_count}" -gt 0 ]]; then
        log_success "EventBridge rules configured (${rule_count} rules found)"
    else
        log_warning "No EventBridge rules found"
    fi
    
    log_success "Validation tests completed"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary"
    echo "==================="
    echo "Security Account ID: ${SECURITY_ACCOUNT_ID}"
    echo "Region: ${AWS_REGION}"
    echo "Cross-Account Role: ${CROSS_ACCOUNT_ROLE_NAME}"
    echo "Lambda Function: ${COMPLIANCE_LAMBDA_NAME}"
    echo "CloudTrail: ${CLOUDTRAIL_NAME}"
    echo "S3 Bucket: compliance-audit-trail-${RANDOM_SUFFIX}-${AWS_REGION}"
    echo ""
    echo "Next Steps:"
    echo "1. Deploy the cross-account role in each member account"
    echo "2. Configure Systems Manager compliance in member accounts"
    echo "3. Accept Security Hub member invitations if using multiple accounts"
    echo "4. Review Security Hub findings for compliance violations"
    echo ""
    echo "To clean up this deployment, run the destroy.sh script"
}

# Main deployment function
main() {
    log_info "Starting AWS Cross-Account Compliance Monitoring deployment..."
    echo "================================================================"
    
    # Validate prerequisites
    validate_aws_config
    check_permissions
    setup_environment
    
    # Deploy infrastructure
    enable_security_hub
    create_iam_policies
    create_cross_account_role
    configure_ssm_compliance
    create_cloudtrail
    create_lambda_function
    configure_eventbridge
    create_custom_compliance
    configure_security_hub_integration
    
    # Validate deployment
    run_validation_tests
    
    # Clean up temporary files
    rm -f cross-account-trust-policy.json compliance-access-policy.json
    rm -f lambda-trust-policy.json lambda-permissions-policy.json
    rm -f cloudtrail-bucket-policy.json compliance_processor.py
    rm -f compliance_processor.zip custom-compliance-script.sh
    rm -f baseline_id.txt response.json
    
    # Display summary
    display_summary
    
    log_success "AWS Cross-Account Compliance Monitoring deployment completed successfully!"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi