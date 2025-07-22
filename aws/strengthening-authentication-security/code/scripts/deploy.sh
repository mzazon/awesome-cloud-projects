#!/bin/bash
set -euo pipefail

# AWS Multi-Factor Authentication with IAM and MFA Devices - Deployment Script
# This script implements comprehensive MFA enforcement using AWS IAM

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
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or lacks permissions. Please configure it first."
    fi
    
    # Check required AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check for required permissions
    log "Verifying IAM permissions..."
    if ! aws iam get-user &> /dev/null && ! aws iam list-roles --max-items 1 &> /dev/null; then
        error "Insufficient IAM permissions. Administrator access or equivalent IAM permissions required."
    fi
    
    success "Prerequisites check passed"
}

# Set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    export AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "AWS region not configured, defaulting to us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers with error handling
    if ! RANDOM_PASSWORD=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null); then
        # Fallback random generation
        RANDOM_PASSWORD=$(date +%s | sha256sum | base64 | head -c 6 | tr '[:upper:]' '[:lower:]')
    fi
    
    export TEST_USER_NAME="${TEST_USER_NAME:-test-user-${RANDOM_PASSWORD}}"
    export MFA_POLICY_NAME="${MFA_POLICY_NAME:-EnforceMFA-${RANDOM_PASSWORD}}"
    export ADMIN_GROUP_NAME="${ADMIN_GROUP_NAME:-MFAAdmins-${RANDOM_PASSWORD}}"
    export TEMP_PASSWORD="${TEMP_PASSWORD:-TempPassword123!}"
    
    # Create deployment state file
    cat > deployment_state.json << EOF
{
    "deployment_id": "mfa-deployment-${RANDOM_PASSWORD}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "test_user_name": "$TEST_USER_NAME",
    "mfa_policy_name": "$MFA_POLICY_NAME",
    "admin_group_name": "$ADMIN_GROUP_NAME",
    "resources_created": []
}
EOF
    
    success "Environment configured for MFA setup"
    log "Test User: $TEST_USER_NAME"
    log "MFA Policy: $MFA_POLICY_NAME"
    log "Admin Group: $ADMIN_GROUP_NAME"
}

# Update deployment state
update_state() {
    local resource_type="$1"
    local resource_name="$2"
    local resource_arn="${3:-N/A}"
    
    # Add resource to state file
    jq --arg type "$resource_type" --arg name "$resource_name" --arg arn "$resource_arn" \
        '.resources_created += [{"type": $type, "name": $name, "arn": $arn, "created": now | strftime("%Y-%m-%dT%H:%M:%SZ")}]' \
        deployment_state.json > temp_state.json && mv temp_state.json deployment_state.json
}

# Create test user and group structure
create_users_and_groups() {
    log "Creating test user and group structure..."
    
    # Check if user already exists
    if aws iam get-user --user-name "$TEST_USER_NAME" &> /dev/null; then
        warning "User $TEST_USER_NAME already exists, skipping creation"
    else
        # Create test user
        aws iam create-user --user-name "$TEST_USER_NAME" || error "Failed to create user"
        update_state "IAM_USER" "$TEST_USER_NAME" "arn:aws:iam::${AWS_ACCOUNT_ID}:user/${TEST_USER_NAME}"
        success "Test user created: $TEST_USER_NAME"
        
        # Create login profile for console access
        if aws iam create-login-profile \
            --user-name "$TEST_USER_NAME" \
            --password "$TEMP_PASSWORD" \
            --password-reset-required &> /dev/null; then
            success "Login profile created with temporary password"
            log "Temporary password: $TEMP_PASSWORD"
        else
            warning "Login profile creation failed, user may already have one"
        fi
    fi
    
    # Check if group already exists
    if aws iam get-group --group-name "$ADMIN_GROUP_NAME" &> /dev/null; then
        warning "Group $ADMIN_GROUP_NAME already exists, skipping creation"
    else
        # Create administrative group for MFA users
        aws iam create-group --group-name "$ADMIN_GROUP_NAME" || error "Failed to create group"
        update_state "IAM_GROUP" "$ADMIN_GROUP_NAME" "arn:aws:iam::${AWS_ACCOUNT_ID}:group/${ADMIN_GROUP_NAME}"
        success "Administrative group created: $ADMIN_GROUP_NAME"
    fi
    
    # Add test user to group (idempotent)
    if aws iam add-user-to-group \
        --user-name "$TEST_USER_NAME" \
        --group-name "$ADMIN_GROUP_NAME" &> /dev/null; then
        success "User added to group"
    else
        warning "User may already be in group or operation failed"
    fi
}

