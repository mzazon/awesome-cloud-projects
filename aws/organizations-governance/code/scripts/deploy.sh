#!/bin/bash

# AWS Multi-Account Governance Deployment Script
# Implements Organizations with Service Control Policies for enterprise governance

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
DRY_RUN=false

# Logging function
log() {
    echo -e "${2:-}$(date '+%Y-%m-%d %H:%M:%S') - $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    log "ERROR: $1" "$RED"
}

log_success() {
    log "SUCCESS: $1" "$GREEN"
}

log_info() {
    log "INFO: $1" "$BLUE"
}

log_warning() {
    log "WARNING: $1" "$YELLOW"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check logs at: $LOG_FILE"
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partial deployment due to error..."
    # Note: Actual cleanup would be performed by destroy.sh
    log_info "Run ./destroy.sh to clean up any created resources"
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
AWS Multi-Account Governance Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without making changes
    -r, --region        AWS region (default: from AWS CLI config)
    -v, --verbose       Enable verbose logging

EXAMPLES:
    $0                  Deploy with default settings
    $0 --dry-run        Show deployment plan
    $0 --region us-west-2 --verbose

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Organization management permissions
    - Multiple AWS accounts or ability to create accounts
EOF
}

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
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                error_exit "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI v2."
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ ! "$aws_version" =~ ^2\. ]]; then
        error_exit "AWS CLI v2 is required. Current version: $aws_version"
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Run 'aws configure' first."
    fi
    
    # Check Organizations permissions
    if ! aws organizations describe-organization &> /dev/null 2>&1; then
        log_warning "No existing organization found or insufficient permissions."
        log_info "This script will create a new organization if you have the required permissions."
    fi
    
    log_success "Prerequisites check completed"
}

# Set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        error_exit "AWS region not set. Use --region option or configure AWS CLI."
    fi
    
    # Get management account ID
    export ORG_MGMT_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    local random_suffix
    random_suffix=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 6)")
    
    export ORG_NAME="enterprise-org-${random_suffix}"
    export CLOUDTRAIL_BUCKET="org-cloudtrail-${random_suffix}"
    export CONFIG_BUCKET="org-config-${random_suffix}"
    
    # Create state file for tracking resources
    export STATE_FILE="${SCRIPT_DIR}/.deployment_state"
    touch "$STATE_FILE"
    
    log_success "Environment setup completed"
    log_info "AWS Region: $AWS_REGION"
    log_info "Management Account: $ORG_MGMT_ACCOUNT_ID"
    log_info "CloudTrail Bucket: $CLOUDTRAIL_BUCKET"
}

# Create S3 buckets for logging
create_logging_buckets() {
    log_info "Creating S3 buckets for organization-wide logging..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create S3 bucket: $CLOUDTRAIL_BUCKET"
        log_info "[DRY RUN] Would create S3 bucket: $CONFIG_BUCKET"
        return 0
    fi
    
    # Create CloudTrail bucket
    if aws s3api head-bucket --bucket "$CLOUDTRAIL_BUCKET" 2>/dev/null; then
        log_warning "CloudTrail bucket $CLOUDTRAIL_BUCKET already exists"
    else
        aws s3 mb "s3://${CLOUDTRAIL_BUCKET}" --region "$AWS_REGION"
        echo "CLOUDTRAIL_BUCKET=$CLOUDTRAIL_BUCKET" >> "$STATE_FILE"
        log_success "Created CloudTrail bucket: $CLOUDTRAIL_BUCKET"
    fi
    
    # Create Config bucket
    if aws s3api head-bucket --bucket "$CONFIG_BUCKET" 2>/dev/null; then
        log_warning "Config bucket $CONFIG_BUCKET already exists"
    else
        aws s3 mb "s3://${CONFIG_BUCKET}" --region "$AWS_REGION"
        echo "CONFIG_BUCKET=$CONFIG_BUCKET" >> "$STATE_FILE"
        log_success "Created Config bucket: $CONFIG_BUCKET"
    fi
}

