#!/bin/bash

# Deploy CloudFormation StackSets for Multi-Account Multi-Region Management
# This script deploys organization-wide governance policies using CloudFormation StackSets

set -e
set -o pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ERROR_LOG="${SCRIPT_DIR}/deploy_errors.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" | tee -a "$ERROR_LOG"
    echo -e "${RED}ERROR: $1${NC}" >&2
}

log_success() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1" | tee -a "$LOG_FILE"
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: $1" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO: $1" | tee -a "$LOG_FILE"
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Check logs for details."
    log_error "Error log: $ERROR_LOG"
    log_error "Full log: $LOG_FILE"
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions
    local caller_identity=$(aws sts get-caller-identity --output json)
    local account_id=$(echo "$caller_identity" | jq -r '.Account')
    local user_arn=$(echo "$caller_identity" | jq -r '.Arn')
    
    log_info "Authenticated as: $user_arn"
    log_info "Account ID: $account_id"
    
    # Check if Organizations is enabled
    if ! aws organizations describe-organization &> /dev/null; then
        log_warning "AWS Organizations not detected. StackSets will use self-managed permissions."
        export USE_SELF_MANAGED="true"
    else
        log_info "AWS Organizations detected. Using service-managed permissions."
        export USE_SELF_MANAGED="false"
    fi
    
    log_success "Prerequisites check completed"
}

# Environment setup
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No AWS region configured. Using default: us-east-1"
    fi
    
    # Get account information
    export MANAGEMENT_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 8 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 8)")
    
    export STACKSET_NAME="org-governance-stackset-${RANDOM_SUFFIX}"
    export TEMPLATE_BUCKET="stackset-templates-${RANDOM_SUFFIX}"
    export EXECUTION_ROLE_STACKSET="execution-roles-stackset-${RANDOM_SUFFIX}"
    
    # Get Organization ID if available
    export ORGANIZATION_ID=$(aws organizations describe-organization \
        --query 'Organization.Id' --output text 2>/dev/null || echo "not-configured")
    
    # Target regions
    export TARGET_REGIONS=${TARGET_REGIONS:-"us-east-1,us-west-2,eu-west-1"}
    
    # Create temporary directory for templates
    export TEMP_DIR=$(mktemp -d)
    
    log_success "Environment configured"
    log_info "Management Account: $MANAGEMENT_ACCOUNT_ID"
    log_info "StackSet Name: $STACKSET_NAME"
    log_info "Template Bucket: $TEMPLATE_BUCKET"
    log_info "Organization ID: $ORGANIZATION_ID"
    log_info "Target Regions: $TARGET_REGIONS"
    log_info "Temporary Directory: $TEMP_DIR"
}

# Create S3 bucket for templates
create_template_bucket() {
    log_info "Creating S3 bucket for templates..."
    
    # Check if bucket already exists
    if aws s3 ls "s3://${TEMPLATE_BUCKET}" &>/dev/null; then
        log_info "Template bucket already exists: $TEMPLATE_BUCKET"
        return 0
    fi
    
    # Create bucket with region-specific location constraint
    if [ "$AWS_REGION" = "us-east-1" ]; then
        aws s3 mb "s3://${TEMPLATE_BUCKET}" --region "$AWS_REGION"
    else
        aws s3 mb "s3://${TEMPLATE_BUCKET}" --region "$AWS_REGION" --create-bucket-configuration LocationConstraint="$AWS_REGION"
    fi
    
    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$TEMPLATE_BUCKET" \
        --versioning-configuration Status=Enabled
    
    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$TEMPLATE_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'
    
    log_success "Template bucket created: $TEMPLATE_BUCKET"
}