# Create MFA enforcement IAM policy
create_mfa_policy() {
    log "Creating MFA enforcement IAM policy..."
    
    # Create comprehensive MFA enforcement policy
    cat > mfa-enforcement-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowViewAccountInfo",
            "Effect": "Allow",
            "Action": [
                "iam:GetAccountPasswordPolicy",
                "iam:ListVirtualMFADevices",
                "iam:GetUser",
                "iam:ListUsers"
            ],
            "Resource": "*"
        },
        {
            "Sid": "AllowManageOwnPasswords",
            "Effect": "Allow",
            "Action": [
                "iam:ChangePassword",
                "iam:GetUser"
            ],
            "Resource": "arn:aws:iam::*:user/${aws:username}"
        },
        {
            "Sid": "AllowManageOwnMFA",
            "Effect": "Allow",
            "Action": [
                "iam:CreateVirtualMFADevice",
                "iam:DeleteVirtualMFADevice",
                "iam:EnableMFADevice",
                "iam:DeactivateMFADevice",
                "iam:ListMFADevices",
                "iam:ResyncMFADevice"
            ],
            "Resource": [
                "arn:aws:iam::*:mfa/${aws:username}",
                "arn:aws:iam::*:user/${aws:username}"
            ]
        },
        {
            "Sid": "DenyAllExceptUnlessMFAAuthenticated",
            "Effect": "Deny",
            "NotAction": [
                "iam:CreateVirtualMFADevice",
                "iam:EnableMFADevice",
                "iam:GetUser",
                "iam:ListMFADevices",
                "iam:ListVirtualMFADevices",
                "iam:ResyncMFADevice",
                "sts:GetSessionToken",
                "iam:ChangePassword",
                "iam:GetAccountPasswordPolicy"
            ],
            "Resource": "*",
            "Condition": {
                "BoolIfExists": {
                    "aws:MultiFactorAuthPresent": "false"
                }
            }
        },
        {
            "Sid": "AllowFullAccessWithMFA",
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*",
            "Condition": {
                "Bool": {
                    "aws:MultiFactorAuthPresent": "true"
                }
            }
        }
    ]
}
EOF
    
    # Check if policy already exists
    if MFA_POLICY_ARN=$(aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${MFA_POLICY_NAME}" --query 'Policy.Arn' --output text 2>/dev/null); then
        warning "Policy $MFA_POLICY_NAME already exists, using existing policy"
    else
        # Create the policy
        MFA_POLICY_ARN=$(aws iam create-policy \
            --policy-name "$MFA_POLICY_NAME" \
            --policy-document file://mfa-enforcement-policy.json \
            --description "Enforce MFA for all AWS access" \
            --query 'Policy.Arn' --output text) || error "Failed to create MFA policy"
        
        update_state "IAM_POLICY" "$MFA_POLICY_NAME" "$MFA_POLICY_ARN"
        success "MFA enforcement policy created: $MFA_POLICY_ARN"
    fi
    
    # Attach policy to group (idempotent)
    if aws iam attach-group-policy \
        --group-name "$ADMIN_GROUP_NAME" \
        --policy-arn "$MFA_POLICY_ARN" &> /dev/null; then
        success "MFA enforcement policy attached to group"
    else
        warning "Policy may already be attached to group"
    fi
    
    # Store policy ARN for cleanup
    echo "$MFA_POLICY_ARN" > mfa_policy_arn.txt
}

