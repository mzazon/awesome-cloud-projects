#!/usr/bin/env python3
"""
AWS CDK Python Application for Advanced CodeBuild Pipelines

This application creates a sophisticated CI/CD pipeline using AWS CodeBuild
with multi-stage builds, intelligent caching, and comprehensive artifact management.

The pipeline includes:
- Dependency caching and management
- Multi-stage build processes
- Parallel architecture builds
- Security scanning and quality gates
- Comprehensive monitoring and analytics
- Automated cache optimization
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    Tags,
)
from constructs import Construct

# Import custom constructs
from stacks.pipeline_stack import AdvancedCodeBuildPipelineStack
from stacks.monitoring_stack import MonitoringStack
from stacks.storage_stack import StorageStack


class AdvancedCodeBuildApp(App):
    """
    Main CDK Application for Advanced CodeBuild Pipeline
    
    This application orchestrates the deployment of a comprehensive
    build pipeline with multiple stages, caching, and monitoring.
    """
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get environment configuration
        account = os.getenv('CDK_DEFAULT_ACCOUNT', os.getenv('AWS_ACCOUNT_ID'))
        region = os.getenv('CDK_DEFAULT_REGION', os.getenv('AWS_REGION', 'us-east-1'))
        
        if not account:
            raise ValueError("AWS account ID must be set via CDK_DEFAULT_ACCOUNT or AWS_ACCOUNT_ID")
        
        env = Environment(account=account, region=region)
        
        # Configuration parameters
        config = self._get_configuration()
        
        # Create storage stack (S3 buckets, ECR)
        storage_stack = StorageStack(
            self, 
            "AdvancedCodeBuildStorage",
            description="Storage infrastructure for advanced CodeBuild pipeline",
            env=env,
            **config
        )
        
        # Create main pipeline stack
        pipeline_stack = AdvancedCodeBuildPipelineStack(
            self,
            "AdvancedCodeBuildPipeline", 
            description="Advanced CodeBuild pipeline with multi-stage builds and caching",
            storage_stack=storage_stack,
            env=env,
            **config
        )
        
        # Create monitoring stack
        monitoring_stack = MonitoringStack(
            self,
            "AdvancedCodeBuildMonitoring",
            description="Monitoring and analytics for advanced CodeBuild pipeline",
            pipeline_stack=pipeline_stack,
            storage_stack=storage_stack,
            env=env,
            **config
        )
        
        # Add dependencies
        pipeline_stack.add_dependency(storage_stack)
        monitoring_stack.add_dependency(pipeline_stack)
        
        # Apply common tags
        self._apply_tags(config.get('project_name', 'advanced-codebuild'))
    
    def _get_configuration(self) -> Dict[str, any]:
        """
        Get configuration parameters from environment variables or defaults
        
        Returns:
            Dict containing configuration parameters
        """
        return {
            'project_name': os.getenv('PROJECT_NAME', 'advanced-codebuild'),
            'environment': os.getenv('ENVIRONMENT', 'dev'),
            'enable_parallel_builds': os.getenv('ENABLE_PARALLEL_BUILDS', 'true').lower() == 'true',
            'cache_retention_days': int(os.getenv('CACHE_RETENTION_DAYS', '30')),
            'artifact_retention_days': int(os.getenv('ARTIFACT_RETENTION_DAYS', '90')),
            'enable_security_scanning': os.getenv('ENABLE_SECURITY_SCANNING', 'true').lower() == 'true',
            'enable_analytics': os.getenv('ENABLE_ANALYTICS', 'true').lower() == 'true',
            'notification_email': os.getenv('NOTIFICATION_EMAIL'),
            'allowed_ip_ranges': os.getenv('ALLOWED_IP_RANGES', '0.0.0.0/0').split(','),
            'build_compute_type': os.getenv('BUILD_COMPUTE_TYPE', 'BUILD_GENERAL1_LARGE'),
            'parallel_architectures': os.getenv('PARALLEL_ARCHITECTURES', 'amd64,arm64').split(','),
        }
    
    def _apply_tags(self, project_name: str) -> None:
        """
        Apply common tags to all resources in the application
        
        Args:
            project_name: Name of the project for tagging
        """
        Tags.of(self).add("Project", project_name)
        Tags.of(self).add("Application", "AdvancedCodeBuildPipeline")
        Tags.of(self).add("Environment", os.getenv('ENVIRONMENT', 'dev'))
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Purpose", "CI/CD Pipeline")
        Tags.of(self).add("CostCenter", os.getenv('COST_CENTER', 'Engineering'))


# Create the application
app = AdvancedCodeBuildApp()

# Synthesize the application
app.synth()