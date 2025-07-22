#!/bin/bash

# S3 Cross-Region Replication with Encryption and Access Controls - Cleanup Script
# Recipe: Replicating S3 Data Across Regions with Encryption
# Version: 1.1

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="/tmp/s3-crr-destroy-$(date +%Y%m%d-%H%M%S).log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR="/tmp/s3-crr-cleanup-$$"
DRY_RUN=false
SKIP_CONFIRMATION=false
FORCE_DELETE=false
DELETE_KMS_KEYS=false
WAIT_TIMEOUT=300

# Function to log messages
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)
            echo -e "${BLUE}[INFO]${NC} ${timestamp} - $message"
            ;;
        SUCCESS)
            echo -e "${GREEN}[SUCCESS]${NC} ${timestamp} - $message"
            ;;
        WARNING)
            echo -e "${YELLOW}[WARNING]${NC} ${timestamp} - $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message"
            ;;
    esac
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to cleanup temporary files
cleanup() {
    log INFO "Cleaning up temporary files..."
    rm -rf "${TEMP_DIR}"
    log INFO "Temporary files cleaned up"
}

# Trap to ensure cleanup happens
trap cleanup EXIT

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy S3 Cross-Region Replication infrastructure and clean up all resources

OPTIONS:
    -h, --help              Show this help message
    -d, --dry-run           Show what would be deleted without making changes
    -y, --yes               Skip confirmation prompts
    -f, --force             Force deletion of resources without additional prompts
    -k, --delete-kms        Also schedule KMS keys for deletion (7-day waiting period)
    -i, --info-file         Path to deployment info file (default: ../deployment-info.json)
    -r, --primary-region    Primary AWS region (required if no info file)
    -s, --secondary-region  Secondary AWS region (required if no info file)
    -v, --verbose           Enable verbose logging

EXAMPLES:
    $0                                          # Clean up using deployment info file
    $0 --dry-run                               # Show what would be deleted
    $0 --force --delete-kms                    # Force delete all resources including KMS keys
    $0 --primary-region us-east-1 --secondary-region us-west-2

NOTES:
    - KMS keys have a 7-day waiting period before deletion
    - Use --force to skip individual confirmation prompts
    - Deployment info file contains resource names from deployment

EOF
}

# Function to validate AWS CLI and credentials
validate_aws_prerequisites() {
    log INFO "Validating AWS prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command_exists aws; then
        log ERROR "AWS CLI is not installed. Please install AWS CLI v2"
        return 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log ERROR "AWS credentials not configured. Please run 'aws configure' or set AWS environment variables"
        return 1
    fi
    
    # Get caller identity
    local caller_identity
    caller_identity=$(aws sts get-caller-identity)
    log INFO "AWS caller identity: $(echo "$caller_identity" | jq -r '.Arn')"
    
    return 0
}

