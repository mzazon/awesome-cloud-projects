#!/bin/bash

# Deploy script for ECR Container Registry Replication Strategies
# This script deploys the complete ECR replication infrastructure
# including repositories, replication rules, lifecycle policies, and monitoring

set -euo pipefail

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

# Error handling
error_exit() {
    log_error "Error on line $1"
    log_error "Deployment failed. Check the logs above for details."
    exit 1
}

trap 'error_exit $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy ECR Container Registry Replication Strategies infrastructure

OPTIONS:
    -h, --help              Show this help message
    -r, --regions          Comma-separated list of replication regions (default: us-west-2,eu-west-1)
    -p, --prefix           Repository prefix (default: enterprise-apps)
    -n, --dry-run          Show what would be deployed without making changes
    -v, --verbose          Enable verbose logging
    -s, --skip-monitoring  Skip monitoring setup
    -t, --test-image       Create and push test image after deployment

Examples:
    $0                                          # Deploy with defaults
    $0 -r us-west-2,ap-southeast-1 -p myapp   # Custom regions and prefix
    $0 -n                                      # Dry run
    $0 -v -t                                   # Verbose with test image
EOF
}

# Default values
REPLICATION_REGIONS="us-west-2,eu-west-1"
REPO_PREFIX="enterprise-apps"
DRY_RUN=false
VERBOSE=false
SKIP_MONITORING=false
CREATE_TEST_IMAGE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/ecr-replication-deploy-$$"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--regions)
            REPLICATION_REGIONS="$2"
            shift 2
            ;;
        -p|--prefix)
            REPO_PREFIX="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -s|--skip-monitoring)
            SKIP_MONITORING=true
            shift
            ;;
        -t|--test-image)
            CREATE_TEST_IMAGE=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Create temp directory
mkdir -p "$TEMP_DIR"

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS CLI version
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ $(echo "$AWS_CLI_VERSION" | cut -d. -f1) -lt 2 ]]; then
        log_error "AWS CLI version 2.x is required. Current version: $AWS_CLI_VERSION"
        exit 1
    fi
    
    # Check Docker if test image is requested
    if [[ "$CREATE_TEST_IMAGE" == true ]]; then
        if ! command -v docker &> /dev/null; then
            log_error "Docker is not installed. Required for test image creation."
            exit 1
        fi
        
        # Check if Docker daemon is running
        if ! docker info &> /dev/null; then
            log_error "Docker daemon is not running. Please start Docker."
            exit 1
        fi
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Set environment variables
set_environment() {
    log "Setting up environment variables..."
    
    # Get AWS configuration
    export AWS_REGION=$(aws configure get region)
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    export SOURCE_REGION="$AWS_REGION"
    
    # Parse destination regions
    IFS=',' read -ra DEST_REGIONS <<< "$REPLICATION_REGIONS"
    export DEST_REGION="${DEST_REGIONS[0]}"
    export SECONDARY_REGION="${DEST_REGIONS[1]:-}"
    
    # Generate unique suffix
    export RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword)
    
    # Set repository names
    export PROD_REPO="${REPO_PREFIX}/production-${RANDOM_SUFFIX}"
    export TEST_REPO="${REPO_PREFIX}/testing-${RANDOM_SUFFIX}"
    
    # Store configuration for cleanup
    cat > "$TEMP_DIR/deployment-config.env" << EOF
AWS_REGION=$AWS_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID
SOURCE_REGION=$SOURCE_REGION
DEST_REGION=$DEST_REGION
SECONDARY_REGION=$SECONDARY_REGION
RANDOM_SUFFIX=$RANDOM_SUFFIX
REPO_PREFIX=$REPO_PREFIX
PROD_REPO=$PROD_REPO
TEST_REPO=$TEST_REPO
REPLICATION_REGIONS=$REPLICATION_REGIONS
EOF
    
    log_success "Environment configured:"
    log "  Account ID: $AWS_ACCOUNT_ID"
    log "  Source Region: $SOURCE_REGION"
    log "  Replication Regions: $REPLICATION_REGIONS"
    log "  Repository Prefix: $REPO_PREFIX"
    log "  Unique Suffix: $RANDOM_SUFFIX"
}

# Create ECR repositories
create_repositories() {
    log "Creating ECR repositories..."
    
    # Create production repository
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would create production repository: $PROD_REPO"
    else
        aws ecr create-repository \
            --repository-name "$PROD_REPO" \
            --image-scanning-configuration scanOnPush=true \
            --image-tag-mutability IMMUTABLE \
            --region "$SOURCE_REGION" > /dev/null
        
        log_success "Created production repository: $PROD_REPO"
    fi
    
    # Create testing repository
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would create testing repository: $TEST_REPO"
    else
        aws ecr create-repository \
            --repository-name "$TEST_REPO" \
            --image-scanning-configuration scanOnPush=true \
            --image-tag-mutability MUTABLE \
            --region "$SOURCE_REGION" > /dev/null
        
        log_success "Created testing repository: $TEST_REPO"
    fi
}

