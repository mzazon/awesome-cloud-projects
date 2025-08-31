#!/bin/bash

# Service Catalog Portfolio CloudFormation Deployment Script
# This script creates an AWS Service Catalog portfolio with standardized CloudFormation templates
# for S3 buckets and Lambda functions, including proper governance and access controls.

set -e  # Exit on any error
set -u  # Exit on undefined variables

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

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running in dry-run mode
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    warning "Running in DRY-RUN mode - no resources will be created"
fi

# Function to execute commands (respects dry-run mode)
execute_command() {
    local cmd="$1"
    local description="$2"
    
    log "$description"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  [DRY-RUN] Would execute: $cmd"
        return 0
    else
        eval "$cmd"
    fi
}

# Cleanup function for error handling
cleanup_on_error() {
    error "Deployment failed. Starting cleanup of partially created resources..."
    
    # Only cleanup if not in dry-run mode
    if [[ "$DRY_RUN" == "false" ]]; then
        # Remove S3 bucket if it exists
        if [[ -n "${TEMPLATE_BUCKET:-}" ]]; then
            aws s3 rm s3://"${TEMPLATE_BUCKET}" --recursive 2>/dev/null || true
            aws s3 rb s3://"${TEMPLATE_BUCKET}" 2>/dev/null || true
        fi
        
        # Clean up local files
        rm -f s3-bucket-template.yaml lambda-function-template.yaml 2>/dev/null || true
        rm -f servicecatalog-trust-policy.json servicecatalog-launch-policy.json 2>/dev/null || true
    fi
    
    exit 1
}

# Set up error handling
trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    log "AWS CLI version: $AWS_CLI_VERSION"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure' or set environment variables."
        exit 1
    fi
    
    # Check required permissions (basic check)
    log "Verifying AWS permissions..."
    if ! aws servicecatalog list-portfolios &> /dev/null; then
        error "Insufficient permissions. This script requires Service Catalog administrator permissions."
        exit 1
    fi
    
    success "Prerequisites check completed"
}

# Initialize environment variables
initialize_environment() {
    log "Initializing environment variables..."
    
    # Set AWS environment variables
    export AWS_REGION=$(aws configure get region)
    if [[ -z "$AWS_REGION" ]]; then
        error "AWS region not configured. Please set a default region."
        exit 1
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique identifiers for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set resource names with unique suffix
    export PORTFOLIO_NAME="enterprise-infrastructure-${RANDOM_SUFFIX}"
    export S3_PRODUCT_NAME="managed-s3-bucket-${RANDOM_SUFFIX}"
    export LAMBDA_PRODUCT_NAME="serverless-function-${RANDOM_SUFFIX}"
    export TEMPLATE_BUCKET="service-catalog-templates-${RANDOM_SUFFIX}"
    
    log "AWS Region: $AWS_REGION"
    log "AWS Account ID: $AWS_ACCOUNT_ID"
    log "Random Suffix: $RANDOM_SUFFIX"
    log "Portfolio Name: $PORTFOLIO_NAME"
    
    success "Environment initialized"
}

# Create S3 bucket for CloudFormation templates
create_template_bucket() {
    log "Creating S3 bucket for CloudFormation templates..."
    
    execute_command "aws s3 mb s3://${TEMPLATE_BUCKET} --region ${AWS_REGION}" \
        "Creating template storage bucket"
    
    success "Template bucket created: s3://${TEMPLATE_BUCKET}"
}

