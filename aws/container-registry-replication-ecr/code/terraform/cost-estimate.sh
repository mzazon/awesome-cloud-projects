#!/bin/bash

# Cost Estimation Script for ECR Container Registry Replication Strategies
# This script provides cost estimates for the deployed infrastructure

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}$1${NC}"
}

print_info() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

# Function to calculate ECR storage costs
calculate_ecr_costs() {
    print_header "ECR Storage Costs"
    echo "=================="
    
    local storage_gb=${1:-10}  # Default 10GB
    local regions=${2:-3}      # Default 3 regions
    
    # ECR pricing (approximate, varies by region)
    local ecr_storage_cost_per_gb=0.10  # $0.10 per GB per month
    
    local total_storage_cost=$(echo "$storage_gb * $ecr_storage_cost_per_gb * $regions" | bc -l)
    
    echo "Storage assumptions:"
    echo "  • Average storage per region: ${storage_gb}GB"
    echo "  • Number of regions: $regions"
    echo "  • Storage cost per GB: \$${ecr_storage_cost_per_gb}/month"
    echo ""
    echo "Monthly storage cost: \$$(printf "%.2f" $total_storage_cost)"
    echo ""
}

# Function to calculate data transfer costs
calculate_data_transfer_costs() {
    print_header "Data Transfer Costs"
    echo "==================="
    
    local monthly_pushes=${1:-100}     # Default 100 pushes per month
    local avg_image_size=${2:-1}       # Default 1GB average image size
    local regions=${3:-3}              # Default 3 regions
    
    # Data transfer pricing (approximate)
    local data_transfer_out_cost=0.09   # $0.09 per GB
    local inter_region_cost=0.02        # $0.02 per GB between regions
    
    # Calculate replication data transfer
    local replication_gb=$(echo "$monthly_pushes * $avg_image_size * ($regions - 1)" | bc -l)
    local replication_cost=$(echo "$replication_gb * $inter_region_cost" | bc -l)
    
    # Calculate outbound data transfer (pulls)
    local monthly_pulls=${4:-500}       # Default 500 pulls per month
    local pull_gb=$(echo "$monthly_pulls * $avg_image_size" | bc -l)
    local pull_cost=$(echo "$pull_gb * $data_transfer_out_cost" | bc -l)
    
    echo "Data transfer assumptions:"
    echo "  • Monthly pushes: $monthly_pushes"
    echo "  • Average image size: ${avg_image_size}GB"
    echo "  • Monthly pulls: $monthly_pulls"
    echo "  • Inter-region cost: \$${inter_region_cost}/GB"
    echo "  • Outbound cost: \$${data_transfer_out_cost}/GB"
    echo ""
    echo "Monthly replication cost: \$$(printf "%.2f" $replication_cost)"
    echo "Monthly pull cost: \$$(printf "%.2f" $pull_cost)"
    echo ""
}

# Function to calculate monitoring costs
calculate_monitoring_costs() {
    print_header "CloudWatch Monitoring Costs"
    echo "============================"
    
    local custom_metrics=${1:-10}      # Default 10 custom metrics
    local alarms=${2:-5}               # Default 5 alarms
    local dashboard_widgets=${3:-10}    # Default 10 dashboard widgets
    
    # CloudWatch pricing (approximate)
    local metric_cost=0.30              # $0.30 per metric per month
    local alarm_cost=0.10               # $0.10 per alarm per month
    local dashboard_cost=3.00           # $3.00 per dashboard per month
    
    local total_metric_cost=$(echo "$custom_metrics * $metric_cost" | bc -l)
    local total_alarm_cost=$(echo "$alarms * $alarm_cost" | bc -l)
    
    echo "Monitoring assumptions:"
    echo "  • Custom metrics: $custom_metrics"
    echo "  • CloudWatch alarms: $alarms"
    echo "  • Dashboard widgets: $dashboard_widgets"
    echo ""
    echo "Monthly metrics cost: \$$(printf "%.2f" $total_metric_cost)"
    echo "Monthly alarms cost: \$$(printf "%.2f" $total_alarm_cost)"
    echo "Monthly dashboard cost: \$$(printf "%.2f" $dashboard_cost)"
    echo ""
}

