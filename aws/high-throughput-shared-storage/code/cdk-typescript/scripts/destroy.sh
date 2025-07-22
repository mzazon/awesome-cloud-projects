#!/bin/bash

# High-Performance File Systems with Amazon FSx - CDK Destruction Script
# This script removes all FSx infrastructure deployed by CDK

set -e

echo "🗑️  Starting destruction of High-Performance File Systems infrastructure..."

# Check prerequisites
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI is required but not installed. Aborting." >&2; exit 1; }
command -v npx >/dev/null 2>&1 || { echo "❌ npx is required but not installed. Aborting." >&2; exit 1; }

# Verify AWS credentials
echo "🔐 Checking AWS credentials..."
aws sts get-caller-identity > /dev/null || { echo "❌ AWS credentials not configured. Please run 'aws configure' first." >&2; exit 1; }

# Set environment variables
export CDK_DEFAULT_REGION=${AWS_REGION:-$(aws configure get region)}
export CDK_DEFAULT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)

echo "📍 Destroying resources in region: $CDK_DEFAULT_REGION"
echo "🏠 Using account: $CDK_DEFAULT_ACCOUNT"

# Warning about costs
echo ""
echo "⚠️  WARNING: This will permanently delete all FSx file systems and data!"
echo "⚠️  Make sure you have backed up any important data before proceeding."
echo "⚠️  This action cannot be undone."
echo ""

# Show what will be destroyed
echo "📋 Resources to be destroyed:"
echo "• FSx for Lustre file system and all data"
echo "• FSx for Windows file system and all data"
echo "• FSx for NetApp ONTAP file system and all data (if deployed)"
echo "• S3 bucket and all contents"
echo "• EC2 test instances"
echo "• CloudWatch alarms and log groups"
echo "• Security groups and IAM roles"
echo ""

# Double confirmation
read -p "🤔 Are you absolutely sure you want to destroy ALL resources? Type 'yes' to confirm: " -r
echo
if [[ ! $REPLY == "yes" ]]; then
    echo "❌ Destruction cancelled"
    exit 1
fi

echo "⏳ Starting destruction process..."

# Additional safety check - list stacks
echo "📋 Checking for existing stacks..."
if ! aws cloudformation describe-stacks --stack-name HighPerformanceFileSystemsStack --region $CDK_DEFAULT_REGION > /dev/null 2>&1; then
    echo "ℹ️  No stack found to destroy"
    exit 0
fi

# Show diff before destruction
echo "📋 Showing destruction diff..."
npx cdk diff

echo ""
echo "⏳ This may take 10-15 minutes as FSx file systems take time to delete..."

# Destroy the stack
npx cdk destroy --force

echo ""
echo "✅ Destruction completed successfully!"
echo ""
echo "💰 All FSx file systems, storage, and compute resources have been removed."
echo "💰 You should no longer incur charges for these resources."
echo ""
echo "🔍 Please verify in the AWS Console that all resources are deleted:"
echo "• FSx console: https://console.aws.amazon.com/fsx/"
echo "• EC2 console: https://console.aws.amazon.com/ec2/"
echo "• S3 console: https://console.aws.amazon.com/s3/"
echo "• CloudFormation console: https://console.aws.amazon.com/cloudformation/"
echo ""