# Function to load deployment information
load_deployment_info() {
    log INFO "Loading deployment information..."
    
    if [[ -f "$INFO_FILE" ]]; then
        log INFO "Loading from deployment info file: $INFO_FILE"
        
        # Check if jq is available for JSON parsing
        if command_exists jq; then
            PRIMARY_REGION=$(jq -r '.primary_region' "$INFO_FILE")
            SECONDARY_REGION=$(jq -r '.secondary_region' "$INFO_FILE")
            SOURCE_BUCKET=$(jq -r '.source_bucket' "$INFO_FILE")
            DEST_BUCKET=$(jq -r '.destination_bucket' "$INFO_FILE")
            REPLICATION_ROLE=$(jq -r '.replication_role' "$INFO_FILE")
            SOURCE_KMS_KEY=$(jq -r '.source_kms_key' "$INFO_FILE")
            DEST_KMS_KEY=$(jq -r '.destination_kms_key' "$INFO_FILE")
            SOURCE_KMS_ALIAS=$(jq -r '.source_kms_alias' "$INFO_FILE")
            DEST_KMS_ALIAS=$(jq -r '.destination_kms_alias' "$INFO_FILE")
            AWS_ACCOUNT_ID=$(jq -r '.aws_account_id' "$INFO_FILE")
        else
            # Fallback parsing without jq
            log WARNING "jq not available, using basic parsing"
            PRIMARY_REGION=$(grep '"primary_region"' "$INFO_FILE" | cut -d'"' -f4)
            SECONDARY_REGION=$(grep '"secondary_region"' "$INFO_FILE" | cut -d'"' -f4)
            SOURCE_BUCKET=$(grep '"source_bucket"' "$INFO_FILE" | cut -d'"' -f4)
            DEST_BUCKET=$(grep '"destination_bucket"' "$INFO_FILE" | cut -d'"' -f4)
            REPLICATION_ROLE=$(grep '"replication_role"' "$INFO_FILE" | cut -d'"' -f4)
            SOURCE_KMS_KEY=$(grep '"source_kms_key"' "$INFO_FILE" | cut -d'"' -f4)
            DEST_KMS_KEY=$(grep '"destination_kms_key"' "$INFO_FILE" | cut -d'"' -f4)
            SOURCE_KMS_ALIAS=$(grep '"source_kms_alias"' "$INFO_FILE" | cut -d'"' -f4)
            DEST_KMS_ALIAS=$(grep '"destination_kms_alias"' "$INFO_FILE" | cut -d'"' -f4)
            AWS_ACCOUNT_ID=$(grep '"aws_account_id"' "$INFO_FILE" | cut -d'"' -f4)
        fi
        
        log SUCCESS "Loaded deployment information from file"
        return 0
    else
        log WARNING "Deployment info file not found: $INFO_FILE"
        
        # Check if regions were provided via command line
        if [[ -z "${PRIMARY_REGION:-}" || -z "${SECONDARY_REGION:-}" ]]; then
            log ERROR "Deployment info file not found and regions not provided via command line"
            log ERROR "Please provide --primary-region and --secondary-region options"
            return 1
        fi
        
        log INFO "Using command-line provided regions"
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        return 0
    fi
}

# Function to discover resources if not loaded from info file
discover_resources() {
    log INFO "Discovering resources..."
    
    mkdir -p "${TEMP_DIR}"
    
    # Discover S3 buckets with CRR configuration
    log INFO "Scanning for S3 buckets with cross-region replication..."
    
    # Get list of all buckets in primary region
    aws s3api list-buckets --region "$PRIMARY_REGION" --query 'Buckets[].Name' --output text > "${TEMP_DIR}/all_buckets.txt"
    
    # Check each bucket for replication configuration
    while read -r bucket; do
        if [[ -n "$bucket" ]]; then
            replication_config=$(aws s3api get-bucket-replication --bucket "$bucket" --region "$PRIMARY_REGION" 2>/dev/null || echo "")
            if [[ -n "$replication_config" ]]; then
                log INFO "Found bucket with replication: $bucket"
                # Add to discovered resources
                echo "$bucket" >> "${TEMP_DIR}/source_buckets.txt"
                
                # Get destination bucket from replication config
                dest_bucket=$(echo "$replication_config" | jq -r '.ReplicationConfiguration.Rules[0].Destination.Bucket' 2>/dev/null | sed 's|arn:aws:s3:::|g|')
                if [[ -n "$dest_bucket" && "$dest_bucket" != "null" ]]; then
                    echo "$dest_bucket" >> "${TEMP_DIR}/dest_buckets.txt"
                fi
                
                # Get replication role
                role_arn=$(echo "$replication_config" | jq -r '.ReplicationConfiguration.Role' 2>/dev/null)
                if [[ -n "$role_arn" && "$role_arn" != "null" ]]; then
                    role_name=$(echo "$role_arn" | cut -d'/' -f2)
                    echo "$role_name" >> "${TEMP_DIR}/replication_roles.txt"
                fi
            fi
        fi
    done < "${TEMP_DIR}/all_buckets.txt"
    
    # Discover KMS aliases
    log INFO "Scanning for KMS aliases..."
    aws kms list-aliases --region "$PRIMARY_REGION" --query 'Aliases[?starts_with(AliasName, `alias/crr-`) || starts_with(AliasName, `alias/s3-crr-`)].AliasName' --output text > "${TEMP_DIR}/source_kms_aliases.txt"
    aws kms list-aliases --region "$SECONDARY_REGION" --query 'Aliases[?starts_with(AliasName, `alias/crr-`) || starts_with(AliasName, `alias/s3-crr-`)].AliasName' --output text > "${TEMP_DIR}/dest_kms_aliases.txt"
    
    log SUCCESS "Resource discovery completed"
}

