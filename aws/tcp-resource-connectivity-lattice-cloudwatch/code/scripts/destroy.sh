#!/bin/bash

# TCP Resource Connectivity with VPC Lattice and CloudWatch - Cleanup Script
# This script safely removes all resources created by the deployment script
# with proper error handling and confirmation prompts

set -euo pipefail

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging setup
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "${LOG_FILE}")
exec 2> >(tee -a "${LOG_FILE}" >&2)

# Global variables
FORCE_DELETE=false
DRY_RUN=false
STATE_FILE="deployment_state.json"

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
    echo -e "${BLUE}[CLEANUP]${NC} $1"
}

# Function to confirm destructive actions
confirm_deletion() {
    if [[ "${FORCE_DELETE}" == "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}⚠️  This will permanently delete all VPC Lattice resources and data!${NC}"
    echo -e "${YELLOW}⚠️  The following resources will be removed:${NC}"
    echo "   - VPC Lattice Service Network and Services"
    echo "   - RDS Database Instance (including all data)"
    echo "   - Target Groups and Listeners"
    echo "   - CloudWatch Dashboard and Alarms"
    echo "   - IAM Roles and Policies"
    echo
    
    read -p "Are you sure you want to proceed? (type 'DELETE' to confirm): " confirmation
    
    if [[ "${confirmation}" != "DELETE" ]]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
    
    print_status "Cleanup confirmed by user"
}

# Function to load deployment state
load_deployment_state() {
    print_header "Loading deployment state..."
    
    if [[ ! -f "${STATE_FILE}" ]]; then
        print_error "Deployment state file '${STATE_FILE}' not found"
        print_error "Please ensure you're running this script from the deployment directory"
        exit 1
    fi
    
    # Validate JSON format
    if ! jq empty "${STATE_FILE}" 2>/dev/null; then
        print_error "Invalid JSON in state file '${STATE_FILE}'"
        exit 1
    fi
    
    # Load variables from state file
    export DEPLOYMENT_ID=$(jq -r '.deployment_id // empty' "${STATE_FILE}")
    export AWS_REGION=$(jq -r '.region // empty' "${STATE_FILE}")
    export AWS_ACCOUNT_ID=$(jq -r '.account_id // empty' "${STATE_FILE}")
    export SERVICE_NETWORK_ID=$(jq -r '.service_network_id // empty' "${STATE_FILE}")
    export SERVICE_NETWORK_NAME=$(jq -r '.service_network_name // empty' "${STATE_FILE}")
    export DATABASE_SERVICE_ID=$(jq -r '.database_service_id // empty' "${STATE_FILE}")
    export DATABASE_SERVICE_NAME=$(jq -r '.database_service_name // empty' "${STATE_FILE}")
    export TARGET_GROUP_ID=$(jq -r '.target_group_id // empty' "${STATE_FILE}")
    export TARGET_GROUP_NAME=$(jq -r '.target_group_name // empty' "${STATE_FILE}")
    export LISTENER_ID=$(jq -r '.listener_id // empty' "${STATE_FILE}")
    export RDS_INSTANCE_ID=$(jq -r '.rds_instance_id // empty' "${STATE_FILE}")
    export RDS_ENDPOINT=$(jq -r '.rds_endpoint // empty' "${STATE_FILE}")
    export RDS_PORT=$(jq -r '.rds_port // empty' "${STATE_FILE}")
    export IAM_ROLE_NAME=$(jq -r '.iam_role_name // empty' "${STATE_FILE}")
    export VPC_ID=$(jq -r '.vpc_id // empty' "${STATE_FILE}")
    export CLOUDWATCH_DASHBOARD=$(jq -r '.cloudwatch_dashboard // empty' "${STATE_FILE}")
    export CLOUDWATCH_ALARM=$(jq -r '.cloudwatch_alarm // empty' "${STATE_FILE}")
    
    # Validate required fields
    if [[ -z "${DEPLOYMENT_ID}" ]]; then
        print_error "Missing deployment_id in state file"
        exit 1
    fi
    
    print_status "Loaded deployment state for ID: ${DEPLOYMENT_ID}"
    print_status "Region: ${AWS_REGION}"
    print_status "Account: ${AWS_ACCOUNT_ID}"
}

# Function to check AWS credentials and permissions
check_prerequisites() {
    print_header "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials not configured"
        exit 1
    fi
    
    # Verify we're in the correct account and region
    local current_account=$(aws sts get-caller-identity --query Account --output text)
    local current_region=$(aws configure get region || echo "")
    
    if [[ "${current_account}" != "${AWS_ACCOUNT_ID}" ]]; then
        print_warning "Current account (${current_account}) differs from deployment account (${AWS_ACCOUNT_ID})"
    fi
    
    if [[ -n "${current_region}" && "${current_region}" != "${AWS_REGION}" ]]; then
        print_warning "Current region (${current_region}) differs from deployment region (${AWS_REGION})"
        print_status "Using deployment region: ${AWS_REGION}"
        export AWS_DEFAULT_REGION="${AWS_REGION}"
    fi
    
    print_status "Prerequisites check completed"
}

# Function to check if resource exists
resource_exists() {
    local resource_type="$1"
    local resource_id="$2"
    
    case "${resource_type}" in
        "service-network")
            aws vpc-lattice get-service-network --service-network-identifier "${resource_id}" &> /dev/null
            ;;
        "service")
            aws vpc-lattice get-service --service-identifier "${resource_id}" &> /dev/null
            ;;
        "target-group")
            aws vpc-lattice get-target-group --target-group-identifier "${resource_id}" &> /dev/null
            ;;
        "rds")
            aws rds describe-db-instances --db-instance-identifier "${resource_id}" &> /dev/null
            ;;
        "iam-role")
            aws iam get-role --role-name "${resource_id}" &> /dev/null
            ;;
        "cloudwatch-dashboard")
            aws cloudwatch get-dashboard --dashboard-name "${resource_id}" &> /dev/null
            ;;
        "cloudwatch-alarm")
            aws cloudwatch describe-alarms --alarm-names "${resource_id}" &> /dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

