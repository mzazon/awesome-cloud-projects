#!/bin/bash

# Destroy script for Advanced Data Lake Governance with Lake Formation and DataZone
# This script safely removes all resources created by the deployment script

set -euo pipefail

# Colors for output formatting
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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Confirmation prompt
confirm_destruction() {
    echo ""
    log_warning "=========================================="
    log_warning "DANGEROUS OPERATION - DATA DESTRUCTION"
    log_warning "=========================================="
    log_warning "This script will permanently delete:"
    log_warning "- All data in the data lake S3 bucket"
    log_warning "- DataZone domain and all projects"
    log_warning "- Lake Formation permissions and filters"
    log_warning "- Glue database and table schemas"
    log_warning "- ETL jobs and associated resources"
    log_warning "- IAM roles and policies"
    log_warning "- CloudWatch logs and alarms"
    log_warning "=========================================="
    echo ""
    
    read -p "Are you absolutely sure you want to continue? (type 'DELETE' to confirm): " confirmation
    if [ "$confirmation" != "DELETE" ]; then
        log_info "Destruction cancelled by user"
        exit 0
    fi
    
    log_warning "Proceeding with resource destruction in 5 seconds..."
    sleep 5
}

# Load deployment state
load_deployment_state() {
    log_info "Loading deployment state..."
    
    # Check for deployment state in multiple locations
    if [ -f "/tmp/deployment_state.env" ]; then
        source /tmp/deployment_state.env
        log_info "Loaded state from local file"
    elif [ -f "./deployment_state.env" ]; then
        source ./deployment_state.env
        log_info "Loaded state from current directory"
    else
        # Try to derive from environment or AWS
        export AWS_REGION=$(aws configure get region || echo "us-east-1")
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        log_warning "No deployment state file found. Using current AWS configuration."
        log_info "You may need to manually specify resource names if they differ from defaults."
        
        # Set default values
        export DOMAIN_NAME="enterprise-data-governance"
        export GLUE_DATABASE="enterprise_data_catalog"
        
        # Try to find the data lake bucket
        POSSIBLE_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `enterprise-datalake`)].Name' --output text)
        if [ -n "$POSSIBLE_BUCKETS" ]; then
            export DATA_LAKE_BUCKET=$(echo $POSSIBLE_BUCKETS | cut -d' ' -f1)
            log_info "Found potential data lake bucket: ${DATA_LAKE_BUCKET}"
        else
            log_warning "Could not automatically detect data lake bucket"
            read -p "Enter the data lake bucket name: " DATA_LAKE_BUCKET
            export DATA_LAKE_BUCKET
        fi
    fi
    
    # Load DataZone variables if available
    if [ -f "/tmp/datazone_vars.env" ]; then
        source /tmp/datazone_vars.env
    fi
    
    log_info "Using configuration:"
    log_info "- Region: ${AWS_REGION}"
    log_info "- Account: ${AWS_ACCOUNT_ID}"
    log_info "- Data Lake Bucket: ${DATA_LAKE_BUCKET:-'not set'}"
    log_info "- Glue Database: ${GLUE_DATABASE:-'not set'}"
    log_info "- Domain Name: ${DOMAIN_NAME:-'not set'}"
}

