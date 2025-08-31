#!/bin/bash

#
# Deploy Script for AWS Parameter Store Configuration Management
# 
# This script deploys the infrastructure and configuration described in the
# "Simple Configuration Management with Parameter Store and CloudShell" recipe.
#
# Prerequisites:
# - AWS CLI installed and configured
# - IAM permissions for Systems Manager Parameter Store operations
# - CloudShell environment or local bash environment
#

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
DRY_RUN=false

# Color codes for output
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
    
    case $level in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handler
error_handler() {
    log "ERROR" "Deployment failed at line $1. Check $LOG_FILE for details."
    exit 1
}

trap 'error_handler $LINENO' ERR

# Help function
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy AWS Parameter Store configuration management infrastructure.

OPTIONS:
    -h, --help          Show this help message
    -d, --dry-run       Show what would be deployed without actually doing it
    -a, --app-name      Specify application name (default: auto-generated)
    -r, --region        Specify AWS region (default: current configured region)

EXAMPLES:
    $0                          # Deploy with auto-generated app name
    $0 --app-name myapp         # Deploy with specific app name
    $0 --dry-run                # Show deployment plan without executing
    $0 --region us-west-2       # Deploy to specific region

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -a|--app-name)
            CUSTOM_APP_NAME="$2"
            shift 2
            ;;
        -r|--region)
            CUSTOM_REGION="$2"
            shift 2
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Initialize logging
echo "Deployment started at $(date)" > "$LOG_FILE"
log "INFO" "Starting AWS Parameter Store configuration management deployment"

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log "ERROR" "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        log "ERROR" "AWS CLI is not configured or credentials are invalid."
        exit 1
    fi
    
    # Check required permissions by attempting to describe parameters
    if ! aws ssm describe-parameters --max-items 1 &> /dev/null; then
        log "ERROR" "Insufficient permissions for Systems Manager Parameter Store operations."
        log "ERROR" "Required permissions: ssm:PutParameter, ssm:GetParameter, ssm:GetParameters, ssm:GetParametersByPath, ssm:DescribeParameters, ssm:DeleteParameter"
        exit 1
    fi
    
    log "SUCCESS" "Prerequisites check passed"
}

# Setup environment variables
setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # Set AWS region
    if [[ -n "${CUSTOM_REGION:-}" ]]; then
        export AWS_REGION="$CUSTOM_REGION"
        log "INFO" "Using custom region: $AWS_REGION"
    else
        export AWS_REGION=$(aws configure get region)
        if [[ -z "$AWS_REGION" ]]; then
            export AWS_REGION="us-east-1"
            log "WARN" "No region configured, defaulting to us-east-1"
        fi
    fi
    
    # Get AWS Account ID
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate or use custom app name
    if [[ -n "${CUSTOM_APP_NAME:-}" ]]; then
        export APP_NAME="$CUSTOM_APP_NAME"
        log "INFO" "Using custom app name: $APP_NAME"
    else
        # Generate random suffix for unique naming
        RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
            --exclude-punctuation --exclude-uppercase \
            --password-length 6 --require-each-included-type \
            --output text --query RandomPassword 2>/dev/null || echo "$(date +%s | tail -c 6)")
        export APP_NAME="myapp-${RANDOM_SUFFIX}"
        log "INFO" "Generated app name: $APP_NAME"
    fi
    
    # Set parameter prefix
    export PARAM_PREFIX="/${APP_NAME}"
    
    log "SUCCESS" "Environment configured:"
    log "INFO" "  - AWS Region: $AWS_REGION"
    log "INFO" "  - AWS Account: $AWS_ACCOUNT_ID"
    log "INFO" "  - App Name: $APP_NAME"
    log "INFO" "  - Parameter Prefix: $PARAM_PREFIX"
}

