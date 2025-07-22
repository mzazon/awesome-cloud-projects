#!/bin/bash

# Smart City Digital Twins with SimSpace Weaver and IoT - Cleanup Script
# This script removes all infrastructure created for the smart city digital twin solution

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Command line options
DRY_RUN=false
FORCE_DELETE=false
SKIP_CONFIRMATION=false
PROJECT_NAME_PATTERN=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        --project-name)
            PROJECT_NAME_PATTERN="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--force] [--yes] [--project-name PREFIX] [--help]"
            echo "  --dry-run         Show what would be deleted without making changes"
            echo "  --force           Delete resources even if they have dependencies"
            echo "  --yes             Skip confirmation prompts"
            echo "  --project-name    Specify project name pattern to delete (e.g., smartcity-abc123)"
            echo "  --help            Show this help message"
            echo ""
            echo "Without --project-name, the script will attempt to find and list all smart city projects"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

if [ "$DRY_RUN" = true ]; then
    info "Running in DRY-RUN mode - no resources will be deleted"
fi

log "Starting Smart City Digital Twins cleanup..."

# Prerequisites check
log "Checking prerequisites..."

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed. Please install AWS CLI version 2.0 or later."
fi

# Check if user is authenticated
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS authentication failed. Please configure your AWS credentials."
fi

# Check if jq is available for JSON parsing
if ! command -v jq &> /dev/null; then
    warn "jq not found. Some operations may be limited. Consider installing jq for better JSON processing."
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

# Get AWS account information
CALLER_IDENTITY=$(aws sts get-caller-identity)
export AWS_ACCOUNT_ID
export AWS_REGION

if [ "$JQ_AVAILABLE" = true ]; then
    AWS_ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account')
    log "Authenticated as: $(echo "$CALLER_IDENTITY" | jq -r '.Arn')"
else
    AWS_ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | grep -o '"Account":"[^"]*"' | cut -d'"' -f4)
    log "Authenticated as AWS account: $AWS_ACCOUNT_ID"
fi

export AWS_REGION=$(aws configure get region)
if [ -z "$AWS_REGION" ]; then
    export AWS_REGION="us-east-1"
    warn "AWS region not configured, defaulting to us-east-1"
fi

log "Using AWS region: $AWS_REGION"
log "Using AWS account: $AWS_ACCOUNT_ID"

# Function to find smart city projects
find_smart_city_projects() {
    log "Discovering Smart City Digital Twin projects..."
    
    # Find DynamoDB tables with smart city pattern
    DYNAMODB_TABLES=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `smartcity-`) && contains(@, `-sensor-data`)]' --output text 2>/dev/null || echo "")
    
    # Find Lambda functions with smart city pattern
    LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `smartcity-`) && (contains(FunctionName, `-processor`) || contains(FunctionName, `-analytics`) || contains(FunctionName, `-simulation-manager`) || contains(FunctionName, `-stream-processor`))].[FunctionName]' --output text 2>/dev/null || echo "")
    
    # Find IoT thing groups with smart city pattern
    IOT_THING_GROUPS=$(aws iot list-thing-groups --query 'thingGroups[?contains(groupName, `smartcity-`) && contains(groupName, `-sensors`)].[groupName]' --output text 2>/dev/null || echo "")
    
    # Extract project names from discovered resources
    DISCOVERED_PROJECTS=""
    
    # From DynamoDB tables
    for table in $DYNAMODB_TABLES; do
        if [[ $table =~ smartcity-([a-z0-9]+)-sensor-data ]]; then
            PROJECT_NAME="smartcity-${BASH_REMATCH[1]}"
            if [[ ! $DISCOVERED_PROJECTS =~ $PROJECT_NAME ]]; then
                DISCOVERED_PROJECTS="$DISCOVERED_PROJECTS $PROJECT_NAME"
            fi
        fi
    done
    
    # From Lambda functions
    for func in $LAMBDA_FUNCTIONS; do
        if [[ $func =~ (smartcity-[a-z0-9]+)-(processor|analytics|simulation-manager|stream-processor) ]]; then
            PROJECT_NAME="${BASH_REMATCH[1]}"
            if [[ ! $DISCOVERED_PROJECTS =~ $PROJECT_NAME ]]; then
                DISCOVERED_PROJECTS="$DISCOVERED_PROJECTS $PROJECT_NAME"
            fi
        fi
    done
    
    # From IoT thing groups
    for group in $IOT_THING_GROUPS; do
        if [[ $group =~ (smartcity-[a-z0-9]+)-sensors ]]; then
            PROJECT_NAME="${BASH_REMATCH[1]}"
            if [[ ! $DISCOVERED_PROJECTS =~ $PROJECT_NAME ]]; then
                DISCOVERED_PROJECTS="$DISCOVERED_PROJECTS $PROJECT_NAME"
            fi
        fi
    done
    
    echo "$DISCOVERED_PROJECTS"
}