# Function to delete objects from S3 buckets
delete_bucket_objects() {
    local bucket=$1
    local region=$2
    
    log INFO "Deleting objects from bucket: $bucket"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete all objects from bucket: $bucket"
        return 0
    fi
    
    # Check if bucket exists
    if ! aws s3api head-bucket --bucket "$bucket" --region "$region" >/dev/null 2>&1; then
        log WARNING "Bucket does not exist or is not accessible: $bucket"
        return 0
    fi
    
    # Delete all object versions and delete markers
    log INFO "Deleting all object versions and delete markers from: $bucket"
    
    # Create a script to handle versioned object deletion
    cat > "${TEMP_DIR}/delete_versions.sh" << 'EOF'
#!/bin/bash
bucket=$1
region=$2

# Delete all object versions
aws s3api list-object-versions --bucket "$bucket" --region "$region" --output json --query 'Versions[].{Key:Key,VersionId:VersionId}' | \
jq -r '.[] | @base64' | \
while read -r obj; do
    key=$(echo "$obj" | base64 --decode | jq -r '.Key')
    version_id=$(echo "$obj" | base64 --decode | jq -r '.VersionId')
    if [[ "$key" != "null" && "$version_id" != "null" ]]; then
        aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" --region "$region" >/dev/null
    fi
done

# Delete all delete markers
aws s3api list-object-versions --bucket "$bucket" --region "$region" --output json --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' | \
jq -r '.[] | @base64' | \
while read -r obj; do
    key=$(echo "$obj" | base64 --decode | jq -r '.Key')
    version_id=$(echo "$obj" | base64 --decode | jq -r '.VersionId')
    if [[ "$key" != "null" && "$version_id" != "null" ]]; then
        aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version_id" --region "$region" >/dev/null
    fi
done
EOF
    
    chmod +x "${TEMP_DIR}/delete_versions.sh"
    
    # Try batch deletion first (faster)
    aws s3 rm "s3://${bucket}/" --recursive --region "$region" >/dev/null 2>&1 || true
    
    # Handle versioned objects if jq is available
    if command_exists jq; then
        "${TEMP_DIR}/delete_versions.sh" "$bucket" "$region"
    else
        log WARNING "jq not available, cannot delete versioned objects. Manual cleanup may be required."
    fi
    
    log SUCCESS "Deleted objects from bucket: $bucket"
}

