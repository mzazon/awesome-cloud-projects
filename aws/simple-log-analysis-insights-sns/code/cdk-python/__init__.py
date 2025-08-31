"""
Simple Log Analysis with CloudWatch Insights and SNS - CDK Python Package

This package provides a complete CDK Python implementation for automated log monitoring
using CloudWatch Logs Insights and SNS notifications.

The solution creates:
- CloudWatch Log Group for application logs
- Lambda function for automated log analysis
- SNS topic for alert notifications  
- EventBridge rule for scheduled execution
- IAM roles with least-privilege permissions

Usage:
    python app.py

For more information, see README.md
"""

__version__ = "1.0.0"
__author__ = "AWS CDK Developer"
__email__ = "developer@example.com"
__description__ = "Simple Log Analysis with CloudWatch Insights and SNS - CDK Python Application"