# Configure virtual MFA device setup
configure_virtual_mfa() {
    log "Configuring virtual MFA device setup..."
    
    # Check if MFA device already exists
    if MFA_SERIAL=$(aws iam list-virtual-mfa-devices \
        --query "VirtualMFADevices[?User.UserName=='${TEST_USER_NAME}'].SerialNumber" \
        --output text 2>/dev/null) && [ -n "$MFA_SERIAL" ]; then
        warning "Virtual MFA device already exists for user: $MFA_SERIAL"
    else
        # Create virtual MFA device for test user
        if aws iam create-virtual-mfa-device \
            --virtual-mfa-device-name "$TEST_USER_NAME" \
            --outfile mfa-qr-code.png \
            --bootstrap-method QRCodePNG &> /dev/null; then
            
            # Get the serial number of the MFA device
            MFA_SERIAL=$(aws iam list-virtual-mfa-devices \
                --query "VirtualMFADevices[?User.UserName=='${TEST_USER_NAME}'].SerialNumber" \
                --output text)
            
            update_state "MFA_DEVICE" "$TEST_USER_NAME" "$MFA_SERIAL"
            success "Virtual MFA device created"
            success "QR Code saved as: mfa-qr-code.png"
            log "MFA Serial Number: $MFA_SERIAL"
            
            # Store MFA serial for cleanup
            echo "$MFA_SERIAL" > mfa_serial.txt
        else
            error "Failed to create virtual MFA device"
        fi
    fi
    
    # Display setup instructions
    cat << EOF

================================================================================
                         MFA SETUP INSTRUCTIONS
================================================================================

🔐 NEXT STEPS FOR MFA ACTIVATION:
1. Open your authenticator app (Google Authenticator, Authy, etc.)
2. Scan the QR code in mfa-qr-code.png
3. Log into AWS Console with:
   - Account: $AWS_ACCOUNT_ID
   - Username: $TEST_USER_NAME
   - Password: $TEMP_PASSWORD
4. Navigate to IAM > Users > $TEST_USER_NAME > Security Credentials
5. Complete MFA device setup by entering two consecutive codes

🚨 EMERGENCY ACCESS PROCEDURES:
- Always maintain backup codes or alternative access methods
- Consider hardware MFA for critical accounts
- Document emergency procedures for MFA device loss
- Test emergency access procedures regularly

📊 CONSOLE LOGIN URL:
https://${AWS_ACCOUNT_ID}.signin.aws.amazon.com/console

================================================================================

EOF
}

