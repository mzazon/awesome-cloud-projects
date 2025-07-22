#!/bin/bash
set -e

# Infrastructure Automation with AWS Proton and CDK - Cleanup Script
# This script removes all AWS Proton infrastructure created by deploy.sh

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check AWS CLI authentication
check_aws_auth() {
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS CLI not configured or authentication failed"
        error "Please run 'aws configure' or set up AWS credentials"
        exit 1
    fi
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    # Try to load from saved file
    if [[ -f "../temp_env_vars.sh" ]]; then
        source ../temp_env_vars.sh
        log "Environment variables loaded from temp_env_vars.sh"
    else
        warn "temp_env_vars.sh not found, attempting to discover resources..."
        
        # Try to discover resources
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        export AWS_REGION=$(aws configure get region)
        
        if [[ -z "$AWS_REGION" ]]; then
            error "AWS region not configured"
            error "Please set AWS region with 'aws configure set region <region>'"
            exit 1
        fi
        
        # Try to find existing resources
        discover_resources
    fi
    
    info "Environment variables:"
    info "  AWS Account ID: $AWS_ACCOUNT_ID"
    info "  AWS Region: $AWS_REGION"
    info "  Random Suffix: $RANDOM_SUFFIX"
    info "  Proton Service Role: $PROTON_SERVICE_ROLE_NAME"
    info "  Template Bucket: $TEMPLATE_BUCKET"
}

# Function to discover existing resources
discover_resources() {
    log "Discovering existing resources..."
    
    # Find Proton service roles
    local proton_roles=$(aws iam list-roles --query 'Roles[?starts_with(RoleName, `ProtonServiceRole-`)].RoleName' --output text)
    if [[ -n "$proton_roles" ]]; then
        export PROTON_SERVICE_ROLE_NAME=$(echo "$proton_roles" | head -n1)
        export RANDOM_SUFFIX=$(echo "$PROTON_SERVICE_ROLE_NAME" | sed 's/ProtonServiceRole-//')
        log "Found Proton service role: $PROTON_SERVICE_ROLE_NAME"
    fi
    
    # Find template buckets
    local template_buckets=$(aws s3 ls | grep "proton-templates-" | awk '{print $3}')
    if [[ -n "$template_buckets" ]]; then
        export TEMPLATE_BUCKET=$(echo "$template_buckets" | head -n1)
        log "Found template bucket: $TEMPLATE_BUCKET"
        
        # Extract suffix from bucket name if not already set
        if [[ -z "$RANDOM_SUFFIX" ]]; then
            export RANDOM_SUFFIX=$(echo "$TEMPLATE_BUCKET" | sed 's/proton-templates-//')
            export PROTON_SERVICE_ROLE_NAME="ProtonServiceRole-$RANDOM_SUFFIX"
        fi
    fi
    
    if [[ -z "$PROTON_SERVICE_ROLE_NAME" || -z "$TEMPLATE_BUCKET" ]]; then
        warn "Could not discover all resources. Some cleanup steps may be skipped."
    fi
}

# Function to confirm destruction
confirm_destruction() {
    warn "This will permanently delete all AWS Proton infrastructure created by this recipe."
    warn "The following resources will be removed:"
    warn "  - Service instances and services"
    warn "  - Environments"
    warn "  - Service and environment templates"
    warn "  - S3 bucket and contents"
    warn "  - IAM roles and policies"
    warn "  - All associated infrastructure (VPC, ECS, Load Balancers, etc.)"
    warn ""
    warn "This action cannot be undone!"
    
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm
    if [[ "$confirm" != "yes" ]]; then
        log "Destruction cancelled by user"
        exit 0
    fi
    
    log "Destruction confirmed, proceeding with cleanup..."
}

