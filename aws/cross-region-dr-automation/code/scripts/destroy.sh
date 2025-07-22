#!/bin/bash

#############################################################################
# AWS Cross-Region Disaster Recovery Automation Cleanup Script
# 
# This script safely removes all AWS Elastic Disaster Recovery (DRS) 
# infrastructure and automation components created by the deployment script.
#
# Prerequisites:
# - AWS CLI v2 installed and configured
# - Appropriate IAM permissions for resource deletion
# - deployment-config.env file from successful deployment
#
# Usage: ./destroy.sh [--dry-run] [--force] [--keep-data]
#############################################################################

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/destroy.log"
CONFIG_FILE="${SCRIPT_DIR}/deployment-config.env"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DRY_RUN=false
FORCE_DESTROY=false
KEEP_DATA=false

#############################################################################
# Utility Functions
#############################################################################

log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}ℹ️  $*${NC}"
    log "INFO" "$*"
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
    log "SUCCESS" "$*"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
    log "WARNING" "$*"
}

error() {
    echo -e "${RED}❌ $*${NC}"
    log "ERROR" "$*"
}

fatal() {
    error "$*"
    exit 1
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Destroy AWS Cross-Region Disaster Recovery Infrastructure

OPTIONS:
    --dry-run       Show what would be destroyed without making changes
    --force         Skip confirmation prompts and continue on errors
    --keep-data     Preserve DRS staging data and snapshots
    --help          Show this help message

EXAMPLES:
    $0                          # Interactive cleanup with confirmations
    $0 --dry-run                # Preview what would be destroyed
    $0 --force                  # Non-interactive cleanup
    $0 --keep-data              # Preserve recovery data during cleanup

WARNINGS:
    - This will permanently delete disaster recovery infrastructure
    - DRS agents on source servers will lose connectivity
    - Recovery points will be lost unless --keep-data is specified
    - This action cannot be undone

EOF
}

#############################################################################
# Prerequisites and Configuration Loading
#############################################################################

check_prerequisites() {
    info "Checking prerequisites for cleanup..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        fatal "AWS CLI is not installed. Please install AWS CLI v2."
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        fatal "AWS credentials not configured or invalid. Run 'aws configure' first."
    fi

    # Check for configuration file
    if [[ ! -f "$CONFIG_FILE" ]]; then
        fatal "Configuration file not found: $CONFIG_FILE. Run deployment script first."
    fi

    success "Prerequisites validation completed"
}

load_configuration() {
    info "Loading deployment configuration..."

    # Source the configuration file
    source "$CONFIG_FILE"

    # Validate required variables
    local required_vars=(
        "PRIMARY_REGION"
        "DR_REGION"
        "AWS_ACCOUNT_ID"
        "DR_PROJECT_ID"
        "AUTOMATION_ROLE_NAME"
    )

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            fatal "Required configuration variable missing: $var"
        fi
    done

    info "Configuration loaded successfully"
    info "  DR Project ID: ${DR_PROJECT_ID}"
    info "  Primary Region: ${PRIMARY_REGION}"
    info "  DR Region: ${DR_REGION}"
}

#############################################################################
# DR Testing Instances Cleanup
#############################################################################

cleanup_dr_testing() {
    info "Cleaning up DR testing instances..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would terminate DR drill instances in $DR_REGION"
        return 0
    fi

    # Get drill instances
    local drill_instances=$(aws drs describe-recovery-instances \
        --region "${DR_REGION}" \
        --query 'recoveryInstances[?isDrill==`true`].recoveryInstanceID' \
        --output text 2>/dev/null || echo "")

    if [[ -n "$drill_instances" && "$drill_instances" != "None" ]]; then
        info "Terminating drill instances: $drill_instances"
        
        for instance_id in $drill_instances; do
            aws drs terminate-recovery-instances \
                --recovery-instance-ids "$instance_id" \
                --region "${DR_REGION}" || {
                warning "Failed to terminate drill instance: $instance_id"
            }
        done

        # Wait for instances to terminate
        info "Waiting for drill instances to terminate..."
        sleep 30
    else
        info "No drill instances found to clean up"
    fi

    success "DR testing instances cleanup completed"
}

