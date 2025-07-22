#!/bin/bash

# VPA Recommendations Report Generator
# This script generates comprehensive reports on VPA recommendations and resource usage

set -e

# Configuration
NAMESPACE="${namespace}"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S UTC')
REPORT_FILE="vpa-recommendations-$(date '+%Y%m%d-%H%M%S').txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_header() {
    echo -e "${BLUE}===========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check if kubectl is available and cluster is accessible
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        print_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
    echo ""
}

# Function to check VPA installation
check_vpa_installation() {
    print_header "VPA Installation Status"
    
    # Check if VPA CRD exists
    if kubectl get crd verticalpodautoscalers.autoscaling.k8s.io &> /dev/null; then
        print_success "VPA CRD is installed"
    else
        print_error "VPA CRD not found - VPA may not be installed"
        return 1
    fi
    
    # Check VPA components
    echo -e "\n${BLUE}VPA Components Status:${NC}"
    kubectl get pods -n kube-system -l app.kubernetes.io/name=vpa -o wide 2>/dev/null || {
        echo "No VPA pods found with standard labels, trying alternative labels..."
        kubectl get pods -n kube-system | grep vpa || print_warning "No VPA pods found"
    }
    
    echo ""
}

# Function to display current resource usage
show_current_usage() {
    print_header "Current Resource Usage"
    
    echo -e "${BLUE}Pod Resource Usage in namespace '$NAMESPACE':${NC}"
    if kubectl top pods -n "$NAMESPACE" 2>/dev/null; then
        print_success "Resource usage data retrieved"
    else
        print_warning "Unable to retrieve resource usage - metrics server may not be available"
    fi
    
    echo -e "\n${BLUE}Node Resource Usage:${NC}"
    if kubectl top nodes 2>/dev/null; then
        print_success "Node resource data retrieved"
    else
        print_warning "Unable to retrieve node resource usage"
    fi
    
    echo ""
}

# Function to show VPA recommendations
show_vpa_recommendations() {
    print_header "VPA Recommendations"
    
    # Get all VPA objects in the namespace
    VPA_OBJECTS=$(kubectl get vpa -n "$NAMESPACE" -o name 2>/dev/null || echo "")
    
    if [ -z "$VPA_OBJECTS" ]; then
        print_warning "No VPA objects found in namespace '$NAMESPACE'"
        return 0
    fi
    
    echo -e "${BLUE}VPA Objects Summary:${NC}"
    kubectl get vpa -n "$NAMESPACE" -o custom-columns=\
"NAME:.metadata.name,TARGET:.spec.targetRef.name,MODE:.spec.updatePolicy.updateMode,CPU_REC:.status.recommendation.containerRecommendations[0].target.cpu,MEMORY_REC:.status.recommendation.containerRecommendations[0].target.memory,LAST_UPDATE:.status.lastUpdateTime" 2>/dev/null || {
        kubectl get vpa -n "$NAMESPACE" 2>/dev/null || print_error "Failed to get VPA objects"
    }
    
    echo ""
    
    # Detailed recommendations for each VPA
    for vpa in $VPA_OBJECTS; do
        VPA_NAME=$(echo "$vpa" | cut -d'/' -f2)
        echo -e "${BLUE}Detailed Recommendations for VPA: $VPA_NAME${NC}"
        echo "-------------------------------------------"
        
        # Get VPA details
        kubectl describe vpa "$VPA_NAME" -n "$NAMESPACE" 2>/dev/null || {
            print_error "Failed to get details for VPA '$VPA_NAME'"
            continue
        }
        
        echo ""
        
        # Extract and format recommendations
        echo -e "${BLUE}Resource Recommendations Analysis:${NC}"
        
        # Get current and recommended resources
        CURRENT_CPU=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="'$VPA_NAME'")].spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "N/A")
        CURRENT_MEM=$(kubectl get deployment -n "$NAMESPACE" -o jsonpath='{.items[?(@.metadata.name=="'$VPA_NAME'")].spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "N/A")
        
        REC_CPU=$(kubectl get vpa "$VPA_NAME" -n "$NAMESPACE" -o jsonpath='{.status.recommendation.containerRecommendations[0].target.cpu}' 2>/dev/null || echo "N/A")
        REC_MEM=$(kubectl get vpa "$VPA_NAME" -n "$NAMESPACE" -o jsonpath='{.status.recommendation.containerRecommendations[0].target.memory}' 2>/dev/null || echo "N/A")
        
        echo "  Current CPU Request:    $CURRENT_CPU"
        echo "  Recommended CPU:        $REC_CPU"
        echo "  Current Memory Request: $CURRENT_MEM"
        echo "  Recommended Memory:     $REC_MEM"
        
        # Calculate potential savings if both values are available
        if [[ "$CURRENT_CPU" != "N/A" && "$REC_CPU" != "N/A" ]]; then
            calculate_savings "$CURRENT_CPU" "$REC_CPU" "CPU"
        fi
        
        if [[ "$CURRENT_MEM" != "N/A" && "$REC_MEM" != "N/A" ]]; then
            calculate_savings "$CURRENT_MEM" "$REC_MEM" "Memory"
        fi
        
        echo ""
    done
}

# Function to calculate potential savings
calculate_savings() {
    local current="$1"
    local recommended="$2"
    local resource_type="$3"
    
    # Simple calculation for demonstration (this is a simplified version)
    if [[ "$current" =~ ^[0-9]+m$ && "$recommended" =~ ^[0-9]+m$ ]]; then
        current_val=${current%m}
        rec_val=${recommended%m}
        if [ "$current_val" -gt 0 ]; then
            savings_percent=$(( (current_val - rec_val) * 100 / current_val ))
            if [ "$savings_percent" -gt 0 ]; then
                print_success "$resource_type savings: ${savings_percent}% reduction possible"
            elif [ "$savings_percent" -lt 0 ]; then
                print_warning "$resource_type increase: $((-savings_percent))% increase recommended"
            else
                echo "  $resource_type: No change recommended"
            fi
        fi
    fi
}

