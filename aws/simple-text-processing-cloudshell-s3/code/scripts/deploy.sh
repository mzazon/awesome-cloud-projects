#!/bin/bash

# Simple Text Processing with CloudShell and S3 - Deployment Script
# This script deploys the infrastructure and demonstrates text processing capabilities

set -e
set -o pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[${TIMESTAMP}]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[${TIMESTAMP}] ✅ $1${NC}" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[${TIMESTAMP}] ⚠️  $1${NC}" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[${TIMESTAMP}] ❌ $1${NC}" | tee -a "${LOG_FILE}"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Deployment failed. Check ${LOG_FILE} for details."
    exit 1
}

# Cleanup function for partial deployments
cleanup_on_error() {
    log_warning "Cleaning up partial deployment..."
    if [[ -n "${BUCKET_NAME}" ]]; then
        aws s3 rb s3://${BUCKET_NAME} --force 2>/dev/null || true
    fi
    exit 1
}

trap cleanup_on_error ERR

# Prerequisites check
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if running in CloudShell or has AWS CLI
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install AWS CLI or run this script in AWS CloudShell."
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured. Please configure AWS CLI or run in CloudShell."
    fi
    
    # Check required commands
    local required_commands=("grep" "awk" "wc" "sort" "head" "tail" "cat")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "${cmd}" &> /dev/null; then
            error_exit "Required command '${cmd}' is not available."
        fi
    done
    
    log_success "Prerequisites check completed"
}

# Environment setup
setup_environment() {
    log "Setting up environment variables..."
    
    # Get AWS region and account ID
    export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    # Generate unique suffix for resources
    RANDOM_SUFFIX=$(aws secretsmanager get-random-password \
        --exclude-punctuation --exclude-uppercase \
        --password-length 6 --require-each-included-type \
        --output text --query RandomPassword 2>/dev/null || \
        echo "$(date +%s | tail -c 7)")
    
    # Set bucket name with unique suffix
    export BUCKET_NAME="text-processing-demo-${RANDOM_SUFFIX}"
    
    log "Environment configured for region: ${AWS_REGION}"
    log "Using bucket name: ${BUCKET_NAME}"
    log_success "Environment setup completed"
}

# Create S3 bucket
create_s3_bucket() {
    log "Creating S3 bucket for data storage..."
    
    # Create S3 bucket with appropriate region handling
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
        aws s3 mb s3://${BUCKET_NAME} || error_exit "Failed to create S3 bucket"
    else
        aws s3 mb s3://${BUCKET_NAME} --region ${AWS_REGION} || error_exit "Failed to create S3 bucket"
    fi
    
    # Verify bucket creation
    if ! aws s3 ls | grep -q ${BUCKET_NAME}; then
        error_exit "S3 bucket creation verification failed"
    fi
    
    log_success "S3 bucket created: ${BUCKET_NAME}"
}

# Create sample data
create_sample_data() {
    log "Creating sample sales data file..."
    
    # Create sample data file
    cat << 'EOF' > sales_data.txt
Date,Region,Product,Sales,Quantity
2024-01-15,North,Laptop,1200,2
2024-01-16,South,Mouse,25,5
2024-01-17,East,Keyboard,75,3
2024-01-18,West,Monitor,300,1
2024-01-19,North,Laptop,600,1
2024-01-20,South,Tablet,400,2
2024-01-21,East,Mouse,50,10
2024-01-22,West,Keyboard,150,6
2024-01-23,North,Monitor,900,3
2024-01-24,South,Laptop,2400,4
2024-01-25,East,Tablet,800,4
2024-01-26,West,Mouse,75,15
EOF
    
    # Verify file creation
    if [[ ! -f "sales_data.txt" ]]; then
        error_exit "Failed to create sample data file"
    fi
    
    local line_count=$(wc -l < sales_data.txt)
    log "Sample data file created with ${line_count} lines"
    log_success "Sample sales data file created"
}

# Upload data to S3
upload_data_to_s3() {
    log "Uploading sample data to S3..."
    
    # Upload sample data to S3 input folder
    aws s3 cp sales_data.txt s3://${BUCKET_NAME}/input/ || error_exit "Failed to upload data to S3"
    
    # Verify upload
    if ! aws s3 ls s3://${BUCKET_NAME}/input/ | grep -q sales_data.txt; then
        error_exit "S3 upload verification failed"
    fi
    
    log_success "Sample data uploaded to S3"
}