# Setup StackSets permissions
setup_stacksets_permissions() {
    log_info "Setting up StackSets permissions..."
    
    # Enable trusted access for CloudFormation StackSets in Organizations
    if [ "$USE_SELF_MANAGED" = "false" ]; then
        aws organizations enable-aws-service-access \
            --service-principal stacksets.cloudformation.amazonaws.com || true
        log_info "Enabled trusted access for CloudFormation StackSets"
    fi
    
    # Create trust policy for StackSet administrator role
    cat > "$TEMP_DIR/stackset-admin-trust-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudformation.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
    
    # Create StackSet administrator role
    if ! aws iam get-role --role-name AWSCloudFormationStackSetAdministrator &>/dev/null; then
        aws iam create-role \
            --role-name AWSCloudFormationStackSetAdministrator \
            --assume-role-policy-document file://"$TEMP_DIR/stackset-admin-trust-policy.json" \
            --description "CloudFormation StackSet Administrator Role"
        
        log_info "Created StackSet administrator role"
    else
        log_info "StackSet administrator role already exists"
    fi
    
    # Create policy for StackSet administrator
    cat > "$TEMP_DIR/stackset-admin-policy.json" << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sts:AssumeRole"
      ],
      "Resource": [
        "arn:aws:iam::*:role/AWSCloudFormationStackSetExecutionRole"
      ]
    }
  ]
}
EOF
    
    # Create and attach policy
    local policy_arn="arn:aws:iam::${MANAGEMENT_ACCOUNT_ID}:policy/AWSCloudFormationStackSetAdministratorPolicy"
    
    if ! aws iam get-policy --policy-arn "$policy_arn" &>/dev/null; then
        aws iam create-policy \
            --policy-name AWSCloudFormationStackSetAdministratorPolicy \
            --policy-document file://"$TEMP_DIR/stackset-admin-policy.json" \
            --description "Policy for CloudFormation StackSet Administrator"
        
        log_info "Created StackSet administrator policy"
    else
        log_info "StackSet administrator policy already exists"
    fi
    
    # Attach policy to role
    aws iam attach-role-policy \
        --role-name AWSCloudFormationStackSetAdministrator \
        --policy-arn "$policy_arn" || true
    
    log_success "StackSet permissions configured"
}

# Create execution role template
create_execution_role_template() {
    log_info "Creating execution role template..."
    
    cat > "$TEMP_DIR/stackset-execution-role-template.yaml" << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'StackSet execution role for target accounts'

Parameters:
  AdministratorAccountId:
    Type: String
    Description: AWS account ID of the StackSet administrator account

Resources:
  ExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: AWSCloudFormationStackSetExecutionRole
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Sub 'arn:aws:iam::${AdministratorAccountId}:role/AWSCloudFormationStackSetAdministrator'
            Action: sts:AssumeRole
      Path: /
      Policies:
        - PolicyName: StackSetExecutionPolicy
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action: '*'
                Resource: '*'
      Tags:
        - Key: Purpose
          Value: StackSetExecution
        - Key: ManagedBy
          Value: CloudFormationStackSets

Outputs:
  ExecutionRoleArn:
    Description: ARN of the execution role
    Value: !GetAtt ExecutionRole.Arn
    Export:
      Name: !Sub '${AWS::StackName}-ExecutionRoleArn'
EOF
    
    # Upload template to S3
    aws s3 cp "$TEMP_DIR/stackset-execution-role-template.yaml" "s3://${TEMPLATE_BUCKET}/"
    
    log_success "Execution role template created and uploaded"
}

