#!/bin/bash

# deploy.sh - Enterprise Authentication with Amplify and External Identity Providers
# This script deploys the complete infrastructure for enterprise authentication integration

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

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
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Cleanup function for trap
cleanup() {
    if [ $? -ne 0 ]; then
        error "Deployment failed. Check the logs above for details."
        warning "You may need to manually clean up partially created resources."
    fi
}
trap cleanup EXIT

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI authentication
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS CLI is not configured or not authenticated."
        exit 1
    fi
    
    # Check Node.js and npm
    if ! command -v node &> /dev/null; then
        error "Node.js is not installed. Please install Node.js 14+ and npm."
        exit 1
    fi
    
    if ! command -v npm &> /dev/null; then
        error "npm is not installed. Please install npm."
        exit 1
    fi
    
    # Check Amplify CLI
    if ! command -v amplify &> /dev/null; then
        warning "Amplify CLI not found. Installing globally..."
        npm install -g @aws-amplify/cli
        if [ $? -ne 0 ]; then
            error "Failed to install Amplify CLI. Please install manually: npm install -g @aws-amplify/cli"
            exit 1
        fi
    fi
    
    success "All prerequisites are satisfied"
}

# Function to set environment variables
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        error "AWS region not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        error "Failed to get AWS account ID. Check AWS CLI configuration."
        exit 1
    fi
    
    # Generate unique identifiers
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    export APP_NAME="enterprise-auth-${RANDOM_SUFFIX}"
    export USER_POOL_NAME="EnterprisePool-${RANDOM_SUFFIX}"
    
    # Save environment variables to file for cleanup script
    cat > .env <<EOF
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
APP_NAME=${APP_NAME}
USER_POOL_NAME=${USER_POOL_NAME}
RANDOM_SUFFIX=${RANDOM_SUFFIX}
EOF
    
    log "Environment configured:"
    log "  AWS Region: ${AWS_REGION}"
    log "  AWS Account: ${AWS_ACCOUNT_ID}"
    log "  App Name: ${APP_NAME}"
    log "  User Pool Name: ${USER_POOL_NAME}"
    
    success "Environment setup complete"
}

# Function to initialize Amplify project
initialize_amplify() {
    log "Initializing Amplify project..."
    
    # Create project directory
    if [ ! -d "${APP_NAME}" ]; then
        mkdir "${APP_NAME}"
    fi
    cd "${APP_NAME}"
    
    # Initialize Amplify project
    log "Running amplify init..."
    amplify init --yes \
        --envName dev \
        --projectName "${APP_NAME}"
    
    if [ $? -ne 0 ]; then
        error "Failed to initialize Amplify project"
        exit 1
    fi
    
    success "Amplify project initialized"
}

# Function to add authentication
add_authentication() {
    log "Adding authentication to Amplify project..."
    
    # Create auth configuration
    cat > amplify/backend/auth/amplify-auth.json <<EOF
{
  "service": "Cognito",
  "providerPlugin": "awscloudformation",
  "dependsOn": [],
  "customAuth": false,
  "frontendAuthConfig": {
    "socialProviders": [],
    "usernameAttributes": ["email"],
    "signupAttributes": ["email"],
    "passwordProtectionSettings": {
      "passwordPolicyMinLength": 8,
      "passwordPolicyCharacters": []
    },
    "mfaConfiguration": "OPTIONAL",
    "mfaTypes": ["SMS"],
    "verificationMechanisms": ["email"]
  }
}
EOF
    
    # Add auth with non-interactive configuration
    echo 'auth' | amplify add auth
    
    if [ $? -ne 0 ]; then
        error "Failed to add authentication"
        exit 1
    fi
    
    success "Authentication added to project"
}

# Function to deploy Amplify backend
deploy_amplify() {
    log "Deploying Amplify backend..."
    
    amplify push --yes
    
    if [ $? -ne 0 ]; then
        error "Failed to deploy Amplify backend"
        exit 1
    fi
    
    # Get User Pool ID
    USER_POOL_ID=$(aws cognito-idp list-user-pools \
        --max-items 20 --query "UserPools[?contains(Name, '${USER_POOL_NAME}')].Id" \
        --output text)
    
    if [ -z "$USER_POOL_ID" ]; then
        # Try alternative method to get User Pool ID
        USER_POOL_ID=$(aws cognito-idp list-user-pools \
            --max-items 50 --query "UserPools[0].Id" --output text)
    fi
    
    if [ -z "$USER_POOL_ID" ]; then
        error "Failed to get User Pool ID"
        exit 1
    fi
    
    export USER_POOL_ID
    echo "USER_POOL_ID=${USER_POOL_ID}" >> ../.env
    
    success "Amplify backend deployed successfully"
    log "User Pool ID: ${USER_POOL_ID}"
}

