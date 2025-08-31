#!/usr/bin/env python3
"""
CDK Python Application for Standardized Service Deployment with VPC Lattice and Service Catalog

This application creates a standardized service deployment infrastructure using AWS Service Catalog
to provide governed self-service deployment of VPC Lattice service templates.
"""

import os
from typing import Any, Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_servicecatalog as servicecatalog,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_iam as iam,
    aws_cloudformation as cloudformation,
    aws_ec2 as ec2,
)
from constructs import Construct


class ServiceCatalogVpcLatticeStack(Stack):
    """
    Main stack for Service Catalog VPC Lattice standardized deployment infrastructure.
    
    This stack creates:
    - S3 bucket for CloudFormation templates
    - Service Catalog portfolio and products
    - IAM roles and policies for launch constraints
    - CloudFormation templates for VPC Lattice resources
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create S3 bucket for CloudFormation templates
        self.template_bucket = self._create_template_bucket(unique_suffix)
        
        # Upload CloudFormation templates to S3
        self._upload_cloudformation_templates()
        
        # Create IAM role for Service Catalog launch constraints
        self.launch_role = self._create_launch_role(unique_suffix)
        
        # Create Service Catalog portfolio
        self.portfolio = self._create_service_catalog_portfolio(unique_suffix)
        
        # Create Service Catalog products
        self.network_product = self._create_service_network_product()
        self.service_product = self._create_lattice_service_product()
        
        # Associate products with portfolio
        self._associate_products_with_portfolio()
        
        # Create launch constraints
        self._create_launch_constraints()
        
        # Grant portfolio access (example with current principal)
        self._grant_portfolio_access()
        
        # Create outputs
        self._create_outputs()

    def _create_template_bucket(self, unique_suffix: str) -> s3.Bucket:
        """Create S3 bucket for storing CloudFormation templates."""
        bucket = s3.Bucket(
            self,
            "TemplateBucket",
            bucket_name=f"service-catalog-templates-{unique_suffix}-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Add bucket policy to allow Service Catalog access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("servicecatalog.amazonaws.com")],
                actions=["s3:GetObject"],
                resources=[f"{bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": self.account
                    }
                }
            )
        )
        
        return bucket

    def _upload_cloudformation_templates(self) -> None:
        """Upload CloudFormation templates to S3 bucket."""
        # Deploy service network template
        s3_deployment.BucketDeployment(
            self,
            "ServiceNetworkTemplateDeployment",
            sources=[s3_deployment.Source.inline(
                "service-network-template.yaml",
                self._get_service_network_template()
            )],
            destination_bucket=self.template_bucket,
            destination_key_prefix="templates/",
        )
        
        # Deploy lattice service template
        s3_deployment.BucketDeployment(
            self,
            "LatticeServiceTemplateDeployment",
            sources=[s3_deployment.Source.inline(
                "lattice-service-template.yaml",
                self._get_lattice_service_template()
            )],
            destination_bucket=self.template_bucket,
            destination_key_prefix="templates/",
        )

    def _create_launch_role(self, unique_suffix: str) -> iam.Role:
        """Create IAM role for Service Catalog launch constraints."""
        role = iam.Role(
            self,
            "ServiceCatalogLaunchRole",
            role_name=f"ServiceCatalogVpcLatticeRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("servicecatalog.amazonaws.com"),
            description="IAM role for Service Catalog VPC Lattice product launches",
        )
        
        # Add VPC Lattice permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "vpc-lattice:*",
                    "ec2:DescribeVpcs",
                    "ec2:DescribeSubnets",
                    "ec2:DescribeSecurityGroups",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "cloudformation:*",
                ],
                resources=["*"],
            )
        )
        
        # Add CloudFormation permissions for stack operations
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudformation:CreateStack",
                    "cloudformation:DeleteStack",
                    "cloudformation:UpdateStack",
                    "cloudformation:DescribeStacks",
                    "cloudformation:DescribeStackEvents",
                    "cloudformation:DescribeStackResources",
                    "cloudformation:GetTemplate",
                ],
                resources=[f"arn:aws:cloudformation:{self.region}:{self.account}:stack/SC-*"],
            )
        )
        
        return role

    def _create_service_catalog_portfolio(self, unique_suffix: str) -> servicecatalog.Portfolio:
        """Create Service Catalog portfolio for VPC Lattice services."""
        portfolio = servicecatalog.Portfolio(
            self,
            "VpcLatticePortfolio",
            display_name=f"vpc-lattice-services-{unique_suffix}",
            description="Standardized VPC Lattice service deployment templates",
            provider_name="Platform Engineering Team",
        )
        
        # Add tag options to portfolio
        tag_option = servicecatalog.TagOptions(
            self,
            "PortfolioTagOptions",
            allowed_values_for_tags={
                "Purpose": ["VPCLatticeStandardization"],
                "Environment": ["Development", "Staging", "Production"],
                "Team": ["Platform", "Application", "Security"],
            }
        )
        
        portfolio.associate_tag_options(tag_option)
        
        return portfolio

    def _create_service_network_product(self) -> servicecatalog.CloudFormationProduct:
        """Create Service Catalog product for VPC Lattice service network."""
        product = servicecatalog.CloudFormationProduct(
            self,
            "ServiceNetworkProduct",
            product_name="standardized-service-network",
            description="Standardized VPC Lattice Service Network",
            owner="Platform Engineering Team",
            product_versions=[
                servicecatalog.CloudFormationProductVersion(
                    product_version_name="v1.0",
                    description="Initial version of standardized service network template",
                    cloud_formation_template=servicecatalog.CloudFormationTemplate.from_url(
                        f"https://s3.{self.region}.amazonaws.com/{self.template_bucket.bucket_name}/templates/service-network-template.yaml"
                    ),
                )
            ],
        )
        
        return product

    def _create_lattice_service_product(self) -> servicecatalog.CloudFormationProduct:
        """Create Service Catalog product for VPC Lattice service."""
        product = servicecatalog.CloudFormationProduct(
            self,
            "LatticeServiceProduct",
            product_name="standardized-lattice-service",
            description="Standardized VPC Lattice Service with Target Group",
            owner="Platform Engineering Team",
            product_versions=[
                servicecatalog.CloudFormationProductVersion(
                    product_version_name="v1.0",
                    description="Initial version of standardized lattice service template",
                    cloud_formation_template=servicecatalog.CloudFormationTemplate.from_url(
                        f"https://s3.{self.region}.amazonaws.com/{self.template_bucket.bucket_name}/templates/lattice-service-template.yaml"
                    ),
                )
            ],
        )
        
        return product

    def _associate_products_with_portfolio(self) -> None:
        """Associate products with the portfolio."""
        self.portfolio.add_product(self.network_product)
        self.portfolio.add_product(self.service_product)

    def _create_launch_constraints(self) -> None:
        """Create launch constraints for products."""
        # Launch constraint for service network product
        servicecatalog.CfnLaunchRoleConstraint(
            self,
            "NetworkProductLaunchConstraint",
            portfolio_id=self.portfolio.portfolio_id,
            product_id=self.network_product.product_id,
            role_arn=self.launch_role.role_arn,
            description="IAM role for VPC Lattice service network deployment",
        )
        
        # Launch constraint for lattice service product
        servicecatalog.CfnLaunchRoleConstraint(
            self,
            "ServiceProductLaunchConstraint",
            portfolio_id=self.portfolio.portfolio_id,
            product_id=self.service_product.product_id,
            role_arn=self.launch_role.role_arn,
            description="IAM role for VPC Lattice service deployment",
        )

    def _grant_portfolio_access(self) -> None:
        """Grant portfolio access to specified principals."""
        # Note: In a real environment, you would grant access to specific IAM users, groups, or roles
        # This is a placeholder - actual principal ARNs should be provided via context or parameters
        
        # Example of granting access to a specific role (uncomment and modify as needed)
        # access_role_arn = self.node.try_get_context("access_role_arn")
        # if access_role_arn:
        #     servicecatalog.CfnPortfolioPrincipalAssociation(
        #         self,
        #         "PortfolioAccess",
        #         portfolio_id=self.portfolio.portfolio_id,
        #         principal_arn=access_role_arn,
        #         principal_type="IAM",
        #     )
        
        pass

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "PortfolioId",
            value=self.portfolio.portfolio_id,
            description="Service Catalog Portfolio ID",
            export_name=f"{self.stack_name}-PortfolioId",
        )
        
        CfnOutput(
            self,
            "NetworkProductId",
            value=self.network_product.product_id,
            description="Service Network Product ID",
            export_name=f"{self.stack_name}-NetworkProductId",
        )
        
        CfnOutput(
            self,
            "ServiceProductId",
            value=self.service_product.product_id,
            description="Lattice Service Product ID",
            export_name=f"{self.stack_name}-ServiceProductId",
        )
        
        CfnOutput(
            self,
            "TemplateBucketName",
            value=self.template_bucket.bucket_name,
            description="S3 bucket containing CloudFormation templates",
            export_name=f"{self.stack_name}-TemplateBucketName",
        )
        
        CfnOutput(
            self,
            "LaunchRoleArn",
            value=self.launch_role.role_arn,
            description="IAM role ARN for Service Catalog launches",
            export_name=f"{self.stack_name}-LaunchRoleArn",
        )

    def _get_service_network_template(self) -> str:
        """Return the CloudFormation template for VPC Lattice service network."""
        return """AWSTemplateFormatVersion: '2010-09-09'