# Function to calculate Lambda costs
calculate_lambda_costs() {
    print_header "Lambda Function Costs"
    echo "====================="
    
    local executions_per_month=${1:-30}  # Default 30 executions (daily)
    local avg_duration=${2:-30}          # Default 30 seconds per execution
    local memory_mb=${3:-256}            # Default 256MB memory
    
    # Lambda pricing (approximate)
    local request_cost=0.0000002         # $0.0000002 per request
    local gb_second_cost=0.0000166667    # $0.0000166667 per GB-second
    
    local total_requests_cost=$(echo "$executions_per_month * $request_cost" | bc -l)
    local gb_seconds=$(echo "$executions_per_month * $avg_duration * $memory_mb / 1024" | bc -l)
    local compute_cost=$(echo "$gb_seconds * $gb_second_cost" | bc -l)
    
    echo "Lambda assumptions:"
    echo "  • Executions per month: $executions_per_month"
    echo "  • Average duration: ${avg_duration}s"
    echo "  • Memory allocation: ${memory_mb}MB"
    echo ""
    echo "Monthly request cost: \$$(printf "%.6f" $total_requests_cost)"
    echo "Monthly compute cost: \$$(printf "%.6f" $compute_cost)"
    echo ""
}

# Function to calculate SNS costs
calculate_sns_costs() {
    print_header "SNS Notification Costs"
    echo "======================"
    
    local notifications_per_month=${1:-10}  # Default 10 notifications
    local email_notifications=${2:-10}      # Default 10 email notifications
    
    # SNS pricing (approximate)
    local sns_publish_cost=0.0000005       # $0.0000005 per request
    local email_cost=0.000002              # $0.000002 per email
    
    local publish_cost=$(echo "$notifications_per_month * $sns_publish_cost" | bc -l)
    local email_delivery_cost=$(echo "$email_notifications * $email_cost" | bc -l)
    
    echo "SNS assumptions:"
    echo "  • Notifications per month: $notifications_per_month"
    echo "  • Email notifications: $email_notifications"
    echo ""
    echo "Monthly publish cost: \$$(printf "%.6f" $publish_cost)"
    echo "Monthly email cost: \$$(printf "%.6f" $email_delivery_cost)"
    echo ""
}

# Function to calculate total estimated costs
calculate_total_costs() {
    print_header "Total Monthly Cost Estimate"
    echo "============================"
    
    # Get parameters or use defaults
    local storage_gb=${1:-10}
    local monthly_pushes=${2:-100}
    local avg_image_size=${3:-1}
    local monthly_pulls=${4:-500}
    local regions=${5:-3}
    
    # Calculate individual costs
    local ecr_storage=$(echo "$storage_gb * 0.10 * $regions" | bc -l)
    local replication_transfer=$(echo "$monthly_pushes * $avg_image_size * ($regions - 1) * 0.02" | bc -l)
    local pull_transfer=$(echo "$monthly_pulls * $avg_image_size * 0.09" | bc -l)
    local monitoring=$(echo "10 * 0.30 + 5 * 0.10 + 3.00" | bc -l)
    local lambda=$(echo "30 * 0.0000002 + 30 * 30 * 256 / 1024 * 0.0000166667" | bc -l)
    local sns=$(echo "10 * 0.0000005 + 10 * 0.000002" | bc -l)
    
    # Calculate total
    local total=$(echo "$ecr_storage + $replication_transfer + $pull_transfer + $monitoring + $lambda + $sns" | bc -l)
    
    echo "Cost breakdown:"
    echo "  • ECR Storage: \$$(printf "%.2f" $ecr_storage)"
    echo "  • Replication Transfer: \$$(printf "%.2f" $replication_transfer)"
    echo "  • Pull Transfer: \$$(printf "%.2f" $pull_transfer)"
    echo "  • CloudWatch Monitoring: \$$(printf "%.2f" $monitoring)"
    echo "  • Lambda Functions: \$$(printf "%.4f" $lambda)"
    echo "  • SNS Notifications: \$$(printf "%.4f" $sns)"
    echo "  ─────────────────────────"
    echo "  • Total Monthly: \$$(printf "%.2f" $total)"
    echo ""
    
    # Calculate annual cost
    local annual=$(echo "$total * 12" | bc -l)
    echo "Estimated Annual Cost: \$$(printf "%.2f" $annual)"
    echo ""
}