# Function to delete S3 buckets
delete_s3_buckets() {
    log INFO "Deleting S3 buckets..."
    
    local buckets_to_delete=()
    
    # Add known buckets if available
    [[ -n "${SOURCE_BUCKET:-}" ]] && buckets_to_delete+=("$SOURCE_BUCKET:$PRIMARY_REGION")
    [[ -n "${DEST_BUCKET:-}" ]] && buckets_to_delete+=("$DEST_BUCKET:$SECONDARY_REGION")
    
    # Add discovered buckets
    if [[ -f "${TEMP_DIR}/source_buckets.txt" ]]; then
        while read -r bucket; do
            [[ -n "$bucket" ]] && buckets_to_delete+=("$bucket:$PRIMARY_REGION")
        done < "${TEMP_DIR}/source_buckets.txt"
    fi
    
    if [[ -f "${TEMP_DIR}/dest_buckets.txt" ]]; then
        while read -r bucket; do
            [[ -n "$bucket" ]] && buckets_to_delete+=("$bucket:$SECONDARY_REGION")
        done < "${TEMP_DIR}/dest_buckets.txt"
    fi
    
    # Remove duplicates
    local unique_buckets=($(printf "%s\n" "${buckets_to_delete[@]}" | sort -u))
    
    for bucket_region in "${unique_buckets[@]}"; do
        local bucket=$(echo "$bucket_region" | cut -d':' -f1)
        local region=$(echo "$bucket_region" | cut -d':' -f2)
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY RUN] Would delete bucket: $bucket in region: $region"
            continue
        fi
        
        # Remove replication configuration first
        log INFO "Removing replication configuration from: $bucket"
        aws s3api delete-bucket-replication --bucket "$bucket" --region "$region" 2>/dev/null || true
        
        # Delete bucket objects
        delete_bucket_objects "$bucket" "$region"
        
        # Delete bucket policy
        log INFO "Removing bucket policy from: $bucket"
        aws s3api delete-bucket-policy --bucket "$bucket" --region "$region" 2>/dev/null || true
        
        # Delete bucket
        log INFO "Deleting bucket: $bucket"
        if aws s3api delete-bucket --bucket "$bucket" --region "$region" 2>/dev/null; then
            log SUCCESS "Deleted bucket: $bucket"
        else
            log ERROR "Failed to delete bucket: $bucket"
        fi
    done
}

# Function to delete IAM roles
delete_iam_roles() {
    log INFO "Deleting IAM roles..."
    
    local roles_to_delete=()
    
    # Add known role if available
    [[ -n "${REPLICATION_ROLE:-}" ]] && roles_to_delete+=("$REPLICATION_ROLE")
    
    # Add discovered roles
    if [[ -f "${TEMP_DIR}/replication_roles.txt" ]]; then
        while read -r role; do
            [[ -n "$role" ]] && roles_to_delete+=("$role")
        done < "${TEMP_DIR}/replication_roles.txt"
    fi
    
    # Remove duplicates
    local unique_roles=($(printf "%s\n" "${roles_to_delete[@]}" | sort -u))
    
    for role in "${unique_roles[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY RUN] Would delete IAM role: $role"
            continue
        fi
        
        # Check if role exists
        if ! aws iam get-role --role-name "$role" >/dev/null 2>&1; then
            log WARNING "IAM role does not exist: $role"
            continue
        fi
        
        # Delete role policies
        log INFO "Deleting inline policies from role: $role"
        aws iam list-role-policies --role-name "$role" --query 'PolicyNames[]' --output text | \
        while read -r policy; do
            if [[ -n "$policy" ]]; then
                aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null || true
            fi
        done
        
        # Detach managed policies
        log INFO "Detaching managed policies from role: $role"
        aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text | \
        while read -r policy_arn; do
            if [[ -n "$policy_arn" ]]; then
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn" 2>/dev/null || true
            fi
        done
        
        # Delete role
        log INFO "Deleting IAM role: $role"
        if aws iam delete-role --role-name "$role" 2>/dev/null; then
            log SUCCESS "Deleted IAM role: $role"
        else
            log ERROR "Failed to delete IAM role: $role"
        fi
    done
}

# Function to delete CloudWatch alarms
delete_cloudwatch_alarms() {
    log INFO "Deleting CloudWatch alarms..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would delete CloudWatch alarms"
        return 0
    fi
    
    # Get list of S3 replication related alarms
    local alarms=$(aws cloudwatch describe-alarms \
        --region "$PRIMARY_REGION" \
        --alarm-name-prefix "S3-Replication-" \
        --query 'MetricAlarms[].AlarmName' \
        --output text)
    
    if [[ -n "$alarms" ]]; then
        log INFO "Deleting CloudWatch alarms: $alarms"
        aws cloudwatch delete-alarms --alarm-names $alarms --region "$PRIMARY_REGION"
        log SUCCESS "Deleted CloudWatch alarms"
    else
        log INFO "No CloudWatch alarms found to delete"
    fi
}

