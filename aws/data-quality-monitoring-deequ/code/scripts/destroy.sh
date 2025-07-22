#!/bin/bash

# AWS Real-time Data Quality Monitoring with Deequ on EMR - Cleanup Script
# This script safely removes all infrastructure created by the deployment script
# including EMR clusters, S3 buckets, SNS topics, IAM roles, and CloudWatch dashboards

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠️  $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ❌ $1${NC}"
}

# Function to confirm destruction
confirm_destruction() {
    echo "=============================================="
    echo "🚨 INFRASTRUCTURE DESTRUCTION CONFIRMATION 🚨"
    echo "=============================================="
    echo
    echo "This script will permanently delete the following resources:"
    echo "   • EMR Cluster and all associated data"
    echo "   • S3 Bucket and all stored data"
    echo "   • SNS Topic and subscriptions"
    echo "   • CloudWatch Dashboard"
    echo "   • IAM Roles (if safe to delete)"
    echo
    warning "THIS ACTION CANNOT BE UNDONE!"
    echo
    
    if [ -t 0 ]; then  # Check if running interactively
        read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
        if [ "$confirmation" != "yes" ]; then
            log "Destruction cancelled by user"
            exit 0
        fi
    else
        warning "Running non-interactively. Proceeding with destruction..."
    fi
    
    echo
    log "Starting infrastructure destruction..."
}

# Function to load environment variables
load_environment() {
    log "Loading environment variables..."
    
    if [ -f "/tmp/deequ-deployment-vars.env" ]; then
        source /tmp/deequ-deployment-vars.env
        success "Loaded environment variables from deployment"
    else
        warning "Deployment variables file not found. Attempting manual detection..."
        
        # Set basic variables
        export AWS_REGION=$(aws configure get region)
        if [ -z "$AWS_REGION" ]; then
            export AWS_REGION="us-east-1"
            warning "AWS region not set, defaulting to us-east-1"
        fi
        
        export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        # Try to detect resources by pattern
        detect_resources
    fi
    
    # Validate AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured. Please run 'aws configure'."
        exit 1
    fi
    
    success "Environment variables loaded"
}

# Function to detect existing resources
detect_resources() {
    log "Detecting existing resources..."
    
    # Find EMR clusters with deequ pattern
    local clusters
    clusters=$(aws emr list-clusters --cluster-states RUNNING WAITING \
        --query "Clusters[?contains(Name, 'deequ-quality-monitor')].{Id:Id,Name:Name}" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$clusters" ]; then
        export CLUSTER_ID=$(echo "$clusters" | head -1 | awk '{print $1}')
        export CLUSTER_NAME=$(echo "$clusters" | head -1 | awk '{print $2}')
        log "Found EMR cluster: ${CLUSTER_NAME} (${CLUSTER_ID})"
    fi
    
    # Find S3 buckets with deequ pattern
    local buckets
    buckets=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'deequ-data-quality')].Name" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$buckets" ]; then
        export S3_BUCKET_NAME=$(echo "$buckets" | head -1)
        log "Found S3 bucket: ${S3_BUCKET_NAME}"
    fi
    
    # Find SNS topics with deequ pattern
    local topics
    topics=$(aws sns list-topics --query "Topics[?contains(TopicArn, 'data-quality-alerts')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$topics" ]; then
        export SNS_TOPIC_ARN=$(echo "$topics" | head -1)
        export SNS_TOPIC_NAME=$(basename "$SNS_TOPIC_ARN")
        log "Found SNS topic: ${SNS_TOPIC_NAME}"
    fi
}