Description: 'Standardized VPC Lattice Service Network'

Parameters:
  NetworkName:
    Type: String
    Default: 'standard-service-network'
    Description: 'Name for the VPC Lattice service network'
  
  AuthType:
    Type: String
    Default: 'AWS_IAM'
    AllowedValues: ['AWS_IAM', 'NONE']
    Description: 'Authentication type for the service network'

Resources:
  ServiceNetwork:
    Type: AWS::VpcLattice::ServiceNetwork
    Properties:
      Name: !Ref NetworkName
      AuthType: !Ref AuthType
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'

  ServiceNetworkPolicy:
    Type: AWS::VpcLattice::AuthPolicy
    Properties:
      ResourceIdentifier: !Ref ServiceNetwork
      Policy:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal: '*'
            Action: 'vpc-lattice-svcs:Invoke'
            Resource: '*'
            Condition:
              StringEquals:
                'aws:PrincipalAccount': !Ref 'AWS::AccountId'

Outputs:
  ServiceNetworkId:
    Description: 'Service Network ID'
    Value: !Ref ServiceNetwork
    Export:
      Name: !Sub '${AWS::StackName}-ServiceNetworkId'
  
  ServiceNetworkArn:
    Description: 'Service Network ARN'
    Value: !GetAtt ServiceNetwork.Arn
    Export:
      Name: !Sub '${AWS::StackName}-ServiceNetworkArn'
