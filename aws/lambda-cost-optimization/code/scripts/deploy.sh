#!/bin/bash

# AWS Lambda Cost Optimizer Deployment Script
# This script enables AWS Compute Optimizer and sets up monitoring for Lambda function optimization

set -e  # Exit on any error
set -u  # Exit on undefined variables

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy.log"
ANALYSIS_DIR="${SCRIPT_DIR}/../analysis"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message function
success() {
    log "${GREEN}✅ $1${NC}"
}

# Warning message function
warning() {
    log "${YELLOW}⚠️  $1${NC}"
}

# Info message function
info() {
    log "${BLUE}ℹ️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        error_exit "AWS CLI is not installed. Please install it first."
    fi
    
    # Check if AWS CLI is configured
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS CLI is not configured. Please run 'aws configure' first."
    fi
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        error_exit "jq is not installed. Please install jq for JSON processing."
    fi
    
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        error_exit "Python 3 is not installed. Please install Python 3."
    fi
    
    success "Prerequisites check completed"
}

# Setup environment variables
setup_environment() {
    info "Setting up environment variables..."
    
    export AWS_REGION=$(aws configure get region)
    if [ -z "$AWS_REGION" ]; then
        export AWS_REGION="us-east-1"
        warning "No region configured, using default: us-east-1"
    fi
    
    export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    log "Region: $AWS_REGION"
    log "Account ID: $AWS_ACCOUNT_ID"
    
    # Create analysis directory
    mkdir -p "$ANALYSIS_DIR"
    
    success "Environment setup completed"
}

# Check if account has Lambda functions
check_lambda_functions() {
    info "Checking for existing Lambda functions..."
    
    local function_count=$(aws lambda list-functions --query 'length(Functions)' --output text 2>/dev/null || echo "0")
    
    if [ "$function_count" -eq 0 ]; then
        warning "No Lambda functions found in region $AWS_REGION"
        warning "You need existing Lambda functions with at least 14 days of usage history for meaningful optimization"
        return 0
    fi
    
    success "Found $function_count Lambda functions"
    return 0
}

# Enable AWS Compute Optimizer
enable_compute_optimizer() {
    info "Enabling AWS Compute Optimizer..."
    
    # Check current enrollment status
    local current_status=$(aws compute-optimizer get-enrollment-status --query 'status' --output text 2>/dev/null || echo "Inactive")
    
    if [ "$current_status" = "Active" ]; then
        success "Compute Optimizer is already enabled"
        return 0
    fi
    
    # Enable Compute Optimizer
    aws compute-optimizer put-enrollment-status --status Active
    
    # Verify enrollment
    local new_status=$(aws compute-optimizer get-enrollment-status --query 'status' --output text)
    
    if [ "$new_status" = "Active" ]; then
        success "Compute Optimizer enabled successfully"
        info "Note: It may take up to 24 hours for initial recommendations to appear"
    else
        error_exit "Failed to enable Compute Optimizer"
    fi
}

# Export Lambda function information
export_lambda_info() {
    info "Exporting Lambda function information..."
    
    # Get list of Lambda functions
    local lambda_functions=$(aws lambda list-functions --query 'Functions[].FunctionName' --output text)
    
    if [ -z "$lambda_functions" ]; then
        warning "No Lambda functions found"
        return 0
    fi
    
    # Export configuration for each function
    local config_file="${ANALYSIS_DIR}/lambda-functions-baseline.json"
    echo "[]" > "$config_file"
    
    for function in $lambda_functions; do
        info "Processing function: $function"
        
        # Get function configuration
        aws lambda get-function-configuration \
            --function-name "$function" \
            --output json > "${ANALYSIS_DIR}/${function}-config.json"
        
        # Add to baseline file
        local memory_size=$(jq -r '.MemorySize' "${ANALYSIS_DIR}/${function}-config.json")
        local timeout=$(jq -r '.Timeout' "${ANALYSIS_DIR}/${function}-config.json")
        
        log "  Memory: ${memory_size} MB, Timeout: ${timeout} seconds"
        
        # Update baseline file
        jq --arg name "$function" --arg memory "$memory_size" --arg timeout "$timeout" \
           '. += [{"functionName": $name, "memorySize": ($memory | tonumber), "timeout": ($timeout | tonumber)}]' \
           "$config_file" > "${config_file}.tmp" && mv "${config_file}.tmp" "$config_file"
    done
    
    success "Lambda function information exported to $ANALYSIS_DIR"
}