# Create CloudFormation templates
create_cloudformation_templates() {
    log "Creating CloudFormation templates..."
    
    # Create S3 bucket template
    cat > s3-bucket-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Managed S3 bucket with security best practices'

Parameters:
  BucketName:
    Type: String
    Description: 'Name for the S3 bucket'
    AllowedPattern: '^[a-z0-9][a-z0-9-]*[a-z0-9]$'
    ConstraintDescription: 'Bucket name must be lowercase alphanumeric with hyphens'

  Environment:
    Type: String
    Default: 'development'
    AllowedValues: ['development', 'staging', 'production']
    Description: 'Environment for resource tagging'

Resources:
  S3Bucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: !Ref BucketName
      BucketEncryption:
        ServerSideEncryptionConfiguration:
          - ServerSideEncryptionByDefault:
              SSEAlgorithm: AES256
      VersioningConfiguration:
        Status: Enabled
      PublicAccessBlockConfiguration:
        BlockPublicAcls: true
        BlockPublicPolicy: true
        IgnorePublicAcls: true
        RestrictPublicBuckets: true
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: ServiceCatalog

Outputs:
  BucketName:
    Description: 'Name of the created S3 bucket'
    Value: !Ref S3Bucket
  BucketArn:
    Description: 'ARN of the created S3 bucket'
    Value: !GetAtt S3Bucket.Arn
EOF

    # Create Lambda function template
    cat > lambda-function-template.yaml << 'EOF'
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Managed Lambda function with IAM role and CloudWatch logging'

Parameters:
  FunctionName:
    Type: String
    Description: 'Name for the Lambda function'
    AllowedPattern: '^[a-zA-Z0-9-_]+$'

  Runtime:
    Type: String
    Default: 'python3.12'
    AllowedValues: ['python3.12', 'python3.11', 'nodejs20.x', 'nodejs22.x']
    Description: 'Runtime environment for the function'

  Environment:
    Type: String
    Default: 'development'
    AllowedValues: ['development', 'staging', 'production']
    Description: 'Environment for resource tagging'

Resources:
  LambdaExecutionRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: ServiceCatalog

  LambdaFunction:
    Type: AWS::Lambda::Function
    Properties:
      FunctionName: !Ref FunctionName
      Runtime: !Ref Runtime
      Handler: 'index.handler'
      Role: !GetAtt LambdaExecutionRole.Arn
      Code:
        ZipFile: |
          def handler(event, context):
              return {
                  'statusCode': 200,
                  'body': 'Hello from Service Catalog managed Lambda!'
              }
      Tags:
        - Key: Environment
          Value: !Ref Environment
        - Key: ManagedBy
          Value: ServiceCatalog

Outputs:
  FunctionName:
    Description: 'Name of the created Lambda function'
    Value: !Ref LambdaFunction
  FunctionArn:
    Description: 'ARN of the created Lambda function'
    Value: !GetAtt LambdaFunction.Arn
EOF

    # Upload templates to S3
    execute_command "aws s3 cp s3-bucket-template.yaml s3://${TEMPLATE_BUCKET}/s3-bucket-template.yaml" \
        "Uploading S3 bucket template"
        
    execute_command "aws s3 cp lambda-function-template.yaml s3://${TEMPLATE_BUCKET}/lambda-function-template.yaml" \
        "Uploading Lambda function template"
    
    success "CloudFormation templates created and uploaded"
}

# Create Service Catalog portfolio
create_portfolio() {
    log "Creating Service Catalog portfolio..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        PORTFOLIO_ID=$(aws servicecatalog create-portfolio \
            --display-name "${PORTFOLIO_NAME}" \
            --description "Enterprise infrastructure templates for development teams" \
            --provider-name "IT Infrastructure Team" \
            --query 'PortfolioDetail.Id' --output text)
        
        echo "PORTFOLIO_ID=${PORTFOLIO_ID}" >> deployment.env
        log "Portfolio ID: ${PORTFOLIO_ID}"
    else
        log "[DRY-RUN] Would create portfolio: ${PORTFOLIO_NAME}"
    fi
    
    success "Service Catalog portfolio created"
}

# Create Service Catalog products
create_products() {
    log "Creating Service Catalog products..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Load portfolio ID
        source deployment.env
        
        # Create S3 bucket product
        S3_PRODUCT_ID=$(aws servicecatalog create-product \
            --name "${S3_PRODUCT_NAME}" \
            --description "Managed S3 bucket with security best practices" \
            --owner "IT Infrastructure Team" \
            --product-type "CLOUD_FORMATION_TEMPLATE" \
            --provisioning-artifact-parameters \
                Name="v1.0",Description="Initial version with encryption and versioning",Type="CLOUD_FORMATION_TEMPLATE",Info="{\"LoadTemplateFromURL\":\"https://${TEMPLATE_BUCKET}.s3.${AWS_REGION}.amazonaws.com/s3-bucket-template.yaml\"}" \
            --query 'ProductViewDetail.ProductViewSummary.ProductId' --output text)
        
        # Create Lambda function product
        LAMBDA_PRODUCT_ID=$(aws servicecatalog create-product \
            --name "${LAMBDA_PRODUCT_NAME}" \
            --description "Managed Lambda function with IAM role and logging" \
            --owner "IT Infrastructure Team" \
            --product-type "CLOUD_FORMATION_TEMPLATE" \
            --provisioning-artifact-parameters \
                Name="v1.0",Description="Initial version with execution role",Type="CLOUD_FORMATION_TEMPLATE",Info="{\"LoadTemplateFromURL\":\"https://${TEMPLATE_BUCKET}.s3.${AWS_REGION}.amazonaws.com/lambda-function-template.yaml\"}" \
            --query 'ProductViewDetail.ProductViewSummary.ProductId' --output text)
        
        echo "S3_PRODUCT_ID=${S3_PRODUCT_ID}" >> deployment.env
        echo "LAMBDA_PRODUCT_ID=${LAMBDA_PRODUCT_ID}" >> deployment.env
        
        log "S3 Product ID: ${S3_PRODUCT_ID}"
        log "Lambda Product ID: ${LAMBDA_PRODUCT_ID}"
    else
        log "[DRY-RUN] Would create products: ${S3_PRODUCT_NAME}, ${LAMBDA_PRODUCT_NAME}"
    fi
    
    success "Service Catalog products created"
}

