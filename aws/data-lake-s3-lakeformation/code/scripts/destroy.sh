#!/bin/bash

# Destroy script for Data Lake Architecture with S3 and Lake Formation
# This script safely removes all resources created by the deployment script

set -euo pipefail

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
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI configuration
check_aws_config() {
    if ! command_exists aws; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI is not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    log "AWS CLI is properly configured"
}

# Function to load deployment configuration
load_deployment_config() {
    if [ ! -f ".deployment_config" ]; then
        warn "No deployment configuration found (.deployment_config)"
        warn "Some resource names will be derived from defaults"
        
        # Set default values
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
        fi
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export LF_ADMIN_USER="lake-formation-admin"
        export DATA_ANALYST_USER="data-analyst"
        export DATA_ENGINEER_USER="data-engineer"
        
        # Try to find resources by pattern
        info "Attempting to discover resources..."
        
        # Find data lake buckets
        RAW_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `datalake-`) && contains(Name, `-raw`)].Name' --output text)
        PROCESSED_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `datalake-`) && contains(Name, `-processed`)].Name' --output text)
        CURATED_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `datalake-`) && contains(Name, `-curated`)].Name' --output text)
        
        # Find databases
        DATABASES=$(aws glue get-databases --query 'DatabaseList[?contains(Name, `sales_`)].Name' --output text)
        
        if [ -z "$RAW_BUCKETS" ] && [ -z "$PROCESSED_BUCKETS" ] && [ -z "$CURATED_BUCKETS" ] && [ -z "$DATABASES" ]; then
            error "No data lake resources found. Please ensure resources exist or provide configuration."
            exit 1
        fi
        
        # Use first found resources
        export RAW_BUCKET=$(echo $RAW_BUCKETS | awk '{print $1}')
        export PROCESSED_BUCKET=$(echo $PROCESSED_BUCKETS | awk '{print $1}')
        export CURATED_BUCKET=$(echo $CURATED_BUCKETS | awk '{print $1}')
        export DATABASE_NAME=$(echo $DATABASES | awk '{print $1}')
        
        # Extract data lake name from bucket name
        if [ -n "$RAW_BUCKET" ]; then
            export DATALAKE_NAME=$(echo "$RAW_BUCKET" | sed 's/-raw$//')
        fi
        
    else
        log "Loading deployment configuration..."
        source .deployment_config
        info "Configuration loaded successfully"
    fi
    
    log "Cleanup configuration:"
    info "  AWS Region: ${AWS_REGION}"
    info "  AWS Account ID: ${AWS_ACCOUNT_ID}"
    info "  Data Lake Name: ${DATALAKE_NAME:-Unknown}"
    info "  Raw Bucket: ${RAW_BUCKET:-Unknown}"
    info "  Processed Bucket: ${PROCESSED_BUCKET:-Unknown}"
    info "  Curated Bucket: ${CURATED_BUCKET:-Unknown}"
    info "  Database Name: ${DATABASE_NAME:-Unknown}"
}

# Function to confirm destruction
confirm_destruction() {
    echo -e "\n${RED}WARNING: This will permanently delete all data lake resources!${NC}"
    echo -e "${YELLOW}This action cannot be undone.${NC}"
    echo -e "\n${BLUE}Resources to be deleted:${NC}"
    
    if [ -n "${RAW_BUCKET:-}" ]; then
        echo -e "  • S3 Bucket: ${RAW_BUCKET}"
    fi
    if [ -n "${PROCESSED_BUCKET:-}" ]; then
        echo -e "  • S3 Bucket: ${PROCESSED_BUCKET}"
    fi
    if [ -n "${CURATED_BUCKET:-}" ]; then
        echo -e "  • S3 Bucket: ${CURATED_BUCKET}"
    fi
    if [ -n "${DATABASE_NAME:-}" ]; then
        echo -e "  • Glue Database: ${DATABASE_NAME}"
    fi
    echo -e "  • Glue Crawlers: sales-crawler, customer-crawler"
    echo -e "  • IAM Roles: LakeFormationServiceRole, GlueCrawlerRole, DataAnalystRole, DataEngineerRole"
    echo -e "  • IAM Users: ${LF_ADMIN_USER}, ${DATA_ANALYST_USER}, ${DATA_ENGINEER_USER}"
    echo -e "  • LF-Tags: Department, Classification, DataZone, AccessLevel"
    echo -e "  • Data Cell Filters: customer_pii_filter, sales_region_filter"
    echo -e "  • CloudTrail: lake-formation-audit-trail"
    echo -e "  • CloudWatch Log Group: /aws/lakeformation/audit"
    
    echo -e "\n${YELLOW}Are you sure you want to proceed? (yes/no):${NC}"
    read -r confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Proceeding with resource destruction..."
}

