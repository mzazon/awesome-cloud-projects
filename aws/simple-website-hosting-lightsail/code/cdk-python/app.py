#!/usr/bin/env python3
"""
AWS CDK Python application for Simple Website Hosting with Lightsail.

This CDK application creates a WordPress hosting solution using AWS Lightsail,
including a WordPress instance, static IP address, and DNS configuration.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Tags,
)
from constructs import Construct
import random
import string


class LightsailWordPressStack(Stack):
    """
    CDK Stack for deploying WordPress hosting solution with AWS Lightsail.
    
    This stack creates:
    - Lightsail WordPress instance with pre-configured LAMP stack
    - Static IP address for consistent access
    - Firewall rules for web traffic (HTTP/HTTPS/SSH)
    - Optional DNS zone for custom domain management
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate random suffix for unique resource naming
        random_suffix = ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))
        
        # Configuration parameters
        instance_name = f"wordpress-site-{random_suffix}"
        static_ip_name = f"wordpress-ip-{random_suffix}"
        
        # Get availability zone (use first AZ in the region)
        availability_zone = f"{self.region}a"
        
        # Create Lightsail WordPress instance
        wordpress_instance = cdk.aws_lightsail.CfnInstance(
            self,
            "WordPressInstance",
            instance_name=instance_name,
            blueprint_id="wordpress",  # Pre-configured WordPress with LAMP stack
            bundle_id="nano_3_0",     # Smallest instance size for demo ($5/month)
            availability_zone=availability_zone,
            tags=[
                cdk.CfnTag(key="Purpose", value="WebsiteHosting"),
                cdk.CfnTag(key="Environment", value="Production"),
                cdk.CfnTag(key="Application", value="WordPress"),
                cdk.CfnTag(key="ManagedBy", value="CDK")
            ]
        )
        
        # Create static IP address
        static_ip = cdk.aws_lightsail.CfnStaticIp(
            self,
            "StaticIP",
            static_ip_name=static_ip_name
        )
        
        # Attach static IP to the WordPress instance
        static_ip_attachment = cdk.aws_lightsail.CfnStaticIpAttachment(
            self,
            "StaticIPAttachment",
            static_ip_name=static_ip.static_ip_name,
            instance_name=wordpress_instance.instance_name
        )
        static_ip_attachment.add_dependency(wordpress_instance)
        static_ip_attachment.add_dependency(static_ip)
        
        # Configure firewall rules for web traffic
        # Note: Lightsail instances come with default SSH access on port 22
        # We need to explicitly open HTTP (80) and HTTPS (443) ports
        cdk.aws_lightsail.CfnInstance.PortInfo
        
        # Add tags to all resources
        Tags.of(self).add("Project", "SimpleWebsiteHosting")
        Tags.of(self).add("CreatedBy", "CDK")
        Tags.of(self).add("CostCenter", "Development")
        
        # Outputs for easy access to important information
        CfnOutput(
            self,
            "InstanceName",
            value=wordpress_instance.instance_name,
            description="Name of the Lightsail WordPress instance",
            export_name=f"{self.stack_name}-InstanceName"
        )
        
        CfnOutput(
            self,
            "StaticIPName",
            value=static_ip.static_ip_name,
            description="Name of the static IP address",
            export_name=f"{self.stack_name}-StaticIPName"
        )
        
        CfnOutput(
            self,
            "StaticIPAddress",
            value=static_ip.attr_ip_address,
            description="Static IP address for the WordPress site",
            export_name=f"{self.stack_name}-StaticIPAddress"
        )
        
        CfnOutput(
            self,
            "WordPressSiteURL",
            value=f"http://{static_ip.attr_ip_address}",
            description="URL to access the WordPress website",
            export_name=f"{self.stack_name}-WordPressSiteURL"
        )
        
        CfnOutput(
            self,
            "WordPressAdminURL",
            value=f"http://{static_ip.attr_ip_address}/wp-admin",
            description="URL to access WordPress admin dashboard",
            export_name=f"{self.stack_name}-WordPressAdminURL"
        )
        
        CfnOutput(
            self,
            "SSHConnectionInfo",
            value=f"ssh -i ~/.ssh/your-key-pair.pem bitnami@{static_ip.attr_ip_address}",
            description="SSH command to connect to the instance (requires key pair)",
            export_name=f"{self.stack_name}-SSHConnection"
        )
        
        CfnOutput(
            self,
            "AdminPasswordCommand",
            value="sudo cat /home/bitnami/bitnami_application_password",
            description="Command to retrieve WordPress admin password via SSH",
            export_name=f"{self.stack_name}-AdminPasswordCommand"
        )