# Associate products with portfolio
associate_products() {
    log "Associating products with portfolio..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Load environment variables
        source deployment.env
        
        # Associate S3 product with portfolio
        execute_command "aws servicecatalog associate-product-with-portfolio \
            --product-id ${S3_PRODUCT_ID} \
            --portfolio-id ${PORTFOLIO_ID}" \
            "Associating S3 product with portfolio"
        
        # Associate Lambda product with portfolio
        execute_command "aws servicecatalog associate-product-with-portfolio \
            --product-id ${LAMBDA_PRODUCT_ID} \
            --portfolio-id ${PORTFOLIO_ID}" \
            "Associating Lambda product with portfolio"
    else
        log "[DRY-RUN] Would associate products with portfolio"
    fi
    
    success "Products associated with portfolio"
}

# Create IAM role for launch constraints
create_launch_role() {
    log "Creating IAM role for launch constraints..."
    
    # Create trust policy for Service Catalog service
    cat > servicecatalog-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "servicecatalog.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Create policy with permissions for S3 and Lambda resources
    cat > servicecatalog-launch-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:DeleteBucket",
                "s3:PutBucketEncryption",
                "s3:PutBucketVersioning",
                "s3:PutBucketPublicAccessBlock",
                "s3:PutBucketTagging",
                "lambda:CreateFunction",
                "lambda:DeleteFunction",
                "lambda:UpdateFunctionCode",
                "lambda:UpdateFunctionConfiguration",
                "lambda:TagResource",
                "lambda:UntagResource",
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:PassRole",
                "iam:TagRole",
                "iam:UntagRole"
            ],
            "Resource": "*"
        }
    ]
}
EOF

    if [[ "$DRY_RUN" == "false" ]]; then
        # Create IAM role
        LAUNCH_ROLE_ARN=$(aws iam create-role \
            --role-name "ServiceCatalogLaunchRole-${RANDOM_SUFFIX}" \
            --assume-role-policy-document file://servicecatalog-trust-policy.json \
            --query 'Role.Arn' --output text)
        
        # Attach policy to role
        execute_command "aws iam put-role-policy \
            --role-name ServiceCatalogLaunchRole-${RANDOM_SUFFIX} \
            --policy-name ServiceCatalogLaunchPolicy \
            --policy-document file://servicecatalog-launch-policy.json" \
            "Attaching launch policy to role"
        
        echo "LAUNCH_ROLE_ARN=${LAUNCH_ROLE_ARN}" >> deployment.env
        echo "LAUNCH_ROLE_NAME=ServiceCatalogLaunchRole-${RANDOM_SUFFIX}" >> deployment.env
        
        log "Launch Role ARN: ${LAUNCH_ROLE_ARN}"
    else
        log "[DRY-RUN] Would create IAM role: ServiceCatalogLaunchRole-${RANDOM_SUFFIX}"
    fi
    
    success "IAM launch role created"
}

# Apply launch constraints
apply_launch_constraints() {
    log "Applying launch constraints to products..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Load environment variables
        source deployment.env
        
        # Apply launch constraint to S3 product
        execute_command "aws servicecatalog create-constraint \
            --portfolio-id ${PORTFOLIO_ID} \
            --product-id ${S3_PRODUCT_ID} \
            --type LAUNCH \
            --parameters '{\"RoleArn\":\"${LAUNCH_ROLE_ARN}\"}'" \
            "Applying launch constraint to S3 product"
        
        # Apply launch constraint to Lambda product
        execute_command "aws servicecatalog create-constraint \
            --portfolio-id ${PORTFOLIO_ID} \
            --product-id ${LAMBDA_PRODUCT_ID} \
            --type LAUNCH \
            --parameters '{\"RoleArn\":\"${LAUNCH_ROLE_ARN}\"}'" \
            "Applying launch constraint to Lambda product"
    else
        log "[DRY-RUN] Would apply launch constraints to products"
    fi
    
    success "Launch constraints applied"
}