# Create standard configuration parameters
create_standard_parameters() {
    log "INFO" "Creating standard configuration parameters..."
    
    local params=(
        "${PARAM_PREFIX}/database/url|postgresql://db.example.com:5432/myapp|Database connection URL for ${APP_NAME}"
        "${PARAM_PREFIX}/config/environment|development|Application environment setting"
        "${PARAM_PREFIX}/features/debug-mode|true|Debug mode feature flag"
    )
    
    for param_config in "${params[@]}"; do
        IFS='|' read -r name value description <<< "$param_config"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] Would create parameter: $name"
            continue
        fi
        
        # Check if parameter already exists
        if aws ssm get-parameter --name "$name" &> /dev/null; then
            log "WARN" "Parameter $name already exists, skipping creation"
            continue
        fi
        
        aws ssm put-parameter \
            --name "$name" \
            --value "$value" \
            --type "String" \
            --description "$description" \
            --tags "Key=Application,Value=${APP_NAME}" "Key=ManagedBy,Value=recipe-deploy-script" \
            &>> "$LOG_FILE"
        
        log "SUCCESS" "Created standard parameter: $name"
    done
}

# Create secure string parameters
create_secure_parameters() {
    log "INFO" "Creating secure string parameters..."
    
    local secure_params=(
        "${PARAM_PREFIX}/api/third-party-key|api-key-12345-secret-value|Third-party API key for ${APP_NAME}"
        "${PARAM_PREFIX}/database/password|super-secure-password-123|Database password for ${APP_NAME}"
    )
    
    for param_config in "${secure_params[@]}"; do
        IFS='|' read -r name value description <<< "$param_config"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] Would create secure parameter: $name"
            continue
        fi
        
        # Check if parameter already exists
        if aws ssm get-parameter --name "$name" &> /dev/null; then
            log "WARN" "Parameter $name already exists, skipping creation"
            continue
        fi
        
        aws ssm put-parameter \
            --name "$name" \
            --value "$value" \
            --type "SecureString" \
            --description "$description" \
            --key-id "alias/aws/ssm" \
            --tags "Key=Application,Value=${APP_NAME}" "Key=ManagedBy,Value=recipe-deploy-script" \
            &>> "$LOG_FILE"
        
        log "SUCCESS" "Created secure parameter: $name"
    done
}

# Create string list parameters
create_stringlist_parameters() {
    log "INFO" "Creating string list parameters..."
    
    local list_params=(
        "${PARAM_PREFIX}/api/allowed-origins|https://app.example.com,https://admin.example.com,https://mobile.example.com|CORS allowed origins for ${APP_NAME}"
        "${PARAM_PREFIX}/deployment/regions|us-east-1,us-west-2,eu-west-1|Supported deployment regions"
    )
    
    for param_config in "${list_params[@]}"; do
        IFS='|' read -r name value description <<< "$param_config"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log "INFO" "[DRY-RUN] Would create string list parameter: $name"
            continue
        fi
        
        # Check if parameter already exists
        if aws ssm get-parameter --name "$name" &> /dev/null; then
            log "WARN" "Parameter $name already exists, skipping creation"
            continue
        fi
        
        aws ssm put-parameter \
            --name "$name" \
            --value "$value" \
            --type "StringList" \
            --description "$description" \
            --tags "Key=Application,Value=${APP_NAME}" "Key=ManagedBy,Value=recipe-deploy-script" \
            &>> "$LOG_FILE"
        
        log "SUCCESS" "Created string list parameter: $name"
    done
}

