#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="MultiRegionDistributedApp"
PRIMARY_REGION="us-east-1"
SECONDARY_REGION="us-west-2"

echo -e "${RED}🗑️  Starting cleanup of Multi-Region Distributed Applications with Aurora DSQL${NC}"

# Warning prompt
echo -e "${YELLOW}⚠️  WARNING: This will permanently delete all resources created by this CDK application.${NC}"
echo -e "${YELLOW}This includes:${NC}"
echo "  - Aurora DSQL clusters in both regions"
echo "  - Lambda functions and their logs"
echo "  - EventBridge custom buses and rules"
echo "  - IAM roles and policies"
echo "  - All associated data"

read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo -e "${GREEN}Aborted. No resources were deleted.${NC}"
    exit 0
fi

# Get AWS account
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Failed to get AWS account ID. Please check your AWS credentials.${NC}"
    exit 1
fi

echo "Using AWS Account: $CDK_DEFAULT_ACCOUNT"

# Function to check if stack exists
stack_exists() {
    local region=$1
    local stack_name=$2
    aws cloudformation describe-stacks --region "$region" --stack-name "$stack_name" &>/dev/null
}

# Function to wait for stack deletion
wait_for_deletion() {
    local region=$1
    local stack_name=$2
    echo -e "${YELLOW}⏳ Waiting for stack deletion to complete in $region...${NC}"
    
    while stack_exists "$region" "$stack_name"; do
        local status=$(aws cloudformation describe-stacks \
            --region "$region" \
            --stack-name "$stack_name" \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "DELETE_COMPLETE")
        
        if [[ "$status" == "DELETE_FAILED" ]]; then
            echo -e "${RED}❌ Stack deletion failed in $region${NC}"
            aws cloudformation describe-stack-events \
                --region "$region" \
                --stack-name "$stack_name" \
                --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].{Resource:LogicalResourceId,Reason:ResourceStatusReason}' \
                --output table
            return 1
        fi
        
        if [[ "$status" == "DELETE_COMPLETE" ]]; then
            break
        fi
        
        echo "Stack status: $status (waiting...)"
        sleep 30
    done
}

# Delete secondary stack first (due to dependencies)
echo -e "${YELLOW}🗑️  Deleting secondary region stack...${NC}"
if stack_exists "$SECONDARY_REGION" "$PROJECT_NAME-Secondary-Stack"; then
    cdk destroy $PROJECT_NAME-Secondary --force
    
    if [ $? -eq 0 ]; then
        wait_for_deletion "$SECONDARY_REGION" "$PROJECT_NAME-Secondary-Stack"
        echo -e "${GREEN}✅ Secondary stack deleted successfully${NC}"
    else
        echo -e "${RED}❌ Failed to initiate secondary stack deletion${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}ℹ️  Secondary stack not found, skipping...${NC}"
fi

# Delete primary stack
echo -e "${YELLOW}🗑️  Deleting primary region stack...${NC}"
if stack_exists "$PRIMARY_REGION" "$PROJECT_NAME-Primary-Stack"; then
    cdk destroy $PROJECT_NAME-Primary --force
    
    if [ $? -eq 0 ]; then
        wait_for_deletion "$PRIMARY_REGION" "$PROJECT_NAME-Primary-Stack"
        echo -e "${GREEN}✅ Primary stack deleted successfully${NC}"
    else
        echo -e "${RED}❌ Failed to initiate primary stack deletion${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}ℹ️  Primary stack not found, skipping...${NC}"
fi

# Verify cleanup
echo -e "${YELLOW}🔍 Verifying resource cleanup...${NC}"

# Check for remaining Aurora DSQL clusters
echo "Checking for Aurora DSQL clusters..."
PRIMARY_CLUSTERS=$(aws dsql list-clusters --region $PRIMARY_REGION --query 'clusters[?contains(tags[].value, `DistributedApp`)]' --output json 2>/dev/null || echo "[]")
SECONDARY_CLUSTERS=$(aws dsql list-clusters --region $SECONDARY_REGION --query 'clusters[?contains(tags[].value, `DistributedApp`)]' --output json 2>/dev/null || echo "[]")