# Function to safely delete resource with retries
safe_delete() {
    local resource_type="$1"
    local resource_id="$2"
    local delete_command="$3"
    local max_attempts=3
    local attempt=1
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "DRY RUN: Would delete ${resource_type}: ${resource_id}"
        return 0
    fi
    
    if ! resource_exists "${resource_type}" "${resource_id}"; then
        print_warning "${resource_type} ${resource_id} does not exist, skipping"
        return 0
    fi
    
    print_status "Deleting ${resource_type}: ${resource_id}"
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if eval "${delete_command}"; then
            print_status "Successfully deleted ${resource_type}: ${resource_id}"
            return 0
        else
            local exit_code=$?
            if [[ ${attempt} -eq ${max_attempts} ]]; then
                print_error "Failed to delete ${resource_type} ${resource_id} after ${max_attempts} attempts"
                return ${exit_code}
            fi
            print_warning "Attempt ${attempt}/${max_attempts} failed, retrying in 10 seconds..."
            sleep 10
            ((attempt++))
        fi
    done
}

# Function to wait for resource deletion
wait_for_deletion() {
    local resource_type="$1"
    local resource_id="$2"
    local max_attempts=30
    local attempt=1
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi
    
    print_status "Waiting for ${resource_type} ${resource_id} to be deleted..."
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        if ! resource_exists "${resource_type}" "${resource_id}"; then
            print_status "${resource_type} ${resource_id} has been deleted"
            return 0
        fi
        
        if [[ ${attempt} -eq ${max_attempts} ]]; then
            print_warning "${resource_type} ${resource_id} still exists after ${max_attempts} attempts"
            return 1
        fi
        
        sleep 10
        ((attempt++))
    done
}