# Create AWS Organization
create_organization() {
    log_info "Creating AWS Organization with all features..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create AWS Organization with all features enabled"
        return 0
    fi
    
    # Check if organization already exists
    if aws organizations describe-organization &> /dev/null; then
        export ORG_ID=$(aws organizations describe-organization --query Organization.Id --output text)
        log_warning "Organization already exists: $ORG_ID"
        
        # Verify all features are enabled
        local feature_set
        feature_set=$(aws organizations describe-organization --query Organization.FeatureSet --output text)
        if [[ "$feature_set" != "ALL" ]]; then
            log_info "Enabling all features for existing organization..."
            aws organizations enable-all-features
        fi
    else
        export ORG_ID=$(aws organizations create-organization \
            --feature-set ALL \
            --query Organization.Id --output text)
        echo "ORG_ID=$ORG_ID" >> "$STATE_FILE"
        log_success "Created organization: $ORG_ID"
    fi
    
    # Verify organization creation
    aws organizations describe-organization \
        --query 'Organization.[Id,MasterAccountId,FeatureSet]' \
        --output table
}

# Create Organizational Units
create_organizational_units() {
    log_info "Creating organizational units..."
    
    local ou_names=("Production" "Development" "Sandbox" "Security")
    local ou_vars=("PROD_OU_ID" "DEV_OU_ID" "SANDBOX_OU_ID" "SECURITY_OU_ID")
    
    for i in "${!ou_names[@]}"; do
        local ou_name="${ou_names[$i]}"
        local ou_var="${ou_vars[$i]}"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would create OU: $ou_name"
            continue
        fi
        
        # Check if OU already exists
        local existing_ou_id
        existing_ou_id=$(aws organizations list-organizational-units \
            --parent-id "$ORG_ID" \
            --query "OrganizationalUnits[?Name=='$ou_name'].Id" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$existing_ou_id" ]]; then
            export "${ou_var}=$existing_ou_id"
            log_warning "OU $ou_name already exists: $existing_ou_id"
        else
            local ou_id
            ou_id=$(aws organizations create-organizational-unit \
                --parent-id "$ORG_ID" \
                --name "$ou_name" \
                --query OrganizationalUnit.Id --output text)
            export "${ou_var}=$ou_id"
            echo "${ou_var}=$ou_id" >> "$STATE_FILE"
            log_success "Created OU $ou_name: $ou_id"
        fi
    done
}

# Enable Service Control Policies
enable_service_control_policies() {
    log_info "Enabling Service Control Policy type..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable SERVICE_CONTROL_POLICY type"
        return 0
    fi
    
    # Check if SCP is already enabled
    local scp_enabled
    scp_enabled=$(aws organizations describe-organization \
        --query 'Organization.AvailablePolicyTypes[?Type==`SERVICE_CONTROL_POLICY`]' \
        --output text)
    
    if [[ -n "$scp_enabled" ]]; then
        log_warning "Service Control Policies already enabled"
    else
        aws organizations enable-policy-type \
            --root-id "$ORG_ID" \
            --policy-type SERVICE_CONTROL_POLICY
        log_success "Enabled Service Control Policies"
    fi
}

# Create Service Control Policies
create_service_control_policies() {
    log_info "Creating Service Control Policies..."
    
    local policy_dir="${SCRIPT_DIR}/../policies"
    mkdir -p "$policy_dir"
    
    # Create cost control SCP
    cat > "${policy_dir}/cost-control-scp.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyExpensiveInstances",
            "Effect": "Deny",
            "Action": [
                "ec2:RunInstances"
            ],
            "Resource": "arn:aws:ec2:*:*:instance/*",
            "Condition": {
                "ForAnyValue:StringLike": {
                    "ec2:InstanceType": [
                        "*.8xlarge",
                        "*.12xlarge",
                        "*.16xlarge",
                        "*.24xlarge",
                        "p3.*",
                        "p4.*",
                        "x1e.*",
                        "r5.*large",
                        "r6i.*large"
                    ]
                }
            }
        },
        {
            "Sid": "DenyExpensiveRDSInstances",
            "Effect": "Deny",
            "Action": [
                "rds:CreateDBInstance",
                "rds:CreateDBCluster"
            ],
            "Resource": "*",
            "Condition": {
                "ForAnyValue:StringLike": {
                    "rds:db-instance-class": [
                        "*.8xlarge",
                        "*.12xlarge",
                        "*.16xlarge",
                        "*.24xlarge"
                    ]
                }
            }
        },
        {
            "Sid": "RequireCostAllocationTags",
            "Effect": "Deny",
            "Action": [
                "ec2:RunInstances",
                "rds:CreateDBInstance",
                "s3:CreateBucket"
            ],
            "Resource": "*",
            "Condition": {
                "Null": {
                    "aws:RequestedRegion": "false"
                },
                "ForAllValues:StringNotEquals": {
                    "aws:TagKeys": [
                        "Department",
                        "Project",
                        "Environment",
                        "Owner"
                    ]
                }
            }
        }
    ]
}
EOF

    # Create security baseline SCP
    cat > "${policy_dir}/security-baseline-scp.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyRootUserActions",
            "Effect": "Deny",
            "Action": "*",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:PrincipalType": "Root"
                }
            }
        },
        {
            "Sid": "DenyCloudTrailDisable",
            "Effect": "Deny",
            "Action": [
                "cloudtrail:StopLogging",
                "cloudtrail:DeleteTrail",
                "cloudtrail:PutEventSelectors",
                "cloudtrail:UpdateTrail"
            ],
            "Resource": "*"
        },
        {
            "Sid": "DenyConfigDisable",
            "Effect": "Deny",
            "Action": [
                "config:DeleteConfigRule",
                "config:DeleteConfigurationRecorder",
                "config:DeleteDeliveryChannel",
                "config:StopConfigurationRecorder"
            ],
            "Resource": "*"
        },
        {
            "Sid": "DenyUnencryptedS3Objects",
            "Effect": "Deny",
            "Action": "s3:PutObject",
            "Resource": "*",
            "Condition": {
                "StringNotEquals": {
                    "s3:x-amz-server-side-encryption": "AES256"
                },
                "Null": {
                    "s3:x-amz-server-side-encryption": "true"
                }
            }
        }
    ]
}
EOF

    # Create region restriction SCP
    cat > "${policy_dir}/region-restriction-scp.json" << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyNonApprovedRegions",
            "Effect": "Deny",
            "NotAction": [
                "iam:*",
                "organizations:*",
                "route53:*",
                "cloudfront:*",
                "waf:*",
                "wafv2:*",
                "waf-regional:*",
                "support:*",
                "trustedadvisor:*"
            ],
            "Resource": "*",
            "Condition": {
                "StringNotEquals": {
                    "aws:RequestedRegion": [
                        "us-east-1",
                        "us-west-2",
                        "eu-west-1"
                    ]
                }
            }
        }
    ]
}
EOF

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create cost control, security baseline, and region restriction SCPs"
        return 0
    fi
    
    # Create policies
    local policies=("cost-control-scp:CostControlPolicy:Policy to control costs and enforce tagging"
                   "security-baseline-scp:SecurityBaselinePolicy:Baseline security controls for all accounts"
                   "region-restriction-scp:RegionRestrictionPolicy:Restrict sandbox accounts to approved regions")
    
    for policy in "${policies[@]}"; do
        IFS=':' read -r file_name policy_name description <<< "$policy"
        
        # Check if policy already exists
        local existing_policy_id
        existing_policy_id=$(aws organizations list-policies \
            --filter SERVICE_CONTROL_POLICY \
            --query "Policies[?Name=='$policy_name'].Id" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$existing_policy_id" ]]; then
            case "$policy_name" in
                "CostControlPolicy") export COST_SCP_ID="$existing_policy_id" ;;
                "SecurityBaselinePolicy") export SECURITY_SCP_ID="$existing_policy_id" ;;
                "RegionRestrictionPolicy") export REGION_SCP_ID="$existing_policy_id" ;;
            esac
            log_warning "Policy $policy_name already exists: $existing_policy_id"
        else
            local policy_id
            policy_id=$(aws organizations create-policy \
                --name "$policy_name" \
                --description "$description" \
                --type SERVICE_CONTROL_POLICY \
                --content "file://${policy_dir}/${file_name}.json" \
                --query Policy.PolicySummary.Id --output text)
            
            case "$policy_name" in
                "CostControlPolicy")
                    export COST_SCP_ID="$policy_id"
                    echo "COST_SCP_ID=$policy_id" >> "$STATE_FILE"
                    ;;
                "SecurityBaselinePolicy")
                    export SECURITY_SCP_ID="$policy_id"
                    echo "SECURITY_SCP_ID=$policy_id" >> "$STATE_FILE"
                    ;;
                "RegionRestrictionPolicy")
                    export REGION_SCP_ID="$policy_id"
                    echo "REGION_SCP_ID=$policy_id" >> "$STATE_FILE"
                    ;;
            esac
            log_success "Created policy $policy_name: $policy_id"
        fi
    done
}