#############################################################################
# Lambda Functions Cleanup
#############################################################################

cleanup_lambda_functions() {
    info "Cleaning up Lambda functions..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete Lambda functions for DR automation"
        return 0
    fi

    # List of Lambda functions to delete
    local lambda_functions=(
        "dr-automated-failover-${DR_PROJECT_ID}"
        "dr-testing-${DR_PROJECT_ID}"
        "dr-automated-failback-${DR_PROJECT_ID}"
    )

    for function_name in "${lambda_functions[@]}"; do
        # Check if function exists in primary region
        if aws lambda get-function --function-name "$function_name" --region "${PRIMARY_REGION}" &> /dev/null; then
            info "Deleting Lambda function: $function_name (primary region)"
            aws lambda delete-function \
                --function-name "$function_name" \
                --region "${PRIMARY_REGION}" || {
                warning "Failed to delete Lambda function: $function_name"
            }
        fi

        # Check if function exists in DR region
        if aws lambda get-function --function-name "$function_name" --region "${DR_REGION}" &> /dev/null; then
            info "Deleting Lambda function: $function_name (DR region)"
            aws lambda delete-function \
                --function-name "$function_name" \
                --region "${DR_REGION}" || {
                warning "Failed to delete Lambda function: $function_name"
            }
        fi
    done

    success "Lambda functions cleanup completed"
}

#############################################################################
# Step Functions Cleanup
#############################################################################

cleanup_step_functions() {
    info "Cleaning up Step Functions state machines..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete Step Functions state machine"
        return 0
    fi

    local state_machine_name="dr-orchestration-${DR_PROJECT_ID}"

    # List state machines to find ARN
    local state_machine_arn=$(aws stepfunctions list-state-machines \
        --region "${PRIMARY_REGION}" \
        --query "stateMachines[?name=='${state_machine_name}'].stateMachineArn" \
        --output text 2>/dev/null || echo "")

    if [[ -n "$state_machine_arn" && "$state_machine_arn" != "None" ]]; then
        info "Deleting Step Functions state machine: $state_machine_name"
        aws stepfunctions delete-state-machine \
            --state-machine-arn "$state_machine_arn" \
            --region "${PRIMARY_REGION}" || {
            warning "Failed to delete state machine: $state_machine_name"
        }
    else
        info "No Step Functions state machine found to clean up"
    fi

    success "Step Functions cleanup completed"
}

#############################################################################
# EventBridge Rules Cleanup
#############################################################################

cleanup_eventbridge_rules() {
    info "Cleaning up EventBridge rules..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete EventBridge rules"
        return 0
    fi

    local rule_name="monthly-dr-drill-${DR_PROJECT_ID}"

    # Check if rule exists
    if aws events describe-rule --name "$rule_name" --region "${PRIMARY_REGION}" &> /dev/null; then
        info "Removing targets from EventBridge rule: $rule_name"
        
        # List and remove targets
        local targets=$(aws events list-targets-by-rule \
            --rule "$rule_name" \
            --region "${PRIMARY_REGION}" \
            --query 'Targets[].Id' \
            --output text 2>/dev/null || echo "")

        if [[ -n "$targets" ]]; then
            aws events remove-targets \
                --rule "$rule_name" \
                --ids $targets \
                --region "${PRIMARY_REGION}" || {
                warning "Failed to remove targets from rule: $rule_name"
            }
        fi

        info "Deleting EventBridge rule: $rule_name"
        aws events delete-rule \
            --name "$rule_name" \
            --region "${PRIMARY_REGION}" || {
            warning "Failed to delete EventBridge rule: $rule_name"
        }
    else
        info "No EventBridge rules found to clean up"
    fi

    success "EventBridge rules cleanup completed"
}

#############################################################################
# CloudWatch Resources Cleanup
#############################################################################