# Function to configure SAML identity provider
configure_saml_provider() {
    log "Configuring SAML identity provider..."
    
    # Note: This requires actual SAML metadata URL from enterprise IdP
    warning "SAML configuration requires actual metadata URL from your identity provider"
    
    # Create placeholder configuration that can be updated later
    log "Creating placeholder SAML identity provider configuration..."
    log "You will need to update this with your actual SAML metadata URL"
    
    # Save SAML configuration instructions
    cat > ../saml-configuration.txt <<EOF
SAML Identity Provider Configuration Instructions:

1. Replace SAML_METADATA_URL with your actual identity provider metadata URL
2. Run the following command to create the identity provider:

aws cognito-idp create-identity-provider \\
    --user-pool-id ${USER_POOL_ID} \\
    --provider-name "EnterpriseAD" \\
    --provider-type SAML \\
    --provider-details MetadataURL=YOUR_SAML_METADATA_URL \\
    --attribute-mapping email=http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress,family_name=http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname,given_name=http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname

3. Configure your SAML Identity Provider with:
   Entity ID: urn:amazon:cognito:sp:${USER_POOL_ID}
   Reply URL: https://COGNITO_DOMAIN/saml2/idpresponse
   Sign-on URL: https://COGNITO_DOMAIN/login?response_type=code&client_id=APP_CLIENT_ID&redirect_uri=http://localhost:3000/auth/callback

EOF
    
    success "SAML configuration instructions saved to saml-configuration.txt"
}

# Function to configure app client
configure_app_client() {
    log "Configuring app client for federation..."
    
    # Get app client ID
    APP_CLIENT_ID=$(aws cognito-idp list-user-pool-clients \
        --user-pool-id "${USER_POOL_ID}" \
        --query 'UserPoolClients[0].ClientId' --output text)
    
    if [ -z "$APP_CLIENT_ID" ]; then
        error "Failed to get app client ID"
        exit 1
    fi
    
    export APP_CLIENT_ID
    echo "APP_CLIENT_ID=${APP_CLIENT_ID}" >> ../.env
    
    # Update app client for federation
    aws cognito-idp update-user-pool-client \
        --user-pool-id "${USER_POOL_ID}" \
        --client-id "${APP_CLIENT_ID}" \
        --supported-identity-providers "COGNITO" \
        --callback-urls "https://localhost:3000/auth/callback" \
        --logout-urls "https://localhost:3000/auth/logout" \
        --allowed-o-auth-flows "code" \
        --allowed-o-auth-scopes "openid" "email" "profile" \
        --allowed-o-auth-flows-user-pool-client
    
    if [ $? -ne 0 ]; then
        error "Failed to configure app client"
        exit 1
    fi
    
    success "App client configured for federated authentication"
    log "App Client ID: ${APP_CLIENT_ID}"
}

# Function to create Cognito domain
create_cognito_domain() {
    log "Creating Cognito domain..."
    
    DOMAIN_PREFIX="enterprise-auth-${RANDOM_SUFFIX}"
    
    aws cognito-idp create-user-pool-domain \
        --domain "${DOMAIN_PREFIX}" \
        --user-pool-id "${USER_POOL_ID}"
    
    if [ $? -ne 0 ]; then
        error "Failed to create Cognito domain"
        exit 1
    fi
    
    # Wait for domain creation
    log "Waiting for domain to become available..."
    max_attempts=10
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        domain_status=$(aws cognito-idp describe-user-pool-domain \
            --domain "${DOMAIN_PREFIX}" \
            --query 'DomainDescription.Status' --output text 2>/dev/null || echo "CREATING")
        
        if [ "$domain_status" = "ACTIVE" ]; then
            break
        fi
        
        log "Domain status: ${domain_status}. Waiting..."
        sleep 10
        ((attempt++))
    done
    
    if [ $attempt -eq $max_attempts ]; then
        warning "Domain creation taking longer than expected. Check manually."
    fi
    
    export COGNITO_DOMAIN="${DOMAIN_PREFIX}.auth.${AWS_REGION}.amazoncognito.com"
    echo "COGNITO_DOMAIN=${COGNITO_DOMAIN}" >> ../.env
    echo "DOMAIN_PREFIX=${DOMAIN_PREFIX}" >> ../.env
    
    success "Authentication domain created: ${COGNITO_DOMAIN}"
}

