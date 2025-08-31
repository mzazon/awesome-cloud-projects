#!/bin/bash

# AWS Well-Architected Tool Assessment Deployment Script
# This script creates and configures a workload for architecture assessment

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error
set -o pipefail  # Exit if any command in a pipeline fails

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=${DRY_RUN:-false}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "INFO" "${BLUE}$*${NC}"
}

log_success() {
    log "SUCCESS" "${GREEN}$*${NC}"
}

log_warning() {
    log "WARNING" "${YELLOW}$*${NC}"
}

log_error() {
    log "ERROR" "${RED}$*${NC}"
}

# Error handling
cleanup_on_error() {
    log_error "Deployment failed. Cleaning up resources..."
    if [[ -n "${WORKLOAD_ID:-}" ]]; then
        aws wellarchitected delete-workload --workload-id "${WORKLOAD_ID}" 2>/dev/null || true
        log_warning "Attempted cleanup of workload: ${WORKLOAD_ID}"
    fi
    exit 1
}

trap cleanup_on_error ERR

# Help function
show_help() {
    cat << EOF
AWS Well-Architected Tool Assessment Deployment Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -n, --workload-name     Custom workload name (optional)
    -d, --description       Custom workload description (optional)
    -e, --environment       Environment type (PRODUCTION|PREPRODUCTION) [default: PREPRODUCTION]
    -i, --industry          Industry type [default: InfoTech]
    -r, --region            AWS region [default: from AWS CLI config]
    --dry-run              Show what would be done without making changes
    -v, --verbose          Enable verbose logging

EXAMPLES:
    $0                                    # Use defaults
    $0 -n "my-web-app" -e PRODUCTION     # Custom name and environment
    $0 --dry-run                         # Preview actions
    $0 -v                                # Verbose output

PREREQUISITES:
    - AWS CLI v2 installed and configured
    - Valid AWS credentials with Well-Architected Tool permissions
    - Internet connectivity for API calls

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--workload-name)
                CUSTOM_WORKLOAD_NAME="$2"
                shift 2
                ;;
            -d|--description)
                CUSTOM_DESCRIPTION="$2"
                shift 2
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                if [[ ! "$ENVIRONMENT" =~ ^(PRODUCTION|PREPRODUCTION)$ ]]; then
                    log_error "Environment must be PRODUCTION or PREPRODUCTION"
                    exit 1
                fi
                shift 2
                ;;
            -i|--industry)
                INDUSTRY_TYPE="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Prerequisite checks
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install AWS CLI v2."
        exit 1
    fi
    
    # Check AWS CLI version
    local aws_version
    aws_version=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    if [[ "${aws_version%%.*}" -lt 2 ]]; then
        log_warning "AWS CLI v1 detected. v2 is recommended for better performance."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid."
        log_info "Run 'aws configure' to set up credentials."
        exit 1
    fi
    
    # Check Well-Architected Tool permissions
    if ! aws wellarchitected list-workloads --query 'WorkloadSummaries[0]' &> /dev/null; then
        log_error "Insufficient permissions for AWS Well-Architected Tool."
        log_info "Required permissions: wellarchitected:* actions"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

# Initialize environment variables
initialize_environment() {
    log_info "Initializing environment..."
    
    # Set AWS region
    if [[ -z "${AWS_REGION:-}" ]]; then
        AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            log_error "AWS region not configured. Set region or use -r option."
            exit 1
        fi
    fi
    export AWS_REGION
    
    # Get AWS account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
    
    # Set defaults
    ENVIRONMENT=${ENVIRONMENT:-"PREPRODUCTION"}
    INDUSTRY_TYPE=${INDUSTRY_TYPE:-"InfoTech"}
    
    # Set workload name
    if [[ -n "${CUSTOM_WORKLOAD_NAME:-}" ]]; then
        export WORKLOAD_NAME="${CUSTOM_WORKLOAD_NAME}-${RANDOM_SUFFIX}"
    else
        export WORKLOAD_NAME="sample-web-app-${RANDOM_SUFFIX}"
    fi
    
    # Set description
    if [[ -n "${CUSTOM_DESCRIPTION:-}" ]]; then
        DESCRIPTION="$CUSTOM_DESCRIPTION"
    else
        DESCRIPTION="Sample web application workload for assessment"
    fi
    
    log_success "Environment initialized"
    log_info "Workload name: ${WORKLOAD_NAME}"
    log_info "AWS Region: ${AWS_REGION}"
    log_info "Environment: ${ENVIRONMENT}"
    log_info "Industry: ${INDUSTRY_TYPE}"
}