# Create governance template
create_governance_template() {
    log_info "Creating governance template..."
    
    cat > "$TEMP_DIR/governance-template.yaml" << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Organization-wide governance and security policies'

Parameters:
  Environment:
    Type: String
    Default: 'all'
    AllowedValues: ['development', 'staging', 'production', 'all']
    Description: Environment for which policies apply
  
  OrganizationId:
    Type: String
    Description: AWS Organizations ID
  
  ComplianceLevel:
    Type: String
    Default: 'standard'
    AllowedValues: ['basic', 'standard', 'strict']
    Description: Compliance level for security policies

Mappings:
  ComplianceConfig:
    basic:
      PasswordMinLength: 8
      RequireMFA: false
      S3PublicReadBlock: true
      S3PublicWriteBlock: true
    standard:
      PasswordMinLength: 12
      RequireMFA: true
      S3PublicReadBlock: true
      S3PublicWriteBlock: true
    strict:
      PasswordMinLength: 16
      RequireMFA: true
      S3PublicReadBlock: true
      S3PublicWriteBlock: true

Resources:
  # Organization-wide password policy
  PasswordPolicy:
    Type: AWS::IAM::AccountPasswordPolicy
    Properties:
      MinimumPasswordLength: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, PasswordMinLength]
      RequireUppercaseCharacters: true
      RequireLowercaseCharacters: true
      RequireNumbers: true
      RequireSymbols: true
      MaxPasswordAge: 90
      PasswordReusePrevention: 12
      HardExpiry: false
      AllowUsersToChangePassword: true
  
  # S3 bucket for CloudTrail logs
  AuditBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Sub 'org-audit-logs-${AWS::AccountId}-${AWS::Region}-${OrganizationId}'
      PublicAccessBlockConfiguration:
        BlockPublicAcls: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, S3PublicReadBlock]
        BlockPublicPolicy: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, S3PublicWriteBlock]
        IgnorePublicAcls: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, S3PublicReadBlock]
        RestrictPublicBuckets: !FindInMap [ComplianceConfig, !Ref ComplianceLevel, S3PublicWriteBlock]
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      VersioningConfiguration:
        Status: Enabled
      LifecycleConfiguration:
        Rules:
          - Id: DeleteOldLogs
            Status: Enabled
            ExpirationInDays: 2555  # 7 years
            NoncurrentVersionExpirationInDays: 365
      Tags:
        - Key: Purpose
          Value: AuditLogs
        - Key: Environment
          Value: !Ref Environment
  
  # CloudTrail bucket policy
  AuditBucketPolicy:
    Type: AWS::S3::BucketPolicy
    Properties:
      Bucket: !Ref AuditBucket
      PolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Sid: AWSCloudTrailAclCheck
            Effect: Allow
            Principal:
              Service: cloudtrail.amazonaws.com
            Action: s3:GetBucketAcl
            Resource: !GetAtt AuditBucket.Arn
          - Sid: AWSCloudTrailWrite
            Effect: Allow
            Principal:
              Service: cloudtrail.amazonaws.com
            Action: s3:PutObject
            Resource: !Sub '${AuditBucket.Arn}/*'
            Condition:
              StringEquals:
                's3:x-amz-acl': bucket-owner-full-control
  
  # CloudTrail for auditing
  OrganizationCloudTrail:
    Type: AWS::CloudTrail::Trail
    Properties:
      TrailName: !Sub 'organization-audit-trail-${AWS::AccountId}-${AWS::Region}'
      S3BucketName: !Ref AuditBucket
      S3KeyPrefix: !Sub 'cloudtrail-logs/${AWS::AccountId}/'
      IncludeGlobalServiceEvents: true
      IsMultiRegionTrail: true
      EnableLogFileValidation: true
      EventSelectors:
        - ReadWriteType: All
          IncludeManagementEvents: true
          DataResources:
            - Type: AWS::S3::Object
              Values: 
                - "arn:aws:s3:::*/*"
      Tags:
        - Key: Purpose
          Value: OrganizationAudit
        - Key: Environment
          Value: !Ref Environment
  
  # CloudWatch Log Group for monitoring
  AuditLogGroup:
    Type: AWS::Logs::LogGroup
    Properties:
      LogGroupName: !Sub '/aws/cloudtrail/${AWS::AccountId}'
      RetentionInDays: 365
      Tags:
        - Key: Purpose
          Value: AuditLogs
        - Key: Environment
          Value: !Ref Environment
  
  # GuardDuty Detector
  GuardDutyDetector:
    Type: AWS::GuardDuty::Detector
    Properties:
      Enable: true
      FindingPublishingFrequency: FIFTEEN_MINUTES
      Tags:
        - Key: Purpose
          Value: SecurityMonitoring
        - Key: Environment
          Value: !Ref Environment