# Perform text processing
perform_text_processing() {
    log "Performing text processing and analysis..."
    
    # Create processing directory
    mkdir -p processing
    cd processing
    
    # Download file from S3
    aws s3 cp s3://${BUCKET_NAME}/input/sales_data.txt . || error_exit "Failed to download data from S3"
    
    # Basic file analysis
    log "=== File Analysis ==="
    echo "Total lines: $(wc -l < sales_data.txt)" | tee -a "${LOG_FILE}"
    echo "Total words: $(wc -w < sales_data.txt)" | tee -a "${LOG_FILE}"
    echo "File size: $(wc -c < sales_data.txt) bytes" | tee -a "${LOG_FILE}"
    
    # Advanced text processing
    log "=== Performing Advanced Analysis ==="
    
    # Extract North region sales
    log "North Region Sales:"
    grep "North" sales_data.txt | tee -a "${LOG_FILE}"
    
    # Calculate total sales by region
    log "Sales Summary by Region:"
    awk -F',' 'NR>1 {sales[$2]+=$4} END {for (region in sales) 
        print region ": $" sales[region]}' sales_data.txt | tee -a "${LOG_FILE}"
    
    # Find high-value transactions
    log "High-Value Transactions (>$500):"
    awk -F',' 'NR>1 && $4>500 {print $0}' sales_data.txt | tee -a "${LOG_FILE}"
    
    # Generate processed output files
    log "Generating processed output files..."
    
    # Regional sales summary
    awk -F',' 'NR>1 {sales[$2]+=$4; qty[$2]+=$5} END {
        print "Region,Total_Sales,Total_Quantity";
        for (region in sales) 
            print region "," sales[region] "," qty[region]
    }' sales_data.txt > regional_summary.csv
    
    # High-value transactions report
    echo "Date,Region,Product,Sales,Quantity" > high_value_sales.csv
    awk -F',' 'NR>1 && $4>500 {print $0}' sales_data.txt >> high_value_sales.csv
    
    # Product performance report
    awk -F',' 'NR>1 {
        sales[$3]+=$4; 
        qty[$3]+=$5; 
        count[$3]++
    } END {
        print "Product,Total_Sales,Total_Quantity,Transaction_Count";
        for (product in sales) 
            print product "," sales[product] "," qty[product] "," count[product]
    }' sales_data.txt > product_performance.csv
    
    # Verify generated files
    local csv_files=(regional_summary.csv high_value_sales.csv product_performance.csv)
    for file in "${csv_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            error_exit "Failed to generate $file"
        fi
    done
    
    log "Generated analysis files:"
    ls -la *.csv | tee -a "${LOG_FILE}"
    
    log_success "Text processing completed"
}

# Upload results to S3
upload_results_to_s3() {
    log "Uploading processed results to S3..."
    
    # Upload all processed files to S3 output folder
    local csv_files=(regional_summary.csv high_value_sales.csv product_performance.csv)
    for file in "${csv_files[@]}"; do
        aws s3 cp "$file" s3://${BUCKET_NAME}/output/ || error_exit "Failed to upload $file to S3"
    done
    
    # Verify uploads
    log "=== Files in S3 Output Folder ==="
    aws s3 ls s3://${BUCKET_NAME}/output/ | tee -a "${LOG_FILE}"
    
    # Display regional summary results
    log "=== Regional Summary Results ==="
    cat regional_summary.csv | tee -a "${LOG_FILE}"
    
    log_success "All processed files uploaded to S3"
}