# Function to delete data cell filters
delete_data_cell_filters() {
    log "Deleting data cell filters..."
    
    if [ -z "${DATABASE_NAME:-}" ]; then
        warn "Database name not found, skipping data cell filter deletion"
        return
    fi
    
    # Delete customer PII filter
    info "Deleting customer PII filter..."
    aws lakeformation delete-data-cells-filter \
        --table-catalog-id "${AWS_ACCOUNT_ID}" \
        --database-name "${DATABASE_NAME}" \
        --table-name "customer_customer_data" \
        --name "customer_pii_filter" 2>/dev/null || warn "Customer PII filter may not exist"
    
    # Delete sales region filter
    info "Deleting sales region filter..."
    aws lakeformation delete-data-cells-filter \
        --table-catalog-id "${AWS_ACCOUNT_ID}" \
        --database-name "${DATABASE_NAME}" \
        --table-name "sales_sales_data" \
        --name "sales_region_filter" 2>/dev/null || warn "Sales region filter may not exist"
    
    log "Data cell filters deleted successfully"
}

# Function to revoke Lake Formation permissions
revoke_lake_formation_permissions() {
    log "Revoking Lake Formation permissions..."
    
    if [ -z "${DATABASE_NAME:-}" ]; then
        warn "Database name not found, skipping permission revocation"
        return
    fi
    
    # Revoke permissions from data analyst role
    info "Revoking permissions from data analyst role..."
    aws lakeformation revoke-permissions \
        --principal '{
            "DataLakePrincipalIdentifier": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/DataAnalystRole"
        }' \
        --resource '{
            "Database": {
                "Name": "'${DATABASE_NAME}'"
            }
        }' \
        --permissions "DESCRIBE" 2>/dev/null || warn "Data analyst database permissions may not exist"
    
    aws lakeformation revoke-permissions \
        --principal '{
            "DataLakePrincipalIdentifier": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/DataAnalystRole"
        }' \
        --resource '{
            "Table": {
                "DatabaseName": "'${DATABASE_NAME}'",
                "Name": "sales_sales_data"
            }
        }' \
        --permissions "SELECT" "DESCRIBE" 2>/dev/null || warn "Data analyst table permissions may not exist"
    
    # Revoke permissions from data engineer role
    info "Revoking permissions from data engineer role..."
    aws lakeformation revoke-permissions \
        --principal '{
            "DataLakePrincipalIdentifier": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/DataEngineerRole"
        }' \
        --resource '{
            "Database": {
                "Name": "'${DATABASE_NAME}'"
            }
        }' \
        --permissions "CREATE_TABLE" "ALTER" "DROP" "DESCRIBE" 2>/dev/null || warn "Data engineer permissions may not exist"
    
    # Revoke tag-based permissions
    info "Revoking tag-based permissions..."
    aws lakeformation revoke-permissions \
        --principal '{
            "DataLakePrincipalIdentifier": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/DataAnalystRole"
        }' \
        --resource '{
            "LFTag": {
                "TagKey": "Department",
                "TagValues": ["Sales"]
            }
        }' \
        --permissions "DESCRIBE" 2>/dev/null || warn "Tag-based permissions may not exist"
    
    aws lakeformation revoke-permissions \
        --principal '{
            "DataLakePrincipalIdentifier": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/DataAnalystRole"
        }' \
        --resource '{
            "LFTag": {
                "TagKey": "Classification",
                "TagValues": ["Internal"]
            }
        }' \
        --permissions "SELECT" "DESCRIBE" 2>/dev/null || warn "Tag-based permissions may not exist"
    
    log "Lake Formation permissions revoked successfully"
}