# Remove DataZone resources
cleanup_datazone() {
    log_info "Cleaning up Amazon DataZone resources..."
    
    if [ -n "${DOMAIN_ID:-}" ]; then
        log_info "Found DataZone domain ID: ${DOMAIN_ID}"
        
        # Delete DataZone project
        if [ -n "${PROJECT_ID:-}" ]; then
            log_info "Deleting DataZone project..."
            aws datazone delete-project \
                --domain-identifier ${DOMAIN_ID} \
                --identifier ${PROJECT_ID} || \
                log_warning "Failed to delete DataZone project or it may not exist"
        fi
        
        # Delete glossary terms
        if [ -n "${GLOSSARY_ID:-}" ]; then
            log_info "Deleting glossary terms..."
            TERM_IDS=$(aws datazone list-glossary-terms \
                --domain-identifier ${DOMAIN_ID} \
                --glossary-identifier ${GLOSSARY_ID} \
                --query 'items[].id' --output text 2>/dev/null || echo "")
            
            for TERM_ID in $TERM_IDS; do
                if [ -n "$TERM_ID" ]; then
                    aws datazone delete-glossary-term \
                        --domain-identifier ${DOMAIN_ID} \
                        --identifier ${TERM_ID} || \
                        log_warning "Failed to delete glossary term: ${TERM_ID}"
                fi
            done
            
            # Delete glossary
            log_info "Deleting business glossary..."
            aws datazone delete-glossary \
                --domain-identifier ${DOMAIN_ID} \
                --identifier ${GLOSSARY_ID} || \
                log_warning "Failed to delete glossary or it may not exist"
        fi
        
        # Delete DataZone domain
        log_info "Deleting DataZone domain..."
        aws datazone delete-domain --identifier ${DOMAIN_ID} || \
            log_warning "Failed to delete DataZone domain or it may not exist"
        
        log_success "DataZone resources cleanup initiated"
    else
        log_warning "No DataZone domain ID found, attempting to find domain by name..."
        if [ -n "${DOMAIN_NAME:-}" ]; then
            FOUND_DOMAIN_ID=$(aws datazone list-domains \
                --query "items[?name=='${DOMAIN_NAME}'].id" \
                --output text 2>/dev/null || echo "")
            if [ -n "$FOUND_DOMAIN_ID" ]; then
                log_info "Found domain by name, deleting..."
                aws datazone delete-domain --identifier ${FOUND_DOMAIN_ID} || \
                    log_warning "Failed to delete found domain"
            else
                log_warning "No DataZone domain found with name: ${DOMAIN_NAME}"
            fi
        fi
    fi
}

# Clean up Lake Formation permissions and filters
cleanup_lake_formation() {
    log_info "Cleaning up Lake Formation permissions and filters..."
    
    if [ -n "${GLUE_DATABASE:-}" ]; then
        # Revoke Lake Formation permissions
        log_info "Revoking Lake Formation permissions..."
        
        # Revoke DataAnalyst permissions
        aws lakeformation revoke-permissions \
            --principal DataLakePrincipalIdentifier=arn:aws:iam::${AWS_ACCOUNT_ID}:role/DataAnalystRole \
            --resource '{
              "Table": {
                "DatabaseName": "'${GLUE_DATABASE}'",
                "Name": "customer_data"
              }
            }' \
            --permissions "SELECT" || \
            log_warning "Failed to revoke customer data permissions"
        
        aws lakeformation revoke-permissions \
            --principal DataLakePrincipalIdentifier=arn:aws:iam::${AWS_ACCOUNT_ID}:role/DataAnalystRole \
            --resource '{
              "Table": {
                "DatabaseName": "'${GLUE_DATABASE}'",
                "Name": "transaction_data"
              }
            }' \
            --permissions "SELECT" || \
            log_warning "Failed to revoke transaction data permissions"
        
        # Delete data cells filter
        log_info "Deleting data cells filter..."
        aws lakeformation delete-data-cells-filter \
            --table-data '{
              "TableCatalogId": "'${AWS_ACCOUNT_ID}'",
              "DatabaseName": "'${GLUE_DATABASE}'",
              "TableName": "customer_data",
              "Name": "customer_data_pii_filter"
            }' || log_warning "Failed to delete data cells filter or it may not exist"
    fi
    
    # Deregister S3 location from Lake Formation
    if [ -n "${DATA_LAKE_BUCKET:-}" ]; then
        log_info "Deregistering S3 location from Lake Formation..."
        aws lakeformation deregister-resource \
            --resource-arn arn:aws:s3:::${DATA_LAKE_BUCKET} || \
            log_warning "Failed to deregister S3 resource or it may not be registered"
    fi
    
    log_success "Lake Formation permissions and filters cleaned up"
}

# Clean up Glue resources
cleanup_glue() {
    log_info "Cleaning up AWS Glue resources..."
    
    # Delete Glue job
    log_info "Deleting Glue ETL job..."
    aws glue delete-job --job-name CustomerDataETLWithLineage || \
        log_warning "Failed to delete Glue job or it may not exist"
    
    if [ -n "${GLUE_DATABASE:-}" ]; then
        # Delete Glue tables
        log_info "Deleting Glue tables..."
        aws glue delete-table \
            --database-name ${GLUE_DATABASE} \
            --name customer_data || \
            log_warning "Failed to delete customer_data table or it may not exist"
        
        aws glue delete-table \
            --database-name ${GLUE_DATABASE} \
            --name transaction_data || \
            log_warning "Failed to delete transaction_data table or it may not exist"
        
        # Delete Glue database
        log_info "Deleting Glue database..."
        aws glue delete-database --name ${GLUE_DATABASE} || \
            log_warning "Failed to delete Glue database or it may not exist"
    fi
    
    log_success "Glue resources cleaned up"
}