if [[ "$PRIMARY_CLUSTERS" != "[]" ]]; then
    echo -e "${YELLOW}⚠️  Found remaining Aurora DSQL clusters in primary region${NC}"
    echo "$PRIMARY_CLUSTERS"
fi

if [[ "$SECONDARY_CLUSTERS" != "[]" ]]; then
    echo -e "${YELLOW}⚠️  Found remaining Aurora DSQL clusters in secondary region${NC}"
    echo "$SECONDARY_CLUSTERS"
fi

# Check for remaining Lambda functions
echo "Checking for Lambda functions..."
PRIMARY_FUNCTIONS=$(aws lambda list-functions --region $PRIMARY_REGION --query 'Functions[?contains(FunctionName, `DSQLProcessor`) || contains(FunctionName, `DistributedApp`)].[FunctionName]' --output text 2>/dev/null || echo "")
SECONDARY_FUNCTIONS=$(aws lambda list-functions --region $SECONDARY_REGION --query 'Functions[?contains(FunctionName, `DSQLProcessor`) || contains(FunctionName, `DistributedApp`)].[FunctionName]' --output text 2>/dev/null || echo "")

if [[ -n "$PRIMARY_FUNCTIONS" ]]; then
    echo -e "${YELLOW}⚠️  Found remaining Lambda functions in primary region: $PRIMARY_FUNCTIONS${NC}"
fi

if [[ -n "$SECONDARY_FUNCTIONS" ]]; then
    echo -e "${YELLOW}⚠️  Found remaining Lambda functions in secondary region: $SECONDARY_FUNCTIONS${NC}"
fi

# Check for EventBridge custom buses
echo "Checking for EventBridge custom buses..."
PRIMARY_BUSES=$(aws events list-event-buses --region $PRIMARY_REGION --query 'EventBuses[?contains(Name, `dsql-events`)].[Name]' --output text 2>/dev/null || echo "")
SECONDARY_BUSES=$(aws events list-event-buses --region $SECONDARY_REGION --query 'EventBuses[?contains(Name, `dsql-events`)].[Name]' --output text 2>/dev/null || echo "")

if [[ -n "$PRIMARY_BUSES" ]]; then
    echo -e "${YELLOW}⚠️  Found remaining EventBridge buses in primary region: $PRIMARY_BUSES${NC}"
fi

if [[ -n "$SECONDARY_BUSES" ]]; then
    echo -e "${YELLOW}⚠️  Found remaining EventBridge buses in secondary region: $SECONDARY_BUSES${NC}"
fi

# Clean up local files
echo -e "${YELLOW}🧹 Cleaning up local files...${NC}"
rm -rf cdk.out/
rm -rf lib/
rm -f *.json
rm -f npm-debug.log*

echo -e "\n${GREEN}✅ Cleanup completed!${NC}"

# Summary
echo -e "\n${GREEN}📋 Cleanup Summary:${NC}"
echo "✅ CDK stacks destroyed"
echo "✅ Local build artifacts cleaned"

if [[ "$PRIMARY_CLUSTERS" != "[]" ]] || [[ "$SECONDARY_CLUSTERS" != "[]" ]] || [[ -n "$PRIMARY_FUNCTIONS" ]] || [[ -n "$SECONDARY_FUNCTIONS" ]] || [[ -n "$PRIMARY_BUSES" ]] || [[ -n "$SECONDARY_BUSES" ]]; then
    echo -e "\n${YELLOW}⚠️  Some resources may still exist. Please check the AWS console and clean up manually if needed.${NC}"
else
    echo -e "\n${GREEN}🎉 All resources have been successfully cleaned up!${NC}"
fi

echo -e "\n${YELLOW}💰 Cost Optimization Tip:${NC}"
echo "If you're not planning to redeploy soon, consider removing the CDK bootstrap stacks as well:"
echo "aws cloudformation delete-stack --region $PRIMARY_REGION --stack-name CDKToolkit"
echo "aws cloudformation delete-stack --region $SECONDARY_REGION --stack-name CDKToolkit"