# Function to remove VPC associations
remove_vpc_associations() {
    print_header "Removing VPC associations..."
    
    if [[ -z "${SERVICE_NETWORK_ID}" ]]; then
        print_warning "No service network ID found, skipping VPC association removal"
        return 0
    fi
    
    # List and delete VPC associations
    local vpc_associations
    vpc_associations=$(aws vpc-lattice list-service-network-vpc-associations \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --query 'items[].arn' --output text 2>/dev/null || echo "")
    
    if [[ -n "${vpc_associations}" ]]; then
        for association in ${vpc_associations}; do
            safe_delete "vpc-association" "${association}" \
                "aws vpc-lattice delete-service-network-vpc-association --service-network-vpc-association-identifier '${association}'"
        done
    else
        print_status "No VPC associations found"
    fi
}

# Function to remove service associations
remove_service_associations() {
    print_header "Removing service associations..."
    
    if [[ -z "${SERVICE_NETWORK_ID}" ]]; then
        print_warning "No service network ID found, skipping service association removal"
        return 0
    fi
    
    # List and delete service associations
    local service_associations
    service_associations=$(aws vpc-lattice list-service-network-service-associations \
        --service-network-identifier "${SERVICE_NETWORK_ID}" \
        --query 'items[].arn' --output text 2>/dev/null || echo "")
    
    if [[ -n "${service_associations}" ]]; then
        for association in ${service_associations}; do
            safe_delete "service-association" "${association}" \
                "aws vpc-lattice delete-service-network-service-association --service-network-service-association-identifier '${association}'"
        done
    else
        print_status "No service associations found"
    fi
}

# Function to remove VPC Lattice resources
remove_lattice_resources() {
    print_header "Removing VPC Lattice resources..."
    
    # Delete listener
    if [[ -n "${LISTENER_ID}" && -n "${DATABASE_SERVICE_ID}" ]]; then
        safe_delete "listener" "${LISTENER_ID}" \
            "aws vpc-lattice delete-listener --service-identifier '${DATABASE_SERVICE_ID}' --listener-identifier '${LISTENER_ID}'"
    fi
    
    # Delete service
    if [[ -n "${DATABASE_SERVICE_ID}" ]]; then
        safe_delete "service" "${DATABASE_SERVICE_ID}" \
            "aws vpc-lattice delete-service --service-identifier '${DATABASE_SERVICE_ID}'"
        
        # Wait for service deletion
        wait_for_deletion "service" "${DATABASE_SERVICE_ID}"
    fi
    
    # Deregister targets and delete target group
    if [[ -n "${TARGET_GROUP_ID}" && -n "${RDS_ENDPOINT}" && -n "${RDS_PORT}" ]]; then
        print_status "Deregistering targets from target group..."
        if [[ "${DRY_RUN}" != "true" ]]; then
            aws vpc-lattice deregister-targets \
                --target-group-identifier "${TARGET_GROUP_ID}" \
                --targets '[{"id": "'${RDS_ENDPOINT}'", "port": '${RDS_PORT}'}]' 2>/dev/null || true
        fi
        
        safe_delete "target-group" "${TARGET_GROUP_ID}" \
            "aws vpc-lattice delete-target-group --target-group-identifier '${TARGET_GROUP_ID}'"
    fi
    
    # Delete service network
    if [[ -n "${SERVICE_NETWORK_ID}" ]]; then
        safe_delete "service-network" "${SERVICE_NETWORK_ID}" \
            "aws vpc-lattice delete-service-network --service-network-identifier '${SERVICE_NETWORK_ID}'"
        
        # Wait for service network deletion
        wait_for_deletion "service-network" "${SERVICE_NETWORK_ID}"
    fi
}

