#!/bin/bash

# Budget Monitoring with AWS Budgets and SNS - Cleanup Script
# This script safely removes all resources created by the budget monitoring solution

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

# Cleanup function for temporary files
cleanup() {
    log "Cleaning up temporary files..."
    rm -f budget.json notifications.json budget_list.json sns_topics.json
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Safely remove AWS Budget Monitoring solution resources.

OPTIONS:
    -b, --budget-name NAME      Specific budget name to delete
    -t, --topic-arn ARN         Specific SNS topic ARN to delete
    -r, --region REGION         AWS region (uses configured region by default)
    -a, --all                   Delete all budget monitoring resources (interactive)
    -f, --force                 Skip confirmation prompts (use with caution)
    -l, --list                  List all budget monitoring resources without deleting
    -h, --help                  Show this help message
    --dry-run                   Show what would be deleted without removing resources

EXAMPLES:
    $0 --list
    $0 --budget-name monthly-cost-budget-abc123
    $0 --budget-name monthly-cost-budget-abc123 --topic-arn arn:aws:sns:us-east-1:123456789012:budget-alerts-abc123
    $0 --all
    $0 --all --force

SAFETY FEATURES:
    - Confirmation prompts before deletion (unless --force is used)
    - Validates resources exist before attempting deletion
    - Handles partial cleanup scenarios gracefully
    - Provides detailed logging of all operations

EOF
}

# Default values
BUDGET_NAME=""
SNS_TOPIC_ARN=""
DELETE_ALL=false
FORCE=false
LIST_ONLY=false
DRY_RUN=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--budget-name)
            BUDGET_NAME="$2"
            shift 2
            ;;
        -t|--topic-arn)
            SNS_TOPIC_ARN="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -a|--all)
            DELETE_ALL=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -l|--list)
            LIST_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

log "Starting Budget Monitoring cleanup..."

# Check prerequisites
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if jq is installed for JSON processing
if ! command -v jq &> /dev/null; then
    warning "jq is not installed. Some output formatting may be limited."
fi

# Check AWS authentication
log "Verifying AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured or invalid. Please run 'aws configure' first."
    exit 1
fi

# Set environment variables
export AWS_REGION=${AWS_REGION:-$(aws configure get region)}
if [[ -z "$AWS_REGION" ]]; then
    export AWS_REGION="us-east-1"
    warning "No region configured, using default: us-east-1"
fi

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [[ -z "$AWS_ACCOUNT_ID" ]]; then
    error "Failed to get AWS account ID"
    exit 1
fi

log "Configuration:"
log "  AWS Region: $AWS_REGION"
log "  AWS Account ID: $AWS_ACCOUNT_ID"

# Function to list budget monitoring resources
list_resources() {
    log "Discovering budget monitoring resources..."
    
    # Find budgets that match our naming pattern
    aws budgets describe-budgets \
        --account-id "${AWS_ACCOUNT_ID}" \
        --query 'Budgets[?contains(BudgetName, `budget`) || contains(BudgetName, `cost`)].{Name:BudgetName,Amount:BudgetLimit.Amount,Unit:BudgetLimit.Unit,Type:BudgetType}' \
        --output table 2>/dev/null || {
        warning "Could not list budgets (this may be normal if no budgets exist)"
    }
    
    # Find SNS topics that match our naming pattern
    if command -v jq &> /dev/null; then
        aws sns list-topics \
            --query 'Topics[*].TopicArn' \
            --output json > sns_topics.json 2>/dev/null || echo "[]" > sns_topics.json
        
        echo
        log "SNS Topics that may be related to budget monitoring:"
        jq -r '.[] | select(contains("budget") or contains("alert") or contains("cost"))' sns_topics.json 2>/dev/null || {
            echo "  No budget-related SNS topics found"
        }
    else
        aws sns list-topics \
            --query 'Topics[?contains(TopicArn, `budget`) || contains(TopicArn, `alert`) || contains(TopicArn, `cost`)].TopicArn' \
            --output table 2>/dev/null || {
            warning "Could not list SNS topics"
        }
    fi
}

# Function to delete a specific budget
delete_budget() {
    local budget_name="$1"
    
    log "Checking if budget '$budget_name' exists..."
    if aws budgets describe-budget \
        --account-id "${AWS_ACCOUNT_ID}" \
        --budget-name "${budget_name}" &> /dev/null; then
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would delete budget: $budget_name"
            return 0
        fi
        
        if [[ "$FORCE" != "true" ]]; then
            echo
            read -p "Delete budget '$budget_name'? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Skipping budget deletion"
                return 0
            fi
        fi
        
        aws budgets delete-budget \
            --account-id "${AWS_ACCOUNT_ID}" \
            --budget-name "${budget_name}" || {
            error "Failed to delete budget: $budget_name"
            return 1
        }
        success "Deleted budget: $budget_name"
    else
        warning "Budget '$budget_name' not found"
    fi
}

# Function to delete a specific SNS topic
delete_sns_topic() {
    local topic_arn="$1"
    
    log "Checking if SNS topic exists: $topic_arn"
    if aws sns get-topic-attributes --topic-arn "$topic_arn" &> /dev/null; then
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "DRY RUN: Would delete SNS topic: $topic_arn"
            return 0
        fi
        
        if [[ "$FORCE" != "true" ]]; then
            echo
            read -p "Delete SNS topic '$topic_arn'? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log "Skipping SNS topic deletion"
                return 0
            fi
        fi
        
        aws sns delete-topic --topic-arn "$topic_arn" || {
            error "Failed to delete SNS topic: $topic_arn"
            return 1
        }
        success "Deleted SNS topic: $topic_arn"
    else
        warning "SNS topic not found: $topic_arn"
    fi
}