# Function to terminate EMR cluster
terminate_emr_cluster() {
    if [ -n "${CLUSTER_ID:-}" ]; then
        log "Terminating EMR cluster: ${CLUSTER_ID}"
        
        # Check if cluster exists and is in a terminable state
        local cluster_state
        cluster_state=$(aws emr describe-cluster --cluster-id "${CLUSTER_ID}" \
            --query 'Cluster.Status.State' --output text 2>/dev/null || echo "NOT_FOUND")
        
        case "$cluster_state" in
            "RUNNING"|"WAITING"|"BOOTSTRAPPING"|"STARTING")
                aws emr terminate-clusters --cluster-ids "${CLUSTER_ID}"
                success "EMR cluster termination initiated"
                
                # Wait for termination with timeout
                log "Waiting for cluster termination (this may take several minutes)..."
                local max_wait=600  # 10 minutes
                local wait_time=0
                local sleep_interval=30
                
                while [ $wait_time -lt $max_wait ]; do
                    cluster_state=$(aws emr describe-cluster --cluster-id "${CLUSTER_ID}" \
                        --query 'Cluster.Status.State' --output text 2>/dev/null || echo "TERMINATED")
                    
                    if [ "$cluster_state" = "TERMINATED" ] || [ "$cluster_state" = "TERMINATED_WITH_ERRORS" ]; then
                        success "EMR cluster terminated successfully"
                        break
                    fi
                    
                    log "Cluster state: $cluster_state. Waiting..."
                    sleep $sleep_interval
                    wait_time=$((wait_time + sleep_interval))
                done
                
                if [ $wait_time -ge $max_wait ]; then
                    warning "Timeout waiting for cluster termination, but continuing cleanup..."
                fi
                ;;
            "TERMINATED"|"TERMINATED_WITH_ERRORS")
                success "EMR cluster already terminated"
                ;;
            "TERMINATING")
                log "EMR cluster already terminating. Waiting..."
                sleep 60
                success "EMR cluster termination in progress"
                ;;
            "NOT_FOUND")
                warning "EMR cluster not found or already deleted"
                ;;
            *)
                warning "EMR cluster in unexpected state: $cluster_state"
                ;;
        esac
    else
        warning "No EMR cluster ID found to terminate"
    fi
}

# Function to delete CloudWatch dashboard
delete_dashboard() {
    log "Deleting CloudWatch dashboard..."
    
    if aws cloudwatch get-dashboard --dashboard-name "DeeQuDataQualityMonitoring" &>/dev/null; then
        aws cloudwatch delete-dashboards --dashboard-names "DeeQuDataQualityMonitoring"
        success "CloudWatch dashboard deleted"
    else
        warning "CloudWatch dashboard not found or already deleted"
    fi
}

# Function to delete S3 bucket and contents
delete_s3_resources() {
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        log "Deleting S3 bucket and contents: ${S3_BUCKET_NAME}"
        
        # Check if bucket exists
        if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
            # Delete all objects in bucket (including versions and delete markers)
            log "Removing all objects from S3 bucket..."
            aws s3 rm "s3://${S3_BUCKET_NAME}" --recursive || warning "Some objects may not have been deleted"
            
            # Delete any object versions if versioning is enabled
            local versions
            versions=$(aws s3api list-object-versions --bucket "${S3_BUCKET_NAME}" \
                --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null || echo "")
            
            if [ -n "$versions" ]; then
                log "Deleting object versions..."
                echo "$versions" | while read -r key version_id; do
                    if [ -n "$key" ] && [ -n "$version_id" ]; then
                        aws s3api delete-object --bucket "${S3_BUCKET_NAME}" --key "$key" --version-id "$version_id" || true
                    fi
                done
            fi
            
            # Delete any delete markers
            local delete_markers
            delete_markers=$(aws s3api list-object-versions --bucket "${S3_BUCKET_NAME}" \
                --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null || echo "")
            
            if [ -n "$delete_markers" ]; then
                log "Deleting delete markers..."
                echo "$delete_markers" | while read -r key version_id; do
                    if [ -n "$key" ] && [ -n "$version_id" ]; then
                        aws s3api delete-object --bucket "${S3_BUCKET_NAME}" --key "$key" --version-id "$version_id" || true
                    fi
                done
            fi
            
            # Delete the bucket
            aws s3 rb "s3://${S3_BUCKET_NAME}" --force
            success "S3 bucket deleted successfully"
        else
            warning "S3 bucket not found or already deleted"
        fi
    else
        warning "No S3 bucket name found to delete"
    fi
}