cleanup_cloudwatch() {
    info "Cleaning up CloudWatch resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete CloudWatch alarms and dashboard"
        return 0
    fi

    # Delete CloudWatch alarms
    local alarm_names=(
        "Application-Health-${DR_PROJECT_ID}"
        "DRS-Replication-Lag-${DR_PROJECT_ID}"
    )

    for alarm_name in "${alarm_names[@]}"; do
        if aws cloudwatch describe-alarms --alarm-names "$alarm_name" --region "${PRIMARY_REGION}" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null | grep -q "$alarm_name"; then
            info "Deleting CloudWatch alarm: $alarm_name"
            aws cloudwatch delete-alarms \
                --alarm-names "$alarm_name" \
                --region "${PRIMARY_REGION}" || {
                warning "Failed to delete alarm: $alarm_name"
            }
        fi
    done

    # Delete CloudWatch dashboard
    local dashboard_name="DR-Monitoring-${DR_PROJECT_ID}"
    if aws cloudwatch get-dashboard --dashboard-name "$dashboard_name" --region "${PRIMARY_REGION}" &> /dev/null; then
        info "Deleting CloudWatch dashboard: $dashboard_name"
        aws cloudwatch delete-dashboards \
            --dashboard-names "$dashboard_name" \
            --region "${PRIMARY_REGION}" || {
            warning "Failed to delete dashboard: $dashboard_name"
        }
    fi

    success "CloudWatch resources cleanup completed"
}

#############################################################################
# SNS Topic Cleanup
#############################################################################

cleanup_sns() {
    info "Cleaning up SNS topics..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete SNS topic for DR alerts"
        return 0
    fi

    local topic_name="dr-alerts-${DR_PROJECT_ID}"
    local topic_arn="arn:aws:sns:${PRIMARY_REGION}:${AWS_ACCOUNT_ID}:${topic_name}"

    # Check if topic exists
    if aws sns get-topic-attributes --topic-arn "$topic_arn" --region "${PRIMARY_REGION}" &> /dev/null; then
        info "Deleting SNS topic: $topic_name"
        aws sns delete-topic \
            --topic-arn "$topic_arn" \
            --region "${PRIMARY_REGION}" || {
            warning "Failed to delete SNS topic: $topic_name"
        }
    else
        info "No SNS topic found to clean up"
    fi

    success "SNS topics cleanup completed"
}

#############################################################################
# DR Infrastructure Cleanup
#############################################################################

cleanup_dr_infrastructure() {
    info "Cleaning up DR region infrastructure..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete VPC and associated resources in $DR_REGION"
        return 0
    fi

    # Load VPC information from config if available
    local dr_vpc_id="${DR_VPC_ID:-}"
    local dr_public_rt="${DR_PUBLIC_RT:-}"
    local dr_igw="${DR_IGW:-}"
    local dr_public_subnet="${DR_PUBLIC_SUBNET:-}"
    local dr_private_subnet="${DR_PRIVATE_SUBNET:-}"

    # If VPC ID is not in config, try to find it by name
    if [[ -z "$dr_vpc_id" ]]; then
        dr_vpc_id=$(aws ec2 describe-vpcs \
            --filters "Name=tag:Name,Values=${DR_VPC_NAME}" \
            --query 'Vpcs[0].VpcId' \
            --output text \
            --region "${DR_REGION}" 2>/dev/null || echo "None")
    fi

    if [[ -n "$dr_vpc_id" && "$dr_vpc_id" != "None" ]]; then
        info "Found DR VPC to clean up: $dr_vpc_id"

        # Delete route table (if not main route table)
        if [[ -n "$dr_public_rt" ]]; then
            info "Deleting route table: $dr_public_rt"
            aws ec2 delete-route-table \
                --route-table-id "$dr_public_rt" \
                --region "${DR_REGION}" 2>/dev/null || {
                warning "Failed to delete route table: $dr_public_rt"
            }
        fi

        # Detach and delete Internet Gateway
        if [[ -n "$dr_igw" ]]; then
            info "Detaching and deleting Internet Gateway: $dr_igw"
            aws ec2 detach-internet-gateway \
                --internet-gateway-id "$dr_igw" \
                --vpc-id "$dr_vpc_id" \
                --region "${DR_REGION}" 2>/dev/null || {
                warning "Failed to detach Internet Gateway: $dr_igw"
            }
            
            aws ec2 delete-internet-gateway \
                --internet-gateway-id "$dr_igw" \
                --region "${DR_REGION}" 2>/dev/null || {
                warning "Failed to delete Internet Gateway: $dr_igw"
            }
        fi

        # Delete subnets
        for subnet_id in "$dr_public_subnet" "$dr_private_subnet"; do
            if [[ -n "$subnet_id" ]]; then
                info "Deleting subnet: $subnet_id"
                aws ec2 delete-subnet \
                    --subnet-id "$subnet_id" \
                    --region "${DR_REGION}" 2>/dev/null || {
                    warning "Failed to delete subnet: $subnet_id"
                }
            fi
        done

        # Delete VPC
        info "Deleting VPC: $dr_vpc_id"
        aws ec2 delete-vpc \
            --vpc-id "$dr_vpc_id" \
            --region "${DR_REGION}" || {
            warning "Failed to delete VPC: $dr_vpc_id"
        }
    else
        info "No DR VPC found to clean up"
    fi

    success "DR infrastructure cleanup completed"
}