# Function to delete KMS aliases and keys
delete_kms_resources() {
    log INFO "Managing KMS resources..."
    
    local aliases_to_delete=()
    local keys_to_delete=()
    
    # Add known aliases if available
    [[ -n "${SOURCE_KMS_ALIAS:-}" ]] && aliases_to_delete+=("$SOURCE_KMS_ALIAS:$PRIMARY_REGION")
    [[ -n "${DEST_KMS_ALIAS:-}" ]] && aliases_to_delete+=("$DEST_KMS_ALIAS:$SECONDARY_REGION")
    
    # Add known keys if available
    [[ -n "${SOURCE_KMS_KEY:-}" ]] && keys_to_delete+=("$SOURCE_KMS_KEY:$PRIMARY_REGION")
    [[ -n "${DEST_KMS_KEY:-}" ]] && keys_to_delete+=("$DEST_KMS_KEY:$SECONDARY_REGION")
    
    # Add discovered aliases
    if [[ -f "${TEMP_DIR}/source_kms_aliases.txt" ]]; then
        while read -r alias; do
            [[ -n "$alias" ]] && aliases_to_delete+=("$alias:$PRIMARY_REGION")
        done < "${TEMP_DIR}/source_kms_aliases.txt"
    fi
    
    if [[ -f "${TEMP_DIR}/dest_kms_aliases.txt" ]]; then
        while read -r alias; do
            [[ -n "$alias" ]] && aliases_to_delete+=("$alias:$SECONDARY_REGION")
        done < "${TEMP_DIR}/dest_kms_aliases.txt"
    fi
    
    # Delete aliases
    for alias_region in "${aliases_to_delete[@]}"; do
        local alias=$(echo "$alias_region" | cut -d':' -f1)
        local region=$(echo "$alias_region" | cut -d':' -f2)
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log INFO "[DRY RUN] Would delete KMS alias: $alias in region: $region"
            continue
        fi
        
        log INFO "Deleting KMS alias: $alias"
        if aws kms delete-alias --alias-name "$alias" --region "$region" 2>/dev/null; then
            log SUCCESS "Deleted KMS alias: $alias"
            
            # Get key ID for the alias to add to deletion list
            key_id=$(aws kms describe-key --key-id "$alias" --region "$region" --query 'KeyMetadata.KeyId' --output text 2>/dev/null || echo "")
            if [[ -n "$key_id" && "$key_id" != "null" ]]; then
                keys_to_delete+=("$key_id:$region")
            fi
        else
            log WARNING "Failed to delete or alias does not exist: $alias"
        fi
    done
    
    # Handle KMS key deletion if requested
    if [[ "$DELETE_KMS_KEYS" == "true" ]]; then
        # Remove duplicates from keys list
        local unique_keys=($(printf "%s\n" "${keys_to_delete[@]}" | sort -u))
        
        for key_region in "${unique_keys[@]}"; do
            local key=$(echo "$key_region" | cut -d':' -f1)
            local region=$(echo "$key_region" | cut -d':' -f2)
            
            if [[ "$DRY_RUN" == "true" ]]; then
                log INFO "[DRY RUN] Would schedule KMS key deletion: $key in region: $region"
                continue
            fi
            
            log INFO "Scheduling KMS key deletion: $key (7-day waiting period)"
            if aws kms schedule-key-deletion --key-id "$key" --pending-window-in-days 7 --region "$region" 2>/dev/null; then
                log SUCCESS "Scheduled KMS key deletion: $key"
            else
                log WARNING "Failed to schedule key deletion or key does not exist: $key"
            fi
        done
    else
        log INFO "KMS key deletion not requested. Use --delete-kms to schedule key deletion."
    fi
}

# Function to clean up temporary and info files
clean_deployment_files() {
    log INFO "Cleaning up deployment files..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "[DRY RUN] Would clean up deployment files"
        return 0
    fi
    
    # Remove deployment info file if it exists
    if [[ -f "$INFO_FILE" ]]; then
        if [[ "$FORCE_DELETE" == "true" ]] || [[ "$SKIP_CONFIRMATION" == "true" ]]; then
            rm -f "$INFO_FILE"
            log SUCCESS "Removed deployment info file: $INFO_FILE"
        else
            read -p "Delete deployment info file? (y/N): " -r
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$INFO_FILE"
                log SUCCESS "Removed deployment info file: $INFO_FILE"
            fi
        fi
    fi
    
    # Clean up any other temporary files in the script directory
    find "$SCRIPT_DIR" -name "*.tmp" -type f -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -name "deployment-*.json" -type f -delete 2>/dev/null || true
}