# Function to delete SNS topic
delete_sns_topic() {
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        log "Deleting SNS topic: ${SNS_TOPIC_ARN}"
        
        # List and unsubscribe all subscriptions first
        local subscriptions
        subscriptions=$(aws sns list-subscriptions-by-topic --topic-arn "${SNS_TOPIC_ARN}" \
            --query 'Subscriptions[].SubscriptionArn' --output text 2>/dev/null || echo "")
        
        if [ -n "$subscriptions" ]; then
            log "Unsubscribing all SNS subscriptions..."
            echo "$subscriptions" | tr '\t' '\n' | while read -r subscription_arn; do
                if [ "$subscription_arn" != "PendingConfirmation" ] && [ -n "$subscription_arn" ]; then
                    aws sns unsubscribe --subscription-arn "$subscription_arn" || true
                fi
            done
        fi
        
        # Delete the topic
        if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &>/dev/null; then
            aws sns delete-topic --topic-arn "${SNS_TOPIC_ARN}"
            success "SNS topic deleted successfully"
        else
            warning "SNS topic not found or already deleted"
        fi
    else
        warning "No SNS topic ARN found to delete"
    fi
}

# Function to check and delete IAM roles safely
delete_iam_roles() {
    log "Checking IAM roles for safe deletion..."
    
    # Check EMR service role
    if aws iam get-role --role-name EMR_DefaultRole &>/dev/null; then
        # Check if role is attached to any other EMR clusters
        local other_clusters
        other_clusters=$(aws emr list-clusters --cluster-states RUNNING WAITING BOOTSTRAPPING STARTING \
            --query "Clusters[?ServiceRole=='EMR_DefaultRole']" --output text 2>/dev/null || echo "")
        
        if [ -z "$other_clusters" ]; then
            log "Deleting EMR service role..."
            aws iam detach-role-policy --role-name EMR_DefaultRole \
                --policy-arn arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceRole || true
            aws iam delete-role --role-name EMR_DefaultRole || true
            success "EMR service role deleted"
        else
            warning "EMR service role in use by other clusters, skipping deletion"
        fi
    else
        log "EMR service role not found or already deleted"
    fi
    
    # Check EMR EC2 role and instance profile
    if aws iam get-instance-profile --instance-profile-name EMR_EC2_DefaultRole &>/dev/null; then
        # Check if instance profile is in use
        local instances_using_profile
        instances_using_profile=$(aws ec2 describe-instances \
            --filters "Name=iam-instance-profile.arn,Values=*EMR_EC2_DefaultRole*" \
            --query 'Reservations[].Instances[?State.Name==`running`]' --output text 2>/dev/null || echo "")
        
        if [ -z "$instances_using_profile" ]; then
            log "Deleting EMR EC2 instance profile and role..."
            aws iam remove-role-from-instance-profile --instance-profile-name EMR_EC2_DefaultRole \
                --role-name EMR_EC2_DefaultRole || true
            aws iam delete-instance-profile --instance-profile-name EMR_EC2_DefaultRole || true
            aws iam detach-role-policy --role-name EMR_EC2_DefaultRole \
                --policy-arn arn:aws:iam::aws:policy/service-role/AmazonElasticMapReduceforEC2Role || true
            aws iam delete-role --role-name EMR_EC2_DefaultRole || true
            success "EMR EC2 role and instance profile deleted"
        else
            warning "EMR EC2 instance profile in use by running instances, skipping deletion"
        fi
    else
        log "EMR EC2 instance profile not found or already deleted"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    
    local temp_files=(
        "/tmp/deequ-deployment-vars.env"
        "/tmp/install-deequ.sh"
        "/tmp/sample-data.py"
        "/tmp/sample_customer_data.csv"
        "/tmp/deequ-quality-monitor.py"
        "/tmp/automated-monitoring.py"
        "/tmp/dashboard-config.json"
        "/tmp/bad-data.csv"
        "/tmp/verification_report.json"
    )
    
    for file in "${temp_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log "Removed temporary file: $file"
        fi
    done
    
    success "Temporary files cleaned up"
}