# Function to show deployment resource configurations
show_deployment_resources() {
    print_header "Current Deployment Resource Configurations"
    
    echo -e "${BLUE}Deployments in namespace '$NAMESPACE':${NC}"
    
    DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" -o name 2>/dev/null || echo "")
    
    if [ -z "$DEPLOYMENTS" ]; then
        print_warning "No deployments found in namespace '$NAMESPACE'"
        return 0
    fi
    
    for deployment in $DEPLOYMENTS; do
        DEPLOY_NAME=$(echo "$deployment" | cut -d'/' -f2)
        echo ""
        echo -e "${BLUE}Deployment: $DEPLOY_NAME${NC}"
        echo "----------------------------"
        
        # Get resource requests and limits
        kubectl get deployment "$DEPLOY_NAME" -n "$NAMESPACE" -o jsonpath='{range .spec.template.spec.containers[*]}Container: {.name}{"\n"}  CPU Request: {.resources.requests.cpu}{"\n"}  Memory Request: {.resources.requests.memory}{"\n"}  CPU Limit: {.resources.limits.cpu}{"\n"}  Memory Limit: {.resources.limits.memory}{"\n"}{end}' 2>/dev/null || {
            print_error "Failed to get resource configuration for deployment '$DEPLOY_NAME'"
        }
    done
    
    echo ""
}

# Function to show cost optimization recommendations
show_cost_optimization_tips() {
    print_header "Cost Optimization Recommendations"
    
    cat << EOF
${YELLOW}General Cost Optimization Tips:${NC}

1. ${GREEN}Right-Size Resources:${NC}
   - Use VPA recommendations to adjust CPU and memory requests
   - Start with VPA in "Off" mode to review recommendations
   - Gradually enable "Auto" mode for non-critical workloads

2. ${GREEN}Monitor Resource Utilization:${NC}
   - Aim for 70-80% CPU and memory utilization
   - Use CloudWatch Container Insights for detailed monitoring
   - Set up alerts for underutilized resources

3. ${GREEN}Implement Resource Limits:${NC}
   - Set appropriate resource limits to prevent resource hogging
   - Use QoS classes effectively (Guaranteed, Burstable, BestEffort)
   - Consider using LimitRanges and ResourceQuotas

4. ${GREEN}Optimize Node Utilization:${NC}
   - Use Cluster Autoscaler to adjust node count based on demand
   - Consider using Spot instances for cost savings
   - Implement node affinity and anti-affinity rules

5. ${GREEN}Regular Review Process:${NC}
   - Review VPA recommendations weekly
   - Analyze cost trends monthly
   - Update resource configurations based on usage patterns

${YELLOW}Next Steps:${NC}
- Review the VPA recommendations above
- Test recommendations in a non-production environment first
- Monitor application performance after applying changes
- Set up automated alerting for resource efficiency

EOF
}

# Function to generate cost estimation
estimate_cost_savings() {
    print_header "Cost Savings Estimation"
    
    echo -e "${BLUE}Estimated Cost Impact:${NC}"
    echo "Note: This is a simplified calculation for demonstration purposes."
    echo ""
    
    # Get cluster information
    local node_count
    node_count=$(kubectl get nodes --no-headers | wc -l)
    
    echo "Cluster Information:"
    echo "  Total Nodes: $node_count"
    echo "  Namespace: $NAMESPACE"
    echo ""
    
    # Calculate potential savings based on resource recommendations
    local total_pods
    total_pods=$(kubectl get pods -n "$NAMESPACE" --no-headers | wc -l)
    
    if [ "$total_pods" -gt 0 ]; then
        echo "Workload Information:"
        echo "  Total Pods in namespace: $total_pods"
        echo ""
        
        echo -e "${YELLOW}Potential Monthly Savings (Estimated):${NC}"
        echo "  - 20-30% reduction in overprovisioned CPU resources"
        echo "  - 15-25% reduction in overprovisioned memory resources"
        echo "  - Estimated total savings: 15-40% of container infrastructure costs"
        echo ""
        echo "Note: Actual savings depend on current resource utilization and pricing model."
    else
        print_warning "No pods found in namespace '$NAMESPACE' for cost calculation"
    fi
}

# Function to save report to file
save_report() {
    local report_content="$1"
    echo "$report_content" > "$REPORT_FILE"
    print_success "Report saved to: $REPORT_FILE"
}

# Main execution function
main() {
    echo "VPA Recommendations Report Generator"
    echo "Generated on: $TIMESTAMP"
    echo "Namespace: $NAMESPACE"
    echo ""
    
    # Capture all output for report
    {
        echo "VPA RECOMMENDATIONS REPORT"
        echo "=========================="
        echo "Generated: $TIMESTAMP"
        echo "Namespace: $NAMESPACE"
        echo ""
        
        check_prerequisites
        check_vpa_installation
        show_current_usage
        show_deployment_resources
        show_vpa_recommendations
        estimate_cost_savings
        show_cost_optimization_tips
        
    } | tee >(sed 's/\x1b\[[0-9;]*m//g' > "$REPORT_FILE")
    
    echo ""
    print_success "VPA recommendations report completed!"
    print_success "Report saved to: $REPORT_FILE"
    
    echo ""
    echo -e "${BLUE}To apply VPA recommendations:${NC}"
    echo "1. Review the recommendations carefully"
    echo "2. Test in a non-production environment first"
    echo "3. Apply changes gradually"
    echo "4. Monitor application performance"
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi