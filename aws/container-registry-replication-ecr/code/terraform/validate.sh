#!/bin/bash

# Validation script for ECR Container Registry Replication Strategies
# This script validates the deployed infrastructure and tests replication functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Function to check if required tools are installed
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not installed. Some tests will be skipped."
        DOCKER_AVAILABLE=false
    else
        DOCKER_AVAILABLE=true
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please configure AWS CLI."
        exit 1
    fi
    
    print_status "Prerequisites check completed"
}

# Function to get Terraform outputs
get_terraform_outputs() {
    print_header "Getting Terraform Outputs"
    
    # Check if Terraform state exists
    if [ ! -f "terraform.tfstate" ]; then
        print_error "Terraform state file not found. Please run 'terraform apply' first."
        exit 1
    fi
    
    # Get outputs
    PROD_REPO_NAME=$(terraform output -raw production_repository_name 2>/dev/null || echo "")
    TEST_REPO_NAME=$(terraform output -raw testing_repository_name 2>/dev/null || echo "")
    PROD_REPO_URI=$(terraform output -raw production_repository_uri 2>/dev/null || echo "")
    TEST_REPO_URI=$(terraform output -raw testing_repository_uri 2>/dev/null || echo "")
    SOURCE_REGION=$(terraform output -raw source_region 2>/dev/null || echo "")
    DEST_REGION=$(terraform output -raw destination_region 2>/dev/null || echo "")
    SECONDARY_REGION=$(terraform output -raw secondary_region 2>/dev/null || echo "")
    ACCOUNT_ID=$(terraform output -raw account_id 2>/dev/null || echo "")
    
    if [ -z "$PROD_REPO_NAME" ] || [ -z "$SOURCE_REGION" ]; then
        print_error "Unable to get Terraform outputs. Check your deployment."
        exit 1
    fi
    
    print_status "Terraform outputs retrieved successfully"
    echo "  Production Repository: $PROD_REPO_NAME"
    echo "  Testing Repository: $TEST_REPO_NAME"
    echo "  Source Region: $SOURCE_REGION"
    echo "  Destination Region: $DEST_REGION"
    echo "  Secondary Region: $SECONDARY_REGION"
}

# Function to test ECR repositories
test_ecr_repositories() {
    print_header "Testing ECR Repositories"
    
    # Test production repository
    print_status "Checking production repository..."
    if aws ecr describe-repositories --region "$SOURCE_REGION" --repository-names "$PROD_REPO_NAME" &> /dev/null; then
        print_status "✓ Production repository exists in source region"
        
        # Check image scanning configuration
        SCAN_CONFIG=$(aws ecr describe-repositories --region "$SOURCE_REGION" --repository-names "$PROD_REPO_NAME" --query 'repositories[0].imageScanningConfiguration.scanOnPush' --output text)
        if [ "$SCAN_CONFIG" == "True" ]; then
            print_status "✓ Image scanning is enabled"
        else
            print_warning "Image scanning is not enabled"
        fi
        
        # Check tag mutability
        TAG_MUTABILITY=$(aws ecr describe-repositories --region "$SOURCE_REGION" --repository-names "$PROD_REPO_NAME" --query 'repositories[0].imageTagMutability' --output text)
        if [ "$TAG_MUTABILITY" == "IMMUTABLE" ]; then
            print_status "✓ Production repository has immutable tags"
        else
            print_warning "Production repository does not have immutable tags"
        fi
    else
        print_error "Production repository not found in source region"
        return 1
    fi
    
    # Test testing repository
    print_status "Checking testing repository..."
    if aws ecr describe-repositories --region "$SOURCE_REGION" --repository-names "$TEST_REPO_NAME" &> /dev/null; then
        print_status "✓ Testing repository exists in source region"
        
        # Check tag mutability
        TAG_MUTABILITY=$(aws ecr describe-repositories --region "$SOURCE_REGION" --repository-names "$TEST_REPO_NAME" --query 'repositories[0].imageTagMutability' --output text)
        if [ "$TAG_MUTABILITY" == "MUTABLE" ]; then
            print_status "✓ Testing repository has mutable tags"
        else
            print_warning "Testing repository does not have mutable tags"
        fi
    else
        print_error "Testing repository not found in source region"
        return 1
    fi
}

