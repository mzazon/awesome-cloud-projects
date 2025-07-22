#!/bin/bash
# Quality Gate Script for CodeGuru Automation
# This script checks CodeGuru recommendations against quality thresholds

set -e

CODE_REVIEW_ARN=$1
MAX_SEVERITY_THRESHOLD="${max_severity_threshold}"
LAMBDA_FUNCTION_NAME="${lambda_function_name}"

if [ -z "$CODE_REVIEW_ARN" ]; then
    echo "Usage: $0 <code-review-arn>"
    echo "Example: $0 arn:aws:codeguru-reviewer:us-east-1:123456789012:code-review/12345678-1234-1234-1234-123456789012"
    exit 1
fi

echo "🔍 Checking code review quality gate..."
echo "Code Review ARN: $CODE_REVIEW_ARN"
echo "Severity Threshold: $MAX_SEVERITY_THRESHOLD"

# Check if Lambda function is available
if [ -n "$LAMBDA_FUNCTION_NAME" ]; then
    echo "📋 Using Lambda function for quality gate evaluation..."
    
    # Invoke Lambda function for quality gate check
    LAMBDA_RESULT=$(aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$(echo "{\"code_review_arn\":\"$CODE_REVIEW_ARN\"}" | base64)" \
        --output text \
        --query 'Payload' \
        /tmp/lambda_output.json 2>/dev/null)
    
    # Parse Lambda response
    if [ -f /tmp/lambda_output.json ]; then
        LAMBDA_OUTPUT=$(cat /tmp/lambda_output.json)
        QUALITY_GATE_PASSED=$(echo "$LAMBDA_OUTPUT" | jq -r '.quality_gate_passed // false')
        QUALITY_GATE_MESSAGE=$(echo "$LAMBDA_OUTPUT" | jq -r '.quality_gate_message // "Unknown status"')
        
        echo "📊 Quality Gate Result: $QUALITY_GATE_MESSAGE"
        
        if [ "$QUALITY_GATE_PASSED" = "true" ]; then
            echo "✅ Quality gate passed!"
            exit 0
        else
            echo "❌ Quality gate failed!"
            exit 1
        fi
    else
        echo "⚠️  Lambda function unavailable, falling back to CLI check..."
    fi
fi

# Fallback to CLI-based quality gate check
echo "📋 Performing CLI-based quality gate evaluation..."

# Get recommendations
echo "📋 Fetching recommendations..."
RECOMMENDATIONS=$(aws codeguru-reviewer list-recommendations \
    --code-review-arn "$CODE_REVIEW_ARN" \
    --query 'RecommendationSummaries[].{Description:Description,Severity:Severity,File:FilePath}' \
    --output json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch recommendations. Please check the code review ARN and permissions."
    exit 1
fi

# Count recommendations by severity
HIGH_SEVERITY=$(echo "$RECOMMENDATIONS" | jq '[.[] | select(.Severity == "HIGH")] | length' 2>/dev/null || echo "0")
CRITICAL_SEVERITY=$(echo "$RECOMMENDATIONS" | jq '[.[] | select(.Severity == "CRITICAL")] | length' 2>/dev/null || echo "0")
MEDIUM_SEVERITY=$(echo "$RECOMMENDATIONS" | jq '[.[] | select(.Severity == "MEDIUM")] | length' 2>/dev/null || echo "0")
LOW_SEVERITY=$(echo "$RECOMMENDATIONS" | jq '[.[] | select(.Severity == "LOW")] | length' 2>/dev/null || echo "0")
INFO_SEVERITY=$(echo "$RECOMMENDATIONS" | jq '[.[] | select(.Severity == "INFO")] | length' 2>/dev/null || echo "0")

echo ""
echo "📊 Code Review Results:"
echo "   Critical Severity Issues: $CRITICAL_SEVERITY"
echo "   High Severity Issues: $HIGH_SEVERITY"
echo "   Medium Severity Issues: $MEDIUM_SEVERITY"
echo "   Low Severity Issues: $LOW_SEVERITY"
echo "   Info Severity Issues: $INFO_SEVERITY"
echo ""

# Determine quality gate result based on threshold
QUALITY_GATE_FAILED=false
FAILURE_REASON=""

case "$MAX_SEVERITY_THRESHOLD" in
    "INFO")
        if [ "$CRITICAL_SEVERITY" -gt 0 ] || [ "$HIGH_SEVERITY" -gt 0 ] || [ "$MEDIUM_SEVERITY" -gt 0 ] || [ "$LOW_SEVERITY" -gt 0 ]; then
            QUALITY_GATE_FAILED=true
            FAILURE_REASON="Found issues above INFO severity"
        fi
        ;;
    "LOW")
        if [ "$CRITICAL_SEVERITY" -gt 0 ] || [ "$HIGH_SEVERITY" -gt 0 ] || [ "$MEDIUM_SEVERITY" -gt 0 ]; then
            QUALITY_GATE_FAILED=true
            FAILURE_REASON="Found issues above LOW severity"
        fi
        ;;
    "MEDIUM")
        if [ "$CRITICAL_SEVERITY" -gt 0 ] || [ "$HIGH_SEVERITY" -gt 0 ]; then
            QUALITY_GATE_FAILED=true
            FAILURE_REASON="Found issues above MEDIUM severity"
        fi
        ;;
    "HIGH")
        if [ "$CRITICAL_SEVERITY" -gt 0 ]; then
            QUALITY_GATE_FAILED=true
            FAILURE_REASON="Found CRITICAL severity issues"
        fi
        ;;
    "CRITICAL")
        # All severity levels are acceptable
        QUALITY_GATE_FAILED=false
        ;;
    *)
        echo "⚠️  Unknown severity threshold: $MAX_SEVERITY_THRESHOLD"
        echo "Valid thresholds: INFO, LOW, MEDIUM, HIGH, CRITICAL"
        exit 1
        ;;
esac

# Quality gate result
if [ "$QUALITY_GATE_FAILED" = true ]; then
    echo "❌ Quality gate failed: $FAILURE_REASON"
    echo "💡 Review and address the high-severity recommendations before proceeding."
    exit 1
else
    echo "✅ Quality gate passed: No issues found above $MAX_SEVERITY_THRESHOLD severity threshold"
    echo "🎉 Code quality meets the required standards!"
    exit 0
fi