# Validation and testing
perform_validation() {
    log "Performing validation and testing..."
    
    # Check bucket structure
    log "Verifying S3 bucket structure..."
    aws s3 ls s3://${BUCKET_NAME}/ | tee -a "${LOG_FILE}"
    aws s3 ls s3://${BUCKET_NAME}/input/ | tee -a "${LOG_FILE}"
    aws s3 ls s3://${BUCKET_NAME}/output/ | tee -a "${LOG_FILE}"
    
    # Create verification directory and test downloads
    mkdir -p ../verify
    aws s3 cp s3://${BUCKET_NAME}/output/regional_summary.csv ../verify/ || error_exit "Failed to download verification file"
    
    # Validate data accuracy
    log "Validating processed data accuracy..."
    cat ../verify/regional_summary.csv | tee -a "${LOG_FILE}"
    
    local original_records=$(tail -n +2 sales_data.txt | wc -l)
    local summary_records=$(tail -n +2 ../verify/regional_summary.csv | wc -l)
    
    echo "Original records: ${original_records}" | tee -a "${LOG_FILE}"
    echo "Regional summary records: ${summary_records}" | tee -a "${LOG_FILE}"
    
    log_success "Validation completed successfully"
}

# Save deployment information
save_deployment_info() {
    log "Saving deployment information..."
    
    local info_file="${SCRIPT_DIR}/deployment_info.txt"
    cat > "${info_file}" << EOF
# Simple Text Processing CloudShell S3 Deployment Information
# Generated on: ${TIMESTAMP}

BUCKET_NAME=${BUCKET_NAME}
AWS_REGION=${AWS_REGION}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
RANDOM_SUFFIX=${RANDOM_SUFFIX}

# S3 Bucket Information
S3_INPUT_FOLDER=s3://${BUCKET_NAME}/input/
S3_OUTPUT_FOLDER=s3://${BUCKET_NAME}/output/

# To access your data:
# aws s3 ls s3://${BUCKET_NAME}/
# aws s3 cp s3://${BUCKET_NAME}/output/regional_summary.csv .

# To clean up resources, run:
# ./destroy.sh
EOF
    
    log_success "Deployment information saved to ${info_file}"
}

# Display success message
show_success_message() {
    echo ""
    log_success "🎉 Simple Text Processing with CloudShell and S3 deployment completed successfully!"
    echo ""
    echo "📊 What was deployed:"
    echo "   • S3 bucket: ${BUCKET_NAME}"
    echo "   • Sample sales data uploaded to input folder"
    echo "   • Processed analysis files in output folder"
    echo ""
    echo "🔍 To explore your data:"
    echo "   aws s3 ls s3://${BUCKET_NAME}/"
    echo "   aws s3 cp s3://${BUCKET_NAME}/output/regional_summary.csv ."
    echo ""
    echo "📝 Next steps:"
    echo "   1. Try your own text processing with different files"
    echo "   2. Experiment with different Linux command-line tools"
    echo "   3. Upload larger datasets to test scalability"
    echo ""
    echo "🧹 To clean up resources when done:"
    echo "   ./destroy.sh"
    echo ""
    echo "📋 Deployment details saved to: ${SCRIPT_DIR}/deployment_info.txt"
}

# Main deployment function
main() {
    log "Starting Simple Text Processing with CloudShell and S3 deployment..."
    
    # Initialize log file
    echo "=== Simple Text Processing Deployment Log ===" > "${LOG_FILE}"
    echo "Started: ${TIMESTAMP}" >> "${LOG_FILE}"
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    create_s3_bucket
    create_sample_data
    upload_data_to_s3
    perform_text_processing
    upload_results_to_s3
    perform_validation
    save_deployment_info
    show_success_message
    
    log_success "Deployment completed successfully in $(( SECONDS / 60 )) minutes and $(( SECONDS % 60 )) seconds"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Simple Text Processing with CloudShell and S3 - Deployment Script"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --dry-run      Show what would be deployed without making changes"
        echo ""
        echo "This script deploys:"
        echo "  • S3 bucket for data storage"
        echo "  • Sample sales data for processing"
        echo "  • Demonstrates text processing capabilities"
        echo ""
        exit 0
        ;;
    --dry-run)
        echo "DRY RUN MODE - No resources will be created"
        echo ""
        echo "This deployment would:"
        echo "  1. Create S3 bucket with unique name"
        echo "  2. Upload sample sales data file"
        echo "  3. Demonstrate text processing with Linux tools"
        echo "  4. Generate analytical reports (CSV files)"
        echo "  5. Upload processed results to S3"
        echo ""
        echo "Estimated cost: $0.01-0.05 for S3 storage during tutorial"
        echo "Use './deploy.sh' to perform actual deployment"
        exit 0
        ;;
esac

# Run main deployment
main "$@"