# Function to delete resources for a specific project
delete_project_resources() {
    local project_name=$1
    
    log "Cleaning up project: $project_name"
    
    # Set project variables
    IOT_THING_GROUP_NAME="${project_name}-sensors"
    DYNAMODB_TABLE_NAME="${project_name}-sensor-data"
    LAMBDA_FUNCTION_NAME="${project_name}-processor"
    S3_BUCKET_NAME="${project_name}-simulation-${AWS_REGION}"
    RULE_NAME="${project_name//-/_}_sensor_processing"
    IAM_ROLE_NAME="${project_name}-lambda-role"
    
    log "Project resources to delete:"
    log "  DynamoDB Table: $DYNAMODB_TABLE_NAME"
    log "  Lambda Functions: ${project_name}-processor, ${project_name}-stream-processor, ${project_name}-simulation-manager, ${project_name}-analytics"
    log "  IoT Thing Group: $IOT_THING_GROUP_NAME"
    log "  IoT Rule: $RULE_NAME"
    log "  S3 Bucket: $S3_BUCKET_NAME"
    log "  IAM Role: $IAM_ROLE_NAME"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY-RUN: Would delete the above resources for project $project_name"
        return 0
    fi
    
    # Step 1: Remove Lambda Functions
    log "Step 1: Removing Lambda functions..."
    
    # Remove event source mappings first
    info "Removing DynamoDB stream event source mappings..."
    EVENT_SOURCE_MAPPINGS=$(aws lambda list-event-source-mappings \
        --function-name "${project_name}-stream-processor" \
        --query 'EventSourceMappings[].UUID' --output text 2>/dev/null || echo "")
    
    for mapping_uuid in $EVENT_SOURCE_MAPPINGS; do
        if [ -n "$mapping_uuid" ] && [ "$mapping_uuid" != "None" ]; then
            log "Deleting event source mapping: $mapping_uuid"
            aws lambda delete-event-source-mapping --uuid "$mapping_uuid" || warn "Failed to delete event source mapping: $mapping_uuid"
            sleep 5  # Wait for deletion to complete
        fi
    done
    
    # Delete Lambda functions
    for func_suffix in "processor" "stream-processor" "simulation-manager" "analytics"; do
        func_name="${project_name}-${func_suffix}"
        if aws lambda get-function --function-name "$func_name" &>/dev/null; then
            log "Deleting Lambda function: $func_name"
            aws lambda delete-function --function-name "$func_name" || warn "Failed to delete Lambda function: $func_name"
        else
            info "Lambda function $func_name does not exist"
        fi
    done
    
    log "✅ Lambda functions deleted"
    
    # Step 2: Remove IoT Resources
    log "Step 2: Removing IoT resources..."
    
    # Delete IoT rule
    if aws iot get-topic-rule --rule-name "$RULE_NAME" &>/dev/null; then
        log "Deleting IoT rule: $RULE_NAME"
        aws iot delete-topic-rule --rule-name "$RULE_NAME" || warn "Failed to delete IoT rule: $RULE_NAME"
    else
        info "IoT rule $RULE_NAME does not exist"
    fi
    
    # Remove things from group and delete them
    info "Removing IoT things from group..."
    if aws iot describe-thing-group --thing-group-name "$IOT_THING_GROUP_NAME" &>/dev/null; then
        # List things in the group
        THINGS_IN_GROUP=$(aws iot list-things-in-thing-group \
            --thing-group-name "$IOT_THING_GROUP_NAME" \
            --query 'things' --output text 2>/dev/null || echo "")
        
        for thing in $THINGS_IN_GROUP; do
            if [ -n "$thing" ] && [ "$thing" != "None" ]; then
                log "Removing thing from group: $thing"
                aws iot remove-thing-from-thing-group \
                    --thing-group-name "$IOT_THING_GROUP_NAME" \
                    --thing-name "$thing" || warn "Failed to remove thing from group: $thing"
                
                log "Deleting IoT thing: $thing"
                aws iot delete-thing --thing-name "$thing" || warn "Failed to delete IoT thing: $thing"
            fi
        done
        
        # Delete thing group
        log "Deleting IoT thing group: $IOT_THING_GROUP_NAME"
        aws iot delete-thing-group --thing-group-name "$IOT_THING_GROUP_NAME" || warn "Failed to delete IoT thing group: $IOT_THING_GROUP_NAME"
    else
        info "IoT thing group $IOT_THING_GROUP_NAME does not exist"
    fi
    
    # Delete IoT policy
    IOT_POLICY_NAME="${project_name}-sensor-policy"
    if aws iot get-policy --policy-name "$IOT_POLICY_NAME" &>/dev/null; then
        log "Deleting IoT policy: $IOT_POLICY_NAME"
        aws iot delete-policy --policy-name "$IOT_POLICY_NAME" || warn "Failed to delete IoT policy: $IOT_POLICY_NAME"
    else
        info "IoT policy $IOT_POLICY_NAME does not exist"
    fi
    
    log "✅ IoT resources deleted"
    
    # Step 3: Remove DynamoDB Table
    log "Step 3: Removing DynamoDB table..."
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE_NAME" &>/dev/null; then
        log "Deleting DynamoDB table: $DYNAMODB_TABLE_NAME"
        aws dynamodb delete-table --table-name "$DYNAMODB_TABLE_NAME"
        
        # Wait for deletion to complete
        log "Waiting for DynamoDB table deletion to complete..."
        aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE_NAME" || warn "DynamoDB table deletion timeout"
    else
        info "DynamoDB table $DYNAMODB_TABLE_NAME does not exist"
    fi
    
    log "✅ DynamoDB table deleted"
    
    # Step 4: Remove S3 Resources
    log "Step 4: Removing S3 resources..."
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" &>/dev/null; then
        log "Deleting S3 bucket contents: $S3_BUCKET_NAME"
        aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive || warn "Failed to delete S3 bucket contents"
        
        log "Deleting S3 bucket: $S3_BUCKET_NAME"
        aws s3 rb "s3://${S3_BUCKET_NAME}" || warn "Failed to delete S3 bucket: $S3_BUCKET_NAME"
    else
        info "S3 bucket $S3_BUCKET_NAME does not exist"
    fi
    
    log "✅ S3 resources deleted"
    
    # Step 5: Remove IAM Roles and Policies
    log "Step 5: Removing IAM role and policies..."
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        # Detach managed policies
        log "Detaching policies from IAM role: $IAM_ROLE_NAME"
        
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$IAM_ROLE_NAME" \
            --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
        
        for policy_arn in $ATTACHED_POLICIES; do
            if [ -n "$policy_arn" ] && [ "$policy_arn" != "None" ]; then
                log "Detaching policy: $policy_arn"
                aws iam detach-role-policy \
                    --role-name "$IAM_ROLE_NAME" \
                    --policy-arn "$policy_arn" || warn "Failed to detach policy: $policy_arn"
            fi
        done
        
        # Delete the role
        log "Deleting IAM role: $IAM_ROLE_NAME"
        aws iam delete-role --role-name "$IAM_ROLE_NAME" || warn "Failed to delete IAM role: $IAM_ROLE_NAME"
    else
        info "IAM role $IAM_ROLE_NAME does not exist"
    fi
    
    log "✅ IAM resources deleted"
    
    log "🎉 Project cleanup completed: $project_name"
}

