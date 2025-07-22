#!/bin/bash

# AWS Cognito User Pools Deployment Script
# This script implements user authentication with Cognito User Pools
# Recipe: Authenticating Users with Cognito User Pools

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check required permissions (basic check)
    local account_id
    account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [ -z "$account_id" ]; then
        log_error "Unable to retrieve AWS account information. Check your permissions."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        log_warning "No region configured, using default: $AWS_REGION"
    fi
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    export USER_POOL_NAME="ecommerce-users-${RANDOM_SUFFIX}"
    export CLIENT_NAME="ecommerce-web-client-${RANDOM_SUFFIX}"
    export DOMAIN_PREFIX="ecommerce-auth-${RANDOM_SUFFIX}"
    
    log_info "User Pool Name: $USER_POOL_NAME"
    log_info "Client Name: $CLIENT_NAME"
    log_info "Domain Prefix: $DOMAIN_PREFIX"
    log_info "AWS Region: $AWS_REGION"
    log_info "AWS Account ID: $AWS_ACCOUNT_ID"
}

# Function to create user pool
create_user_pool() {
    log_info "Creating Cognito User Pool..."
    
    # Check if user pool already exists
    local existing_pool
    existing_pool=$(aws cognito-idp list-user-pools --max-items 60 \
        --query "UserPools[?Name=='$USER_POOL_NAME'].Id" --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_pool" ] && [ "$existing_pool" != "None" ]; then
        log_warning "User pool '$USER_POOL_NAME' already exists with ID: $existing_pool"
        export USER_POOL_ID="$existing_pool"
        return 0
    fi
    
    # Create user pool with comprehensive configuration
    USER_POOL_ID=$(aws cognito-idp create-user-pool \
        --pool-name "$USER_POOL_NAME" \
        --policies '{
            "PasswordPolicy": {
                "MinimumLength": 12,
                "RequireUppercase": true,
                "RequireLowercase": true,
                "RequireNumbers": true,
                "RequireSymbols": true,
                "TemporaryPasswordValidityDays": 1
            }
        }' \
        --username-attributes email \
        --auto-verified-attributes email \
        --mfa-configuration OPTIONAL \
        --enabled-mfas SOFTWARE_TOKEN_MFA SMS_MFA \
        --device-configuration '{
            "ChallengeRequiredOnNewDevice": true,
            "DeviceOnlyRememberedOnUserPrompt": false
        }' \
        --admin-create-user-config '{
            "AllowAdminCreateUserOnly": false,
            "UnusedAccountValidityDays": 7
        }' \
        --user-attribute-update-settings '{
            "AttributesRequireVerificationBeforeUpdate": ["email"]
        }' \
        --verification-message-template '{
            "DefaultEmailOption": "CONFIRM_WITH_LINK",
            "EmailSubject": "Welcome to ECommerce - Verify Your Email",
            "EmailMessage": "Please click the link to verify your email: {##Verify Email##}",
            "EmailSubjectByLink": "Welcome to ECommerce - Verify Your Email",
            "EmailMessageByLink": "Please click the link to verify your email: {##Verify Email##}"
        }' \
        --query 'UserPool.Id' --output text)
    
    export USER_POOL_ID
    log_success "Created User Pool: $USER_POOL_ID"
}

# Function to configure advanced security features
configure_security_features() {
    log_info "Configuring advanced security features..."
    
    # Enable advanced security features
    aws cognito-idp put-user-pool-add-ons \
        --user-pool-id "$USER_POOL_ID" \
        --user-pool-add-ons AdvancedSecurityMode=ENFORCED 2>/dev/null || {
        log_warning "Failed to enable advanced security mode (may require additional permissions)"
    }
    
    # Set up threat protection configuration
    aws cognito-idp set-risk-configuration \
        --user-pool-id "$USER_POOL_ID" \
        --compromised-credentials-risk-configuration '{
            "EventFilter": ["SIGN_IN", "PASSWORD_CHANGE", "SIGN_UP"],
            "Actions": {
                "EventAction": "BLOCK"
            }
        }' \
        --account-takeover-risk-configuration '{
            "NotifyConfiguration": {
                "From": "noreply@example.com",
                "Subject": "Security Alert for Your Account",
                "HtmlBody": "<p>We detected suspicious activity on your account.</p>",
                "TextBody": "We detected suspicious activity on your account."
            },
            "Actions": {
                "LowAction": {
                    "Notify": true,
                    "EventAction": "NO_ACTION"
                },
                "MediumAction": {
                    "Notify": true,
                    "EventAction": "MFA_IF_CONFIGURED"
                },
                "HighAction": {
                    "Notify": true,
                    "EventAction": "BLOCK"
                }
            }
        }' 2>/dev/null || {
        log_warning "Failed to configure risk settings (may require SES verification)"
    }
    
    log_success "Advanced security features configured"
}

