#!/usr/bin/env python3
"""
CDK Python Application for Automated Report Generation with EventBridge Scheduler and S3

This application deploys a serverless solution for automated business report generation
using EventBridge Scheduler, AWS Lambda, S3, and Amazon SES. The solution demonstrates
best practices for serverless architecture, security, and operational excellence.

Architecture Components:
- EventBridge Scheduler: Automated execution trigger
- Lambda Function: Report generation and processing logic
- S3 Buckets: Data storage and report archival
- Amazon SES: Email delivery for report notifications
- IAM Roles: Least-privilege security access

Author: AWS CDK Team
Version: 1.0
"""

import os
import aws_cdk as cdk
from automated_report_stack import AutomatedReportStack

# Initialize CDK application
app = cdk.App()

# Deploy the automated report generation stack
AutomatedReportStack(
    app, 
    "AutomatedReportStack",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    ),
    description="Automated report generation using EventBridge Scheduler, Lambda, S3, and SES"
)

# Add tags to all resources for cost tracking and governance
cdk.Tags.of(app).add("Project", "AutomatedReporting")
cdk.Tags.of(app).add("Environment", "Production")
cdk.Tags.of(app).add("Owner", "DataTeam")

# Synthesize CloudFormation template
app.synth()