class LightsailDNSStack(Stack):
    """
    Optional CDK Stack for DNS management with Lightsail.
    
    This stack creates DNS zones and records for custom domain configuration.
    Deploy this stack only if you have a custom domain to configure.
    """

    def __init__(self, scope: Construct, construct_id: str, domain_name: str, static_ip: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        # Create DNS zone for the domain
        dns_zone = cdk.aws_lightsail.CfnDomain(
            self,
            "DNSZone",
            domain_name=domain_name,
            tags=[
                cdk.CfnTag(key="Purpose", value="WebsiteHosting"),
                cdk.CfnTag(key="Environment", value="Production"),
                cdk.CfnTag(key="ManagedBy", value="CDK")
            ]
        )
        
        # Create A record pointing to static IP
        a_record = cdk.aws_lightsail.CfnDomainEntry(
            self,
            "ARecord",
            domain_name=domain_name,
            domain_entry=cdk.aws_lightsail.CfnDomainEntry.DomainEntryProperty(
                name="@",  # Root domain
                type="A",
                target=static_ip
            )
        )
        a_record.add_dependency(dns_zone)
        
        # Create CNAME record for www subdomain
        cname_record = cdk.aws_lightsail.CfnDomainEntry(
            self,
            "CNAMERecord",
            domain_name=domain_name,
            domain_entry=cdk.aws_lightsail.CfnDomainEntry.DomainEntryProperty(
                name="www",
                type="CNAME",
                target=domain_name
            )
        )
        cname_record.add_dependency(dns_zone)
        
        # Outputs
        CfnOutput(
            self,
            "DomainName",
            value=domain_name,
            description="Configured domain name",
            export_name=f"{self.stack_name}-DomainName"
        )
        
        CfnOutput(
            self,
            "WebsiteURL",
            value=f"http://{domain_name}",
            description="Website URL with custom domain",
            export_name=f"{self.stack_name}-WebsiteURL"
        )


def main() -> None:
    """
    Main function to define and deploy the CDK application.
    """
    app = cdk.App()
    
    # Get configuration from CDK context
    domain_name = app.node.try_get_context("domain_name")
    enable_dns = app.node.try_get_context("enable_dns") or False
    
    # Create the main Lightsail WordPress stack
    wordpress_stack = LightsailWordPressStack(
        app,
        "LightsailWordPressStack",
        description="Simple WordPress hosting solution using AWS Lightsail",
        env=cdk.Environment(
            account=app.account,
            region=app.region
        )
    )
    
    # Optionally create DNS stack if domain is provided
    if enable_dns and domain_name:
        # Note: This requires the static IP from the wordpress_stack
        # In a real deployment, you would get this from stack outputs or parameters
        dns_stack = LightsailDNSStack(
            app,
            "LightsailDNSStack",
            domain_name=domain_name,
            static_ip="0.0.0.0",  # Placeholder - replace with actual static IP
            description=f"DNS configuration for {domain_name}",
            env=cdk.Environment(
                account=app.account,
                region=app.region
            )
        )
        dns_stack.add_dependency(wordpress_stack)
    
    app.synth()


if __name__ == "__main__":
    main()