# Create monitoring scripts
create_monitoring_scripts() {
    info "Creating monitoring and optimization scripts..."
    
    # Create performance monitoring script
    cat > "${ANALYSIS_DIR}/monitor-performance.sh" << 'EOF'
#!/bin/bash

# Performance monitoring script for optimized Lambda functions
set -e

LAMBDA_FUNCTIONS=$(aws lambda list-functions --query 'Functions[].FunctionName' --output text)
START_TIME=$(date -d '1 hour ago' '+%Y-%m-%dT%H:%M:%S')
END_TIME=$(date '+%Y-%m-%dT%H:%M:%S')

echo "Performance Monitor Report"
echo "Time Range: $START_TIME to $END_TIME"
echo "="*60

for function in $LAMBDA_FUNCTIONS; do
    echo "Function: $function"
    
    # Current memory configuration
    CURRENT_MEMORY=$(aws lambda get-function-configuration \
        --function-name $function \
        --query 'MemorySize' \
        --output text)
    echo "  Current Memory: $CURRENT_MEMORY MB"
    
    # Get recent performance metrics
    INVOCATIONS=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Invocations \
        --dimensions Name=FunctionName,Value=$function \
        --start-time $START_TIME \
        --end-time $END_TIME \
        --period 3600 \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    AVG_DURATION=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Duration \
        --dimensions Name=FunctionName,Value=$function \
        --start-time $START_TIME \
        --end-time $END_TIME \
        --period 3600 \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "0")
    
    ERROR_COUNT=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Errors \
        --dimensions Name=FunctionName,Value=$function \
        --start-time $START_TIME \
        --end-time $END_TIME \
        --period 3600 \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    echo "  Recent Invocations: $INVOCATIONS"
    echo "  Average Duration: ${AVG_DURATION} ms"
    echo "  Error Count: $ERROR_COUNT"
    echo "  Status: $([ "${ERROR_COUNT}" = "0" ] && echo "✅ Healthy" || echo "⚠️  Check for issues")"
    echo "---"
done
EOF

    chmod +x "${ANALYSIS_DIR}/monitor-performance.sh"
    
    # Create optimization application script
    cat > "${ANALYSIS_DIR}/apply-optimizations.sh" << 'EOF'
#!/bin/bash

# Apply Compute Optimizer recommendations with safety controls
set -e

RECOMMENDATIONS_FILE="compute-optimizer-recommendations.json"
SAVINGS_THRESHOLD=${1:-1.00}  # Default to $1/month minimum savings

if [ ! -f "$RECOMMENDATIONS_FILE" ]; then
    echo "Recommendations file not found. Run the analysis first."
    exit 1
fi

echo "Applying optimizations with savings >= \$${SAVINGS_THRESHOLD}/month"
echo ""

python3 << PYTHON_EOF
import json
import subprocess
import sys

try:
    with open('$RECOMMENDATIONS_FILE', 'r') as f:
        data = json.load(f)
except FileNotFoundError:
    print("Recommendations file not found")
    sys.exit(1)
except json.JSONDecodeError:
    print("Invalid JSON in recommendations file")
    sys.exit(1)

recommendations = data.get('lambdaFunctionRecommendations', [])
savings_threshold = float('$SAVINGS_THRESHOLD')

print(f"Found {len(recommendations)} recommendations")
print(f"Applying optimizations with savings >= \${savings_threshold:.2f}/month\\n")

total_applied = 0
total_savings = 0

for rec in recommendations:
    function_name = rec['functionName']
    finding = rec['finding']
    current_memory = rec['currentMemorySize']
    
    if finding != "Optimized" and 'memorySizeRecommendationOptions' in rec:
        best_option = rec['memorySizeRecommendationOptions'][0]
        recommended_memory = best_option['memorySize']
        savings = best_option.get('estimatedMonthlySavings', {}).get('value', 0)
        
        if savings >= savings_threshold:
            print(f"Optimizing {function_name}:")
            print(f"  {current_memory} MB → {recommended_memory} MB")
            print(f"  Expected savings: \${savings:.2f}/month")
            
            # Apply the optimization using AWS CLI
            cmd = [
                'aws', 'lambda', 'update-function-configuration',
                '--function-name', function_name,
                '--memory-size', str(recommended_memory)
            ]
            
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, check=True)
                print(f"  ✅ Successfully updated {function_name}")
                total_applied += 1
                total_savings += savings
            except subprocess.CalledProcessError as e:
                print(f"  ❌ Failed to update {function_name}: {e.stderr}")
            
            print()
        else:
            print(f"Skipping {function_name} (savings: \${savings:.2f} < threshold)")