# Create configuration management script
create_config_script() {
    log "INFO" "Creating configuration management script..."
    
    local script_path="${SCRIPT_DIR}/config-manager.sh"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Would create configuration management script at: $script_path"
        return
    fi
    
    cat > "$script_path" << 'EOF'
#!/bin/bash

#
# Configuration Management Script for AWS Parameter Store
# 
# This script provides utilities for managing configuration parameters
# stored in AWS Systems Manager Parameter Store.
#

PARAM_PREFIX="${1:-/myapp-default}"
ACTION="${2:-get}"

case $ACTION in
    "get")
        echo "=== Configuration for ${PARAM_PREFIX} ==="
        aws ssm get-parameters-by-path \
            --path "${PARAM_PREFIX}" \
            --recursive \
            --with-decryption \
            --query 'Parameters[].[Name,Value,Type]' \
            --output table
        ;;
    "backup")
        echo "=== Backing up configuration for ${PARAM_PREFIX} ==="
        backup_file="config-backup-$(date +%Y%m%d-%H%M%S).json"
        aws ssm get-parameters-by-path \
            --path "${PARAM_PREFIX}" \
            --recursive \
            --with-decryption \
            --output json > "$backup_file"
        echo "Configuration backed up to: $backup_file"
        ;;
    "count")
        COUNT=$(aws ssm get-parameters-by-path \
            --path "${PARAM_PREFIX}" \
            --recursive \
            --query 'length(Parameters)' \
            --output text)
        echo "Total parameters under ${PARAM_PREFIX}: ${COUNT}"
        ;;
    "export")
        echo "=== Exporting configuration as environment variables ==="
        aws ssm get-parameters-by-path \
            --path "${PARAM_PREFIX}" \
            --recursive \
            --with-decryption \
            --query 'Parameters[].[Name,Value]' \
            --output text | \
            while read name value; do
                env_name=$(echo "${name}" | sed "s|${PARAM_PREFIX}/||" | \
                    tr '/' '_' | tr '[:lower:]' '[:upper:]')
                echo "export ${env_name}='${value}'"
            done
        ;;
    *)
        echo "Usage: $0 <param-prefix> [get|backup|count|export]"
        echo ""
        echo "Commands:"
        echo "  get     - Display all parameters in table format"
        echo "  backup  - Create JSON backup of all parameters"
        echo "  count   - Show total number of parameters"
        echo "  export  - Generate export statements for environment variables"
        echo ""
        echo "Examples:"
        echo "  $0 /myapp get"
        echo "  $0 /myapp backup"
        echo "  $0 /myapp count"
        echo "  eval \$($0 /myapp export)  # Load parameters as env vars"
        exit 1
        ;;
esac
EOF
    
    chmod +x "$script_path"
    log "SUCCESS" "Created configuration management script: $script_path"
}

# Validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "[DRY-RUN] Skipping validation in dry-run mode"
        return
    fi
    
    # Count created parameters
    local param_count=$(aws ssm get-parameters-by-path \
        --path "$PARAM_PREFIX" \
        --recursive \
        --query 'length(Parameters)' \
        --output text 2>/dev/null || echo "0")
    
    if [[ "$param_count" -gt 0 ]]; then
        log "SUCCESS" "Deployment validation passed: $param_count parameters created"
        
        # Display created parameters
        log "INFO" "Created parameters:"
        aws ssm describe-parameters \
            --parameter-filters "Key=Name,Option=BeginsWith,Values=${PARAM_PREFIX}" \
            --query 'Parameters[].[Name,Type,Description]' \
            --output table
    else
        log "ERROR" "Deployment validation failed: No parameters found"
        exit 1
    fi
}

# Save deployment state
save_deployment_state() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return
    fi
    
    local state_file="${SCRIPT_DIR}/deployment-state.json"
    
    cat > "$state_file" << EOF
{
    "deployment_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "aws_region": "$AWS_REGION",
    "aws_account_id": "$AWS_ACCOUNT_ID",
    "app_name": "$APP_NAME",
    "param_prefix": "$PARAM_PREFIX",
    "script_version": "1.0"
}
EOF
    
    log "SUCCESS" "Deployment state saved to: $state_file"
}

# Main deployment function
main() {
    log "INFO" "================================================"
    log "INFO" "AWS Parameter Store Configuration Management"
    log "INFO" "Deployment Script v1.0"
    log "INFO" "================================================"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "INFO" "Running in DRY-RUN mode - no resources will be created"
    fi
    
    check_prerequisites
    setup_environment
    
    create_standard_parameters
    create_secure_parameters
    create_stringlist_parameters
    create_config_script
    
    validate_deployment
    save_deployment_state
    
    log "SUCCESS" "================================================"
    log "SUCCESS" "Deployment completed successfully!"
    log "SUCCESS" "================================================"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        echo ""
        log "INFO" "Next steps:"
        log "INFO" "1. Test parameter retrieval:"
        log "INFO" "   ${SCRIPT_DIR}/config-manager.sh $PARAM_PREFIX get"
        log "INFO" ""
        log "INFO" "2. Create a configuration backup:"
        log "INFO" "   ${SCRIPT_DIR}/config-manager.sh $PARAM_PREFIX backup"
        log "INFO" ""
        log "INFO" "3. When finished, clean up resources:"
        log "INFO" "   ${SCRIPT_DIR}/destroy.sh"
        echo ""
        log "INFO" "Application Name: $APP_NAME"
        log "INFO" "Parameter Prefix: $PARAM_PREFIX"
        log "INFO" "AWS Region: $AWS_REGION"
    fi
}

# Run main function
main "$@"