# Function to verify cleanup completion
verify_cleanup() {
    log "Verifying cleanup completion..."
    
    local cleanup_issues=0
    
    # Check EMR clusters
    if [ -n "${CLUSTER_ID:-}" ]; then
        local cluster_state
        cluster_state=$(aws emr describe-cluster --cluster-id "${CLUSTER_ID}" \
            --query 'Cluster.Status.State' --output text 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$cluster_state" != "TERMINATED" ] && [ "$cluster_state" != "TERMINATED_WITH_ERRORS" ] && [ "$cluster_state" != "NOT_FOUND" ]; then
            warning "EMR cluster still exists in state: $cluster_state"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check S3 bucket
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        if aws s3api head-bucket --bucket "${S3_BUCKET_NAME}" 2>/dev/null; then
            warning "S3 bucket still exists: ${S3_BUCKET_NAME}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check SNS topic
    if [ -n "${SNS_TOPIC_ARN:-}" ]; then
        if aws sns get-topic-attributes --topic-arn "${SNS_TOPIC_ARN}" &>/dev/null; then
            warning "SNS topic still exists: ${SNS_TOPIC_ARN}"
            cleanup_issues=$((cleanup_issues + 1))
        fi
    fi
    
    # Check CloudWatch dashboard
    if aws cloudwatch get-dashboard --dashboard-name "DeeQuDataQualityMonitoring" &>/dev/null; then
        warning "CloudWatch dashboard still exists"
        cleanup_issues=$((cleanup_issues + 1))
    fi
    
    if [ $cleanup_issues -eq 0 ]; then
        success "All resources cleaned up successfully"
    else
        warning "$cleanup_issues resources may still exist. Manual cleanup may be required."
    fi
}

# Function to display cleanup summary
show_summary() {
    echo
    echo "=========================================="
    echo "🧹 CLEANUP COMPLETED! 🧹"
    echo "=========================================="
    echo
    echo "📋 Resources Processed:"
    if [ -n "${CLUSTER_ID:-}" ]; then
        echo "   • EMR Cluster: ${CLUSTER_NAME:-Unknown} (${CLUSTER_ID})"
    fi
    if [ -n "${S3_BUCKET_NAME:-}" ]; then
        echo "   • S3 Bucket: ${S3_BUCKET_NAME}"
    fi
    if [ -n "${SNS_TOPIC_NAME:-}" ]; then
        echo "   • SNS Topic: ${SNS_TOPIC_NAME}"
    fi
    echo "   • CloudWatch Dashboard: DeeQuDataQualityMonitoring"
    echo "   • IAM Roles: EMR_DefaultRole, EMR_EC2_DefaultRole (if safe)"
    echo "   • Temporary Files: Cleaned up"
    echo
    echo "💰 Cost Impact:"
    echo "   • EMR cluster charges have been stopped"
    echo "   • S3 storage charges have been eliminated"
    echo "   • CloudWatch and SNS charges have been minimized"
    echo
    echo "⚠️  Important Notes:"
    echo "   • If you had data in the S3 bucket, it has been permanently deleted"
    echo "   • Any email subscriptions to SNS have been removed"
    echo "   • CloudWatch logs may be retained according to their retention policy"
    echo "   • IAM roles were only deleted if not in use by other resources"
    echo
    echo "🔍 Manual Verification:"
    echo "   • Check EMR console for any remaining clusters"
    echo "   • Verify S3 console shows no remaining buckets with 'deequ' in the name"
    echo "   • Confirm SNS console shows no topics with 'data-quality-alerts' in the name"
    echo
}

# Main execution function
main() {
    echo "=================================================="
    echo "🧹 AWS Deequ Data Quality Monitoring - Cleanup"
    echo "=================================================="
    echo
    
    confirm_destruction
    load_environment
    terminate_emr_cluster
    delete_dashboard
    delete_s3_resources
    delete_sns_topic
    delete_iam_roles
    cleanup_temp_files
    verify_cleanup
    show_summary
    
    log "Cleanup script completed successfully!"
}

# Handle script interruption
trap 'error "Cleanup script interrupted. Some resources may still exist."; exit 1' INT TERM

# Run main function
main "$@"