print(f"\\nOptimization Summary:")
print(f"Functions optimized: {total_applied}")
print(f"Total expected monthly savings: \${total_savings:.2f}")
print(f"Total expected annual savings: \${total_savings * 12:.2f}")
print("\\nOptimization complete!")
PYTHON_EOF
EOF

    chmod +x "${ANALYSIS_DIR}/apply-optimizations.sh"
    
    # Create analysis script
    cat > "${ANALYSIS_DIR}/analyze-recommendations.sh" << 'EOF'
#!/bin/bash

# Analyze Compute Optimizer recommendations
set -e

echo "Retrieving Compute Optimizer recommendations..."

# Get recommendations and save to file
aws compute-optimizer get-lambda-function-recommendations \
    --output json > compute-optimizer-recommendations.json

# Display recommendations in table format
echo ""
echo "Lambda Function Recommendations Summary:"
echo "========================================"
aws compute-optimizer get-lambda-function-recommendations \
    --output table \
    --query 'lambdaFunctionRecommendations[*].[functionName,finding,currentMemorySize,memorySizeRecommendationOptions[0].memorySize,memorySizeRecommendationOptions[0].estimatedMonthlySavings.value]'

# Process recommendations with Python for detailed analysis
echo ""
echo "Detailed Analysis:"
echo "=================="

python3 << 'PYTHON_EOF'
import json
import os

try:
    with open('compute-optimizer-recommendations.json', 'r') as f:
        data = json.load(f)
except FileNotFoundError:
    print("No recommendations file found. May need to wait for Compute Optimizer to analyze functions.")
    exit(0)

recommendations = data.get('lambdaFunctionRecommendations', [])

if not recommendations:
    print("No recommendations available yet.")
    print("Compute Optimizer requires at least 14 days of metrics to generate recommendations.")
    exit(0)

print(f"Found {len(recommendations)} function recommendations\n")

total_potential_savings = 0
optimized_count = 0
under_provisioned_count = 0
over_provisioned_count = 0

for rec in recommendations:
    function_name = rec['functionName']
    finding = rec['finding']
    current_memory = rec['currentMemorySize']
    
    print(f"Function: {function_name}")
    print(f"  Current Status: {finding}")
    print(f"  Current Memory: {current_memory} MB")
    
    if finding == "Optimized":
        optimized_count += 1
        print("  ✅ Already optimized")
    else:
        # Get recommendation options
        if 'memorySizeRecommendationOptions' in rec:
            best_option = rec['memorySizeRecommendationOptions'][0]
            recommended_memory = best_option['memorySize']
            savings = best_option.get('estimatedMonthlySavings', {}).get('value', 0)
            
            print(f"  📊 Recommended Memory: {recommended_memory} MB")
            print(f"  💰 Estimated Monthly Savings: ${savings:.2f}")
            
            total_potential_savings += savings
            
            if current_memory > recommended_memory:
                over_provisioned_count += 1
                print("  ⬇️  Over-provisioned - Consider reducing memory")
            else:
                under_provisioned_count += 1
                print("  ⬆️  Under-provisioned - Consider increasing memory")
    
    print()

print("="*50)
print("OPTIMIZATION SUMMARY")
print("="*50)
print(f"Functions already optimized: {optimized_count}")
print(f"Over-provisioned functions: {over_provisioned_count}")
print(f"Under-provisioned functions: {under_provisioned_count}")
print(f"Total potential monthly savings: ${total_potential_savings:.2f}")
print(f"Potential annual savings: ${total_potential_savings * 12:.2f}")
PYTHON_EOF
EOF

    chmod +x "${ANALYSIS_DIR}/analyze-recommendations.sh"
    
    success "Monitoring and optimization scripts created in $ANALYSIS_DIR"
}