Outputs:
  CloudTrailArn:
    Description: CloudTrail ARN
    Value: !GetAtt OrganizationCloudTrail.Arn
    Export:
      Name: !Sub '${AWS::StackName}-CloudTrailArn'
  
  AuditBucketName:
    Description: Audit bucket name
    Value: !Ref AuditBucket
    Export:
      Name: !Sub '${AWS::StackName}-AuditBucketName'
  
  GuardDutyDetectorId:
    Description: GuardDuty detector ID
    Value: !Ref GuardDutyDetector
    Export:
      Name: !Sub '${AWS::StackName}-GuardDutyDetectorId'
EOF
    
    # Upload template to S3
    aws s3 cp "$TEMP_DIR/governance-template.yaml" "s3://${TEMPLATE_BUCKET}/"
    
    log_success "Governance template created and uploaded"
}

# Create execution roles StackSet
create_execution_roles_stackset() {
    log_info "Creating execution roles StackSet..."
    
    # Check if StackSet already exists
    if aws cloudformation describe-stack-set --stack-set-name "$EXECUTION_ROLE_STACKSET" &>/dev/null; then
        log_info "Execution roles StackSet already exists"
        return 0
    fi
    
    # Create StackSet
    aws cloudformation create-stack-set \
        --stack-set-name "$EXECUTION_ROLE_STACKSET" \
        --description "Deploy StackSet execution roles to target accounts" \
        --template-url "https://${TEMPLATE_BUCKET}.s3.${AWS_REGION}.amazonaws.com/stackset-execution-role-template.yaml" \
        --parameters ParameterKey=AdministratorAccountId,ParameterValue="$MANAGEMENT_ACCOUNT_ID" \
        --capabilities CAPABILITY_NAMED_IAM \
        --permission-model SELF_MANAGED
    
    log_success "Execution roles StackSet created: $EXECUTION_ROLE_STACKSET"
}