# Function to remove RDS resources
remove_rds_resources() {
    print_header "Removing RDS resources..."
    
    # Delete RDS instance
    if [[ -n "${RDS_INSTANCE_ID}" ]]; then
        if resource_exists "rds" "${RDS_INSTANCE_ID}"; then
            print_status "Deleting RDS instance: ${RDS_INSTANCE_ID} (this may take 5-10 minutes)"
            
            if [[ "${DRY_RUN}" != "true" ]]; then
                aws rds delete-db-instance \
                    --db-instance-identifier "${RDS_INSTANCE_ID}" \
                    --skip-final-snapshot
                
                print_status "Waiting for RDS instance deletion..."
                aws rds wait db-instance-deleted --db-instance-identifier "${RDS_INSTANCE_ID}"
                print_status "RDS instance deleted successfully"
            else
                print_status "DRY RUN: Would delete RDS instance: ${RDS_INSTANCE_ID}"
            fi
        else
            print_warning "RDS instance ${RDS_INSTANCE_ID} does not exist, skipping"
        fi
        
        # Delete DB subnet group
        local subnet_group_name="${RDS_INSTANCE_ID}-subnet-group"
        print_status "Deleting DB subnet group: ${subnet_group_name}"
        
        if [[ "${DRY_RUN}" != "true" ]]; then
            aws rds delete-db-subnet-group \
                --db-subnet-group-name "${subnet_group_name}" 2>/dev/null || true
        else
            print_status "DRY RUN: Would delete DB subnet group: ${subnet_group_name}"
        fi
    fi
}

# Function to remove CloudWatch resources
remove_cloudwatch_resources() {
    print_header "Removing CloudWatch resources..."
    
    # Delete CloudWatch dashboard
    if [[ -n "${CLOUDWATCH_DASHBOARD}" ]]; then
        safe_delete "cloudwatch-dashboard" "${CLOUDWATCH_DASHBOARD}" \
            "aws cloudwatch delete-dashboards --dashboard-names '${CLOUDWATCH_DASHBOARD}'"
    fi
    
    # Delete CloudWatch alarm
    if [[ -n "${CLOUDWATCH_ALARM}" ]]; then
        safe_delete "cloudwatch-alarm" "${CLOUDWATCH_ALARM}" \
            "aws cloudwatch delete-alarms --alarm-names '${CLOUDWATCH_ALARM}'"
    fi
}