# Function to delete Glue resources
delete_glue_resources() {
    log "Deleting Glue resources..."
    
    # Delete crawlers
    info "Deleting Glue crawlers..."
    aws glue delete-crawler --name "sales-crawler" 2>/dev/null || warn "Sales crawler may not exist"
    aws glue delete-crawler --name "customer-crawler" 2>/dev/null || warn "Customer crawler may not exist"
    
    # Delete database
    if [ -n "${DATABASE_NAME:-}" ]; then
        info "Deleting Glue database: ${DATABASE_NAME}"
        aws glue delete-database --name "${DATABASE_NAME}" 2>/dev/null || warn "Database ${DATABASE_NAME} may not exist"
    fi
    
    log "Glue resources deleted successfully"
}

# Function to deregister S3 buckets from Lake Formation
deregister_s3_buckets() {
    log "Deregistering S3 buckets from Lake Formation..."
    
    # Deregister buckets
    for bucket in "${RAW_BUCKET:-}" "${PROCESSED_BUCKET:-}" "${CURATED_BUCKET:-}"; do
        if [ -n "$bucket" ]; then
            info "Deregistering bucket: $bucket"
            aws lakeformation deregister-resource \
                --resource-arn "arn:aws:s3:::$bucket" 2>/dev/null || warn "Bucket $bucket may not be registered"
        fi
    done
    
    log "S3 buckets deregistered from Lake Formation successfully"
}

# Function to delete LF-Tags
delete_lf_tags() {
    log "Deleting LF-Tags..."
    
    # Delete all LF-Tags
    info "Deleting Department tag..."
    aws lakeformation delete-lf-tag --tag-key "Department" 2>/dev/null || warn "Department tag may not exist"
    
    info "Deleting Classification tag..."
    aws lakeformation delete-lf-tag --tag-key "Classification" 2>/dev/null || warn "Classification tag may not exist"
    
    info "Deleting DataZone tag..."
    aws lakeformation delete-lf-tag --tag-key "DataZone" 2>/dev/null || warn "DataZone tag may not exist"
    
    info "Deleting AccessLevel tag..."
    aws lakeformation delete-lf-tag --tag-key "AccessLevel" 2>/dev/null || warn "AccessLevel tag may not exist"
    
    log "LF-Tags deleted successfully"
}

# Function to delete IAM resources
delete_iam_resources() {
    log "Deleting IAM resources..."
    
    # Detach and delete policies from Glue crawler role
    info "Cleaning up Glue crawler role..."
    aws iam detach-role-policy \
        --role-name GlueCrawlerRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole 2>/dev/null || warn "Policy may not be attached"
    
    aws iam detach-role-policy \
        --role-name GlueCrawlerRole \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/GlueS3AccessPolicy" 2>/dev/null || warn "Policy may not be attached"
    
    # Delete custom policy
    info "Deleting custom S3 access policy..."
    aws iam delete-policy \
        --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/GlueS3AccessPolicy" 2>/dev/null || warn "Policy may not exist"
    
    # Detach policies from other roles
    info "Cleaning up Lake Formation service role..."
    aws iam detach-role-policy \
        --role-name LakeFormationServiceRole \
        --policy-arn arn:aws:iam::aws:policy/service-role/LakeFormationServiceRole 2>/dev/null || warn "Policy may not be attached"
    
    info "Cleaning up data analyst role..."
    aws iam detach-role-policy \
        --role-name DataAnalystRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonAthenaFullAccess 2>/dev/null || warn "Policy may not be attached"
    
    info "Cleaning up data engineer role..."
    aws iam detach-role-policy \
        --role-name DataEngineerRole \
        --policy-arn arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess 2>/dev/null || warn "Policy may not be attached"
    
    # Delete IAM roles
    info "Deleting IAM roles..."
    aws iam delete-role --role-name LakeFormationServiceRole 2>/dev/null || warn "LakeFormationServiceRole may not exist"
    aws iam delete-role --role-name GlueCrawlerRole 2>/dev/null || warn "GlueCrawlerRole may not exist"
    aws iam delete-role --role-name DataAnalystRole 2>/dev/null || warn "DataAnalystRole may not exist"
    aws iam delete-role --role-name DataEngineerRole 2>/dev/null || warn "DataEngineerRole may not exist"
    
    # Delete IAM users
    info "Deleting IAM users..."
    aws iam detach-user-policy \
        --user-name "${LF_ADMIN_USER}" \
        --policy-arn arn:aws:iam::aws:policy/LakeFormationDataAdmin 2>/dev/null || warn "Policy may not be attached"
    
    aws iam delete-user --user-name "${LF_ADMIN_USER}" 2>/dev/null || warn "User ${LF_ADMIN_USER} may not exist"
    aws iam delete-user --user-name "${DATA_ANALYST_USER}" 2>/dev/null || warn "User ${DATA_ANALYST_USER} may not exist"
    aws iam delete-user --user-name "${DATA_ENGINEER_USER}" 2>/dev/null || warn "User ${DATA_ENGINEER_USER} may not exist"
    
    log "IAM resources deleted successfully"
}