# Attach policies to OUs
attach_policies_to_ous() {
    log_info "Attaching Service Control Policies to Organizational Units..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would attach cost control SCP to Production and Development OUs"
        log_info "[DRY RUN] Would attach security baseline SCP to Production OU"
        log_info "[DRY RUN] Would attach region restriction SCP to Sandbox OU"
        return 0
    fi
    
    # Define policy attachments
    local attachments=(
        "$COST_SCP_ID:$PROD_OU_ID:cost control to Production"
        "$COST_SCP_ID:$DEV_OU_ID:cost control to Development"
        "$SECURITY_SCP_ID:$PROD_OU_ID:security baseline to Production"
        "$REGION_SCP_ID:$SANDBOX_OU_ID:region restriction to Sandbox"
    )
    
    for attachment in "${attachments[@]}"; do
        IFS=':' read -r policy_id target_id description <<< "$attachment"
        
        # Check if policy is already attached
        local attached_targets
        attached_targets=$(aws organizations list-targets-for-policy \
            --policy-id "$policy_id" \
            --query "Targets[?TargetId=='$target_id'].TargetId" \
            --output text 2>/dev/null || echo "")
        
        if [[ -n "$attached_targets" ]]; then
            log_warning "Policy already attached: $description"
        else
            aws organizations attach-policy \
                --policy-id "$policy_id" \
                --target-id "$target_id"
            log_success "Attached $description"
        fi
    done
}