"""

    def _get_lattice_service_template(self) -> str:
        """Return the CloudFormation template for VPC Lattice service."""
        return """AWSTemplateFormatVersion: '2010-09-09'
Description: 'Standardized VPC Lattice Service with Target Group'

Parameters:
  ServiceName:
    Type: String
    Description: 'Name for the VPC Lattice service'
  
  ServiceNetworkId:
    Type: String
    Description: 'Service Network ID to associate with'
  
  TargetType:
    Type: String
    Default: 'IP'
    AllowedValues: ['IP', 'LAMBDA', 'ALB']
    Description: 'Type of targets for the target group'
  
  VpcId:
    Type: AWS::EC2::VPC::Id
    Description: 'VPC ID for the target group'
  
  Port:
    Type: Number
    Default: 80
    MinValue: 1
    MaxValue: 65535
    Description: 'Port for the service listener'
  
  Protocol:
    Type: String
    Default: 'HTTP'
    AllowedValues: ['HTTP', 'HTTPS']
    Description: 'Protocol for the service listener'

Resources:
  TargetGroup:
    Type: AWS::VpcLattice::TargetGroup
    Properties:
      Name: !Sub '${ServiceName}-targets'
      Type: !Ref TargetType
      Port: !Ref Port
      Protocol: !Ref Protocol
      VpcIdentifier: !Ref VpcId
      HealthCheck:
        Enabled: true
        HealthCheckIntervalSeconds: 30
        HealthCheckTimeoutSeconds: 5
        HealthyThresholdCount: 2
        UnhealthyThresholdCount: 3
        Matcher:
          HttpCode: '200'
        Path: '/health'
        Port: !Ref Port
        Protocol: !Ref Protocol
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'

  Service:
    Type: AWS::VpcLattice::Service
    Properties:
      Name: !Ref ServiceName
      AuthType: 'AWS_IAM'
      Tags:
        - Key: 'Purpose'
          Value: 'StandardizedDeployment'
        - Key: 'ManagedBy'
          Value: 'ServiceCatalog'

  Listener:
    Type: AWS::VpcLattice::Listener
    Properties:
      ServiceIdentifier: !Ref Service
      Name: 'default-listener'
      Port: !Ref Port
      Protocol: !Ref Protocol
      DefaultAction:
        Forward:
          TargetGroups:
            - TargetGroupIdentifier: !Ref TargetGroup
              Weight: 100

  ServiceNetworkAssociation:
    Type: AWS::VpcLattice::ServiceNetworkServiceAssociation
    Properties:
      ServiceIdentifier: !Ref Service
      ServiceNetworkIdentifier: !Ref ServiceNetworkId

Outputs:
  ServiceId:
    Description: 'VPC Lattice Service ID'
    Value: !Ref Service
  
  ServiceArn:
    Description: 'VPC Lattice Service ARN'
    Value: !GetAtt Service.Arn
  
  TargetGroupId:
    Description: 'Target Group ID'
    Value: !Ref TargetGroup
  
  TargetGroupArn:
    Description: 'Target Group ARN'
    Value: !GetAtt TargetGroup.Arn
"""


# CDK Application
app = cdk.App()

# Get unique suffix from context (default to 'demo' for testing)
unique_suffix = app.node.try_get_context("unique_suffix") or "demo"

# Create the main stack
ServiceCatalogVpcLatticeStack(
    app,
    "ServiceCatalogVpcLatticeStack",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
    ),
    description="Standardized Service Deployment with VPC Lattice and Service Catalog",
)

app.synth()