# Function to delete service instances
delete_service_instances() {
    log "Deleting service instances..."
    
    # List all service instances
    local service_instances=$(aws proton list-service-instances \
        --query 'serviceInstances[].{service:serviceName,instance:name}' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$service_instances" ]]; then
        while IFS=$'\t' read -r service_name instance_name; do
            if [[ -n "$service_name" && -n "$instance_name" ]]; then
                log "Deleting service instance: $service_name/$instance_name"
                
                # Delete service instance
                aws proton delete-service-instance \
                    --service-name "$service_name" \
                    --name "$instance_name" 2>/dev/null || warn "Failed to delete service instance $service_name/$instance_name"
                
                # Wait for deletion
                log "Waiting for service instance $service_name/$instance_name to be deleted..."
                aws proton wait service-instance-deleted \
                    --service-name "$service_name" \
                    --name "$instance_name" 2>/dev/null || warn "Wait failed for service instance $service_name/$instance_name"
            fi
        done <<< "$service_instances"
        
        log "Service instances deleted"
    else
        warn "No service instances found"
    fi
}

# Function to delete services
delete_services() {
    log "Deleting services..."
    
    # List all services
    local services=$(aws proton list-services \
        --query 'services[].name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$services" ]]; then
        for service_name in $services; do
            if [[ -n "$service_name" ]]; then
                log "Deleting service: $service_name"
                
                # Delete service
                aws proton delete-service \
                    --name "$service_name" 2>/dev/null || warn "Failed to delete service $service_name"
            fi
        done
        
        log "Services deleted"
    else
        warn "No services found"
    fi
}

# Function to delete environments
delete_environments() {
    log "Deleting environments..."
    
    # List all environments
    local environments=$(aws proton list-environments \
        --query 'environments[].name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$environments" ]]; then
        for env_name in $environments; do
            if [[ -n "$env_name" ]]; then
                log "Deleting environment: $env_name"
                
                # Delete environment
                aws proton delete-environment \
                    --name "$env_name" 2>/dev/null || warn "Failed to delete environment $env_name"
                
                # Wait for deletion
                log "Waiting for environment $env_name to be deleted..."
                aws proton wait environment-deleted \
                    --name "$env_name" 2>/dev/null || warn "Wait failed for environment $env_name"
            fi
        done
        
        log "Environments deleted"
    else
        warn "No environments found"
    fi
}

# Function to delete service template versions and templates
delete_service_templates() {
    log "Deleting service templates..."
    
    # List all service templates
    local service_templates=$(aws proton list-service-templates \
        --query 'templates[].name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$service_templates" ]]; then
        for template_name in $service_templates; do
            if [[ -n "$template_name" ]]; then
                log "Deleting service template: $template_name"
                
                # List all versions of the template
                local versions=$(aws proton list-service-template-versions \
                    --template-name "$template_name" \
                    --query 'templateVersions[].[majorVersion,minorVersion]' \
                    --output text 2>/dev/null || echo "")
                
                # Delete all versions
                while IFS=$'\t' read -r major_version minor_version; do
                    if [[ -n "$major_version" && -n "$minor_version" ]]; then
                        log "Deleting service template version: $template_name v$major_version.$minor_version"
                        
                        aws proton delete-service-template-version \
                            --template-name "$template_name" \
                            --major-version "$major_version" \
                            --minor-version "$minor_version" 2>/dev/null || warn "Failed to delete service template version $template_name v$major_version.$minor_version"
                    fi
                done <<< "$versions"
                
                # Delete the template
                aws proton delete-service-template \
                    --name "$template_name" 2>/dev/null || warn "Failed to delete service template $template_name"
            fi
        done
        
        log "Service templates deleted"
    else
        warn "No service templates found"
    fi
}

# Function to delete environment template versions and templates
delete_environment_templates() {
    log "Deleting environment templates..."
    
    # List all environment templates
    local environment_templates=$(aws proton list-environment-templates \
        --query 'templates[].name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$environment_templates" ]]; then
        for template_name in $environment_templates; do
            if [[ -n "$template_name" ]]; then
                log "Deleting environment template: $template_name"
                
                # List all versions of the template
                local versions=$(aws proton list-environment-template-versions \
                    --template-name "$template_name" \
                    --query 'templateVersions[].[majorVersion,minorVersion]' \
                    --output text 2>/dev/null || echo "")
                
                # Delete all versions
                while IFS=$'\t' read -r major_version minor_version; do
                    if [[ -n "$major_version" && -n "$minor_version" ]]; then
                        log "Deleting environment template version: $template_name v$major_version.$minor_version"
                        
                        aws proton delete-environment-template-version \
                            --template-name "$template_name" \
                            --major-version "$major_version" \
                            --minor-version "$minor_version" 2>/dev/null || warn "Failed to delete environment template version $template_name v$major_version.$minor_version"
                    fi
                done <<< "$versions"
                
                # Delete the template
                aws proton delete-environment-template \
                    --name "$template_name" 2>/dev/null || warn "Failed to delete environment template $template_name"
            fi
        done
        
        log "Environment templates deleted"
    else
        warn "No environment templates found"
    fi
}

# Function to delete S3 bucket and contents
delete_s3_bucket() {
    log "Deleting S3 bucket and contents..."
    
    if [[ -n "$TEMPLATE_BUCKET" ]]; then
        # Check if bucket exists
        if aws s3api head-bucket --bucket "$TEMPLATE_BUCKET" 2>/dev/null; then
            log "Deleting all objects in bucket: $TEMPLATE_BUCKET"
            
            # Delete all objects including versions
            aws s3 rm s3://"$TEMPLATE_BUCKET" --recursive 2>/dev/null || warn "Failed to delete objects from bucket $TEMPLATE_BUCKET"
            
            # Delete all object versions if versioning is enabled
            aws s3api delete-objects \
                --bucket "$TEMPLATE_BUCKET" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$TEMPLATE_BUCKET" \
                    --query '{Objects: Versions[].{Key: Key, VersionId: VersionId}}' \
                    --output json 2>/dev/null | jq -c)" 2>/dev/null || warn "Failed to delete object versions"
            
            # Delete all delete markers
            aws s3api delete-objects \
                --bucket "$TEMPLATE_BUCKET" \
                --delete "$(aws s3api list-object-versions \
                    --bucket "$TEMPLATE_BUCKET" \
                    --query '{Objects: DeleteMarkers[].{Key: Key, VersionId: VersionId}}' \
                    --output json 2>/dev/null | jq -c)" 2>/dev/null || warn "Failed to delete delete markers"
            
            # Delete the bucket
            aws s3api delete-bucket --bucket "$TEMPLATE_BUCKET" 2>/dev/null || warn "Failed to delete bucket $TEMPLATE_BUCKET"
            
            log "S3 bucket deleted: $TEMPLATE_BUCKET"
        else
            warn "S3 bucket not found: $TEMPLATE_BUCKET"
        fi
    else
        warn "Template bucket name not available, skipping S3 cleanup"
    fi
}

# Function to delete IAM role
delete_iam_role() {
    log "Deleting IAM role..."
    
    if [[ -n "$PROTON_SERVICE_ROLE_NAME" ]]; then
        # Check if role exists
        if aws iam get-role --role-name "$PROTON_SERVICE_ROLE_NAME" 2>/dev/null; then
            log "Deleting IAM role: $PROTON_SERVICE_ROLE_NAME"
            
            # Detach all policies
            local attached_policies=$(aws iam list-attached-role-policies \
                --role-name "$PROTON_SERVICE_ROLE_NAME" \
                --query 'AttachedPolicies[].PolicyArn' \
                --output text 2>/dev/null || echo "")
            
            if [[ -n "$attached_policies" ]]; then
                for policy_arn in $attached_policies; do
                    if [[ -n "$policy_arn" ]]; then
                        log "Detaching policy: $policy_arn"
                        aws iam detach-role-policy \
                            --role-name "$PROTON_SERVICE_ROLE_NAME" \
                            --policy-arn "$policy_arn" 2>/dev/null || warn "Failed to detach policy $policy_arn"
                    fi
                done
            fi
            
            # Delete the role
            aws iam delete-role --role-name "$PROTON_SERVICE_ROLE_NAME" 2>/dev/null || warn "Failed to delete role $PROTON_SERVICE_ROLE_NAME"
            
            log "IAM role deleted: $PROTON_SERVICE_ROLE_NAME"
        else
            warn "IAM role not found: $PROTON_SERVICE_ROLE_NAME"
        fi
    else
        warn "Proton service role name not available, skipping IAM cleanup"
    fi
}

# Function to cleanup CDK bootstrap resources (optional)
cleanup_cdk_bootstrap() {
    log "CDK Bootstrap cleanup..."
    
    read -p "Do you want to remove CDK bootstrap resources? This will affect other CDK applications. (y/n): " cleanup_cdk
    if [[ "$cleanup_cdk" == "y" || "$cleanup_cdk" == "Y" ]]; then
        warn "Removing CDK bootstrap resources..."
        
        # Delete CDK bootstrap stack
        if aws cloudformation describe-stacks --stack-name "CDKToolkit" 2>/dev/null; then
            aws cloudformation delete-stack --stack-name "CDKToolkit" 2>/dev/null || warn "Failed to delete CDK bootstrap stack"
            log "CDK bootstrap stack deletion initiated"
        else
            warn "CDK bootstrap stack not found"
        fi
        
        # Delete CDK bootstrap S3 bucket
        local cdk_bucket=$(aws s3 ls | grep "cdk-" | grep "${AWS_ACCOUNT_ID}-${AWS_REGION}" | awk '{print $3}')
        if [[ -n "$cdk_bucket" ]]; then
            aws s3 rm s3://"$cdk_bucket" --recursive 2>/dev/null || warn "Failed to delete CDK bootstrap bucket contents"
            aws s3api delete-bucket --bucket "$cdk_bucket" 2>/dev/null || warn "Failed to delete CDK bootstrap bucket"
            log "CDK bootstrap bucket deleted: $cdk_bucket"
        fi
    else
        log "Skipping CDK bootstrap cleanup"
    fi
}

# Function to cleanup temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    # Remove temporary files
    rm -f ../temp_env_vars.sh
    rm -rf ../temp
    
    log "Temporary files cleaned up"
}

# Function to validate cleanup
validate_cleanup() {
    log "Validating cleanup..."
    
    local cleanup_errors=0
    
    # Check for remaining service instances
    local remaining_instances=$(aws proton list-service-instances \
        --query 'serviceInstances[].name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_instances" ]]; then
        error "Service instances still exist: $remaining_instances"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check for remaining services
    local remaining_services=$(aws proton list-services \
        --query 'services[].name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_services" ]]; then
        error "Services still exist: $remaining_services"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check for remaining environments
    local remaining_environments=$(aws proton list-environments \
        --query 'environments[].name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_environments" ]]; then
        error "Environments still exist: $remaining_environments"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check for remaining templates
    local remaining_service_templates=$(aws proton list-service-templates \
        --query 'templates[].name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_service_templates" ]]; then
        error "Service templates still exist: $remaining_service_templates"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    local remaining_environment_templates=$(aws proton list-environment-templates \
        --query 'templates[].name' \
        --output text 2>/dev/null || echo "")
    
    if [[ -n "$remaining_environment_templates" ]]; then
        error "Environment templates still exist: $remaining_environment_templates"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check for bucket
    if [[ -n "$TEMPLATE_BUCKET" ]] && aws s3api head-bucket --bucket "$TEMPLATE_BUCKET" 2>/dev/null; then
        error "S3 bucket still exists: $TEMPLATE_BUCKET"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    # Check for IAM role
    if [[ -n "$PROTON_SERVICE_ROLE_NAME" ]] && aws iam get-role --role-name "$PROTON_SERVICE_ROLE_NAME" 2>/dev/null; then
        error "IAM role still exists: $PROTON_SERVICE_ROLE_NAME"
        cleanup_errors=$((cleanup_errors + 1))
    fi
    
    if [[ $cleanup_errors -eq 0 ]]; then
        log "✅ Cleanup validation passed - all resources removed"
    else
        error "❌ Cleanup validation failed - $cleanup_errors resources still exist"
        error "You may need to manually remove remaining resources"
        return 1
    fi
}

# Function to display summary
display_summary() {
    log "Cleanup Summary:"
    info "✅ Service instances deleted"
    info "✅ Services deleted"
    info "✅ Environments deleted"
    info "✅ Service templates deleted"
    info "✅ Environment templates deleted"
    info "✅ S3 bucket and contents deleted"
    info "✅ IAM role deleted"
    info "✅ Temporary files cleaned up"
    info ""
    info "All AWS Proton infrastructure has been removed successfully!"
    info "Note: CDK bootstrap resources were preserved unless explicitly removed"
}

# Main execution
main() {
    log "Starting AWS Proton infrastructure cleanup..."
    
    # Check if running in scripts directory
    if [[ ! -f "destroy.sh" ]]; then
        error "This script must be run from the scripts directory"
        exit 1
    fi
    
    # Check prerequisites
    if ! command_exists aws; then
        error "AWS CLI is not installed"
        exit 1
    fi
    
    check_aws_auth
    
    # Load environment and confirm
    load_environment
    confirm_destruction
    
    # Execute cleanup steps in reverse order
    delete_service_instances
    delete_services
    delete_environments
    delete_service_templates
    delete_environment_templates
    delete_s3_bucket
    delete_iam_role
    cleanup_cdk_bootstrap
    cleanup_temp_files
    
    # Validate cleanup
    validate_cleanup
    
    display_summary
    
    log "Cleanup completed successfully! 🎉"
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"