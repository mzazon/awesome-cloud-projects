#!/usr/bin/env python3
"""
AWS CDK Application for Hybrid Cloud Connectivity with Direct Connect

This application deploys a complete hybrid cloud connectivity solution using:
- AWS Direct Connect Gateway
- Transit Gateway with multiple VPC attachments
- Route 53 Resolver endpoints for DNS resolution
- CloudWatch monitoring and alerting
- Security controls (NACLs, Security Groups, VPC Flow Logs)

Author: Recipe Generator
Version: 1.0
"""

import os
import aws_cdk as cdk
from aws_cdk import (
    Environment,
    Tags,
)
from hybrid_connectivity_stack import HybridConnectivityStack


def main() -> None:
    """
    Main entry point for the CDK application.
    
    Creates and configures the hybrid connectivity stack with proper
    environment settings and global tags.
    """
    app = cdk.App()
    
    # Get environment configuration
    account = os.getenv('CDK_DEFAULT_ACCOUNT') or app.node.try_get_context('account')
    region = os.getenv('CDK_DEFAULT_REGION') or app.node.try_get_context('region')
    
    # Get project configuration from context or environment
    project_id = (
        app.node.try_get_context('project_id') or 
        os.getenv('PROJECT_ID') or 
        'hybrid-dx'
    )
    
    environment_name = (
        app.node.try_get_context('environment') or 
        os.getenv('ENVIRONMENT') or 
        'production'
    )
    
    # BGP ASN configuration
    on_premises_asn = int(
        app.node.try_get_context('on_premises_asn') or 
        os.getenv('ON_PREMISES_ASN') or 
        '65000'
    )
    
    aws_asn = int(
        app.node.try_get_context('aws_asn') or 
        os.getenv('AWS_ASN') or 
        '64512'
    )
    
    # On-premises network configuration
    on_premises_cidr = (
        app.node.try_get_context('on_premises_cidr') or 
        os.getenv('ON_PREMISES_CIDR') or 
        '10.0.0.0/8'
    )
    
    # Validate environment configuration
    if not account:
        raise ValueError("AWS account ID must be specified via CDK_DEFAULT_ACCOUNT or context")
    
    if not region:
        raise ValueError("AWS region must be specified via CDK_DEFAULT_REGION or context")
    
    # Create environment
    env = Environment(account=account, region=region)
    
    # Create the main stack
    stack = HybridConnectivityStack(
        app,
        f"HybridConnectivity-{project_id}",
        project_id=project_id,
        environment_name=environment_name,
        on_premises_asn=on_premises_asn,
        aws_asn=aws_asn,
        on_premises_cidr=on_premises_cidr,
        env=env,
        description=f"Hybrid Cloud Connectivity with Direct Connect - {project_id}",
        termination_protection=True if environment_name == 'production' else False,
    )
    
    # Add global tags
    Tags.of(stack).add("Project", f"HybridConnectivity-{project_id}")
    Tags.of(stack).add("Environment", environment_name)
    Tags.of(stack).add("ManagedBy", "CDK")
    Tags.of(stack).add("Recipe", "hybrid-cloud-connectivity-aws-direct-connect")
    Tags.of(stack).add("Version", "1.0")
    
    # Add cost allocation tags
    Tags.of(stack).add("CostCenter", "Infrastructure")
    Tags.of(stack).add("Owner", "NetworkTeam")
    
    app.synth()


if __name__ == "__main__":
    main()