# Function to create user pool client
create_user_pool_client() {
    log_info "Creating User Pool Client..."
    
    # Check if client already exists
    local existing_client
    existing_client=$(aws cognito-idp list-user-pool-clients \
        --user-pool-id "$USER_POOL_ID" \
        --query "UserPoolClients[?ClientName=='$CLIENT_NAME'].ClientId" --output text 2>/dev/null || echo "")
    
    if [ -n "$existing_client" ] && [ "$existing_client" != "None" ]; then
        log_warning "User pool client '$CLIENT_NAME' already exists with ID: $existing_client"
        export CLIENT_ID="$existing_client"
        return 0
    fi
    
    # Create user pool client with OAuth flows
    CLIENT_ID=$(aws cognito-idp create-user-pool-client \
        --user-pool-id "$USER_POOL_ID" \
        --client-name "$CLIENT_NAME" \
        --generate-secret \
        --refresh-token-validity 30 \
        --access-token-validity 60 \
        --id-token-validity 60 \
        --token-validity-units AccessToken=minutes,IdToken=minutes,RefreshToken=days \
        --read-attributes email,email_verified,name,family_name,given_name,phone_number \
        --write-attributes email,name,family_name,given_name,phone_number \
        --explicit-auth-flows ALLOW_USER_SRP_AUTH,ALLOW_REFRESH_TOKEN_AUTH,ALLOW_USER_PASSWORD_AUTH \
        --supported-identity-providers COGNITO \
        --callback-urls https://localhost:3000/callback,https://example.com/callback \
        --logout-urls https://localhost:3000/logout,https://example.com/logout \
        --allowed-o-auth-flows code,implicit \
        --allowed-o-auth-scopes openid,email,profile \
        --allowed-o-auth-flows-user-pool-client \
        --prevent-user-existence-errors ENABLED \
        --enable-token-revocation \
        --auth-session-validity 3 \
        --query 'UserPoolClient.ClientId' --output text)
    
    export CLIENT_ID
    log_success "Created User Pool Client: $CLIENT_ID"
}

