#!/bin/bash

# Deploy script for AWS CodeArtifact Artifact Management
# This script deploys the complete CodeArtifact infrastructure described in the recipe

set -e
set -o pipefail

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

# Function to check if AWS CLI is installed and configured
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
    
    # Check for Node.js/npm (optional for testing)
    if command -v npm &> /dev/null; then
        log_info "npm found - npm package testing will be available"
    else
        log_warning "npm not found - npm package testing will be skipped"
    fi
    
    # Check for Python/pip (optional for testing)
    if command -v pip &> /dev/null; then
        log_info "pip found - Python package testing will be available"
    else
        log_warning "pip not found - Python package testing will be skipped"
    fi
    
    log_success "Prerequisites check completed"
}

# Function to set environment variables
setup_environment() {
    log_info "Setting up environment variables..."
    
    # Set AWS region and account ID
    export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
    if [[ -z "$AWS_REGION" ]]; then
        log_error "AWS region not set. Please set AWS_REGION environment variable or configure AWS CLI."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    if [[ -z "$AWS_ACCOUNT_ID" ]]; then
        log_error "Unable to get AWS Account ID"
        exit 1
    fi
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo $(date +%s | tail -c 6))
    
    # Set domain and repository names
    export DOMAIN_NAME="my-company-domain-${RANDOM_SUFFIX}"
    export NPM_STORE_REPO="npm-store"
    export PYPI_STORE_REPO="pypi-store"
    export TEAM_REPO="team-dev"
    export PROD_REPO="production"
    export DOMAIN_OWNER=${AWS_ACCOUNT_ID}
    
    log_info "Domain: ${DOMAIN_NAME}"
    log_info "AWS Account: ${AWS_ACCOUNT_ID}"
    log_info "Region: ${AWS_REGION}"
    
    log_success "Environment setup completed"
}

# Function to check if domain already exists
check_existing_domain() {
    log_info "Checking if domain already exists..."
    
    if aws codeartifact describe-domain --domain ${DOMAIN_NAME} --region ${AWS_REGION} &> /dev/null; then
        log_warning "Domain ${DOMAIN_NAME} already exists, skipping creation"
        return 0
    fi
    return 1
}

# Function to create CodeArtifact domain
create_domain() {
    if check_existing_domain; then
        return 0
    fi
    
    log_info "Creating CodeArtifact domain..."
    
    aws codeartifact create-domain \
        --domain ${DOMAIN_NAME} \
        --region ${AWS_REGION}
    
    log_success "Created CodeArtifact domain: ${DOMAIN_NAME}"
}

# Function to check if repository exists
check_repository_exists() {
    local repo_name=$1
    aws codeartifact describe-repository \
        --domain ${DOMAIN_NAME} \
        --domain-owner ${DOMAIN_OWNER} \
        --repository ${repo_name} \
        --region ${AWS_REGION} &> /dev/null
}

# Function to create repositories
create_repositories() {
    log_info "Creating repository hierarchy..."
    
    # Create npm store repository
    if ! check_repository_exists ${NPM_STORE_REPO}; then
        aws codeartifact create-repository \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${NPM_STORE_REPO} \
            --description "npm packages from public registry" \
            --region ${AWS_REGION}
        log_success "Created npm store repository"
    else
        log_warning "npm store repository already exists, skipping creation"
    fi
    
    # Create pypi store repository
    if ! check_repository_exists ${PYPI_STORE_REPO}; then
        aws codeartifact create-repository \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${PYPI_STORE_REPO} \
            --description "Python packages from PyPI" \
            --region ${AWS_REGION}
        log_success "Created pypi store repository"
    else
        log_warning "pypi store repository already exists, skipping creation"
    fi
    
    # Create team development repository
    if ! check_repository_exists ${TEAM_REPO}; then
        aws codeartifact create-repository \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${TEAM_REPO} \
            --description "Team development artifacts" \
            --region ${AWS_REGION}
        log_success "Created team development repository"
    else
        log_warning "team development repository already exists, skipping creation"
    fi
    
    # Create production repository
    if ! check_repository_exists ${PROD_REPO}; then
        aws codeartifact create-repository \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${PROD_REPO} \
            --description "Production-ready artifacts" \
            --region ${AWS_REGION}
        log_success "Created production repository"
    else
        log_warning "production repository already exists, skipping creation"
    fi
    
    log_success "Repository hierarchy created"
}