# Function to show cost optimization tips
show_optimization_tips() {
    print_header "Cost Optimization Tips"
    echo "======================"
    
    echo "1. Storage Optimization:"
    echo "   • Configure aggressive lifecycle policies for testing repositories"
    echo "   • Use image layer caching to reduce storage duplication"
    echo "   • Monitor repository sizes regularly"
    echo ""
    
    echo "2. Data Transfer Optimization:"
    echo "   • Use repository filtering to replicate only necessary images"
    echo "   • Pull images from the nearest region"
    echo "   • Implement image compression strategies"
    echo ""
    
    echo "3. Monitoring Optimization:"
    echo "   • Use composite alarms to reduce alarm count"
    echo "   • Set appropriate alarm thresholds to avoid false positives"
    echo "   • Archive old CloudWatch logs regularly"
    echo ""
    
    echo "4. Lambda Optimization:"
    echo "   • Optimize Lambda function execution time"
    echo "   • Use appropriate memory allocation"
    echo "   • Consider using EventBridge scheduled rules instead of frequent executions"
    echo ""
    
    echo "5. General Tips:"
    echo "   • Enable AWS Cost Explorer for detailed cost analysis"
    echo "   • Set up billing alerts for cost monitoring"
    echo "   • Review and adjust resource usage regularly"
    echo "   • Consider using AWS Cost Optimization Hub recommendations"
    echo ""
}

# Function to show usage help
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Calculate cost estimates for ECR Container Registry Replication Strategies"
    echo ""
    echo "Options:"
    echo "  -s, --storage GB        Average storage per region (default: 10GB)"
    echo "  -p, --pushes NUM        Monthly pushes (default: 100)"
    echo "  -i, --image-size GB     Average image size (default: 1GB)"
    echo "  -u, --pulls NUM         Monthly pulls (default: 500)"
    echo "  -r, --regions NUM       Number of regions (default: 3)"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                      # Use default values"
    echo "  $0 -s 20 -p 200 -i 2    # 20GB storage, 200 pushes, 2GB images"
    echo "  $0 --storage 50 --pushes 500 --image-size 0.5 --pulls 1000 --regions 2"
    echo ""
}

# Parse command line arguments
STORAGE_GB=10
MONTHLY_PUSHES=100
AVG_IMAGE_SIZE=1
MONTHLY_PULLS=500
REGIONS=3

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--storage)
            STORAGE_GB="$2"
            shift 2
            ;;
        -p|--pushes)
            MONTHLY_PUSHES="$2"
            shift 2
            ;;
        -i|--image-size)
            AVG_IMAGE_SIZE="$2"
            shift 2
            ;;
        -u|--pulls)
            MONTHLY_PULLS="$2"
            shift 2
            ;;
        -r|--regions)
            REGIONS="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "ECR Container Registry Replication Strategies - Cost Estimation"
    echo "=============================================================="
    echo ""
    
    print_warning "Note: These are approximate costs based on US East (N. Virginia) pricing."
    print_warning "Actual costs may vary based on region, usage patterns, and AWS pricing changes."
    echo ""
    
    calculate_ecr_costs $STORAGE_GB $REGIONS
    calculate_data_transfer_costs $MONTHLY_PUSHES $AVG_IMAGE_SIZE $REGIONS $MONTHLY_PULLS
    calculate_monitoring_costs
    calculate_lambda_costs
    calculate_sns_costs
    calculate_total_costs $STORAGE_GB $MONTHLY_PUSHES $AVG_IMAGE_SIZE $MONTHLY_PULLS $REGIONS
    show_optimization_tips
    
    echo ""
    print_info "For accurate pricing, use the AWS Pricing Calculator: https://calculator.aws/"
    print_info "Enable AWS Cost Explorer for detailed cost analysis and recommendations."
}

# Check if bc is available
if ! command -v bc &> /dev/null; then
    echo "Error: 'bc' calculator is required but not installed."
    echo "Please install it using your package manager (e.g., apt-get install bc, yum install bc)"
    exit 1
fi

# Run main function
main