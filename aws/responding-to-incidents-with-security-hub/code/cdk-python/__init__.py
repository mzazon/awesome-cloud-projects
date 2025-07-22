"""
AWS CDK Python application for Security Hub Incident Response

This package provides a complete CDK implementation for automated security
incident response using AWS Security Hub, EventBridge, Lambda, and SNS.

Author: AWS CDK Security Team
Version: 1.0.0
License: MIT
"""

__version__ = "1.0.0"
__author__ = "AWS CDK Security Team"
__email__ = "security@example.com"

# Package metadata
__title__ = "security-incident-response-cdk"
__description__ = "AWS CDK Python application for automated Security Hub incident response"
__url__ = "https://github.com/your-org/security-incident-response-cdk"

# Import main components for easy access
from .security_incident_response_stack import SecurityIncidentResponseStack

__all__ = [
    "SecurityIncidentResponseStack",
]