# Clean up S3 resources
cleanup_s3() {
    log_info "Cleaning up S3 resources..."
    
    if [ -n "${DATA_LAKE_BUCKET:-}" ]; then
        # Check if bucket exists
        if aws s3api head-bucket --bucket ${DATA_LAKE_BUCKET} 2>/dev/null; then
            log_warning "Deleting all objects in bucket: ${DATA_LAKE_BUCKET}"
            
            # Delete all object versions (for versioned bucket)
            log_info "Deleting all object versions..."
            aws s3api delete-objects \
                --bucket ${DATA_LAKE_BUCKET} \
                --delete "$(aws s3api list-object-versions \
                    --bucket ${DATA_LAKE_BUCKET} \
                    --output json \
                    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" \
                    2>/dev/null || log_warning "No versioned objects to delete"
            
            # Delete all delete markers
            aws s3api delete-objects \
                --bucket ${DATA_LAKE_BUCKET} \
                --delete "$(aws s3api list-object-versions \
                    --bucket ${DATA_LAKE_BUCKET} \
                    --output json \
                    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" \
                    2>/dev/null || log_warning "No delete markers to remove"
            
            # Delete all current objects
            log_info "Deleting all current objects..."
            aws s3 rm s3://${DATA_LAKE_BUCKET} --recursive || \
                log_warning "Failed to delete some objects"
            
            # Delete the bucket
            log_info "Deleting S3 bucket..."
            aws s3 rb s3://${DATA_LAKE_BUCKET} || \
                error_exit "Failed to delete S3 bucket"
            
            log_success "S3 bucket and all contents deleted"
        else
            log_warning "S3 bucket ${DATA_LAKE_BUCKET} does not exist or is not accessible"
        fi
    else
        log_warning "No S3 bucket specified for deletion"
    fi
}

# Clean up CloudWatch resources
cleanup_cloudwatch() {
    log_info "Cleaning up CloudWatch resources..."
    
    # Delete CloudWatch alarms
    log_info "Deleting CloudWatch alarms..."
    aws cloudwatch delete-alarms --alarm-names "DataLakeETLFailures" || \
        log_warning "Failed to delete CloudWatch alarm or it may not exist"
    
    # Delete CloudWatch log groups
    log_info "Deleting CloudWatch log groups..."
    aws logs delete-log-group --log-group-name /aws/datazone/data-quality || \
        log_warning "Failed to delete log group or it may not exist"
    
    # Delete CloudWatch log groups for Glue job (if any)
    aws logs delete-log-group --log-group-name /aws/glue/jobs/output || \
        log_warning "No Glue output log group to delete"
    
    aws logs delete-log-group --log-group-name /aws/glue/jobs/error || \
        log_warning "No Glue error log group to delete"
    
    log_success "CloudWatch resources cleaned up"
}

# Clean up SNS resources
cleanup_sns() {
    log_info "Cleaning up SNS resources..."
    
    if [ -n "${ALERT_TOPIC_ARN:-}" ]; then
        log_info "Deleting SNS topic..."
        aws sns delete-topic --topic-arn ${ALERT_TOPIC_ARN} || \
            log_warning "Failed to delete SNS topic or it may not exist"
    else
        # Try to find and delete by name
        TOPIC_ARN=$(aws sns list-topics \
            --query 'Topics[?contains(TopicArn, `DataQualityAlerts`)].TopicArn' \
            --output text 2>/dev/null || echo "")
        if [ -n "$TOPIC_ARN" ]; then
            log_info "Found SNS topic by name, deleting..."
            aws sns delete-topic --topic-arn ${TOPIC_ARN} || \
                log_warning "Failed to delete found SNS topic"
        else
            log_warning "No SNS topic found to delete"
        fi
    fi
    
    log_success "SNS resources cleaned up"
}