# Create Well-Architected workload
create_workload() {
    log_info "Creating Well-Architected workload..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would create workload with name: ${WORKLOAD_NAME}"
        return 0
    fi
    
    # Create workload
    local create_output
    create_output=$(aws wellarchitected create-workload \
        --workload-name "${WORKLOAD_NAME}" \
        --description "${DESCRIPTION}" \
        --environment "${ENVIRONMENT}" \
        --aws-regions "${AWS_REGION}" \
        --review-owner "$(aws sts get-caller-identity --query Arn --output text)" \
        --lenses "wellarchitected" \
        --industry-type "${INDUSTRY_TYPE}" \
        --architectural-design "Three-tier web application with load balancer, application servers, and database" \
        --output json)
    
    if [[ $? -eq 0 ]]; then
        export WORKLOAD_ID=$(echo "$create_output" | jq -r '.WorkloadId')
        log_success "Workload created with ID: ${WORKLOAD_ID}"
        
        # Save workload ID to file for cleanup script
        echo "${WORKLOAD_ID}" > "${SCRIPT_DIR}/.workload_id"
        echo "${WORKLOAD_NAME}" > "${SCRIPT_DIR}/.workload_name"
    else
        log_error "Failed to create workload"
        exit 1
    fi
}

# Verify workload creation
verify_workload() {
    log_info "Verifying workload configuration..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify workload configuration"
        return 0
    fi
    
    # Get workload details
    local workload_details
    workload_details=$(aws wellarchitected get-workload \
        --workload-id "${WORKLOAD_ID}" \
        --query '{
            WorkloadName: Workload.WorkloadName,
            Environment: Workload.Environment,
            ReviewOwner: Workload.ReviewOwner,
            Lenses: Workload.Lenses,
            RiskCounts: Workload.RiskCounts
        }' --output json)
    
    if [[ $? -eq 0 ]]; then
        log_success "Workload configuration verified"
        log_info "Workload details:"
        echo "$workload_details" | jq '.'
    else
        log_error "Failed to verify workload configuration"
        exit 1
    fi
}

# Initialize lens review
initialize_lens_review() {
    log_info "Initializing lens review..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would initialize lens review"
        return 0
    fi
    
    # Get lens review summary
    local lens_review
    lens_review=$(aws wellarchitected get-lens-review \
        --workload-id "${WORKLOAD_ID}" \
        --lens-alias "wellarchitected" \
        --query '{
            LensName: LensReview.LensName,
            LensStatus: LensReview.LensStatus,
            PillarReviewSummaries: LensReview.PillarReviewSummaries[].{
                PillarId: PillarId,
                PillarName: PillarName,
                RiskCounts: RiskCounts
            }
        }' --output json)
    
    if [[ $? -eq 0 ]]; then
        log_success "Lens review initialized"
        log_info "Available pillars for assessment:"
        echo "$lens_review" | jq '.PillarReviewSummaries[]'
    else
        log_error "Failed to initialize lens review"
        exit 1
    fi
}

# Display sample questions
display_sample_questions() {
    log_info "Displaying sample assessment questions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would display sample questions"
        return 0
    fi
    
    # List sample questions from Operational Excellence pillar
    local questions
    questions=$(aws wellarchitected list-answers \
        --workload-id "${WORKLOAD_ID}" \
        --lens-alias "wellarchitected" \
        --pillar-id "operationalExcellence" \
        --query 'AnswerSummaries[0:3].{
            QuestionId: QuestionId,
            QuestionTitle: QuestionTitle,
            IsApplicable: IsApplicable,
            SelectedChoices: SelectedChoices
        }' --output json)
    
    if [[ $? -eq 0 ]]; then
        log_success "Sample questions retrieved"
        log_info "Operational Excellence questions (first 3):"
        echo "$questions" | jq '.'
    else
        log_warning "Unable to retrieve sample questions"
    fi
}

# Main deployment function
main() {
    log_info "Starting AWS Well-Architected Tool deployment..."
    log_info "Log file: ${LOG_FILE}"
    
    parse_arguments "$@"
    check_prerequisites
    initialize_environment
    create_workload
    verify_workload
    initialize_lens_review
    display_sample_questions
    
    log_success "Deployment completed successfully!"
    
    cat << EOF

🎉 AWS Well-Architected Tool Assessment Ready!

Workload Details:
  - Name: ${WORKLOAD_NAME}
  - ID: ${WORKLOAD_ID}
  - Environment: ${ENVIRONMENT}
  - Region: ${AWS_REGION}

Next Steps:
1. Access the AWS Well-Architected Tool in the AWS Console
2. Navigate to your workload: ${WORKLOAD_NAME}
3. Begin answering assessment questions for each pillar
4. Review recommendations and improvement plans

To clean up resources, run:
  ./destroy.sh

For more information, visit:
  https://docs.aws.amazon.com/wellarchitected/latest/userguide/intro.html

EOF
}

# Execute main function with all arguments
main "$@"