# Function to delete all budget monitoring resources interactively
delete_all_resources() {
    log "Discovering all budget monitoring resources for interactive deletion..."
    
    # Get all budgets
    if command -v jq &> /dev/null; then
        aws budgets describe-budgets \
            --account-id "${AWS_ACCOUNT_ID}" \
            --query 'Budgets[*].BudgetName' \
            --output json > budget_list.json 2>/dev/null || echo "[]" > budget_list.json
        
        # Process each budget
        local budget_count=$(jq length budget_list.json)
        if [[ $budget_count -gt 0 ]]; then
            log "Found $budget_count budget(s) in your account"
            for i in $(seq 0 $((budget_count - 1))); do
                local budget_name=$(jq -r ".[$i]" budget_list.json)
                
                if [[ "$FORCE" != "true" ]]; then
                    echo
                    read -p "Delete budget '$budget_name'? (y/N): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        delete_budget "$budget_name"
                    else
                        log "Skipping budget: $budget_name"
                    fi
                else
                    delete_budget "$budget_name"
                fi
            done
        else
            log "No budgets found in your account"
        fi
        
        # Get SNS topics that might be budget-related
        aws sns list-topics \
            --query 'Topics[*].TopicArn' \
            --output json > sns_topics.json 2>/dev/null || echo "[]" > sns_topics.json
        
        local budget_topics=$(jq -r '.[] | select(contains("budget") or contains("alert") or contains("cost"))' sns_topics.json 2>/dev/null)
        
        if [[ -n "$budget_topics" ]]; then
            echo "$budget_topics" | while read -r topic_arn; do
                if [[ -n "$topic_arn" ]]; then
                    if [[ "$FORCE" != "true" ]]; then
                        echo
                        read -p "Delete SNS topic '$topic_arn'? (y/N): " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then
                            delete_sns_topic "$topic_arn"
                        else
                            log "Skipping SNS topic: $topic_arn"
                        fi
                    else
                        delete_sns_topic "$topic_arn"
                    fi
                fi
            done
        else
            log "No budget-related SNS topics found"
        fi
    else
        warning "jq not available. Limited cleanup functionality."
        
        # Fallback without jq
        aws budgets describe-budgets \
            --account-id "${AWS_ACCOUNT_ID}" \
            --query 'Budgets[*].BudgetName' \
            --output text 2>/dev/null | tr '\t' '\n' | while read -r budget_name; do
            if [[ -n "$budget_name" ]]; then
                if [[ "$FORCE" != "true" ]]; then
                    echo
                    read -p "Delete budget '$budget_name'? (y/N): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        delete_budget "$budget_name"
                    fi
                else
                    delete_budget "$budget_name"
                fi
            fi
        done
    fi
}

# Load deployment information if available
if [[ -f "deployment_info.txt" ]]; then
    log "Found deployment information file"
    if [[ -z "$BUDGET_NAME" ]]; then
        BUDGET_NAME=$(grep "Budget Name:" deployment_info.txt | cut -d' ' -f3- 2>/dev/null || echo "")
    fi
    if [[ -z "$SNS_TOPIC_ARN" ]]; then
        SNS_TOPIC_ARN=$(grep "SNS Topic ARN:" deployment_info.txt | cut -d' ' -f4- 2>/dev/null || echo "")
    fi
    
    if [[ -n "$BUDGET_NAME" ]]; then
        log "Loaded budget name from deployment info: $BUDGET_NAME"
    fi
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        log "Loaded SNS topic ARN from deployment info: $SNS_TOPIC_ARN"
    fi
fi

# Main execution logic
if [[ "$LIST_ONLY" == "true" ]]; then
    list_resources
    exit 0
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY RUN MODE - No resources will be deleted"
fi

if [[ "$DELETE_ALL" == "true" ]]; then
    if [[ "$FORCE" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        warning "This will attempt to delete ALL budget monitoring resources in your account."
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Cleanup cancelled by user"
            exit 0
        fi
    fi
    delete_all_resources
elif [[ -n "$BUDGET_NAME" || -n "$SNS_TOPIC_ARN" ]]; then
    # Delete specific resources
    if [[ -n "$BUDGET_NAME" ]]; then
        delete_budget "$BUDGET_NAME"
    fi
    
    if [[ -n "$SNS_TOPIC_ARN" ]]; then
        delete_sns_topic "$SNS_TOPIC_ARN"
    fi
else
    log "No specific resources specified. Use --list to see available resources or --all for interactive cleanup."
    show_help
    exit 1
fi

# Clean up local files
if [[ "$DRY_RUN" != "true" ]]; then
    if [[ -f "deployment_info.txt" ]]; then
        if [[ "$FORCE" == "true" ]] || { echo; read -p "Remove deployment_info.txt file? (y/N): " -n 1 -r; echo; [[ $REPLY =~ ^[Yy]$ ]]; }; then
            rm -f deployment_info.txt
            success "Removed deployment_info.txt"
        fi
    fi
fi

if [[ "$DRY_RUN" == "true" ]]; then
    success "Dry run completed - no resources were modified"
else
    success "Cleanup completed successfully!"
fi

log "Cleanup operation finished"