# Setup CloudWatch alarms for monitoring
setup_cloudwatch_alarms() {
    info "Setting up CloudWatch alarms for Lambda monitoring..."
    
    # Check if SNS topic exists, create if needed
    local sns_topic_arn="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:lambda-optimization-alerts"
    
    if ! aws sns get-topic-attributes --topic-arn "$sns_topic_arn" &>/dev/null; then
        info "Creating SNS topic for alerts..."
        aws sns create-topic --name lambda-optimization-alerts
        success "SNS topic created: lambda-optimization-alerts"
        warning "Remember to subscribe to the SNS topic to receive alerts"
    else
        success "SNS topic already exists"
    fi
    
    # Create CloudWatch alarm for high error rates
    aws cloudwatch put-metric-alarm \
        --alarm-name "Lambda-Optimization-High-Error-Rate" \
        --alarm-description "Monitor error rate after Lambda optimization" \
        --metric-name Errors \
        --namespace AWS/Lambda \
        --statistic Sum \
        --period 300 \
        --threshold 5 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 2 \
        --alarm-actions "$sns_topic_arn" \
        --ok-actions "$sns_topic_arn"
    
    success "CloudWatch alarm created: Lambda-Optimization-High-Error-Rate"
    
    # Create alarm for duration increases
    aws cloudwatch put-metric-alarm \
        --alarm-name "Lambda-Optimization-Duration-Increase" \
        --alarm-description "Monitor duration increase after optimization" \
        --metric-name Duration \
        --namespace AWS/Lambda \
        --statistic Average \
        --period 300 \
        --threshold 10000 \
        --comparison-operator GreaterThanThreshold \
        --evaluation-periods 3 \
        --alarm-actions "$sns_topic_arn" \
        --ok-actions "$sns_topic_arn"
    
    success "CloudWatch alarm created: Lambda-Optimization-Duration-Increase"
}

# Create README file
create_readme() {
    info "Creating README file..."
    
    cat > "${ANALYSIS_DIR}/README.md" << 'EOF'
# Lambda Cost Optimization Analysis

This directory contains tools and data for analyzing and optimizing AWS Lambda function costs using AWS Compute Optimizer.

## Files

- `lambda-functions-baseline.json` - Baseline configuration of all Lambda functions
- `compute-optimizer-recommendations.json` - Recommendations from AWS Compute Optimizer
- `monitor-performance.sh` - Script to monitor function performance after optimization
- `apply-optimizations.sh` - Script to apply optimization recommendations
- `analyze-recommendations.sh` - Script to analyze and display recommendations

## Usage

### 1. Analyze Current Recommendations

```bash
./analyze-recommendations.sh
```

This will fetch the latest recommendations from Compute Optimizer and display a summary.

### 2. Apply Optimizations

```bash
# Apply optimizations with default $1/month savings threshold
./apply-optimizations.sh

# Apply optimizations with custom savings threshold (e.g., $5/month)
./apply-optimizations.sh 5.00
```

### 3. Monitor Performance

```bash
# Monitor performance of optimized functions
./monitor-performance.sh
```

## Important Notes

- Compute Optimizer requires at least 14 days of metrics to generate recommendations
- It may take up to 24 hours after enabling for initial recommendations to appear
- Always monitor function performance after applying optimizations
- Consider testing optimizations in non-production environments first

## CloudWatch Alarms

The deployment script sets up CloudWatch alarms to monitor:
- High error rates after optimization
- Significant duration increases after optimization

Make sure to subscribe to the SNS topic `lambda-optimization-alerts` to receive notifications.
EOF

    success "README created in $ANALYSIS_DIR"
}

# Main deployment function
main() {
    log "Starting AWS Lambda Cost Optimizer deployment..."
    log "Timestamp: $(date)"
    log "Script: $0"
    log "Log file: $LOG_FILE"
    
    # Clear previous log
    > "$LOG_FILE"
    
    check_prerequisites
    setup_environment
    check_lambda_functions
    enable_compute_optimizer
    export_lambda_info
    create_monitoring_scripts
    setup_cloudwatch_alarms
    create_readme
    
    log ""
    success "Deployment completed successfully!"
    log ""
    info "Next steps:"
    log "1. Wait 24 hours for Compute Optimizer to generate initial recommendations"
    log "2. Run analysis script: cd $ANALYSIS_DIR && ./analyze-recommendations.sh"
    log "3. Apply optimizations: cd $ANALYSIS_DIR && ./apply-optimizations.sh"
    log "4. Monitor performance: cd $ANALYSIS_DIR && ./monitor-performance.sh"
    log ""
    warning "Remember to subscribe to the SNS topic 'lambda-optimization-alerts' for monitoring alerts"
    
    log "Deployment completed at: $(date)"
}

# Run main function
main "$@"