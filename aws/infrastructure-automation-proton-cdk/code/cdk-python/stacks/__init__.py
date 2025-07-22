"""
Stack modules for AWS CDK Proton Infrastructure Automation

This package contains the CDK stack definitions for creating standardized
infrastructure components that integrate with AWS Proton templates.
"""

from .vpc_stack import VpcStack
from .ecs_stack import EcsStack
from .proton_infrastructure_stack import ProtonInfrastructureStack

__all__ = [
    "VpcStack",
    "EcsStack", 
    "ProtonInfrastructureStack",
]