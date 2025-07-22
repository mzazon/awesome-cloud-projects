#!/bin/bash
# AWS Data Exchange Subscriber Access Script
# This script helps subscribers accept data grants and export entitled data

set -e

# Configuration variables (provided by Terraform)
SUBSCRIBER_BUCKET="${subscriber_bucket}"
AWS_REGION="${aws_region}"

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "$${BLUE}ℹ️  $1$${NC}"
}

print_success() {
    echo -e "$${GREEN}✅ $1$${NC}"
}

print_warning() {
    echo -e "$${YELLOW}⚠️  $1$${NC}"
}

print_error() {
    echo -e "$${RED}❌ $1$${NC}"
}

# Function to show usage information
show_usage() {
    echo "AWS Data Exchange Subscriber Access Script"
    echo ""
    echo "Usage: $0 <data-grant-id> [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -b, --bucket <name>     Override subscriber bucket name (default: $SUBSCRIBER_BUCKET)"
    echo "  -r, --region <region>   Override AWS region (default: $AWS_REGION)"
    echo "  -d, --dry-run           Show what would be done without executing"
    echo "  -v, --verbose           Enable verbose output"
    echo ""
    echo "Examples:"
    echo "  $0 dg-1234567890abcdef0"
    echo "  $0 dg-1234567890abcdef0 --bucket my-custom-bucket"
    echo "  $0 dg-1234567890abcdef0 --dry-run"
}

# Function to validate prerequisites
validate_prerequisites() {
    print_info "Validating prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! aws sts get-caller-identity &> /dev/null; then
        print_error "AWS credentials are not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    # Check if Data Exchange service is available in the region
    local available_regions=$(aws dataexchange describe-data-sets --region $AWS_REGION --max-items 1 2>/dev/null || echo "")
    if [ -z "$available_regions" ]; then
        print_warning "Data Exchange may not be available in region: $AWS_REGION"
    fi
    
    print_success "Prerequisites validated"
}

# Function to accept data grant
accept_data_grant() {
    local data_grant_id=$1
    local dry_run=$2
    
    print_info "Accepting data grant: $data_grant_id"
    
    if [ "$dry_run" = "true" ]; then
        print_warning "DRY RUN: Would accept data grant $data_grant_id"
        return 0
    fi
    
    # Accept the data grant
    local accept_response=$(aws dataexchange accept-data-grant \
        --data-grant-id "$data_grant_id" \
        --region "$AWS_REGION" \
        --output json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        print_success "Data grant accepted successfully"
        
        if [ "$VERBOSE" = "true" ]; then
            echo "Response: $accept_response"
        fi
    else
        print_error "Failed to accept data grant. Please check the grant ID and your permissions."
        exit 1
    fi
}

# Function to list entitled datasets
list_entitled_datasets() {
    local dry_run=$1
    
    print_info "Listing entitled datasets..."
    
    if [ "$dry_run" = "true" ]; then
        print_warning "DRY RUN: Would list entitled datasets"
        return 0
    fi
    
    local entitled_datasets=$(aws dataexchange list-data-sets \
        --origin ENTITLED \
        --region "$AWS_REGION" \
        --output json)
    
    if [ $? -eq 0 ]; then
        local dataset_count=$(echo "$entitled_datasets" | jq '.DataSets | length')
        print_success "Found $dataset_count entitled dataset(s)"
        
        if [ "$VERBOSE" = "true" ]; then
            echo "$entitled_datasets" | jq '.DataSets[] | {Id: .Id, Name: .Name, Description: .Description}'
        fi
        
        # Return the first dataset ID
        echo "$entitled_datasets" | jq -r '.DataSets[0].Id // empty'
    else
        print_error "Failed to list entitled datasets"
        exit 1
    fi
}

# Function to create subscriber bucket if needed
create_subscriber_bucket() {
    local bucket_name=$1
    local dry_run=$2
    
    print_info "Checking subscriber bucket: $bucket_name"
    
    if [ "$dry_run" = "true" ]; then
        print_warning "DRY RUN: Would check/create bucket $bucket_name"
        return 0
    fi
    
    # Check if bucket exists
    if aws s3 ls "s3://$bucket_name" &> /dev/null; then
        print_success "Bucket $bucket_name already exists"
    else
        print_info "Creating subscriber bucket: $bucket_name"
        
        if [ "$AWS_REGION" = "us-east-1" ]; then
            aws s3 mb "s3://$bucket_name" --region "$AWS_REGION"
        else
            aws s3 mb "s3://$bucket_name" --region "$AWS_REGION" \
                --create-bucket-configuration LocationConstraint="$AWS_REGION"
        fi
        
        if [ $? -eq 0 ]; then
            print_success "Created bucket: $bucket_name"
        else
            print_error "Failed to create bucket: $bucket_name"
            exit 1
        fi
    fi
}

# Function to export entitled assets
export_entitled_assets() {
    local dataset_id=$1
    local bucket_name=$2
    local dry_run=$3
    
    print_info "Exporting entitled assets from dataset: $dataset_id"
    
    if [ "$dry_run" = "true" ]; then
        print_warning "DRY RUN: Would export assets from $dataset_id to s3://$bucket_name/imported-data/"
        return 0
    fi
    
    # Get the latest revision
    local latest_revision=$(aws dataexchange list-revisions \
        --data-set-id "$dataset_id" \
        --region "$AWS_REGION" \
        --output json | jq -r '.Revisions | sort_by(.CreatedAt) | last | .Id')
    
    if [ "$latest_revision" = "null" ] || [ -z "$latest_revision" ]; then
        print_error "No revisions found for dataset: $dataset_id"
        exit 1
    fi
    
    print_info "Using latest revision: $latest_revision"
    
    # List assets in the revision
    local assets=$(aws dataexchange list-revision-assets \
        --data-set-id "$dataset_id" \
        --revision-id "$latest_revision" \
        --region "$AWS_REGION" \
        --output json)
    
    local asset_count=$(echo "$assets" | jq '.Assets | length')
    print_info "Found $asset_count asset(s) to export"
    
    if [ "$asset_count" -eq 0 ]; then
        print_warning "No assets found in the revision"
        return 0
    fi
    
    # Create export job
    local export_job=$(aws dataexchange create-job \
        --type EXPORT_ASSETS_TO_S3 \
        --details "{
            \"ExportAssetsToS3JobDetails\": {
                \"DataSetId\": \"$dataset_id\",
                \"RevisionId\": \"$latest_revision\",
                \"AssetDestinations\": [
                    {
                        \"AssetId\": \"*\",
                        \"Bucket\": \"$bucket_name\",
                        \"Key\": \"imported-data/\"
                    }
                ]
            }
        }" \
        --region "$AWS_REGION" \
        --output json)
    
    if [ $? -eq 0 ]; then
        local job_id=$(echo "$export_job" | jq -r '.Id')
        print_success "Export job created: $job_id"
        
        # Wait for job completion
        print_info "Waiting for export job to complete..."
        
        local job_status=""
        local max_attempts=30
        local attempt=0
        
        while [ $attempt -lt $max_attempts ]; do
            sleep 10
            attempt=$((attempt + 1))
            
            local job_details=$(aws dataexchange get-job \
                --job-id "$job_id" \
                --region "$AWS_REGION" \
                --output json)
            
            job_status=$(echo "$job_details" | jq -r '.State')
            
            if [ "$job_status" = "COMPLETED" ]; then
                print_success "Export job completed successfully"
                print_success "Data exported to: s3://$bucket_name/imported-data/"
                break
            elif [ "$job_status" = "ERROR" ]; then
                local error_details=$(echo "$job_details" | jq -r '.Errors[]?.Message // "Unknown error"')
                print_error "Export job failed: $error_details"
                exit 1
            else
                print_info "Export job status: $job_status (attempt $attempt/$max_attempts)"
            fi
        done
        
        if [ "$job_status" != "COMPLETED" ]; then
            print_error "Export job timed out or failed"
            exit 1
        fi
    else
        print_error "Failed to create export job"
        exit 1
    fi
}