# Configure replication
configure_replication() {
    log "Configuring cross-region replication..."
    
    # Build destinations array
    local destinations=""
    IFS=',' read -ra REGIONS <<< "$REPLICATION_REGIONS"
    for region in "${REGIONS[@]}"; do
        if [[ -n "$destinations" ]]; then
            destinations+=","
        fi
        destinations+="{\"region\":\"$region\",\"registryId\":\"$AWS_ACCOUNT_ID\"}"
    done
    
    # Create replication configuration
    cat > "$TEMP_DIR/replication-config.json" << EOF
{
  "rules": [
    {
      "destinations": [$destinations],
      "repositoryFilters": [
        {
          "filter": "$REPO_PREFIX",
          "filterType": "PREFIX_MATCH"
        }
      ]
    }
  ]
}
EOF
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would configure replication to regions: $REPLICATION_REGIONS"
        [[ "$VERBOSE" == true ]] && cat "$TEMP_DIR/replication-config.json"
    else
        aws ecr put-replication-configuration \
            --replication-configuration "file://$TEMP_DIR/replication-config.json" \
            --region "$SOURCE_REGION" > /dev/null
        
        log_success "Configured replication to regions: $REPLICATION_REGIONS"
    fi
}

# Create lifecycle policies
create_lifecycle_policies() {
    log "Creating lifecycle policies..."
    
    # Production lifecycle policy
    cat > "$TEMP_DIR/prod-lifecycle-policy.json" << EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 production images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["prod", "release"],
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "Delete untagged images older than 1 day",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 1
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
    
    # Testing lifecycle policy
    cat > "$TEMP_DIR/test-lifecycle-policy.json" << EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 5 testing images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["test", "dev", "staging"],
        "countType": "imageCountMoreThan",
        "countNumber": 5
      },
      "action": {
        "type": "expire"
      }
    },
    {
      "rulePriority": 2,
      "description": "Delete images older than 7 days",
      "selection": {
        "tagStatus": "any",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 7
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would apply lifecycle policies to repositories"
    else
        # Apply production lifecycle policy
        aws ecr put-lifecycle-policy \
            --repository-name "$PROD_REPO" \
            --lifecycle-policy-text "file://$TEMP_DIR/prod-lifecycle-policy.json" \
            --region "$SOURCE_REGION" > /dev/null
        
        # Apply testing lifecycle policy
        aws ecr put-lifecycle-policy \
            --repository-name "$TEST_REPO" \
            --lifecycle-policy-text "file://$TEMP_DIR/test-lifecycle-policy.json" \
            --region "$SOURCE_REGION" > /dev/null
        
        log_success "Applied lifecycle policies to repositories"
    fi
}

# Create repository policies
create_repository_policies() {
    log "Creating repository access policies..."
    
    # Production repository policy
    cat > "$TEMP_DIR/prod-repo-policy.json" << EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "ProdReadOnlyAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$AWS_ACCOUNT_ID:root"
      },
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability"
      ]
    },
    {
      "Sid": "ProdPushAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$AWS_ACCOUNT_ID:root"
      },
      "Action": [
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ]
    }
  ]
}
EOF
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would apply repository policies"
    else
        aws ecr set-repository-policy \
            --repository-name "$PROD_REPO" \
            --policy-text "file://$TEMP_DIR/prod-repo-policy.json" \
            --region "$SOURCE_REGION" > /dev/null
        
        log_success "Applied repository policy to production repository"
    fi
}