# Function to delete CloudTrail and CloudWatch resources
delete_cloudtrail_cloudwatch() {
    log "Deleting CloudTrail and CloudWatch resources..."
    
    # Stop and delete CloudTrail
    info "Stopping CloudTrail logging..."
    aws cloudtrail stop-logging --name lake-formation-audit-trail 2>/dev/null || warn "CloudTrail may not exist"
    
    info "Deleting CloudTrail..."
    aws cloudtrail delete-trail --name lake-formation-audit-trail 2>/dev/null || warn "CloudTrail may not exist"
    
    # Delete CloudWatch log group
    info "Deleting CloudWatch log group..."
    aws logs delete-log-group --log-group-name /aws/lakeformation/audit 2>/dev/null || warn "Log group may not exist"
    
    log "CloudTrail and CloudWatch resources deleted successfully"
}

# Function to delete S3 buckets
delete_s3_buckets() {
    log "Deleting S3 buckets..."
    
    # Delete bucket contents and buckets
    for bucket in "${RAW_BUCKET:-}" "${PROCESSED_BUCKET:-}" "${CURATED_BUCKET:-}"; do
        if [ -n "$bucket" ]; then
            info "Deleting bucket: $bucket"
            
            # Empty bucket first
            if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
                info "Emptying bucket contents..."
                aws s3 rm "s3://$bucket" --recursive 2>/dev/null || warn "Bucket may already be empty"
                
                # Remove versioned objects if any
                aws s3api delete-objects --bucket "$bucket" --delete "$(aws s3api list-object-versions --bucket "$bucket" --output json | jq '{Objects: [.Versions[]? | {Key:.Key, VersionId:.VersionId}], Quiet: false}')" 2>/dev/null || warn "No versioned objects to delete"
                
                # Remove delete markers
                aws s3api delete-objects --bucket "$bucket" --delete "$(aws s3api list-object-versions --bucket "$bucket" --output json | jq '{Objects: [.DeleteMarkers[]? | {Key:.Key, VersionId:.VersionId}], Quiet: false}')" 2>/dev/null || warn "No delete markers to remove"
                
                # Delete bucket
                aws s3 rb "s3://$bucket" 2>/dev/null || warn "Bucket $bucket may not exist"
            else
                warn "Bucket $bucket does not exist or is not accessible"
            fi
        fi
    done
    
    log "S3 buckets deleted successfully"
}

# Function to reset Lake Formation settings
reset_lake_formation_settings() {
    log "Resetting Lake Formation settings..."
    
    # Reset Lake Formation settings to default
    info "Resetting Lake Formation to default settings..."
    
    # Create default settings configuration
    cat > reset-lf-settings.json << EOF
{
    "DataLakeAdmins": [{
        "DataLakePrincipalIdentifier": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
    }],
    "CreateDatabaseDefaultPermissions": [{
        "Principal": "IAMAllowedPrincipals",
        "Permissions": ["ALL"]
    }],
    "CreateTableDefaultPermissions": [{
        "Principal": "IAMAllowedPrincipals",
        "Permissions": ["ALL"]
    }],
    "TrustedResourceOwners": [],
    "AllowExternalDataFiltering": false,
    "ExternalDataFilteringAllowList": []
}
EOF
    
    # Apply default Lake Formation settings
    aws lakeformation put-data-lake-settings \
        --data-lake-settings file://reset-lf-settings.json 2>/dev/null || warn "Failed to reset Lake Formation settings"
    
    rm -f reset-lf-settings.json
    
    log "Lake Formation settings reset successfully"
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f glue-s3-policy.json lf-settings.json customer-filter.json sales-region-filter.json
    rm -f sales_data.csv customer_data.csv reset-lf-settings.json
    rm -f .deployment_config
    
    log "Temporary files cleaned up successfully"
}