# Function to show cleanup summary
show_cleanup_summary() {
    log INFO "Cleanup Summary:"
    log INFO "================"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log INFO "DRY RUN MODE - No resources were actually deleted"
    else
        log SUCCESS "S3 Cross-Region Replication cleanup completed!"
    fi
    
    log INFO "Primary Region: ${PRIMARY_REGION:-N/A}"
    log INFO "Secondary Region: ${SECONDARY_REGION:-N/A}"
    log INFO "Log File: $LOG_FILE"
    
    if [[ "$DELETE_KMS_KEYS" == "true" && "$DRY_RUN" != "true" ]]; then
        log WARNING "KMS keys have been scheduled for deletion with a 7-day waiting period"
        log INFO "You can cancel the deletion during this period if needed"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -f|--force)
            FORCE_DELETE=true
            SKIP_CONFIRMATION=true
            shift
            ;;
        -k|--delete-kms)
            DELETE_KMS_KEYS=true
            shift
            ;;
        -i|--info-file)
            INFO_FILE="$2"
            shift 2
            ;;
        -r|--primary-region)
            PRIMARY_REGION="$2"
            shift 2
            ;;
        -s|--secondary-region)
            SECONDARY_REGION="$2"
            shift 2
            ;;
        -v|--verbose)
            set -x
            shift
            ;;
        *)
            log ERROR "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Set default values
INFO_FILE="${INFO_FILE:-${SCRIPT_DIR}/../deployment-info.json}"

# Main execution
main() {
    log INFO "Starting S3 Cross-Region Replication cleanup..."
    log INFO "Script version: 1.1"
    log INFO "Cleanup mode: $(if [[ "$DRY_RUN" == "true" ]]; then echo "DRY RUN"; else echo "LIVE"; fi)"
    
    # Validate prerequisites
    validate_aws_prerequisites || exit 1
    
    # Load deployment information
    load_deployment_info || exit 1
    
    # If we don't have complete info, try to discover resources
    if [[ -z "${SOURCE_BUCKET:-}" ]]; then
        discover_resources
    fi
    
    # Show what will be deleted
    log INFO "Resources to be deleted:"
    log INFO "  Primary Region: ${PRIMARY_REGION:-N/A}"
    log INFO "  Secondary Region: ${SECONDARY_REGION:-N/A}"
    log INFO "  Source Bucket: ${SOURCE_BUCKET:-[will be discovered]}"
    log INFO "  Destination Bucket: ${DEST_BUCKET:-[will be discovered]}"
    log INFO "  Replication Role: ${REPLICATION_ROLE:-[will be discovered]}"
    log INFO "  KMS Keys: $(if [[ "$DELETE_KMS_KEYS" == "true" ]]; then echo "YES (scheduled for deletion)"; else echo "NO"; fi)"
    
    # Show confirmation if not skipped
    if [[ "$SKIP_CONFIRMATION" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        log WARNING "This will permanently delete the following resources:"
        log WARNING "  - S3 buckets and all their contents"
        log WARNING "  - IAM roles and policies"
        log WARNING "  - CloudWatch alarms"
        log WARNING "  - KMS aliases"
        if [[ "$DELETE_KMS_KEYS" == "true" ]]; then
            log WARNING "  - KMS keys (scheduled for 7-day deletion)"
        fi
        echo
        read -p "Are you sure you want to continue? (y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log INFO "Cleanup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute cleanup steps in reverse order of creation
    delete_cloudwatch_alarms
    delete_s3_buckets
    delete_iam_roles
    delete_kms_resources
    clean_deployment_files
    
    show_cleanup_summary
}

# Run main function
main "$@"