# Implement MFA compliance monitoring
implement_monitoring() {
    log "Implementing MFA compliance monitoring..."
    
    # Check if CloudTrail is enabled
    if ! aws cloudtrail describe-trails --query 'trailList[0].Name' --output text &> /dev/null; then
        warning "CloudTrail is not configured. Some monitoring features may not work."
        warning "Please ensure CloudTrail is enabled for comprehensive MFA monitoring."
    fi
    
    # Create CloudWatch dashboard for MFA monitoring
    cat > mfa-dashboard.json << EOF
{
    "widgets": [
        {
            "type": "metric",
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    ["AWS/CloudTrailMetrics", "MFALoginCount"],
                    [".", "NonMFALoginCount"]
                ],
                "period": 300,
                "stat": "Sum",
                "region": "${AWS_REGION}",
                "title": "MFA vs Non-MFA Logins",
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "log",
            "width": 12,
            "height": 6,
            "properties": {
                "query": "SOURCE '/aws/cloudtrail'\n| fields @timestamp, sourceIPAddress, userIdentity.type, userIdentity.userName, responseElements.ConsoleLogin\n| filter eventName = \"ConsoleLogin\"\n| filter responseElements.ConsoleLogin = \"Success\"\n| stats count() by userIdentity.userName\n| sort count desc",
                "region": "${AWS_REGION}",
                "title": "Console Logins by User",
                "view": "table"
            }
        }
    ]
}
EOF
    
    # Create CloudWatch dashboard
    if aws cloudwatch put-dashboard \
        --dashboard-name "MFA-Security-Dashboard-${RANDOM_PASSWORD}" \
        --dashboard-body file://mfa-dashboard.json &> /dev/null; then
        update_state "CLOUDWATCH_DASHBOARD" "MFA-Security-Dashboard-${RANDOM_PASSWORD}" "N/A"
        success "CloudWatch dashboard created: MFA-Security-Dashboard-${RANDOM_PASSWORD}"
    else
        warning "Failed to create CloudWatch dashboard. CloudTrail may not be configured."
    fi
    
    # Create CloudWatch metric filters only if CloudTrail log group exists
    if aws logs describe-log-groups --log-group-name-prefix "CloudTrail" --query 'logGroups[0].logGroupName' --output text &> /dev/null; then
        CLOUDTRAIL_LOG_GROUP=$(aws logs describe-log-groups --log-group-name-prefix "CloudTrail" --query 'logGroups[0].logGroupName' --output text)
        
        # Create metric filter for MFA events
        if aws logs put-metric-filter \
            --log-group-name "$CLOUDTRAIL_LOG_GROUP" \
            --filter-name "MFAUsageFilter-${RANDOM_PASSWORD}" \
            --filter-pattern '{ ($.eventName = ConsoleLogin) && ($.responseElements.ConsoleLogin = "Success") && ($.additionalEventData.MFAUsed = "Yes") }' \
            --metric-transformations \
                metricName=MFALoginCount,metricNamespace=AWS/CloudTrailMetrics,metricValue=1 &> /dev/null; then
            update_state "METRIC_FILTER" "MFAUsageFilter-${RANDOM_PASSWORD}" "$CLOUDTRAIL_LOG_GROUP"
            success "MFA usage metric filter created"
        else
            warning "Failed to create MFA usage metric filter"
        fi
        
        # Create metric filter for non-MFA events
        if aws logs put-metric-filter \
            --log-group-name "$CLOUDTRAIL_LOG_GROUP" \
            --filter-name "NonMFAUsageFilter-${RANDOM_PASSWORD}" \
            --filter-pattern '{ ($.eventName = ConsoleLogin) && ($.responseElements.ConsoleLogin = "Success") && ($.additionalEventData.MFAUsed = "No") }' \
            --metric-transformations \
                metricName=NonMFALoginCount,metricNamespace=AWS/CloudTrailMetrics,metricValue=1 &> /dev/null; then
            update_state "METRIC_FILTER" "NonMFAUsageFilter-${RANDOM_PASSWORD}" "$CLOUDTRAIL_LOG_GROUP"
            success "Non-MFA usage metric filter created"
        else
            warning "Failed to create non-MFA usage metric filter"
        fi
    else
        warning "CloudTrail log group not found. Metric filters cannot be created."
    fi
    
    # Create alarm for non-MFA logins
    if aws cloudwatch put-metric-alarm \
        --alarm-name "Non-MFA-Console-Logins-${RANDOM_PASSWORD}" \
        --alarm-description "Alert on console logins without MFA" \
        --metric-name NonMFALoginCount \
        --namespace AWS/CloudTrailMetrics \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --treat-missing-data notBreaching &> /dev/null; then
        update_state "CLOUDWATCH_ALARM" "Non-MFA-Console-Logins-${RANDOM_PASSWORD}" "N/A"
        success "CloudWatch alarm created for non-MFA logins"
    else
        warning "Failed to create CloudWatch alarm"
    fi
}