# Setup monitoring
setup_monitoring() {
    if [[ "$SKIP_MONITORING" == true ]]; then
        log "Skipping monitoring setup as requested"
        return
    fi
    
    log "Setting up CloudWatch monitoring..."
    
    # Create CloudWatch dashboard
    cat > "$TEMP_DIR/ecr-dashboard.json" << EOF
{
  "widgets": [
    {
      "type": "metric",
      "width": 12,
      "height": 6,
      "properties": {
        "metrics": [
          ["AWS/ECR", "RepositoryPullCount", "RepositoryName", "$PROD_REPO"],
          ["AWS/ECR", "RepositoryPushCount", "RepositoryName", "$PROD_REPO"],
          ["AWS/ECR", "RepositoryPullCount", "RepositoryName", "$TEST_REPO"],
          ["AWS/ECR", "RepositoryPushCount", "RepositoryName", "$TEST_REPO"]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "$SOURCE_REGION",
        "title": "ECR Repository Activity"
      }
    }
  ]
}
EOF
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would create CloudWatch dashboard: ECR-Replication-Monitoring-$RANDOM_SUFFIX"
    else
        aws cloudwatch put-dashboard \
            --dashboard-name "ECR-Replication-Monitoring-$RANDOM_SUFFIX" \
            --dashboard-body "file://$TEMP_DIR/ecr-dashboard.json" \
            --region "$SOURCE_REGION" > /dev/null
        
        log_success "Created CloudWatch dashboard: ECR-Replication-Monitoring-$RANDOM_SUFFIX"
    fi
    
    # Create SNS topic for notifications
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would create SNS topic for replication alerts"
    else
        TOPIC_ARN=$(aws sns create-topic \
            --name "ECR-Replication-Alerts-$RANDOM_SUFFIX" \
            --region "$SOURCE_REGION" \
            --output text --query TopicArn)
        
        # Store topic ARN for cleanup
        echo "TOPIC_ARN=$TOPIC_ARN" >> "$TEMP_DIR/deployment-config.env"
        
        log_success "Created SNS topic: $TOPIC_ARN"
    fi
}

# Create test image
create_test_image() {
    if [[ "$CREATE_TEST_IMAGE" == false ]]; then
        log "Skipping test image creation as requested"
        return
    fi
    
    log "Creating and pushing test image..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would create and push test image"
        return
    fi
    
    # Get ECR login
    aws ecr get-login-password --region "$SOURCE_REGION" | \
        docker login --username AWS --password-stdin \
        "$AWS_ACCOUNT_ID.dkr.ecr.$SOURCE_REGION.amazonaws.com"
    
    # Create test Dockerfile
    cat > "$TEMP_DIR/Dockerfile" << EOF
FROM alpine:latest
RUN echo "Enterprise Application v1.0 - Build $(date)" > /app-info.txt
RUN echo "Repository: $PROD_REPO" >> /app-info.txt
RUN echo "Build ID: $RANDOM_SUFFIX" >> /app-info.txt
CMD ["cat", "/app-info.txt"]
EOF
    
    # Build and push test image
    docker build -t "test-app:$RANDOM_SUFFIX" "$TEMP_DIR"
    docker tag "test-app:$RANDOM_SUFFIX" \
        "$AWS_ACCOUNT_ID.dkr.ecr.$SOURCE_REGION.amazonaws.com/$PROD_REPO:prod-1.0"
    
    docker push "$AWS_ACCOUNT_ID.dkr.ecr.$SOURCE_REGION.amazonaws.com/$PROD_REPO:prod-1.0"
    
    log_success "Created and pushed test image: $PROD_REPO:prod-1.0"
}

# Verify deployment
verify_deployment() {
    log "Verifying deployment..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN: Would verify deployment"
        return
    fi
    
    # Check repositories
    local repo_count=$(aws ecr describe-repositories \
        --region "$SOURCE_REGION" \
        --query "repositories[?starts_with(repositoryName, '$REPO_PREFIX')].repositoryName" \
        --output text | wc -w)
    
    if [[ "$repo_count" -eq 2 ]]; then
        log_success "Verified: 2 repositories created"
    else
        log_error "Expected 2 repositories, found $repo_count"
        return 1
    fi
    
    # Check replication configuration
    local replication_rules=$(aws ecr describe-registry \
        --region "$SOURCE_REGION" \
        --query 'replicationConfiguration.rules' \
        --output text)
    
    if [[ "$replication_rules" != "None" ]]; then
        log_success "Verified: Replication configuration applied"
    else
        log_error "Replication configuration not found"
        return 1
    fi
    
    # Check lifecycle policies
    for repo in "$PROD_REPO" "$TEST_REPO"; do
        if aws ecr get-lifecycle-policy \
            --repository-name "$repo" \
            --region "$SOURCE_REGION" &> /dev/null; then
            log_success "Verified: Lifecycle policy applied to $repo"
        else
            log_error "Lifecycle policy not found for $repo"
            return 1
        fi
    done
    
    log_success "Deployment verification completed successfully"
}

# Main deployment function
main() {
    log "Starting ECR Container Registry Replication Strategies deployment..."
    log "Deployment ID: $RANDOM_SUFFIX"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY RUN MODE - No resources will be created"
    fi
    
    check_prerequisites
    set_environment
    create_repositories
    configure_replication
    create_lifecycle_policies
    create_repository_policies
    setup_monitoring
    create_test_image
    verify_deployment
    
    log_success "Deployment completed successfully!"
    log ""
    log "📋 Deployment Summary:"
    log "  - Deployment ID: $RANDOM_SUFFIX"
    log "  - Source Region: $SOURCE_REGION"
    log "  - Replication Regions: $REPLICATION_REGIONS"
    log "  - Production Repository: $PROD_REPO"
    log "  - Testing Repository: $TEST_REPO"
    log "  - Configuration saved to: $TEMP_DIR/deployment-config.env"
    log ""
    log "🔍 Next Steps:"
    log "  1. Wait 5-10 minutes for replication to complete"
    log "  2. Check replication status in destination regions"
    log "  3. Monitor CloudWatch dashboard for repository activity"
    log "  4. Use ./destroy.sh to clean up resources when done"
    log ""
    log "📊 Useful Commands:"
    log "  aws ecr describe-repositories --region $SOURCE_REGION"
    log "  aws ecr describe-registry --region $SOURCE_REGION"
    log "  aws ecr describe-images --repository-name $PROD_REPO --region $SOURCE_REGION"
    
    # Copy config file to scripts directory for cleanup
    cp "$TEMP_DIR/deployment-config.env" "$SCRIPT_DIR/last-deployment.env"
    
    log_success "Deployment configuration saved to $SCRIPT_DIR/last-deployment.env"
}

# Run main function
main "$@"