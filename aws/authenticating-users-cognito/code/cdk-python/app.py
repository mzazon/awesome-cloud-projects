#!/usr/bin/env python3
"""
CDK Python application for Authenticating Users with Cognito User Pools.

This application creates a comprehensive user authentication system using Amazon Cognito
User Pools with advanced security features, multi-factor authentication, social identity
providers, and role-based access control.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    aws_cognito as cognito,
    aws_iam as iam,
    aws_ses as ses,
    aws_sns as sns,
)
from constructs import Construct


class CognitoUserPoolStack(Stack):
    """
    CDK Stack for Amazon Cognito User Pool authentication system.
    
    This stack implements a complete user authentication solution with:
    - Strong password policies and security features
    - Multi-factor authentication (MFA) support
    - Social identity provider integration
    - Role-based access control through user groups
    - Custom user attributes for business logic
    - Email and SMS notification configuration
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        app_name: str = "ecommerce",
        domain_prefix: Optional[str] = None,
        callback_urls: List[str] = None,
        logout_urls: List[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Cognito User Pool stack.
        
        Args:
            scope: The construct scope
            construct_id: The construct ID
            app_name: Name prefix for resources
            domain_prefix: Custom domain prefix for hosted UI
            callback_urls: List of allowed callback URLs
            logout_urls: List of allowed logout URLs
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Set default values
        if callback_urls is None:
            callback_urls = ["https://localhost:3000/callback", "https://example.com/callback"]
        if logout_urls is None:
            logout_urls = ["https://localhost:3000/logout", "https://example.com/logout"]
        if domain_prefix is None:
            domain_prefix = f"{app_name}-auth-{cdk.Aws.ACCOUNT_ID}"[:63]  # Domain prefix max 63 chars

        # Store configuration
        self.app_name = app_name
        self.domain_prefix = domain_prefix

        # Create IAM role for SMS delivery
        self.sns_role = self._create_sns_role()

        # Create the user pool with comprehensive configuration
        self.user_pool = self._create_user_pool()

        # Configure advanced security features
        self._configure_advanced_security()

        # Create user pool client
        self.user_pool_client = self._create_user_pool_client(callback_urls, logout_urls)

        # Create hosted UI domain
        self.user_pool_domain = self._create_hosted_ui_domain()

        # Create user groups for role-based access
        self.user_groups = self._create_user_groups()

        # Create test users
        self._create_test_users()

        # Add custom attributes
        self._add_custom_attributes()

        # Configure email and SMS settings
        self._configure_messaging()

        # Create outputs
        self._create_outputs()

    def _create_sns_role(self) -> iam.Role:
        """Create IAM role for SNS SMS delivery."""
        return iam.Role(
            self,
            "CognitoSNSRole",
            role_name=f"{self.app_name}-cognito-sns-role",
            assumed_by=iam.ServicePrincipal("cognito-idp.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSNSFullAccess")
            ],
            description="IAM role for Cognito to send SMS messages via SNS"
        )

    def _create_user_pool(self) -> cognito.UserPool:
        """Create user pool with comprehensive security configuration."""
        return cognito.UserPool(
            self,
            "UserPool",
            user_pool_name=f"{self.app_name}-users",
            # Authentication configuration
            sign_in_aliases=cognito.SignInAliases(email=True),
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
            
            # Password policy with strong requirements
            password_policy=cognito.PasswordPolicy(
                min_length=12,
                require_lowercase=True,
                require_uppercase=True,
                require_digits=True,
                require_symbols=True,
                temp_password_validity=Duration.days(1)
            ),
            
            # Multi-factor authentication configuration
            mfa=cognito.Mfa.OPTIONAL,
            mfa_second_factor=cognito.MfaSecondFactor(
                sms=True,
                otp=True
            ),
            
            # Device tracking configuration
            device_tracking=cognito.DeviceTracking(
                challenge_required_on_new_device=True,
                device_only_remembered_on_user_prompt=False
            ),
            
            # Account recovery and admin configuration
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            admin_create_user_config=cognito.AdminCreateUserConfig(
                allow_admin_create_user_only=False,
                invite_message=cognito.InviteMessage(
                    email_subject="Welcome to ECommerce - Verify Your Email",
                    email_body="Please click the link to verify your email: {##Verify Email##}",
                    sms_message="Your temporary password is {####}"
                ),
                user_invite_validity=Duration.days(7)
            ),
            
            # Email verification configuration
            user_verification=cognito.UserVerificationConfig(
                email_subject="Welcome to ECommerce - Verify Your Email",
                email_body="Please click the link to verify your email: {##Verify Email##}",
                email_style=cognito.VerificationEmailStyle.LINK,
                sms_message="Your verification code is {####}"
            ),
            
            # Attributes that require verification before update
            user_attribute_update_settings=cognito.UserAttributeUpdateSettings(
                attributes_require_verification_before_update=[cognito.UserPoolAttribute.EMAIL]
            ),
            
            # Standard attributes
            standard_attributes=cognito.StandardAttributes(
                email=cognito.StandardAttribute(required=True, mutable=True),
                given_name=cognito.StandardAttribute(required=False, mutable=True),
                family_name=cognito.StandardAttribute(required=False, mutable=True),
                phone_number=cognito.StandardAttribute(required=False, mutable=True)
            ),
            
            # Security and cleanup
            removal_policy=RemovalPolicy.DESTROY,
            deletion_protection=False
        )

    def _configure_advanced_security(self) -> None:
        """Configure advanced security features for the user pool."""
        # Enable advanced security features
        cfn_user_pool = self.user_pool.node.default_child
        cfn_user_pool.user_pool_add_ons = cognito.CfnUserPool.UserPoolAddOnsProperty(
            advanced_security_mode="ENFORCED"
        )

        # Configure risk-based authentication
        cognito.CfnUserPoolRiskConfigurationAttachment(
            self,
            "RiskConfiguration",
            user_pool_id=self.user_pool.user_pool_id,
            
            # Compromised credentials detection
            compromised_credentials_risk_configuration=cognito.CfnUserPoolRiskConfigurationAttachment.CompromisedCredentialsRiskConfigurationProperty(
                event_filter=["SIGN_IN", "PASSWORD_CHANGE", "SIGN_UP"],
                actions=cognito.CfnUserPoolRiskConfigurationAttachment.CompromisedCredentialsActionsProperty(
                    event_action="BLOCK"
                )
            ),
            
            # Account takeover protection
            account_takeover_risk_configuration=cognito.CfnUserPoolRiskConfigurationAttachment.AccountTakeoverRiskConfigurationProperty(
                notify_configuration=cognito.CfnUserPoolRiskConfigurationAttachment.NotifyConfigurationProperty(
                    from_="noreply@example.com",
                    subject="Security Alert for Your Account",
                    html_body="<p>We detected suspicious activity on your account.</p>",
                    text_body="We detected suspicious activity on your account."
                ),
                actions=cognito.CfnUserPoolRiskConfigurationAttachment.AccountTakeoverActionsProperty(
                    low_action=cognito.CfnUserPoolRiskConfigurationAttachment.AccountTakeoverActionProperty(
                        notify=True,
                        event_action="NO_ACTION"
                    ),
                    medium_action=cognito.CfnUserPoolRiskConfigurationAttachment.AccountTakeoverActionProperty(
                        notify=True,
                        event_action="MFA_IF_CONFIGURED"
                    ),
                    high_action=cognito.CfnUserPoolRiskConfigurationAttachment.AccountTakeoverActionProperty(
                        notify=True,
                        event_action="BLOCK"
                    )
                )
            )
        )

    def _create_user_pool_client(self, callback_urls: List[str], logout_urls: List[str]) -> cognito.UserPoolClient:
        """Create user pool client with OAuth configuration."""
        return cognito.UserPoolClient(
            self,
            "UserPoolClient",
            user_pool=self.user_pool,
            user_pool_client_name=f"{self.app_name}-web-client",
            
            # Generate client secret for server-side applications
            generate_secret=True,
            
            # Token validity configuration
            access_token_validity=Duration.minutes(60),
            id_token_validity=Duration.minutes(60),
            refresh_token_validity=Duration.days(30),
            
            # Authentication flows
            auth_flows=cognito.AuthFlow(
                user_srp=True,
                user_password=True,
                admin_user_password=True,
                custom=True
            ),
            
            # OAuth configuration
            o_auth=cognito.OAuthSettings(
                flows=cognito.OAuthFlows(
                    authorization_code_grant=True,
                    implicit_code_grant=True
                ),
                scopes=[
                    cognito.OAuthScope.OPENID,
                    cognito.OAuthScope.EMAIL,
                    cognito.OAuthScope.PROFILE
                ],
                callback_urls=callback_urls,
                logout_urls=logout_urls
            ),
            
            # Attribute permissions
            read_attributes=cognito.ClientAttributes(
                email=True,
                email_verified=True,
                given_name=True,
                family_name=True,
                phone_number=True
            ),
            write_attributes=cognito.ClientAttributes(
                email=True,
                given_name=True,
                family_name=True,
                phone_number=True
            ),
            
            # Security settings
            prevent_user_existence_errors=True,
            enable_token_revocation=True,
            auth_session_validity=Duration.minutes(3),
            
            # Supported identity providers
            supported_identity_providers=[
                cognito.UserPoolClientIdentityProvider.COGNITO
            ]
        )

    def _create_hosted_ui_domain(self) -> cognito.UserPoolDomain:
        """Create hosted UI domain for authentication."""
        return cognito.UserPoolDomain(
            self,
            "UserPoolDomain",
            user_pool=self.user_pool,
            cognito_domain=cognito.CognitoDomainOptions(
                domain_prefix=self.domain_prefix
            )
        )

    def _create_user_groups(self) -> Dict[str, cognito.CfnUserPoolGroup]:
        """Create user groups for role-based access control."""
        groups = {}
        
        # Administrator group with highest precedence
        groups["administrators"] = cognito.CfnUserPoolGroup(
            self,
            "AdministratorsGroup",
            user_pool_id=self.user_pool.user_pool_id,
            group_name="Administrators",
            description="Administrator users with full access",
            precedence=1
        )
        
        # Premium customers group
        groups["premium_customers"] = cognito.CfnUserPoolGroup(
            self,
            "PremiumCustomersGroup",
            user_pool_id=self.user_pool.user_pool_id,
            group_name="PremiumCustomers",
            description="Premium customer users with enhanced features",
            precedence=5
        )
        
        # Regular customers group with lowest precedence
        groups["customers"] = cognito.CfnUserPoolGroup(
            self,
            "CustomersGroup",
            user_pool_id=self.user_pool.user_pool_id,
            group_name="Customers",
            description="Regular customer users",
            precedence=10
        )
        
        return groups

    def _create_test_users(self) -> None:
        """Create test users for validation."""
        # Admin test user
        admin_user = cognito.CfnUserPoolUser(
            self,
            "AdminTestUser",
            user_pool_id=self.user_pool.user_pool_id,
            username="admin@example.com",
            user_attributes=[
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="email", value="admin@example.com"),
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="name", value="Admin User"),
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="given_name", value="Admin"),
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="family_name", value="User"),
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="email_verified", value="true")
            ],
            message_action="SUPPRESS",
            temporary_password="TempPass123!"
        )
        
        # Add admin user to administrators group
        cognito.CfnUserPoolUserToGroupAttachment(
            self,
            "AdminUserGroupAttachment",
            user_pool_id=self.user_pool.user_pool_id,
            username=admin_user.ref,
            group_name=self.user_groups["administrators"].ref
        )
        
        # Customer test user
        customer_user = cognito.CfnUserPoolUser(
            self,
            "CustomerTestUser",
            user_pool_id=self.user_pool.user_pool_id,
            username="customer@example.com",
            user_attributes=[
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="email", value="customer@example.com"),
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="name", value="Customer User"),
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="given_name", value="Customer"),
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="family_name", value="User"),
                cognito.CfnUserPoolUser.AttributeTypeProperty(name="email_verified", value="true")
            ],
            message_action="SUPPRESS",
            temporary_password="TempPass123!"
        )
        
        # Add customer user to customers group
        cognito.CfnUserPoolUserToGroupAttachment(
            self,
            "CustomerUserGroupAttachment",
            user_pool_id=self.user_pool.user_pool_id,
            username=customer_user.ref,
            group_name=self.user_groups["customers"].ref
        )

    def _add_custom_attributes(self) -> None:
        """Add custom attributes for business logic."""
        # Note: Custom attributes must be added during user pool creation
        # This is a placeholder for documentation purposes
        # In practice, custom attributes would be added to the UserPool constructor
        pass

    def _configure_messaging(self) -> None:
        """Configure email and SMS messaging settings."""
        # Configure SMS settings with the SNS role
        cfn_user_pool = self.user_pool.node.default_child
        cfn_user_pool.sms_configuration = cognito.CfnUserPool.SmsConfigurationProperty(
            sns_caller_arn=self.sns_role.role_arn,
            external_id=f"cognito-{self.user_pool.user_pool_id}"
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for easy access to resource information."""
        # User Pool outputs
        cdk.CfnOutput(
            self,
            "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="ID of the Cognito User Pool",
            export_name=f"{self.stack_name}-UserPoolId"
        )
        
        cdk.CfnOutput(
            self,
            "UserPoolArn",
            value=self.user_pool.user_pool_arn,
            description="ARN of the Cognito User Pool",
            export_name=f"{self.stack_name}-UserPoolArn"
        )
        
        # User Pool Client outputs
        cdk.CfnOutput(
            self,
            "UserPoolClientId",
            value=self.user_pool_client.user_pool_client_id,
            description="ID of the Cognito User Pool Client",
            export_name=f"{self.stack_name}-UserPoolClientId"
        )
        
        # Hosted UI outputs
        cdk.CfnOutput(
            self,
            "HostedUIUrl",
            value=f"https://{self.domain_prefix}.auth.{cdk.Aws.REGION}.amazoncognito.com",
            description="URL of the Cognito Hosted UI",
            export_name=f"{self.stack_name}-HostedUIUrl"
        )
        
        cdk.CfnOutput(
            self,
            "LoginUrl",
            value=f"https://{self.domain_prefix}.auth.{cdk.Aws.REGION}.amazoncognito.com/login?client_id={self.user_pool_client.user_pool_client_id}&response_type=code&scope=openid+email+profile&redirect_uri=https://localhost:3000/callback",
            description="Login URL for the application",
            export_name=f"{self.stack_name}-LoginUrl"
        )
        
        cdk.CfnOutput(
            self,
            "LogoutUrl",
            value=f"https://{self.domain_prefix}.auth.{cdk.Aws.REGION}.amazoncognito.com/logout?client_id={self.user_pool_client.user_pool_client_id}&logout_uri=https://localhost:3000/logout",
            description="Logout URL for the application",
            export_name=f"{self.stack_name}-LogoutUrl"
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get configuration from context or environment variables
    app_name = app.node.try_get_context("appName") or os.environ.get("APP_NAME", "ecommerce")
    domain_prefix = app.node.try_get_context("domainPrefix") or os.environ.get("DOMAIN_PREFIX")
    callback_urls = app.node.try_get_context("callbackUrls") or [
        "https://localhost:3000/callback",
        "https://example.com/callback"
    ]
    logout_urls = app.node.try_get_context("logoutUrls") or [
        "https://localhost:3000/logout", 
        "https://example.com/logout"
    ]
    
    # Create the stack
    CognitoUserPoolStack(
        app,
        "CognitoUserPoolStack",
        app_name=app_name,
        domain_prefix=domain_prefix,
        callback_urls=callback_urls,
        logout_urls=logout_urls,
        description="Complete user authentication system with Cognito User Pools",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION")
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()