# Clean up IAM resources
cleanup_iam() {
    log_info "Cleaning up IAM resources..."
    
    # Clean up Lake Formation service role
    log_info "Deleting Lake Formation service role..."
    aws iam delete-role-policy \
        --role-name LakeFormationServiceRole \
        --policy-name LakeFormationServicePolicy || \
        log_warning "Failed to delete LakeFormationServiceRole policy or it may not exist"
    
    aws iam delete-role --role-name LakeFormationServiceRole || \
        log_warning "Failed to delete LakeFormationServiceRole or it may not exist"
    
    # Clean up Data Analyst role
    log_info "Deleting Data Analyst role..."
    aws iam detach-role-policy \
        --role-name DataAnalystRole \
        --policy-arn arn:aws:iam::aws:policy/AmazonAthenaFullAccess || \
        log_warning "Failed to detach Athena policy or it may not be attached"
    
    aws iam delete-role --role-name DataAnalystRole || \
        log_warning "Failed to delete DataAnalystRole or it may not exist"
    
    log_success "IAM resources cleaned up"
}

# Clean up temporary files
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    # Remove temporary files from deployment
    rm -f /tmp/lf-service-role-trust-policy.json
    rm -f /tmp/lf-service-role-policy.json
    rm -f /tmp/data-analyst-trust-policy.json
    rm -f /tmp/customer_data_etl.py
    rm -f /tmp/sample_customer_data.csv
    rm -f /tmp/sample_transaction_data.csv
    rm -f /tmp/data_quality_rules.json
    rm -f /tmp/deployment_state.env
    rm -f /tmp/datazone_vars.env
    
    # Remove local deployment state files if they exist
    rm -f ./deployment_state.env
    rm -f ./datazone_vars.env
    
    log_success "Temporary files cleaned up"
}

# Verify cleanup completion
verify_cleanup() {
    log_info "Verifying cleanup completion..."
    
    local errors=0
    
    # Check S3 bucket
    if [ -n "${DATA_LAKE_BUCKET:-}" ]; then
        if aws s3api head-bucket --bucket ${DATA_LAKE_BUCKET} 2>/dev/null; then
            log_error "S3 bucket still exists: ${DATA_LAKE_BUCKET}"
            errors=$((errors + 1))
        fi
    fi
    
    # Check Glue database
    if [ -n "${GLUE_DATABASE:-}" ]; then
        if aws glue get-database --name ${GLUE_DATABASE} 2>/dev/null; then
            log_error "Glue database still exists: ${GLUE_DATABASE}"
            errors=$((errors + 1))
        fi
    fi
    
    # Check IAM roles
    if aws iam get-role --role-name LakeFormationServiceRole 2>/dev/null; then
        log_error "IAM role still exists: LakeFormationServiceRole"
        errors=$((errors + 1))
    fi
    
    if aws iam get-role --role-name DataAnalystRole 2>/dev/null; then
        log_error "IAM role still exists: DataAnalystRole"
        errors=$((errors + 1))
    fi
    
    # Check Glue job
    if aws glue get-job --job-name CustomerDataETLWithLineage 2>/dev/null; then
        log_error "Glue job still exists: CustomerDataETLWithLineage"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        log_success "Cleanup verification passed - all resources removed"
    else
        log_warning "Cleanup verification found $errors remaining resources"
        log_warning "You may need to manually remove these resources"
    fi
}

# Display final cleanup summary
show_cleanup_summary() {
    log_info "================================================================"
    log_success "Data Lake Governance cleanup completed!"
    log_info "================================================================"
    log_info ""
    log_info "Resources removed:"
    log_info "✓ Amazon DataZone domain and projects"
    log_info "✓ Lake Formation permissions and filters"
    log_info "✓ AWS Glue database and tables"
    log_info "✓ AWS Glue ETL job"
    log_info "✓ S3 data lake bucket and all contents"
    log_info "✓ IAM roles and policies"
    log_info "✓ CloudWatch alarms and log groups"
    log_info "✓ SNS topics and subscriptions"
    log_info "✓ Temporary files and deployment state"
    log_info ""
    log_info "If you experience any issues or need to remove additional"
    log_info "resources manually, please check the AWS console."
    log_info ""
    log_success "Cleanup process completed successfully!"
}

# Main cleanup function
main() {
    log_info "Starting Data Lake Governance cleanup..."
    log_info "================================================================"
    
    # Get user confirmation
    confirm_destruction
    
    # Execute cleanup steps in reverse order of deployment
    load_deployment_state
    cleanup_datazone
    cleanup_lake_formation
    cleanup_glue
    cleanup_s3
    cleanup_cloudwatch
    cleanup_sns
    cleanup_iam
    cleanup_temp_files
    
    # Verify and summarize
    verify_cleanup
    show_cleanup_summary
}

# Handle script interruption
trap 'log_warning "Cleanup interrupted by user"; exit 1' INT TERM

# Execute main function
main "$@"