# Function to create sample application
create_sample_app() {
    log "Creating sample React application..."
    
    # Create React application
    npx create-react-app frontend --template typescript --yes
    
    if [ $? -ne 0 ]; then
        error "Failed to create React application"
        exit 1
    fi
    
    cd frontend
    
    # Install Amplify libraries
    npm install aws-amplify @aws-amplify/ui-react
    
    if [ $? -ne 0 ]; then
        error "Failed to install Amplify libraries"
        exit 1
    fi
    
    # Configure Amplify
    cat > src/aws-exports.js <<EOF
const awsconfig = {
  Auth: {
    region: '${AWS_REGION}',
    userPoolId: '${USER_POOL_ID}',
    userPoolWebClientId: '${APP_CLIENT_ID}',
    oauth: {
      domain: '${COGNITO_DOMAIN}',
      scope: ['openid', 'email', 'profile'],
      redirectSignIn: 'http://localhost:3000/auth/callback',
      redirectSignOut: 'http://localhost:3000/auth/logout',
      responseType: 'code'
    }
  }
};
export default awsconfig;
EOF
    
    # Create authentication component
    cat > src/App.tsx <<'EOF'
import React from 'react';
import { Amplify } from 'aws-amplify';
import { Authenticator } from '@aws-amplify/ui-react';
import '@aws-amplify/ui-react/styles.css';
import awsconfig from './aws-exports';

Amplify.configure(awsconfig);

function App() {
  return (
    <Authenticator>
      {({ signOut, user }) => (
        <main style={{ padding: '2rem', fontFamily: 'Arial, sans-serif' }}>
          <h1>Enterprise Authentication Demo</h1>
          <div style={{ background: '#f5f5f5', padding: '1rem', borderRadius: '4px', marginBottom: '1rem' }}>
            <h3>User Information:</h3>
            <p><strong>Email:</strong> {user?.attributes?.email}</p>
            <p><strong>User ID:</strong> {user?.userId}</p>
          </div>
          <button 
            onClick={signOut}
            style={{ 
              background: '#ff4757', 
              color: 'white', 
              border: 'none', 
              padding: '0.5rem 1rem', 
              borderRadius: '4px',
              cursor: 'pointer'
            }}
          >
            Sign out
          </button>
        </main>
      )}
    </Authenticator>
  );
}

export default App;
EOF
    
    cd ..
    success "Sample application created and configured"
}

# Function to display deployment summary
display_summary() {
    log "Deployment Summary:"
    echo "==========================================="
    echo "✅ Amplify project initialized: ${APP_NAME}"
    echo "✅ Cognito User Pool created: ${USER_POOL_ID}"
    echo "✅ App Client configured: ${APP_CLIENT_ID}"
    echo "✅ Authentication domain: ${COGNITO_DOMAIN}"
    echo "✅ Sample React application created"
    echo ""
    echo "Next Steps:"
    echo "1. Configure your SAML Identity Provider using instructions in saml-configuration.txt"
    echo "2. Update the SAML provider configuration with actual metadata URL"
    echo "3. Test the application by running: cd ${APP_NAME}/frontend && npm start"
    echo ""
    echo "Configuration files saved:"
    echo "- Environment variables: .env"
    echo "- SAML configuration: saml-configuration.txt"
    echo ""
    warning "Remember to configure your external SAML identity provider before testing federation"
    echo "==========================================="
}

# Main deployment function
main() {
    log "Starting Enterprise Authentication deployment..."
    
    check_prerequisites
    setup_environment
    initialize_amplify
    add_authentication
    deploy_amplify
    configure_saml_provider
    configure_app_client
    create_cognito_domain
    create_sample_app
    
    success "Deployment completed successfully!"
    display_summary
}

# Run main function
main "$@"