# Function to remove IAM resources
remove_iam_resources() {
    print_header "Removing IAM resources..."
    
    if [[ -n "${IAM_ROLE_NAME}" ]]; then
        # Detach policies first
        print_status "Detaching policies from IAM role: ${IAM_ROLE_NAME}"
        if [[ "${DRY_RUN}" != "true" ]]; then
            local attached_policies
            attached_policies=$(aws iam list-attached-role-policies \
                --role-name "${IAM_ROLE_NAME}" \
                --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            
            for policy_arn in ${attached_policies}; do
                aws iam detach-role-policy \
                    --role-name "${IAM_ROLE_NAME}" \
                    --policy-arn "${policy_arn}" 2>/dev/null || true
            done
        fi
        
        safe_delete "iam-role" "${IAM_ROLE_NAME}" \
            "aws iam delete-role --role-name '${IAM_ROLE_NAME}'"
    fi
}

# Function to cleanup deployment state
cleanup_deployment_state() {
    print_header "Cleaning up deployment state..."
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        print_status "DRY RUN: Would remove deployment state files"
        return 0
    fi
    
    # Update state file to mark as deleted
    if [[ -f "${STATE_FILE}" ]]; then
        jq '.deployment_status = "DELETED" | .deleted_at = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"' \
            "${STATE_FILE}" > "${STATE_FILE}.deleted" 2>/dev/null || true
        
        print_status "Deployment state saved to ${STATE_FILE}.deleted"
    fi
    
    # List files that will remain
    print_status "Cleanup completed. Remaining files:"
    ls -la *.log *.json 2>/dev/null || true
}

# Function to display cleanup summary
display_cleanup_summary() {
    print_header "Cleanup Summary"
    
    if [[ "${DRY_RUN}" == "true" ]]; then
        cat << EOF

🔍 DRY RUN SUMMARY - No resources were actually deleted

📋 Resources that would be removed:
   - Deployment ID: ${DEPLOYMENT_ID}
   - Region: ${AWS_REGION}

🏗️ Infrastructure that would be deleted:
   - Service Network: ${SERVICE_NETWORK_NAME} (${SERVICE_NETWORK_ID})
   - Database Service: ${DATABASE_SERVICE_NAME} (${DATABASE_SERVICE_ID})
   - RDS Instance: ${RDS_INSTANCE_ID}
   - Target Group: ${TARGET_GROUP_NAME} (${TARGET_GROUP_ID})
   - CloudWatch Dashboard: ${CLOUDWATCH_DASHBOARD}
   - CloudWatch Alarm: ${CLOUDWATCH_ALARM}
   - IAM Role: ${IAM_ROLE_NAME}

To actually delete these resources, run: $0 --force

EOF
    else
        cat << EOF

🎉 Cleanup completed successfully!

📋 Cleanup Details:
   - Deployment ID: ${DEPLOYMENT_ID}
   - Region: ${AWS_REGION}
   - Cleanup completed at: $(date)

🗑️ Resources Removed:
   ✅ VPC Lattice Service Network and Services
   ✅ RDS Database Instance
   ✅ Target Groups and Listeners
   ✅ CloudWatch Dashboard and Alarms
   ✅ IAM Roles and Policies

📁 Log File: ${LOG_FILE}
📁 State File: ${STATE_FILE}.deleted

💰 Cost Impact:
   All billable resources have been removed. You should see charges stop within 24 hours.

EOF
    fi
}

# Function to handle errors during cleanup
handle_cleanup_error() {
    print_error "Cleanup encountered an error. Some resources may not have been deleted."
    print_error "Please check the log file: ${LOG_FILE}"
    print_error "You may need to manually delete remaining resources in the AWS Console."
    
    # List any remaining resources
    print_status "Checking for remaining resources..."
    
    if [[ -n "${SERVICE_NETWORK_ID}" ]] && resource_exists "service-network" "${SERVICE_NETWORK_ID}"; then
        print_warning "Service Network still exists: ${SERVICE_NETWORK_ID}"
    fi
    
    if [[ -n "${RDS_INSTANCE_ID}" ]] && resource_exists "rds" "${RDS_INSTANCE_ID}"; then
        print_warning "RDS Instance still exists: ${RDS_INSTANCE_ID}"
    fi
    
    if [[ -n "${IAM_ROLE_NAME}" ]] && resource_exists "iam-role" "${IAM_ROLE_NAME}"; then
        print_warning "IAM Role still exists: ${IAM_ROLE_NAME}"
    fi
    
    exit 1
}

# Main cleanup function
main() {
    print_header "Starting VPC Lattice TCP Resource Connectivity Cleanup"
    print_status "Timestamp: $(date)"
    print_status "Log file: ${LOG_FILE}"
    
    # Set up error handling
    trap handle_cleanup_error ERR
    
    # Execute cleanup steps
    load_deployment_state
    check_prerequisites
    confirm_deletion
    
    print_header "Beginning resource cleanup..."
    
    remove_vpc_associations
    remove_service_associations
    remove_lattice_resources
    remove_rds_resources
    remove_cloudwatch_resources
    remove_iam_resources
    cleanup_deployment_state
    
    display_cleanup_summary
    
    if [[ "${DRY_RUN}" != "true" ]]; then
        print_status "🎉 Cleanup completed successfully!"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            cat << EOF
VPC Lattice TCP Resource Connectivity Cleanup Script

This script safely removes all resources created by the deployment script.

Usage: $0 [OPTIONS]

Options:
    --help, -h          Show this help message
    --force             Skip confirmation prompts (use with caution)
    --dry-run           Show what would be deleted without making changes
    --state-file FILE   Specify custom state file (default: deployment_state.json)
    --debug             Enable debug output

Safety Features:
    - Confirmation prompts for destructive actions
    - Resource existence checking before deletion
    - Retry logic for transient failures
    - Comprehensive logging of all actions

Examples:
    $0                      # Interactive cleanup with confirmations
    $0 --force              # Automated cleanup without prompts
    $0 --dry-run            # Preview what would be deleted
    $0 --state-file my.json # Use custom state file

EOF
            exit 0
            ;;
        --force)
            FORCE_DELETE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            print_status "DRY RUN MODE - No resources will be deleted"
            shift
            ;;
        --state-file)
            STATE_FILE="$2"
            shift 2
            ;;
        --debug)
            set -x
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            print_error "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute main function
main "$@"