# Function to list exported files
list_exported_files() {
    local bucket_name=$1
    local dry_run=$2
    
    print_info "Listing exported files in bucket: $bucket_name"
    
    if [ "$dry_run" = "true" ]; then
        print_warning "DRY RUN: Would list files in s3://$bucket_name/imported-data/"
        return 0
    fi
    
    local files=$(aws s3 ls "s3://$bucket_name/imported-data/" --recursive --region "$AWS_REGION")
    
    if [ $? -eq 0 ] && [ -n "$files" ]; then
        print_success "Exported files:"
        echo "$files"
    else
        print_warning "No files found in the imported-data folder"
    fi
}

# Main script execution
main() {
    local data_grant_id=""
    local bucket_name="$SUBSCRIBER_BUCKET"
    local region="$AWS_REGION"
    local dry_run="false"
    local verbose="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -b|--bucket)
                bucket_name="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                shift 2
                ;;
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$data_grant_id" ]; then
                    data_grant_id="$1"
                else
                    print_error "Multiple data grant IDs provided"
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [ -z "$data_grant_id" ]; then
        print_error "Data grant ID is required"
        show_usage
        exit 1
    fi
    
    # Set global variables
    AWS_REGION="$region"
    VERBOSE="$verbose"
    
    # Print configuration
    print_info "Configuration:"
    echo "  Data Grant ID: $data_grant_id"
    echo "  Subscriber Bucket: $bucket_name"
    echo "  AWS Region: $AWS_REGION"
    echo "  Dry Run: $dry_run"
    echo "  Verbose: $verbose"
    echo ""
    
    # Execute main workflow
    validate_prerequisites
    accept_data_grant "$data_grant_id" "$dry_run"
    
    local entitled_dataset_id=$(list_entitled_datasets "$dry_run")
    
    if [ -n "$entitled_dataset_id" ] && [ "$entitled_dataset_id" != "null" ]; then
        print_info "Using entitled dataset: $entitled_dataset_id"
        create_subscriber_bucket "$bucket_name" "$dry_run"
        export_entitled_assets "$entitled_dataset_id" "$bucket_name" "$dry_run"
        list_exported_files "$bucket_name" "$dry_run"
    else
        print_warning "No entitled datasets found after accepting the grant"
    fi
    
    print_success "Subscriber access script completed successfully!"
}

# Execute main function with all arguments
main "$@"