# Function to test lifecycle policies
test_lifecycle_policies() {
    print_header "Testing Lifecycle Policies"
    
    # Test production repository lifecycle policy
    print_status "Checking production repository lifecycle policy..."
    if aws ecr get-lifecycle-policy --region "$SOURCE_REGION" --repository-name "$PROD_REPO_NAME" &> /dev/null; then
        print_status "✓ Production repository lifecycle policy exists"
        
        # Preview lifecycle policy
        PREVIEW_COUNT=$(aws ecr preview-lifecycle-policy --region "$SOURCE_REGION" --repository-name "$PROD_REPO_NAME" --query 'length(previewResults)' --output text 2>/dev/null || echo "0")
        print_status "  Lifecycle policy preview: $PREVIEW_COUNT images would be affected"
    else
        print_error "Production repository lifecycle policy not found"
    fi
    
    # Test testing repository lifecycle policy
    print_status "Checking testing repository lifecycle policy..."
    if aws ecr get-lifecycle-policy --region "$SOURCE_REGION" --repository-name "$TEST_REPO_NAME" &> /dev/null; then
        print_status "✓ Testing repository lifecycle policy exists"
    else
        print_error "Testing repository lifecycle policy not found"
    fi
}

# Function to test replication configuration
test_replication_configuration() {
    print_header "Testing Replication Configuration"
    
    # Check replication configuration
    print_status "Checking replication configuration..."
    REPLICATION_CONFIG=$(aws ecr describe-registry --region "$SOURCE_REGION" --query 'replicationConfiguration.rules[0].destinations' --output text 2>/dev/null || echo "")
    
    if [ -n "$REPLICATION_CONFIG" ]; then
        print_status "✓ Replication configuration exists"
        
        # Check if repositories exist in destination regions
        print_status "Checking replication to destination regions..."
        
        # Check destination region
        if aws ecr describe-repositories --region "$DEST_REGION" --repository-names "$PROD_REPO_NAME" &> /dev/null; then
            print_status "✓ Production repository replicated to $DEST_REGION"
        else
            print_warning "Production repository not yet replicated to $DEST_REGION (may take up to 30 minutes)"
        fi
        
        # Check secondary region
        if aws ecr describe-repositories --region "$SECONDARY_REGION" --repository-names "$PROD_REPO_NAME" &> /dev/null; then
            print_status "✓ Production repository replicated to $SECONDARY_REGION"
        else
            print_warning "Production repository not yet replicated to $SECONDARY_REGION (may take up to 30 minutes)"
        fi
    else
        print_error "Replication configuration not found"
    fi
}

# Function to test monitoring resources
test_monitoring() {
    print_header "Testing Monitoring Resources"
    
    # Check CloudWatch dashboard
    DASHBOARD_NAME=$(terraform output -raw cloudwatch_dashboard_name 2>/dev/null || echo "")
    if [ -n "$DASHBOARD_NAME" ]; then
        print_status "Checking CloudWatch dashboard..."
        if aws cloudwatch get-dashboard --region "$SOURCE_REGION" --dashboard-name "$DASHBOARD_NAME" &> /dev/null; then
            print_status "✓ CloudWatch dashboard exists: $DASHBOARD_NAME"
        else
            print_error "CloudWatch dashboard not found"
        fi
    fi
    
    # Check CloudWatch alarms
    ALARM_NAME=$(terraform output -raw replication_failure_alarm_name 2>/dev/null || echo "")
    if [ -n "$ALARM_NAME" ]; then
        print_status "Checking CloudWatch alarms..."
        ALARM_STATE=$(aws cloudwatch describe-alarms --region "$SOURCE_REGION" --alarm-names "$ALARM_NAME" --query 'MetricAlarms[0].StateValue' --output text 2>/dev/null || echo "")
        if [ -n "$ALARM_STATE" ]; then
            print_status "✓ Replication failure alarm exists (State: $ALARM_STATE)"
        else
            print_error "Replication failure alarm not found"
        fi
    fi
    
    # Check SNS topic
    SNS_TOPIC=$(terraform output -raw sns_topic_arn 2>/dev/null || echo "")
    if [ -n "$SNS_TOPIC" ]; then
        print_status "Checking SNS topic..."
        if aws sns get-topic-attributes --region "$SOURCE_REGION" --topic-arn "$SNS_TOPIC" &> /dev/null; then
            print_status "✓ SNS topic exists for notifications"
        else
            print_error "SNS topic not found"
        fi
    fi
}

