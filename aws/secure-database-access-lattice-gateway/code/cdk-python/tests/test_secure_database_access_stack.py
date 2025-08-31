"""
Unit tests for Secure Database Access Stack with VPC Lattice Resource Gateway

This module contains unit tests for the CDK stack that creates secure
cross-account database access using AWS VPC Lattice Resource Gateway.
"""

import pytest
import aws_cdk as cdk
from aws_cdk import assertions

from stacks.secure_database_access_stack import SecureDatabaseAccessStack


class TestSecureDatabaseAccessStack:
    """Test class for SecureDatabaseAccessStack"""
    
    def setup_method(self):
        """Set up test fixtures before each test method"""
        self.app = cdk.App()
        self.consumer_account_id = "123456789012"
        
    def test_stack_creation(self):
        """Test that the stack can be created without errors"""
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        # Basic assertion that stack was created
        assert stack is not None
        assert stack.stack_name == "TestStack"
    
    def test_vpc_creation(self):
        """Test that VPC is created with correct configuration"""
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Check that VPC is created
        template.has_resource_properties("AWS::EC2::VPC", {
            "CidrBlock": "10.0.0.0/16",
            "EnableDnsHostnames": True,
            "EnableDnsSupport": True,
        })
        
        # Check that subnets are created
        template.resource_count_is("AWS::EC2::Subnet", 6)  # 2 public + 2 private + 2 isolated
    
    def test_security_groups_creation(self):
        """Test that security groups are created with proper rules"""
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Check that security groups are created
        template.has_resource_properties("AWS::EC2::SecurityGroup", {
            "GroupDescription": "Security group for VPC Lattice shared RDS database"
        })
        
        template.has_resource_properties("AWS::EC2::SecurityGroup", {
            "GroupDescription": "Security group for VPC Lattice Resource Gateway"
        })
    
    def test_rds_database_creation(self):
        """Test that RDS database is created with security configuration"""
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Check that RDS instance is created
        template.has_resource_properties("AWS::RDS::DBInstance", {
            "DBInstanceClass": "db.t3.micro",
            "Engine": "mysql",
            "PubliclyAccessible": False,
            "StorageEncrypted": True,
        })
        
        # Check that DB subnet group is created
        template.has_resource_properties("AWS::RDS::DBSubnetGroup", {
            "DBSubnetGroupDescription": "Subnet group for VPC Lattice shared database"
        })
    
    def test_secrets_manager_integration(self):
        """Test that database credentials are stored in Secrets Manager"""
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Check that secret is created
        template.has_resource_properties("AWS::SecretsManager::Secret", {
            "Description": "Credentials for VPC Lattice shared database"
        })
    
    def test_ram_resource_share_creation(self):
        """Test that AWS RAM resource share is created"""
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Check that RAM resource share is created
        template.has_resource_properties("AWS::RAM::ResourceShare", {
            "Principals": [self.consumer_account_id],
            "AllowExternalPrincipals": True,
        })
    
    def test_cloudwatch_log_groups_creation(self):
        """Test that CloudWatch log groups are created for monitoring"""
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Check that log groups are created
        template.has_resource_properties("AWS::Logs::LogGroup", {
            "LogGroupName": assertions.Match.string_like_regexp(r"/aws/vpc/flowlogs/.*")
        })
        
        template.has_resource_properties("AWS::Logs::LogGroup", {
            "LogGroupName": assertions.Match.string_like_regexp(r"/aws/vpc-lattice/.*")
        })
    
    def test_stack_outputs(self):
        """Test that required stack outputs are created"""
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Check that key outputs are present
        template.has_output("VpcId", {})
        template.has_output("DatabaseEndpoint", {})
        template.has_output("DatabasePort", {})
        template.has_output("ConsumerAccountId", {})
    
    def test_tagging_strategy(self):
        """Test that resources are properly tagged"""
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        # Check that stack has proper tags applied
        template = assertions.Template.from_stack(stack)
        
        # Note: Tag checking in CDK tests can be complex due to how tags are applied
        # This is a basic check that the stack was created successfully with tagging
        assert stack.tags.tag_values().get("Project") == "VPCLatticeResourceGateway"
    
    def test_invalid_consumer_account_id(self):
        """Test that invalid consumer account ID raises appropriate error"""
        with pytest.raises(Exception):
            SecureDatabaseAccessStack(
                self.app,
                "TestStack",
                consumer_account_id="invalid-account-id",
                env=cdk.Environment(account="123456789012", region="us-east-1")
            )
    
    def test_configuration_parameters(self):
        """Test that configuration parameters are properly applied"""
        # Set context for testing
        self.app.node.set_context("database_instance_class", "db.t3.small")
        self.app.node.set_context("enable_deletion_protection", True)
        self.app.node.set_context("multi_az_deployment", True)
        
        stack = SecureDatabaseAccessStack(
            self.app,
            "TestStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Note: Some configuration checks would require more complex template analysis
        # This ensures the stack can be created with different configurations
        assert stack is not None


# Integration test class for more complex scenarios
class TestSecureDatabaseAccessStackIntegration:
    """Integration tests for complex scenarios"""
    
    def setup_method(self):
        """Set up test fixtures"""
        self.app = cdk.App()
        self.consumer_account_id = "123456789012"
    
    def test_production_configuration(self):
        """Test production-like configuration"""
        # Set production context
        self.app.node.set_context("environment", "production")
        self.app.node.set_context("enable_deletion_protection", True)
        self.app.node.set_context("multi_az_deployment", True)
        self.app.node.set_context("enable_performance_insights", True)
        self.app.node.set_context("enable_enhanced_monitoring", True)
        self.app.node.set_context("database_backup_retention_days", 30)
        
        stack = SecureDatabaseAccessStack(
            self.app,
            "ProductionStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Verify production settings are applied
        template.has_resource_properties("AWS::RDS::DBInstance", {
            "BackupRetentionPeriod": 30,
            "MultiAZ": True,
            "DeletionProtection": True,
        })
    
    def test_development_configuration(self):
        """Test development-optimized configuration"""
        # Set development context
        self.app.node.set_context("environment", "development")
        self.app.node.set_context("enable_deletion_protection", False)
        self.app.node.set_context("multi_az_deployment", False)
        self.app.node.set_context("database_backup_retention_days", 1)
        
        stack = SecureDatabaseAccessStack(
            self.app,
            "DevelopmentStack",
            consumer_account_id=self.consumer_account_id,
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        
        template = assertions.Template.from_stack(stack)
        
        # Verify development settings are applied
        template.has_resource_properties("AWS::RDS::DBInstance", {
            "BackupRetentionPeriod": 1,
            "MultiAZ": False,
            "DeletionProtection": False,
        })


if __name__ == "__main__":
    pytest.main([__file__])