# Function to configure external connections
configure_external_connections() {
    log_info "Configuring external connections..."
    
    # Check if external connection already exists for npm
    if ! aws codeartifact list-repositories-in-domain \
        --domain ${DOMAIN_NAME} \
        --domain-owner ${DOMAIN_OWNER} \
        --region ${AWS_REGION} \
        --query "repositories[?name=='${NPM_STORE_REPO}'].externalConnections[?externalConnectionName=='public:npmjs']" \
        --output text | grep -q "public:npmjs"; then
        
        aws codeartifact associate-external-connection \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${NPM_STORE_REPO} \
            --external-connection "public:npmjs" \
            --region ${AWS_REGION}
        log_success "Configured external connection to npmjs"
    else
        log_warning "External connection to npmjs already exists"
    fi
    
    # Check if external connection already exists for pypi
    if ! aws codeartifact list-repositories-in-domain \
        --domain ${DOMAIN_NAME} \
        --domain-owner ${DOMAIN_OWNER} \
        --region ${AWS_REGION} \
        --query "repositories[?name=='${PYPI_STORE_REPO}'].externalConnections[?externalConnectionName=='public:pypi']" \
        --output text | grep -q "public:pypi"; then
        
        aws codeartifact associate-external-connection \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${PYPI_STORE_REPO} \
            --external-connection "public:pypi" \
            --region ${AWS_REGION}
        log_success "Configured external connection to PyPI"
    else
        log_warning "External connection to PyPI already exists"
    fi
    
    log_success "External connections configured"
}

# Function to setup upstream relationships
setup_upstream_relationships() {
    log_info "Setting up repository upstream relationships..."
    
    # Configure team repository with upstream connections
    aws codeartifact update-repository \
        --domain ${DOMAIN_NAME} \
        --domain-owner ${DOMAIN_OWNER} \
        --repository ${TEAM_REPO} \
        --upstreams repositoryName=${NPM_STORE_REPO} repositoryName=${PYPI_STORE_REPO} \
        --region ${AWS_REGION}
    
    # Configure production repository with upstream to team repo
    aws codeartifact update-repository \
        --domain ${DOMAIN_NAME} \
        --domain-owner ${DOMAIN_OWNER} \
        --repository ${PROD_REPO} \
        --upstreams repositoryName=${TEAM_REPO} \
        --region ${AWS_REGION}
    
    log_success "Upstream repository relationships configured"
}

# Function to create IAM policies
create_iam_policies() {
    log_info "Creating IAM policies..."
    
    # Create temporary directory for policy files
    mkdir -p /tmp/codeartifact-policies
    
    # Create developer policy
    cat > /tmp/codeartifact-policies/dev-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "codeartifact:GetAuthorizationToken",
                "codeartifact:GetRepositoryEndpoint",
                "codeartifact:ReadFromRepository",
                "codeartifact:PublishPackageVersion",
                "codeartifact:PutPackageMetadata"
            ],
            "Resource": [
                "arn:aws:codeartifact:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${DOMAIN_NAME}",
                "arn:aws:codeartifact:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${DOMAIN_NAME}/${TEAM_REPO}",
                "arn:aws:codeartifact:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${DOMAIN_NAME}/${NPM_STORE_REPO}",
                "arn:aws:codeartifact:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${DOMAIN_NAME}/${PYPI_STORE_REPO}",
                "arn:aws:codeartifact:${AWS_REGION}:${AWS_ACCOUNT_ID}:package/${DOMAIN_NAME}/${TEAM_REPO}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "sts:GetServiceBearerToken",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "sts:AWSServiceName": "codeartifact.amazonaws.com"
                }
            }
        }
    ]
}
EOF
    
    # Create production policy
    cat > /tmp/codeartifact-policies/prod-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "codeartifact:GetAuthorizationToken",
                "codeartifact:GetRepositoryEndpoint",
                "codeartifact:ReadFromRepository"
            ],
            "Resource": [
                "arn:aws:codeartifact:${AWS_REGION}:${AWS_ACCOUNT_ID}:domain/${DOMAIN_NAME}",
                "arn:aws:codeartifact:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${DOMAIN_NAME}/${PROD_REPO}",
                "arn:aws:codeartifact:${AWS_REGION}:${AWS_ACCOUNT_ID}:package/${DOMAIN_NAME}/${PROD_REPO}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "sts:GetServiceBearerToken",
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "sts:AWSServiceName": "codeartifact.amazonaws.com"
                }
            }
        }
    ]
}
EOF
    
    log_success "IAM policies created in /tmp/codeartifact-policies/"
}

# Function to configure package manager authentication
configure_package_managers() {
    log_info "Configuring package manager authentication..."
    
    # Configure npm if available
    if command -v npm &> /dev/null; then
        aws codeartifact login \
            --tool npm \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${TEAM_REPO} \
            --region ${AWS_REGION}
        log_success "Configured npm authentication"
    else
        log_warning "npm not available, skipping npm configuration"
    fi
    
    # Configure pip if available
    if command -v pip &> /dev/null; then
        aws codeartifact login \
            --tool pip \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${TEAM_REPO} \
            --region ${AWS_REGION}
        log_success "Configured pip authentication"
    else
        log_warning "pip not available, skipping pip configuration"
    fi
    
    log_success "Package manager authentication configured"
}