# Function to set up hosted UI domain
setup_hosted_ui() {
    log_info "Setting up Hosted UI domain..."
    
    # Check if domain already exists
    local domain_status
    domain_status=$(aws cognito-idp describe-user-pool-domain \
        --domain "$DOMAIN_PREFIX" \
        --query 'DomainDescription.Status' --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$domain_status" = "ACTIVE" ]; then
        log_warning "Domain '$DOMAIN_PREFIX' already exists and is active"
        return 0
    elif [ "$domain_status" != "NOT_FOUND" ]; then
        log_warning "Domain '$DOMAIN_PREFIX' exists with status: $domain_status"
        return 0
    fi
    
    # Create user pool domain for hosted UI
    aws cognito-idp create-user-pool-domain \
        --user-pool-id "$USER_POOL_ID" \
        --domain "$DOMAIN_PREFIX" > /dev/null
    
    # Wait for domain to be active (with timeout)
    local attempts=0
    local max_attempts=30
    while [ $attempts -lt $max_attempts ]; do
        domain_status=$(aws cognito-idp describe-user-pool-domain \
            --domain "$DOMAIN_PREFIX" \
            --query 'DomainDescription.Status' --output text 2>/dev/null || echo "PENDING")
        
        if [ "$domain_status" = "ACTIVE" ]; then
            break
        fi
        
        log_info "Waiting for domain to be active... (attempt $((attempts + 1))/$max_attempts)"
        sleep 10
        attempts=$((attempts + 1))
    done
    
    if [ "$domain_status" != "ACTIVE" ]; then
        log_warning "Domain may not be fully active yet. Status: $domain_status"
    fi
    
    log_success "Created hosted UI domain: https://${DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com"
}

# Function to create user groups
create_user_groups() {
    log_info "Creating user groups for role-based access..."
    
    # List of groups to create
    local groups=(
        "Administrators:Administrator users with full access:1"
        "Customers:Regular customer users:10"
        "PremiumCustomers:Premium customer users with enhanced features:5"
    )
    
    for group_info in "${groups[@]}"; do
        IFS=':' read -r group_name description precedence <<< "$group_info"
        
        # Check if group already exists
        local existing_group
        existing_group=$(aws cognito-idp list-groups \
            --user-pool-id "$USER_POOL_ID" \
            --query "Groups[?GroupName=='$group_name'].GroupName" --output text 2>/dev/null || echo "")
        
        if [ -n "$existing_group" ] && [ "$existing_group" != "None" ]; then
            log_warning "Group '$group_name' already exists"
            continue
        fi
        
        # Create group
        aws cognito-idp create-group \
            --user-pool-id "$USER_POOL_ID" \
            --group-name "$group_name" \
            --description "$description" \
            --precedence "$precedence" > /dev/null
        
        log_success "Created group: $group_name"
    done
}

# Function to configure messaging settings
configure_messaging() {
    log_info "Configuring email and SMS settings..."
    
    # Create SNS role for Cognito if it doesn't exist
    local sns_role_arn
    sns_role_arn=$(aws iam get-role \
        --role-name CognitoSNSRole \
        --query 'Role.Arn' --output text 2>/dev/null || echo "")
    
    if [ -z "$sns_role_arn" ]; then
        log_info "Creating SNS role for Cognito..."
        
        # Create SNS role for Cognito
        aws iam create-role \
            --role-name CognitoSNSRole \
            --assume-role-policy-document '{
                "Version": "2012-10-17",
                "Statement": [{
                    "Effect": "Allow",
                    "Principal": {"Service": "cognito-idp.amazonaws.com"},
                    "Action": "sts:AssumeRole"
                }]
            }' > /dev/null
        
        # Wait for role to be available
        sleep 10
        
        aws iam attach-role-policy \
            --role-name CognitoSNSRole \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSNSFullAccess" > /dev/null
        
        # Wait for policy attachment
        sleep 5
        
        sns_role_arn=$(aws iam get-role \
            --role-name CognitoSNSRole \
            --query 'Role.Arn' --output text)
        
        log_success "Created SNS role: $sns_role_arn"
    else
        log_info "SNS role already exists: $sns_role_arn"
    fi
    
    # Update user pool with SNS configuration
    aws cognito-idp update-user-pool \
        --user-pool-id "$USER_POOL_ID" \
        --sms-configuration SnsCallerArn="$sns_role_arn",ExternalId="cognito-${USER_POOL_ID}" > /dev/null
    
    log_success "Configured SMS delivery settings"
}

# Function to create test users
create_test_users() {
    log_info "Creating test users..."
    
    # Test users configuration
    local users=(
        "admin@example.com:Admin User:Admin:User:Administrators"
        "customer@example.com:Customer User:Customer:User:Customers"
    )
    
    for user_info in "${users[@]}"; do
        IFS=':' read -r username name given_name family_name group_name <<< "$user_info"
        
        # Check if user already exists
        local existing_user
        existing_user=$(aws cognito-idp admin-get-user \
            --user-pool-id "$USER_POOL_ID" \
            --username "$username" \
            --query 'Username' --output text 2>/dev/null || echo "")
        
        if [ -n "$existing_user" ] && [ "$existing_user" != "None" ]; then
            log_warning "User '$username' already exists"
        else
            # Create test user
            aws cognito-idp admin-create-user \
                --user-pool-id "$USER_POOL_ID" \
                --username "$username" \
                --user-attributes Name=email,Value="$username" Name=name,Value="$name" Name=given_name,Value="$given_name" Name=family_name,Value="$family_name" \
                --message-action SUPPRESS \
                --temporary-password "TempPass123!" > /dev/null
            
            log_success "Created user: $username"
        fi
        
        # Add user to group
        aws cognito-idp admin-add-user-to-group \
            --user-pool-id "$USER_POOL_ID" \
            --username "$username" \
            --group-name "$group_name" 2>/dev/null || {
            log_warning "Failed to add user '$username' to group '$group_name' (user may already be in group)"
        }
    done
}