# Set up organization-wide CloudTrail
setup_organization_cloudtrail() {
    log_info "Setting up organization-wide CloudTrail..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure CloudTrail bucket policy and create organization trail"
        return 0
    fi
    
    # Configure bucket policy for CloudTrail
    cat > "${SCRIPT_DIR}/../policies/cloudtrail-bucket-policy.json" << EOF
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
            "Resource": "arn:aws:s3:::${CLOUDTRAIL_BUCKET}"
        },
        {
            "Sid": "AWSCloudTrailWrite",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${CLOUDTRAIL_BUCKET}/*",
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
    aws s3api put-bucket-policy \
        --bucket "$CLOUDTRAIL_BUCKET" \
        --policy "file://${SCRIPT_DIR}/../policies/cloudtrail-bucket-policy.json"
    
    # Check if trail already exists
    local existing_trail
    existing_trail=$(aws cloudtrail describe-trails \
        --query "trailList[?Name=='OrganizationTrail'].TrailARN" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$existing_trail" ]]; then
        export CLOUDTRAIL_ARN="$existing_trail"
        log_warning "CloudTrail OrganizationTrail already exists: $existing_trail"
    else
        export CLOUDTRAIL_ARN=$(aws cloudtrail create-trail \
            --name "OrganizationTrail" \
            --s3-bucket-name "$CLOUDTRAIL_BUCKET" \
            --include-global-service-events \
            --is-multi-region-trail \
            --is-organization-trail \
            --query TrailARN --output text)
        echo "CLOUDTRAIL_ARN=$CLOUDTRAIL_ARN" >> "$STATE_FILE"
        log_success "Created organization-wide CloudTrail: $CLOUDTRAIL_ARN"
    fi
    
    # Start CloudTrail logging
    aws cloudtrail start-logging --name "$CLOUDTRAIL_ARN"
    log_success "Started CloudTrail logging"
}

# Configure billing and cost allocation
configure_billing() {
    log_info "Configuring consolidated billing and cost allocation..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would enable cost allocation tags and create organization budget"
        return 0
    fi
    
    # Enable cost allocation tags (best effort - may fail in some regions)
    local tags=("Department" "Project" "Environment" "Owner")
    for tag in "${tags[@]}"; do
        aws ce put-dimension-key \
            --key "$tag" \
            --match-options EQUALS 2>/dev/null || \
            log_warning "Could not enable cost allocation tag: $tag (may not be supported in this region)"
    done
    
    # Create organization-wide budget
    local current_month
    local next_month
    current_month=$(date -d 'first day of this month' '+%Y-%m-01' 2>/dev/null || date -v1d '+%Y-%m-01')
    next_month=$(date -d 'first day of next month' '+%Y-%m-01' 2>/dev/null || date -v+1m -v1d '+%Y-%m-01')
    
    cat > "${SCRIPT_DIR}/../policies/organization-budget.json" << EOF
{
    "BudgetName": "OrganizationMasterBudget",
    "BudgetLimit": {
        "Amount": "5000",
        "Unit": "USD"
    },
    "TimeUnit": "MONTHLY",
    "TimePeriod": {
        "Start": "${current_month}",
        "End": "${next_month}"
    },
    "BudgetType": "COST",
    "CostFilters": {
        "LinkedAccount": ["${ORG_MGMT_ACCOUNT_ID}"]
    }
}
EOF
    
    # Check if budget already exists
    local existing_budget
    existing_budget=$(aws budgets describe-budgets \
        --account-id "$ORG_MGMT_ACCOUNT_ID" \
        --query "Budgets[?BudgetName=='OrganizationMasterBudget'].BudgetName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$existing_budget" ]]; then
        log_warning "Budget OrganizationMasterBudget already exists"
    else
        aws budgets create-budget \
            --account-id "$ORG_MGMT_ACCOUNT_ID" \
            --budget "file://${SCRIPT_DIR}/../policies/organization-budget.json"
        log_success "Created organization budget"
    fi
}

# Create governance monitoring dashboard
create_governance_dashboard() {
    log_info "Creating governance monitoring dashboard..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create CloudWatch dashboard for governance monitoring"
        return 0
    fi
    
    cat > "${SCRIPT_DIR}/../policies/governance-dashboard.json" << 'EOF'
{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/Organizations", "TotalAccounts" ],
                    [ "AWS/Organizations", "ActiveAccounts" ]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "us-east-1",
                "title": "Organization Account Metrics",
                "period": 300
            }
        },
        {
            "type": "log",
            "x": 0,
            "y": 6,
            "width": 24,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/cloudtrail' | fields @timestamp, sourceIPAddress, userIdentity.type, eventName, errorMessage\n| filter eventName like /organizations/\n| sort @timestamp desc\n| limit 100",
                "region": "us-east-1",
                "title": "Organization API Activity",
                "view": "table"
            }
        }
    ]
}
EOF
    
    # Check if dashboard already exists
    local existing_dashboard
    existing_dashboard=$(aws cloudwatch list-dashboards \
        --query "DashboardEntries[?DashboardName=='OrganizationGovernance'].DashboardName" \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$existing_dashboard" ]]; then
        log_warning "Dashboard OrganizationGovernance already exists"
    else
        aws cloudwatch put-dashboard \
            --dashboard-name "OrganizationGovernance" \
            --dashboard-body "file://${SCRIPT_DIR}/../policies/governance-dashboard.json"
        log_success "Created governance monitoring dashboard"
    fi
}

# Validate deployment
validate_deployment() {
    log_info "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would validate organization structure and policy enforcement"
        return 0
    fi
    
    # Verify organization structure
    log_info "Verifying organization structure..."
    aws organizations list-organizational-units \
        --parent-id "$ORG_ID" \
        --query 'OrganizationalUnits[*].[Name,Id]' \
        --output table
    
    # Check CloudTrail status
    log_info "Checking CloudTrail status..."
    aws cloudtrail get-trail-status \
        --name "OrganizationTrail" \
        --query '[IsLogging,LatestDeliveryTime]' \
        --output table
    
    # List attached policies
    log_info "Verifying policy attachments..."
    for ou_id in "$PROD_OU_ID" "$DEV_OU_ID" "$SANDBOX_OU_ID"; do
        local policies
        policies=$(aws organizations list-policies-for-target \
            --target-id "$ou_id" \
            --filter SERVICE_CONTROL_POLICY \
            --query 'Policies[*].Name' \
            --output text)
        log_info "OU $ou_id has policies: $policies"
    done
    
    log_success "Deployment validation completed"
}

# Main deployment function
main() {
    log_info "Starting AWS Multi-Account Governance deployment..."
    log_info "Log file: $LOG_FILE"
    
    parse_args "$@"
    check_prerequisites
    setup_environment
    
    # Core deployment steps
    create_logging_buckets
    create_organization
    create_organizational_units
    enable_service_control_policies
    create_service_control_policies
    attach_policies_to_ous
    setup_organization_cloudtrail
    configure_billing
    create_governance_dashboard
    
    # Validation
    validate_deployment
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "Dry run completed. No resources were created."
        log_info "Run without --dry-run to deploy the infrastructure."
    else
        log_success "Multi-Account Governance deployment completed successfully!"
        log_info "Organization ID: $ORG_ID"
        log_info "CloudTrail ARN: $CLOUDTRAIL_ARN"
        log_info "View your governance dashboard at: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=OrganizationGovernance"
        log_info "Deployment state saved to: $STATE_FILE"
    fi
}

# Run main function with all arguments
main "$@"