# Grant portfolio access
grant_portfolio_access() {
    log "Granting portfolio access to current user..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Load environment variables
        source deployment.env
        
        # Get current user ARN
        CURRENT_USER_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
        
        # Associate current user with portfolio
        execute_command "aws servicecatalog associate-principal-with-portfolio \
            --portfolio-id ${PORTFOLIO_ID} \
            --principal-arn ${CURRENT_USER_ARN} \
            --principal-type IAM" \
            "Granting portfolio access to current user"
        
        echo "CURRENT_USER_ARN=${CURRENT_USER_ARN}" >> deployment.env
        
        log "Current User ARN: ${CURRENT_USER_ARN}"
    else
        log "[DRY-RUN] Would grant portfolio access to current user"
    fi
    
    success "Portfolio access granted"
}

# Validate deployment
validate_deployment() {
    log "Validating deployment..."
    
    if [[ "$DRY_RUN" == "false" ]]; then
        # Load environment variables
        source deployment.env
        
        # Verify portfolio creation
        PORTFOLIO_COUNT=$(aws servicecatalog list-portfolios \
            --query "length(PortfolioDetails[?DisplayName=='${PORTFOLIO_NAME}'])" \
            --output text)
        
        if [[ "$PORTFOLIO_COUNT" != "1" ]]; then
            error "Portfolio validation failed"
            exit 1
        fi
        
        # Verify products in portfolio
        PRODUCT_COUNT=$(aws servicecatalog search-products-as-admin \
            --portfolio-id "${PORTFOLIO_ID}" \
            --query 'length(ProductViewDetails)' --output text)
        
        if [[ "$PRODUCT_COUNT" != "2" ]]; then
            error "Product validation failed. Expected 2 products, found ${PRODUCT_COUNT}"
            exit 1
        fi
        
        log "Portfolio contains ${PRODUCT_COUNT} products"
        
        # Test product search as end user
        AVAILABLE_PRODUCTS=$(aws servicecatalog search-products \
            --query 'length(ProductViewSummaries)' --output text)
        
        log "Found ${AVAILABLE_PRODUCTS} available products for current user"
    else
        log "[DRY-RUN] Would validate deployment"
    fi
    
    success "Deployment validation completed"
}

# Store deployment variables
store_deployment_vars() {
    if [[ "$DRY_RUN" == "false" ]]; then
        echo "RANDOM_SUFFIX=${RANDOM_SUFFIX}" >> deployment.env
        echo "TEMPLATE_BUCKET=${TEMPLATE_BUCKET}" >> deployment.env
        echo "PORTFOLIO_NAME=${PORTFOLIO_NAME}" >> deployment.env
        echo "S3_PRODUCT_NAME=${S3_PRODUCT_NAME}" >> deployment.env
        echo "LAMBDA_PRODUCT_NAME=${LAMBDA_PRODUCT_NAME}" >> deployment.env
        echo "AWS_REGION=${AWS_REGION}" >> deployment.env
        echo "AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}" >> deployment.env
        
        success "Deployment variables stored in deployment.env"
    fi
}

# Main deployment function
main() {
    log "Starting AWS Service Catalog Portfolio deployment..."
    
    check_prerequisites
    initialize_environment
    store_deployment_vars
    create_template_bucket
    create_cloudformation_templates
    create_portfolio
    create_products
    associate_products
    create_launch_role
    apply_launch_constraints
    grant_portfolio_access
    validate_deployment
    
    success "===========================================" 
    success "AWS Service Catalog Portfolio Deployment Complete!"
    success "==========================================="
    
    if [[ "$DRY_RUN" == "false" ]]; then
        log ""
        log "Deployment Summary:"
        log "  Portfolio Name: ${PORTFOLIO_NAME}"
        log "  Template Bucket: s3://${TEMPLATE_BUCKET}"
        log "  AWS Region: ${AWS_REGION}"
        log ""
        log "Next Steps:"
        log "  1. Access AWS Service Catalog in the console"
        log "  2. Browse available products in your portfolio"
        log "  3. Launch S3 buckets and Lambda functions using the templates"
        log ""
        log "To clean up resources, run: ./destroy.sh"
        log ""
        log "All deployment details saved in: deployment.env"
    else
        log ""
        log "DRY-RUN completed successfully. No resources were created."
        log "Run without --dry-run to perform actual deployment."
    fi
}

# Run main function
main "$@"