# Deploy execution roles to target accounts
deploy_execution_roles() {
    log_info "Deploying execution roles to target accounts..."
    
    # Get target accounts
    local target_accounts=""
    if [ "$USE_SELF_MANAGED" = "false" ]; then
        target_accounts=$(aws organizations list-accounts \
            --query "Accounts[?Status=='ACTIVE' && Id!='${MANAGEMENT_ACCOUNT_ID}'].Id" \
            --output text | tr '\t' ',')
    fi
    
    if [ -z "$target_accounts" ]; then
        log_warning "No target accounts found in organization or using self-managed mode"
        read -p "Enter comma-separated target account IDs (or press Enter to skip): " target_accounts
        
        if [ -z "$target_accounts" ]; then
            log_warning "No target accounts provided. Skipping execution role deployment."
            return 0
        fi
    fi
    
    export TARGET_ACCOUNTS="$target_accounts"
    log_info "Target accounts: $TARGET_ACCOUNTS"
    
    # Check if instances already exist
    local existing_instances=$(aws cloudformation list-stack-instances \
        --stack-set-name "$EXECUTION_ROLE_STACKSET" \
        --query 'Summaries[].Account' --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_instances" ]; then
        log_info "Execution role instances already exist in some accounts"
        return 0
    fi
    
    # Deploy execution roles
    local operation_id=$(aws cloudformation create-stack-instances \
        --stack-set-name "$EXECUTION_ROLE_STACKSET" \
        --accounts "$TARGET_ACCOUNTS" \
        --regions "$AWS_REGION" \
        --query 'OperationId' --output text)
    
    log_info "Deploying execution roles... Operation ID: $operation_id"
    
    # Wait for completion
    aws cloudformation wait stack-set-operation-complete \
        --stack-set-name "$EXECUTION_ROLE_STACKSET" \
        --operation-id "$operation_id"
    
    log_success "Execution roles deployed to target accounts"
}

# Create governance StackSet
create_governance_stackset() {
    log_info "Creating governance StackSet..."
    
    # Check if StackSet already exists
    if aws cloudformation describe-stack-set --stack-set-name "$STACKSET_NAME" &>/dev/null; then
        log_info "Governance StackSet already exists"
        return 0
    fi
    
    # Determine permission model
    local permission_model="SELF_MANAGED"
    local auto_deployment=""
    
    if [ "$USE_SELF_MANAGED" = "false" ]; then
        permission_model="SERVICE_MANAGED"
        auto_deployment="--auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false"
    fi
    
    # Create StackSet
    aws cloudformation create-stack-set \
        --stack-set-name "$STACKSET_NAME" \
        --description "Organization-wide governance and security policies" \
        --template-url "https://${TEMPLATE_BUCKET}.s3.${AWS_REGION}.amazonaws.com/governance-template.yaml" \
        --parameters ParameterKey=Environment,ParameterValue=all \
                    ParameterKey=OrganizationId,ParameterValue="$ORGANIZATION_ID" \
                    ParameterKey=ComplianceLevel,ParameterValue=standard \
        --capabilities CAPABILITY_IAM \
        --permission-model "$permission_model" \
        $auto_deployment
    
    log_success "Governance StackSet created: $STACKSET_NAME"
}

# Deploy governance StackSet
deploy_governance_stackset() {
    log_info "Deploying governance StackSet..."
    
    # Check if instances already exist
    local existing_instances=$(aws cloudformation list-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --query 'Summaries[].Account' --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_instances" ]; then
        log_info "Governance StackSet instances already exist"
        return 0
    fi
    
    local operation_id=""
    
    if [ "$USE_SELF_MANAGED" = "false" ]; then
        # Deploy to organizational units
        local ou_ids=$(aws organizations list-organizational-units-for-parent \
            --parent-id "$(aws organizations list-roots --query 'Roots[0].Id' --output text)" \
            --query 'OrganizationalUnits[].Id' --output text 2>/dev/null | tr '\t' ',')
        
        if [ -n "$ou_ids" ]; then
            log_info "Deploying to organizational units: $ou_ids"
            operation_id=$(aws cloudformation create-stack-instances \
                --stack-set-name "$STACKSET_NAME" \
                --deployment-targets OrganizationalUnitIds="$ou_ids" \
                --regions "$TARGET_REGIONS" \
                --operation-preferences RegionConcurrencyType=PARALLEL,MaxConcurrentPercentage=100 \
                --query 'OperationId' --output text)
        else
            log_warning "No organizational units found"
        fi
    fi
    
    # If no OUs or self-managed, deploy to accounts directly
    if [ -z "$operation_id" ] && [ -n "$TARGET_ACCOUNTS" ]; then
        log_info "Deploying to accounts directly: $TARGET_ACCOUNTS"
        operation_id=$(aws cloudformation create-stack-instances \
            --stack-set-name "$STACKSET_NAME" \
            --accounts "$TARGET_ACCOUNTS" \
            --regions "$TARGET_REGIONS" \
            --query 'OperationId' --output text)
    fi
    
    if [ -n "$operation_id" ]; then
        log_info "Deploying governance policies... Operation ID: $operation_id"
        
        # Wait for completion
        aws cloudformation wait stack-set-operation-complete \
            --stack-set-name "$STACKSET_NAME" \
            --operation-id "$operation_id"
        
        log_success "Governance policies deployed across organization"
    else
        log_warning "No deployment operation initiated"
    fi
}

# Create monitoring resources
create_monitoring() {
    log_info "Creating monitoring resources..."
    
    # Create SNS topic for alerts
    local alert_topic_arn=$(aws sns create-topic \
        --name "StackSetAlerts-${RANDOM_SUFFIX}" \
        --output text --query TopicArn)
    
    export ALERT_TOPIC_ARN="$alert_topic_arn"
    
    # Create CloudWatch alarm for failed operations
    aws cloudwatch put-metric-alarm \
        --alarm-name "StackSetOperationFailure-${STACKSET_NAME}" \
        --alarm-description "Alert when StackSet operations fail" \
        --metric-name StackSetOperationFailureCount \
        --namespace AWS/CloudFormation \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$alert_topic_arn" \
        --dimensions Name=StackSetName,Value="$STACKSET_NAME"
    
    log_success "Monitoring resources created"
}

# Validation
validate_deployment() {
    log_info "Validating deployment..."
    
    # Check StackSet status
    local stackset_status=$(aws cloudformation describe-stack-set \
        --stack-set-name "$STACKSET_NAME" \
        --query 'StackSet.Status' --output text)
    
    if [ "$stackset_status" != "ACTIVE" ]; then
        log_error "StackSet is not in ACTIVE state: $stackset_status"
        return 1
    fi
    
    # Check stack instances
    local instance_count=$(aws cloudformation list-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --query 'length(Summaries[])' --output text)
    
    log_info "StackSet instances deployed: $instance_count"
    
    # Check for failed instances
    local failed_instances=$(aws cloudformation list-stack-instances \
        --stack-set-name "$STACKSET_NAME" \
        --query 'Summaries[?Status!=`CURRENT`].{Account:Account,Region:Region,Status:Status}' \
        --output json)
    
    if [ "$failed_instances" != "[]" ]; then
        log_error "Found failed stack instances: $failed_instances"
        return 1
    fi
    
    log_success "Deployment validation completed successfully"
}

# Save deployment information
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > "$SCRIPT_DIR/deployment-info.json" << EOF
{
  "deployment_timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "stackset_name": "$STACKSET_NAME",
  "execution_role_stackset": "$EXECUTION_ROLE_STACKSET",
  "template_bucket": "$TEMPLATE_BUCKET",
  "management_account_id": "$MANAGEMENT_ACCOUNT_ID",
  "organization_id": "$ORGANIZATION_ID",
  "target_regions": "$TARGET_REGIONS",
  "target_accounts": "$TARGET_ACCOUNTS",
  "alert_topic_arn": "$ALERT_TOPIC_ARN",
  "use_self_managed": "$USE_SELF_MANAGED",
  "aws_region": "$AWS_REGION"
}
EOF
    
    log_success "Deployment information saved to deployment-info.json"
}

# Main deployment function
main() {
    log_info "Starting CloudFormation StackSets deployment..."
    
    check_prerequisites
    setup_environment
    create_template_bucket
    setup_stacksets_permissions
    create_execution_role_template
    create_governance_template
    create_execution_roles_stackset
    deploy_execution_roles
    create_governance_stackset
    deploy_governance_stackset
    create_monitoring
    validate_deployment
    save_deployment_info
    
    # Cleanup temporary files
    rm -rf "$TEMP_DIR"
    
    log_success "CloudFormation StackSets deployment completed successfully!"
    log_info "Deployment details saved in: $SCRIPT_DIR/deployment-info.json"
    log_info "Logs available at: $LOG_FILE"
    
    echo
    echo -e "${GREEN}🎉 Deployment Summary:${NC}"
    echo -e "${BLUE}   StackSet Name: $STACKSET_NAME${NC}"
    echo -e "${BLUE}   Template Bucket: $TEMPLATE_BUCKET${NC}"
    echo -e "${BLUE}   Target Regions: $TARGET_REGIONS${NC}"
    echo -e "${BLUE}   Management Account: $MANAGEMENT_ACCOUNT_ID${NC}"
    echo -e "${BLUE}   Organization ID: $ORGANIZATION_ID${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "${YELLOW}1. Review the deployment logs for any warnings${NC}"
    echo -e "${YELLOW}2. Check the CloudFormation console for StackSet status${NC}"
    echo -e "${YELLOW}3. Test governance policies in target accounts${NC}"
    echo -e "${YELLOW}4. Set up compliance monitoring and reporting${NC}"
    echo
}

# Run main function
main "$@"