# Function to configure repository permissions
configure_repository_permissions() {
    log_info "Configuring repository permissions..."
    
    # Create repository policy
    cat > /tmp/codeartifact-policies/team-repo-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
            },
            "Action": [
                "codeartifact:ReadFromRepository",
                "codeartifact:PublishPackageVersion",
                "codeartifact:PutPackageMetadata"
            ],
            "Resource": "*"
        }
    ]
}
EOF
    
    # Apply repository policy
    aws codeartifact put-repository-permissions-policy \
        --domain ${DOMAIN_NAME} \
        --domain-owner ${DOMAIN_OWNER} \
        --repository ${TEAM_REPO} \
        --policy-document file:///tmp/codeartifact-policies/team-repo-policy.json \
        --region ${AWS_REGION}
    
    log_success "Repository permissions configured"
}

# Function to test package installation (optional)
test_package_installation() {
    log_info "Testing package installation (optional)..."
    
    # Test npm package installation if npm is available
    if command -v npm &> /dev/null; then
        log_info "Testing npm package installation..."
        NPM_REGISTRY=$(aws codeartifact get-repository-endpoint \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${TEAM_REPO} \
            --format npm \
            --region ${AWS_REGION} \
            --query repositoryEndpoint --output text)
        
        # Create temporary package.json for testing
        mkdir -p /tmp/npm-test
        cd /tmp/npm-test
        echo '{"name": "test-app", "version": "1.0.0"}' > package.json
        
        if npm install lodash --registry ${NPM_REGISTRY} &> /dev/null; then
            log_success "npm package installation test successful"
        else
            log_warning "npm package installation test failed"
        fi
        
        cd - > /dev/null
        rm -rf /tmp/npm-test
    fi
    
    # Test pip package installation if pip is available
    if command -v pip &> /dev/null; then
        log_info "Testing pip package installation..."
        PIP_INDEX_URL=$(aws codeartifact get-repository-endpoint \
            --domain ${DOMAIN_NAME} \
            --domain-owner ${DOMAIN_OWNER} \
            --repository ${TEAM_REPO} \
            --format pypi \
            --region ${AWS_REGION} \
            --query repositoryEndpoint --output text)simple/
        
        if pip install requests --index-url ${PIP_INDEX_URL} --target /tmp/pip-test &> /dev/null; then
            log_success "pip package installation test successful"
            rm -rf /tmp/pip-test
        else
            log_warning "pip package installation test failed"
        fi
    fi
}

# Function to save deployment info
save_deployment_info() {
    log_info "Saving deployment information..."
    
    cat > codeartifact-deployment.env << EOF
# CodeArtifact Deployment Information
# Generated on $(date)

export AWS_REGION=${AWS_REGION}
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
export DOMAIN_NAME=${DOMAIN_NAME}
export NPM_STORE_REPO=${NPM_STORE_REPO}
export PYPI_STORE_REPO=${PYPI_STORE_REPO}
export TEAM_REPO=${TEAM_REPO}
export PROD_REPO=${PROD_REPO}
export DOMAIN_OWNER=${DOMAIN_OWNER}

# Repository endpoints
NPM_ENDPOINT=\$(aws codeartifact get-repository-endpoint --domain ${DOMAIN_NAME} --domain-owner ${DOMAIN_OWNER} --repository ${TEAM_REPO} --format npm --region ${AWS_REGION} --query repositoryEndpoint --output text)
PIP_ENDPOINT=\$(aws codeartifact get-repository-endpoint --domain ${DOMAIN_NAME} --domain-owner ${DOMAIN_OWNER} --repository ${TEAM_REPO} --format pypi --region ${AWS_REGION} --query repositoryEndpoint --output text)simple/

echo "npm registry: \$NPM_ENDPOINT"
echo "pip index URL: \$PIP_ENDPOINT"
EOF
    
    log_success "Deployment information saved to codeartifact-deployment.env"
}

# Main deployment function
main() {
    log_info "Starting CodeArtifact deployment..."
    
    check_prerequisites
    setup_environment
    create_domain
    create_repositories
    configure_external_connections
    setup_upstream_relationships
    create_iam_policies
    configure_package_managers
    configure_repository_permissions
    test_package_installation
    save_deployment_info
    
    log_success "CodeArtifact deployment completed successfully!"
    log_info "Domain: ${DOMAIN_NAME}"
    log_info "Repositories: ${NPM_STORE_REPO}, ${PYPI_STORE_REPO}, ${TEAM_REPO}, ${PROD_REPO}"
    log_info "IAM policies created in /tmp/codeartifact-policies/"
    log_info "Deployment info saved to codeartifact-deployment.env"
    
    echo ""
    log_info "Next steps:"
    echo "1. Source the deployment environment: source codeartifact-deployment.env"
    echo "2. Attach IAM policies to appropriate users/roles"
    echo "3. Test package management with your development tools"
    echo "4. Use destroy.sh to clean up resources when done"
}

# Run main function
main "$@"