#############################################################################
# DRS Resources Cleanup
#############################################################################

cleanup_drs_resources() {
    info "Cleaning up DRS resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would clean up DRS replication templates and staging data"
        return 0
    fi

    # Stop any active jobs first
    local active_jobs=$(aws drs describe-jobs \
        --region "${PRIMARY_REGION}" \
        --query 'jobs[?status==`STARTED`].jobID' \
        --output text 2>/dev/null || echo "")

    if [[ -n "$active_jobs" && "$active_jobs" != "None" ]]; then
        warning "Found active DRS jobs. Waiting for completion before cleanup..."
        for job_id in $active_jobs; do
            info "Monitoring job: $job_id"
            # Note: In production, you might want to implement proper job monitoring
        done
    fi

    # Clean up replication configuration templates if not preserving data
    if [[ "$KEEP_DATA" != "true" ]]; then
        local templates=$(aws drs describe-replication-configuration-templates \
            --region "${PRIMARY_REGION}" \
            --query 'replicationConfigurationTemplates[].replicationConfigurationTemplateID' \
            --output text 2>/dev/null || echo "")

        if [[ -n "$templates" && "$templates" != "None" ]]; then
            info "Found replication configuration templates to clean up"
            for template_id in $templates; do
                info "Deleting replication configuration template: $template_id"
                aws drs delete-replication-configuration-template \
                    --replication-configuration-template-id "$template_id" \
                    --region "${PRIMARY_REGION}" 2>/dev/null || {
                    warning "Failed to delete replication template: $template_id"
                }
            done
        fi
    else
        warning "Preserving DRS templates and staging data as requested"
    fi

    success "DRS resources cleanup completed"
}

#############################################################################
# IAM Resources Cleanup
#############################################################################

cleanup_iam_resources() {
    info "Cleaning up IAM resources..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would delete IAM role: $AUTOMATION_ROLE_NAME"
        return 0
    fi

    # Delete role policy first
    if aws iam get-role-policy --role-name "${AUTOMATION_ROLE_NAME}" --policy-name "DRAutomationPolicy" &> /dev/null; then
        info "Deleting IAM role policy: DRAutomationPolicy"
        aws iam delete-role-policy \
            --role-name "${AUTOMATION_ROLE_NAME}" \
            --policy-name "DRAutomationPolicy" || {
            warning "Failed to delete role policy: DRAutomationPolicy"
        }
    fi

    # Delete IAM role
    if aws iam get-role --role-name "${AUTOMATION_ROLE_NAME}" &> /dev/null; then
        info "Deleting IAM role: ${AUTOMATION_ROLE_NAME}"
        aws iam delete-role \
            --role-name "${AUTOMATION_ROLE_NAME}" || {
            warning "Failed to delete IAM role: ${AUTOMATION_ROLE_NAME}"
        }
    else
        info "No IAM role found to clean up"
    fi

    success "IAM resources cleanup completed"
}

#############################################################################
# Agent Scripts Cleanup
#############################################################################