# Validation and testing
run_validation() {
    log "Running validation tests..."
    
    # Test 1: Verify user creation
    if aws iam get-user --user-name "$TEST_USER_NAME" &> /dev/null; then
        success "✅ Test user exists and is accessible"
    else
        error "❌ Test user validation failed"
    fi
    
    # Test 2: Verify group creation and membership
    if aws iam get-groups-for-user --user-name "$TEST_USER_NAME" --query "Groups[?GroupName=='${ADMIN_GROUP_NAME}']" --output text | grep -q "$ADMIN_GROUP_NAME"; then
        success "✅ User is member of MFA admin group"
    else
        error "❌ Group membership validation failed"
    fi
    
    # Test 3: Verify policy attachment
    if aws iam list-attached-group-policies --group-name "$ADMIN_GROUP_NAME" --query "AttachedPolicies[?PolicyName=='${MFA_POLICY_NAME}']" --output text | grep -q "$MFA_POLICY_NAME"; then
        success "✅ MFA policy is attached to group"
    else
        error "❌ Policy attachment validation failed"
    fi
    
    # Test 4: Verify MFA device exists
    if aws iam list-mfa-devices --user-name "$TEST_USER_NAME" --query 'MFADevices[0].SerialNumber' --output text | grep -q "arn:aws:iam"; then
        success "✅ MFA device is configured for user"
    else
        warning "⚠️ MFA device not yet activated (requires manual setup)"
    fi
    
    # Test 5: Policy simulation
    log "Testing policy simulation..."
    if aws iam simulate-principal-policy \
        --policy-source-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:user/${TEST_USER_NAME}" \
        --action-names "s3:ListBuckets" \
        --context-entries ContextKeyName=aws:MultiFactorAuthPresent,ContextKeyValues=false,ContextKeyType=boolean \
        --query 'EvaluationResults[0].EvalDecision' --output text | grep -q "deny"; then
        success "✅ MFA policy correctly denies access without MFA"
    else
        warning "⚠️ Policy simulation results unclear"
    fi
    
    # Generate deployment summary
    cat << EOF

================================================================================
                           DEPLOYMENT SUMMARY
================================================================================

✅ RESOURCES CREATED:
- IAM User: $TEST_USER_NAME
- IAM Group: $ADMIN_GROUP_NAME  
- IAM Policy: $MFA_POLICY_NAME
- MFA Device: Virtual MFA for $TEST_USER_NAME
- CloudWatch Dashboard: MFA-Security-Dashboard-${RANDOM_PASSWORD}
- CloudWatch Alarms: Non-MFA login monitoring

📁 FILES CREATED:
- deployment_state.json (deployment tracking)
- mfa-enforcement-policy.json (policy document)
- mfa-qr-code.png (QR code for MFA setup)
- mfa-dashboard.json (CloudWatch dashboard config)

🔗 CONSOLE ACCESS:
- URL: https://${AWS_ACCOUNT_ID}.signin.aws.amazon.com/console
- Username: $TEST_USER_NAME
- Password: $TEMP_PASSWORD

⚠️ IMPORTANT NEXT STEPS:
1. Complete MFA setup using the QR code
2. Test console login with MFA
3. Review CloudWatch dashboard for monitoring
4. Implement this pattern for production users
5. Run destroy.sh script when testing is complete

📊 COST ESTIMATE:
- IAM resources: Free
- CloudWatch dashboard: ~$3/month
- CloudWatch alarms: $0.10/alarm/month
- CloudTrail (if enabled): $2.00/100,000 events

================================================================================

EOF
}

# Main deployment function
main() {
    log "Starting AWS MFA deployment..."
    
    # Check if jq is available for JSON processing
    if ! command -v jq &> /dev/null; then
        error "jq is required for this script. Please install jq first."
    fi
    
    check_prerequisites
    setup_environment
    create_users_and_groups
    create_mfa_policy
    configure_virtual_mfa
    implement_monitoring
    run_validation
    
    success "🎉 AWS MFA deployment completed successfully!"
    warning "Remember to complete MFA setup and run destroy.sh when finished testing."
}

# Trap for cleanup on script interruption
cleanup_on_exit() {
    if [ -f "temp_state.json" ]; then
        rm -f temp_state.json
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main "$@"