# Function to run post-destruction validation
run_post_destruction_validation() {
    log "Running post-destruction validation..."
    
    # Check if buckets are deleted
    for bucket in "${RAW_BUCKET:-}" "${PROCESSED_BUCKET:-}" "${CURATED_BUCKET:-}"; do
        if [ -n "$bucket" ]; then
            if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
                warn "Bucket $bucket still exists"
            else
                info "✓ Bucket $bucket successfully deleted"
            fi
        fi
    done
    
    # Check if database is deleted
    if [ -n "${DATABASE_NAME:-}" ]; then
        if aws glue get-database --name "${DATABASE_NAME}" 2>/dev/null; then
            warn "Database ${DATABASE_NAME} still exists"
        else
            info "✓ Database ${DATABASE_NAME} successfully deleted"
        fi
    fi
    
    # Check if crawlers are deleted
    if aws glue get-crawler --name "sales-crawler" 2>/dev/null; then
        warn "Sales crawler still exists"
    else
        info "✓ Sales crawler successfully deleted"
    fi
    
    if aws glue get-crawler --name "customer-crawler" 2>/dev/null; then
        warn "Customer crawler still exists"
    else
        info "✓ Customer crawler successfully deleted"
    fi
    
    # Check if IAM roles are deleted
    for role in "LakeFormationServiceRole" "GlueCrawlerRole" "DataAnalystRole" "DataEngineerRole"; do
        if aws iam get-role --role-name "$role" 2>/dev/null; then
            warn "Role $role still exists"
        else
            info "✓ Role $role successfully deleted"
        fi
    done
    
    # Check if IAM users are deleted
    for user in "${LF_ADMIN_USER}" "${DATA_ANALYST_USER}" "${DATA_ENGINEER_USER}"; do
        if aws iam get-user --user-name "$user" 2>/dev/null; then
            warn "User $user still exists"
        else
            info "✓ User $user successfully deleted"
        fi
    done
    
    # Check if CloudTrail is deleted
    if aws cloudtrail describe-trails --trail-name-list lake-formation-audit-trail 2>/dev/null | grep -q "lake-formation-audit-trail"; then
        warn "CloudTrail lake-formation-audit-trail still exists"
    else
        info "✓ CloudTrail successfully deleted"
    fi
    
    log "Post-destruction validation completed"
}

# Function to display destruction summary
display_destruction_summary() {
    log "Destruction completed!"
    
    echo -e "\n${GREEN}=== DESTRUCTION SUMMARY ===${NC}"
    echo -e "${GREEN}The following resources have been removed:${NC}"
    echo -e "  ✓ Data Cell Filters"
    echo -e "  ✓ Lake Formation Permissions"
    echo -e "  ✓ Glue Crawlers and Database"
    echo -e "  ✓ S3 Buckets and Data"
    echo -e "  ✓ LF-Tags"
    echo -e "  ✓ IAM Roles and Users"
    echo -e "  ✓ CloudTrail and CloudWatch Resources"
    echo -e "  ✓ Temporary Files"
    echo -e "\n${GREEN}Lake Formation settings have been reset to defaults.${NC}"
    echo -e "\n${YELLOW}All data lake resources have been permanently deleted.${NC}"
    echo -e "${BLUE}Thank you for using the Data Lake Architecture recipe!${NC}"
}

# Main execution
main() {
    log "Starting Data Lake Architecture destruction..."
    
    # Pre-destruction setup
    check_aws_config
    load_deployment_config
    confirm_destruction
    
    # Destruction sequence (reverse order of creation)
    delete_data_cell_filters
    revoke_lake_formation_permissions
    delete_glue_resources
    deregister_s3_buckets
    delete_lf_tags
    delete_iam_resources
    delete_cloudtrail_cloudwatch
    delete_s3_buckets
    reset_lake_formation_settings
    cleanup_temp_files
    
    # Post-destruction validation and summary
    run_post_destruction_validation
    display_destruction_summary
    
    log "Destruction completed successfully!"
}

# Execute main function
main "$@"