# Function to confirm deletion
confirm_deletion() {
    local projects_list="$1"
    
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi
    
    echo ""
    warn "⚠️  DESTRUCTIVE OPERATION WARNING ⚠️"
    echo ""
    warn "This will PERMANENTLY DELETE the following Smart City Digital Twin projects and ALL associated resources:"
    
    for project in $projects_list; do
        warn "  • $project"
    done
    
    echo ""
    warn "Resources that will be deleted include:"
    warn "  - DynamoDB tables (all data will be lost)"
    warn "  - Lambda functions and their code"
    warn "  - IoT things, policies, and rules"
    warn "  - S3 buckets and their contents"
    warn "  - IAM roles and policies"
    echo ""
    
    if [ "$FORCE_DELETE" = true ]; then
        warn "FORCE mode enabled - deletion will proceed without additional prompts"
        return 0
    fi
    
    read -p "Are you absolutely sure you want to proceed? Type 'DELETE' to confirm: " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log "Operation cancelled by user"
        exit 0
    fi
    
    read -p "Last chance! This action cannot be undone. Type 'YES' to proceed: " final_confirmation
    if [ "$final_confirmation" != "YES" ]; then
        log "Operation cancelled by user"
        exit 0
    fi
}

# Main execution logic
if [ -n "$PROJECT_NAME_PATTERN" ]; then
    # User specified a project name pattern
    PROJECTS_TO_DELETE="$PROJECT_NAME_PATTERN"
    log "Using specified project pattern: $PROJECT_NAME_PATTERN"
else
    # Discover projects automatically
    PROJECTS_TO_DELETE=$(find_smart_city_projects)
fi

# Remove leading/trailing whitespace and check if any projects found
PROJECTS_TO_DELETE=$(echo "$PROJECTS_TO_DELETE" | xargs)

if [ -z "$PROJECTS_TO_DELETE" ]; then
    warn "No Smart City Digital Twin projects found."
    log "Use --project-name to specify a specific project if you know the exact name."
    exit 0
fi

log "Found Smart City Digital Twin projects:"
for project in $PROJECTS_TO_DELETE; do
    log "  • $project"
done

if [ "$DRY_RUN" = false ]; then
    confirm_deletion "$PROJECTS_TO_DELETE"
fi

# Delete each project
for project in $PROJECTS_TO_DELETE; do
    delete_project_resources "$project"
done

if [ "$DRY_RUN" = false ]; then
    log ""
    log "🎉 All Smart City Digital Twin cleanup operations completed successfully!"
    log ""
    log "Summary:"
    log "========"
    for project in $PROJECTS_TO_DELETE; do
        log "  ✅ Deleted project: $project"
    done
    log ""
    log "All associated AWS resources have been removed."
    log "You will no longer be charged for these resources."
else
    log ""
    log "DRY-RUN completed. No resources were actually deleted."
    log "Run without --dry-run to perform the actual cleanup."
fi

log "Cleanup script finished."