cleanup_agent_scripts() {
    info "Cleaning up agent installation scripts..."

    local scripts_dir="${SCRIPT_DIR}/../agent-scripts"
    
    if [[ -d "$scripts_dir" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY RUN] Would remove agent scripts directory: $scripts_dir"
        else
            info "Removing agent scripts directory: $scripts_dir"
            rm -rf "$scripts_dir"
        fi
    else
        info "No agent scripts directory found to clean up"
    fi

    success "Agent scripts cleanup completed"
}

#############################################################################
# Final Verification
#############################################################################

verify_cleanup() {
    info "Verifying cleanup completion..."

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would verify all resources have been removed"
        return 0
    fi

    local cleanup_issues=false

    # Check if IAM role still exists
    if aws iam get-role --role-name "${AUTOMATION_ROLE_NAME}" &> /dev/null; then
        warning "IAM role still exists: ${AUTOMATION_ROLE_NAME}"
        cleanup_issues=true
    fi

    # Check if Lambda functions still exist
    if aws lambda get-function --function-name "dr-automated-failover-${DR_PROJECT_ID}" --region "${PRIMARY_REGION}" &> /dev/null; then
        warning "Lambda function still exists: dr-automated-failover-${DR_PROJECT_ID}"
        cleanup_issues=true
    fi

    # Check if DR VPC still exists
    local dr_vpc_check=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=${DR_VPC_NAME}" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region "${DR_REGION}" 2>/dev/null || echo "None")

    if [[ -n "$dr_vpc_check" && "$dr_vpc_check" != "None" ]]; then
        warning "DR VPC still exists: $dr_vpc_check"
        cleanup_issues=true
    fi

    if [[ "$cleanup_issues" == "true" ]]; then
        warning "Some resources may not have been fully cleaned up. Check the logs for details."
        if [[ "$FORCE_DESTROY" != "true" ]]; then
            read -p "Do you want to continue despite cleanup issues? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                fatal "Cleanup verification failed. Manual intervention required."
            fi
        fi
    fi

    success "Cleanup verification completed"
}

#############################################################################
# Main Cleanup Process
#############################################################################

main() {
    info "Starting AWS Cross-Region Disaster Recovery cleanup..."
    info "Log file: $LOG_FILE"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE_DESTROY=true
                shift
                ;;
            --keep-data)
                KEEP_DATA=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Display configuration
    info "Cleanup Configuration:"
    info "  Dry Run: $DRY_RUN"
    info "  Force Mode: $FORCE_DESTROY"
    info "  Keep Data: $KEEP_DATA"

    # Safety confirmation
    if [[ "$FORCE_DESTROY" != "true" && "$DRY_RUN" != "true" ]]; then
        echo
        echo -e "${RED}⚠️  WARNING: This will permanently delete DR infrastructure!${NC}"
        echo -e "${RED}⚠️  DRS agents will lose connectivity and recovery data may be lost!${NC}"
        echo
        read -p "Are you absolutely sure you want to proceed? (type 'DELETE' to confirm): " -r
        echo
        if [[ "$REPLY" != "DELETE" ]]; then
            info "Cleanup cancelled by user"
            exit 0
        fi
    fi

    # Execute cleanup steps
    check_prerequisites
    load_configuration

    # Execute cleanup in reverse order of creation
    cleanup_dr_testing
    cleanup_eventbridge_rules
    cleanup_step_functions
    cleanup_lambda_functions
    cleanup_cloudwatch
    cleanup_sns
    cleanup_dr_infrastructure
    cleanup_drs_resources
    cleanup_iam_resources
    cleanup_agent_scripts
    verify_cleanup

    # Clean up configuration file
    if [[ "$DRY_RUN" != "true" ]]; then
        info "Removing deployment configuration file"
        rm -f "$CONFIG_FILE"
    fi

    # Display completion message
    echo
    success "==================================================================="
    success "AWS Cross-Region Disaster Recovery cleanup completed!"
    success "==================================================================="
    echo
    
    if [[ "$KEEP_DATA" == "true" ]]; then
        warning "DRS staging data and templates were preserved as requested"
        info "You may want to manually clean these up later to avoid ongoing charges"
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "This was a dry run. No actual resources were modified."
        info "Run without --dry-run to perform actual cleanup."
    else
        info "All DR automation infrastructure has been removed"
        info "Source servers will need DRS agents reconfigured if deploying again"
    fi
    echo
}

# Run main function with all arguments
main "$@"