# Function to add custom attributes
add_custom_attributes() {
    log_info "Adding custom attributes..."
    
    # Add custom attributes for business logic
    aws cognito-idp add-custom-attributes \
        --user-pool-id "$USER_POOL_ID" \
        --custom-attributes Name="customer_tier",AttributeDataType="String",DeveloperOnlyAttribute=false,Required=false,StringAttributeConstraints="{\"MinLength\":1,\"MaxLength\":20}" Name="last_login",AttributeDataType="DateTime",DeveloperOnlyAttribute=false,Required=false Name="subscription_status",AttributeDataType="String",DeveloperOnlyAttribute=false,Required=false,StringAttributeConstraints="{\"MinLength\":1,\"MaxLength\":50}" 2>/dev/null || {
        log_warning "Failed to add custom attributes (may already exist)"
    }
    
    log_success "Custom attributes configured"
}

# Function to generate configuration
generate_configuration() {
    log_info "Generating client configuration..."
    
    # Get client secret for server-side applications
    local client_secret
    client_secret=$(aws cognito-idp describe-user-pool-client \
        --user-pool-id "$USER_POOL_ID" \
        --client-id "$CLIENT_ID" \
        --query 'UserPoolClient.ClientSecret' --output text)
    
    # Create configuration file for applications
    cat > cognito-config.json << EOF
{
    "UserPoolId": "$USER_POOL_ID",
    "ClientId": "$CLIENT_ID",
    "ClientSecret": "$client_secret",
    "Region": "$AWS_REGION",
    "HostedUIUrl": "https://${DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com",
    "LoginUrl": "https://${DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com/login?client_id=${CLIENT_ID}&response_type=code&scope=openid+email+profile&redirect_uri=https://localhost:3000/callback",
    "LogoutUrl": "https://${DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com/logout?client_id=${CLIENT_ID}&logout_uri=https://localhost:3000/logout"
}
EOF
    
    log_success "Generated client configuration file: cognito-config.json"
}

# Function to display deployment summary
display_summary() {
    log_info "Deployment Summary:"
    echo "===================="
    echo "User Pool ID: $USER_POOL_ID"
    echo "Client ID: $CLIENT_ID"
    echo "Hosted UI Domain: https://${DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com"
    echo "Login URL: https://${DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com/login?client_id=${CLIENT_ID}&response_type=code&scope=openid+email+profile&redirect_uri=https://localhost:3000/callback"
    echo ""
    echo "Test Users:"
    echo "- admin@example.com (Group: Administrators)"
    echo "- customer@example.com (Group: Customers)"
    echo "- Temporary Password: TempPass123!"
    echo ""
    echo "Configuration file: cognito-config.json"
    echo "===================="
}

# Main deployment function
main() {
    log_info "Starting AWS Cognito User Pools deployment..."
    
    check_prerequisites
    setup_environment
    create_user_pool
    configure_security_features
    create_user_pool_client
    setup_hosted_ui
    create_user_groups
    configure_messaging
    create_test_users
    add_custom_attributes
    generate_configuration
    display_summary
    
    log_success "AWS Cognito User Pools deployment completed successfully!"
    log_info "You can now test the authentication system using the provided URLs and test credentials."
}

# Trap errors and cleanup
trap 'log_error "Deployment failed. Check the error messages above."; exit 1' ERR

# Execute main function
main "$@"