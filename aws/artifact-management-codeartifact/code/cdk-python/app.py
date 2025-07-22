#!/usr/bin/env python3
"""
CDK Application for AWS CodeArtifact Artifact Management
This application creates a complete CodeArtifact setup with domain, repositories,
external connections, and IAM policies for secure artifact management.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_codeartifact as codeartifact,
    aws_iam as iam,
    aws_kms as kms,
    CfnOutput,
    RemovalPolicy,
    Tags
)
from constructs import Construct
from typing import Dict, List


class CodeArtifactStack(Stack):
    """
    CDK Stack for AWS CodeArtifact infrastructure.
    
    Creates a complete artifact management solution including:
    - CodeArtifact domain with KMS encryption
    - Repository hierarchy (npm-store, pypi-store, team-dev, production)
    - External connections to public registries
    - IAM policies for developer and production access
    - Repository permissions and upstream configurations
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create domain name with random suffix for uniqueness
        domain_name = f"my-company-domain-{cdk.Names.unique_id(self)[:6].lower()}"

        # Create KMS key for CodeArtifact encryption
        self.artifact_key = kms.Key(
            self,
            "CodeArtifactKey",
            description="KMS key for CodeArtifact domain encryption",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create CodeArtifact domain
        self.domain = codeartifact.CfnDomain(
            self,
            "ArtifactDomain",
            domain_name=domain_name,
            encryption_key=self.artifact_key.key_arn,
            permissions_policy_document=self._create_domain_policy()
        )

        # Create repositories
        self.repositories = self._create_repositories()

        # Create external connections
        self._create_external_connections()

        # Configure upstream relationships
        self._configure_upstream_relationships()

        # Create IAM policies
        self.iam_policies = self._create_iam_policies()

        # Add repository permissions
        self._add_repository_permissions()

        # Add tags to all resources
        self._add_tags()

        # Create outputs
        self._create_outputs()

    def _create_repositories(self) -> Dict[str, codeartifact.CfnRepository]:
        """Create the repository hierarchy for artifact management."""
        repositories = {}

        # Repository configurations
        repo_configs = {
            "npm-store": {
                "description": "npm packages from public registry",
                "format": "npm"
            },
            "pypi-store": {
                "description": "Python packages from PyPI",
                "format": "pypi"
            },
            "team-dev": {
                "description": "Team development artifacts",
                "format": "generic"
            },
            "production": {
                "description": "Production-ready artifacts",
                "format": "generic"
            }
        }

        for repo_name, config in repo_configs.items():
            repositories[repo_name] = codeartifact.CfnRepository(
                self,
                f"Repository{repo_name.replace('-', '').title()}",
                domain_name=self.domain.domain_name,
                repository_name=repo_name,
                description=config["description"],
                permissions_policy_document=self._create_repository_policy(repo_name)
            )
            # Ensure repository depends on domain
            repositories[repo_name].add_dependency(self.domain)

        return repositories

    def _create_external_connections(self) -> None:
        """Create external connections to public package repositories."""
        # External connection for npm repository
        npm_external = codeartifact.CfnRepository(
            self,
            "NpmExternalConnection",
            domain_name=self.domain.domain_name,
            repository_name=self.repositories["npm-store"].repository_name,
            external_connections=["public:npmjs"]
        )
        npm_external.add_dependency(self.repositories["npm-store"])

        # External connection for PyPI repository
        pypi_external = codeartifact.CfnRepository(
            self,
            "PypiExternalConnection",
            domain_name=self.domain.domain_name,
            repository_name=self.repositories["pypi-store"].repository_name,
            external_connections=["public:pypi"]
        )
        pypi_external.add_dependency(self.repositories["pypi-store"])

    def _configure_upstream_relationships(self) -> None:
        """Configure upstream repository relationships for package resolution hierarchy."""
        # Configure team repository with upstream connections to store repositories
        team_upstream = codeartifact.CfnRepository(
            self,
            "TeamUpstreamConfig",
            domain_name=self.domain.domain_name,
            repository_name=self.repositories["team-dev"].repository_name,
            upstreams=[
                self.repositories["npm-store"].repository_name,
                self.repositories["pypi-store"].repository_name
            ]
        )
        team_upstream.add_dependency(self.repositories["team-dev"])
        team_upstream.add_dependency(self.repositories["npm-store"])
        team_upstream.add_dependency(self.repositories["pypi-store"])

        # Configure production repository with upstream to team repository
        prod_upstream = codeartifact.CfnRepository(
            self,
            "ProductionUpstreamConfig",
            domain_name=self.domain.domain_name,
            repository_name=self.repositories["production"].repository_name,
            upstreams=[self.repositories["team-dev"].repository_name]
        )
        prod_upstream.add_dependency(self.repositories["production"])
        prod_upstream.add_dependency(self.repositories["team-dev"])

    def _create_iam_policies(self) -> Dict[str, iam.ManagedPolicy]:
        """Create IAM policies for different access patterns."""
        policies = {}

        # Developer policy for team repository access
        developer_statements = [
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codeartifact:GetAuthorizationToken",
                    "codeartifact:GetRepositoryEndpoint",
                    "codeartifact:ReadFromRepository",
                    "codeartifact:PublishPackageVersion",
                    "codeartifact:PutPackageMetadata"
                ],
                resources=[
                    f"arn:aws:codeartifact:{self.region}:{self.account}:domain/{self.domain.domain_name}",
                    f"arn:aws:codeartifact:{self.region}:{self.account}:repository/{self.domain.domain_name}/*",
                    f"arn:aws:codeartifact:{self.region}:{self.account}:package/{self.domain.domain_name}/*/*"
                ]
            ),
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sts:GetServiceBearerToken"],
                resources=["*"],
                conditions={
                    "StringEquals": {
                        "sts:AWSServiceName": "codeartifact.amazonaws.com"
                    }
                }
            )
        ]

        policies["developer"] = iam.ManagedPolicy(
            self,
            "DeveloperPolicy",
            managed_policy_name=f"CodeArtifact-Developer-{cdk.Names.unique_id(self)[:8]}",
            description="Policy for developers to access CodeArtifact repositories",
            statements=developer_statements
        )

        # Production policy for read-only access
        production_statements = [
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codeartifact:GetAuthorizationToken",
                    "codeartifact:GetRepositoryEndpoint",
                    "codeartifact:ReadFromRepository"
                ],
                resources=[
                    f"arn:aws:codeartifact:{self.region}:{self.account}:domain/{self.domain.domain_name}",
                    f"arn:aws:codeartifact:{self.region}:{self.account}:repository/{self.domain.domain_name}/{self.repositories['production'].repository_name}",
                    f"arn:aws:codeartifact:{self.region}:{self.account}:package/{self.domain.domain_name}/{self.repositories['production'].repository_name}/*"
                ]
            ),
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sts:GetServiceBearerToken"],
                resources=["*"],
                conditions={
                    "StringEquals": {
                        "sts:AWSServiceName": "codeartifact.amazonaws.com"
                    }
                }
            )
        ]

        policies["production"] = iam.ManagedPolicy(
            self,
            "ProductionPolicy",
            managed_policy_name=f"CodeArtifact-Production-{cdk.Names.unique_id(self)[:8]}",
            description="Policy for production access to CodeArtifact repositories",
            statements=production_statements
        )

        return policies

    def _create_domain_policy(self) -> Dict:
        """Create domain-level permissions policy."""
        return {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"arn:aws:iam::{self.account}:root"
                    },
                    "Action": [
                        "codeartifact:GetDomainPermissionsPolicy",
                        "codeartifact:ListRepositoriesInDomain"
                    ],
                    "Resource": "*"
                }
            ]
        }

    def _create_repository_policy(self, repository_name: str) -> Dict:
        """Create repository-level permissions policy."""
        return {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": f"arn:aws:iam::{self.account}:root"
                    },
                    "Action": [
                        "codeartifact:ReadFromRepository",
                        "codeartifact:PublishPackageVersion" if repository_name in ["team-dev"] else "codeartifact:ReadFromRepository",
                        "codeartifact:PutPackageMetadata"
                    ],
                    "Resource": "*"
                }
            ]
        }

    def _add_repository_permissions(self) -> None:
        """Add fine-grained repository permissions."""
        # Team repository permissions are already configured in _create_repository_policy
        # Additional permissions can be added here as needed
        pass

    def _add_tags(self) -> None:
        """Add tags to all resources."""
        Tags.of(self).add("Project", "CodeArtifact-Management")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Recipe", "artifact-management-codeartifact")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        # Domain outputs
        CfnOutput(
            self,
            "DomainName",
            value=self.domain.domain_name,
            description="CodeArtifact domain name"
        )

        CfnOutput(
            self,
            "DomainArn",
            value=self.domain.attr_arn,
            description="CodeArtifact domain ARN"
        )

        # Repository outputs
        for repo_name, repository in self.repositories.items():
            CfnOutput(
                self,
                f"{repo_name.replace('-', '').title()}RepositoryName",
                value=repository.repository_name,
                description=f"{repo_name} repository name"
            )

            CfnOutput(
                self,
                f"{repo_name.replace('-', '').title()}RepositoryArn",
                value=repository.attr_arn,
                description=f"{repo_name} repository ARN"
            )

        # IAM policy outputs
        for policy_name, policy in self.iam_policies.items():
            CfnOutput(
                self,
                f"{policy_name.title()}PolicyArn",
                value=policy.managed_policy_arn,
                description=f"{policy_name} IAM policy ARN"
            )

        # KMS key output
        CfnOutput(
            self,
            "EncryptionKeyArn",
            value=self.artifact_key.key_arn,
            description="KMS key ARN for CodeArtifact encryption"
        )

        # Usage instructions
        CfnOutput(
            self,
            "LoginCommand",
            value=f"aws codeartifact login --tool npm --domain {self.domain.domain_name} --repository {self.repositories['team-dev'].repository_name}",
            description="Command to configure npm authentication"
        )


class CodeArtifactApp(cdk.App):
    """CDK Application for CodeArtifact infrastructure."""

    def __init__(self):
        super().__init__()

        # Create the main stack
        CodeArtifactStack(
            self,
            "CodeArtifactStack",
            description="Complete AWS CodeArtifact setup for enterprise artifact management",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            )
        )


# Create and run the application
app = CodeArtifactApp()
app.synth()