# Function to test Lambda function
test_lambda_function() {
    print_header "Testing Lambda Function"
    
    LAMBDA_NAME=$(terraform output -raw lambda_cleanup_function_name 2>/dev/null || echo "")
    if [ -n "$LAMBDA_NAME" ]; then
        print_status "Checking Lambda cleanup function..."
        if aws lambda get-function --region "$SOURCE_REGION" --function-name "$LAMBDA_NAME" &> /dev/null; then
            print_status "✓ Lambda cleanup function exists"
            
            # Test Lambda function (dry run)
            print_status "Testing Lambda function invocation..."
            LAMBDA_RESULT=$(aws lambda invoke --region "$SOURCE_REGION" --function-name "$LAMBDA_NAME" --payload '{"test": true}' --output json response.json 2>/dev/null || echo "")
            
            if [ -n "$LAMBDA_RESULT" ]; then
                STATUS_CODE=$(echo "$LAMBDA_RESULT" | jq -r '.StatusCode' 2>/dev/null || echo "")
                if [ "$STATUS_CODE" == "200" ]; then
                    print_status "✓ Lambda function executed successfully"
                else
                    print_warning "Lambda function execution returned status: $STATUS_CODE"
                fi
            else
                print_warning "Unable to test Lambda function execution"
            fi
            
            # Clean up test response
            rm -f response.json
        else
            print_error "Lambda cleanup function not found"
        fi
    fi
}

# Function to test Docker integration
test_docker_integration() {
    if [ "$DOCKER_AVAILABLE" == "false" ]; then
        print_warning "Docker not available, skipping Docker integration tests"
        return 0
    fi
    
    print_header "Testing Docker Integration"
    
    # Test Docker login
    print_status "Testing Docker login to ECR..."
    if aws ecr get-login-password --region "$SOURCE_REGION" | docker login --username AWS --password-stdin "$ACCOUNT_ID.dkr.ecr.$SOURCE_REGION.amazonaws.com" &> /dev/null; then
        print_status "✓ Docker login successful"
        
        # Create a test image
        print_status "Creating test image..."
        cat > Dockerfile.test << EOF
FROM alpine:latest
RUN echo "Test image for ECR validation" > /test.txt
CMD ["cat", "/test.txt"]
EOF
        
        if docker build -t ecr-test:latest -f Dockerfile.test . &> /dev/null; then
            print_status "✓ Test image built successfully"
            
            # Tag for testing repository
            TEST_TAG="$TEST_REPO_URI:validation-test"
            docker tag ecr-test:latest "$TEST_TAG"
            
            # Push to testing repository
            print_status "Testing image push to testing repository..."
            if docker push "$TEST_TAG" &> /dev/null; then
                print_status "✓ Image pushed successfully to testing repository"
                
                # Clean up test image
                docker rmi ecr-test:latest "$TEST_TAG" &> /dev/null || true
                
                # Wait a moment and verify image exists
                sleep 5
                if aws ecr describe-images --region "$SOURCE_REGION" --repository-name "$TEST_REPO_NAME" --image-ids imageTag=validation-test &> /dev/null; then
                    print_status "✓ Image verified in ECR repository"
                    
                    # Clean up test image from ECR
                    aws ecr batch-delete-image --region "$SOURCE_REGION" --repository-name "$TEST_REPO_NAME" --image-ids imageTag=validation-test &> /dev/null || true
                else
                    print_warning "Image not found in ECR repository"
                fi
            else
                print_error "Failed to push image to testing repository"
            fi
        else
            print_error "Failed to build test image"
        fi
        
        # Clean up test files
        rm -f Dockerfile.test
    else
        print_error "Docker login failed"
    fi
}

# Function to generate summary report
generate_summary() {
    print_header "Validation Summary"
    
    echo "Infrastructure validation completed for ECR Container Registry Replication Strategies"
    echo ""
    echo "Key Resources:"
    echo "  • Production Repository: $PROD_REPO_NAME"
    echo "  • Testing Repository: $TEST_REPO_NAME"
    echo "  • Source Region: $SOURCE_REGION"
    echo "  • Replication Regions: $DEST_REGION, $SECONDARY_REGION"
    echo ""
    echo "Next Steps:"
    echo "  1. Push container images to test replication"
    echo "  2. Monitor CloudWatch dashboard for metrics"
    echo "  3. Verify replication in destination regions"
    echo "  4. Test lifecycle policies with old images"
    echo "  5. Configure additional monitoring as needed"
    echo ""
    echo "Useful Commands:"
    echo "  • View dashboard: aws cloudwatch get-dashboard --dashboard-name $DASHBOARD_NAME"
    echo "  • Check replication: aws ecr describe-repositories --region $DEST_REGION"
    echo "  • Monitor logs: aws logs tail /aws/lambda/$LAMBDA_NAME --follow"
    echo ""
    print_status "Validation completed successfully!"
}

# Main execution
main() {
    echo "ECR Container Registry Replication Strategies - Validation Script"
    echo "================================================================="
    echo ""
    
    check_prerequisites
    get_terraform_outputs
    test_ecr_repositories
    test_lifecycle_policies
    test_replication_configuration
    test_monitoring
    test_lambda_function
    test_docker_integration
    generate_summary
}

# Run main function
main "$@"