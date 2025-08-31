# Simple Website Hosting with AWS Lightsail - Terraform Configuration
# This configuration creates a complete WordPress hosting environment using Lightsail
# including instance, static IP, DNS configuration, and security settings

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  # Combine project name with random suffix for unique identifiers
  resource_prefix = "${var.project_name}-${random_id.suffix.hex}"
  
  # Availability zone for Lightsail instance (first AZ in the region)
  availability_zone = "${var.aws_region}a"
  
  # Combined tags for all resources
  common_tags = merge(
    {
      Name        = local.resource_prefix
      Environment = var.environment
      Project     = "Simple Website Hosting"
      ManagedBy   = "Terraform"
      Recipe      = "simple-website-hosting-lightsail"
    },
    var.additional_tags
  )
}

# WordPress Lightsail Instance
# Creates a virtual private server with pre-configured WordPress LAMP stack
resource "aws_lightsail_instance" "wordpress" {
  name              = local.resource_prefix
  availability_zone = local.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.instance_bundle_id
  key_pair_name     = var.instance_key_pair_name != "" ? var.instance_key_pair_name : null

  # User data script to customize WordPress installation
  user_data = <<-EOF
    #!/bin/bash
    # Update system packages
    apt-get update && apt-get upgrade -y
    
    # Configure WordPress with basic security settings
    # Note: Bitnami WordPress stores admin password in /home/bitnami/bitnami_application_password
    
    # Set proper file permissions for WordPress
    chown -R bitnami:daemon /opt/bitnami/wordpress/wp-content/
    chmod -R 755 /opt/bitnami/wordpress/wp-content/
    
    # Enable WordPress security plugins and updates
    sudo -u bitnami wp core update --path=/opt/bitnami/wordpress/ || true
    sudo -u bitnami wp plugin update --all --path=/opt/bitnami/wordpress/ || true
    
    # Configure Apache for better performance
    echo "ServerTokens Prod" >> /opt/bitnami/apache2/conf/httpd.conf
    echo "ServerSignature Off" >> /opt/bitnami/apache2/conf/httpd.conf
    
    # Restart services to apply changes
    /opt/bitnami/ctlscript.sh restart apache
    /opt/bitnami/ctlscript.sh restart mysql
    
    # Log completion
    echo "WordPress instance configuration completed at $(date)" >> /var/log/wordpress-setup.log
  EOF

  tags = local.common_tags
}

# Static IP Address for consistent access
# Provides a permanent IP address that persists through instance restarts
resource "aws_lightsail_static_ip" "wordpress" {
  count = var.enable_static_ip ? 1 : 0
  name  = "${local.resource_prefix}-ip"
}

# Attach static IP to the WordPress instance
resource "aws_lightsail_static_ip_attachment" "wordpress" {
  count          = var.enable_static_ip ? 1 : 0
  static_ip_name = aws_lightsail_static_ip.wordpress[0].name
  instance_name  = aws_lightsail_instance.wordpress.name

  # Ensure instance is ready before attaching IP
  depends_on = [aws_lightsail_instance.wordpress]
}

# Configure firewall rules for web traffic
# Opens necessary ports for HTTP, HTTPS, and SSH access
resource "aws_lightsail_instance_public_ports" "wordpress" {
  instance_name = aws_lightsail_instance.wordpress.name

  # HTTP port (80) - for web traffic and Let's Encrypt challenges
  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
    cidrs     = ["0.0.0.0/0"]
  }

  # HTTPS port (443) - for secure web traffic
  port_info {
    protocol  = "tcp"
    from_port = 443
    to_port   = 443
    cidrs     = ["0.0.0.0/0"]
  }

  # SSH port (22) - for administrative access
  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
    cidrs     = var.allowed_ssh_cidrs
  }

  # MySQL port (3306) - typically not needed externally for WordPress
  # Uncomment if you need direct database access
  # port_info {
  #   protocol  = "tcp"
  #   from_port = 3306
  #   to_port   = 3306
  #   cidrs     = var.allowed_ssh_cidrs
  # }

  depends_on = [aws_lightsail_instance.wordpress]
}

# DNS Zone for custom domain (optional)
# Creates a Lightsail-managed DNS zone for custom domain configuration
resource "aws_lightsail_domain" "wordpress" {
  count       = var.custom_domain != "" && var.create_dns_zone ? 1 : 0
  domain_name = var.custom_domain

  tags = local.common_tags
}

# A record pointing to static IP (root domain)
resource "aws_lightsail_domain_entry" "wordpress_root" {
  count  = var.custom_domain != "" && var.create_dns_zone && var.enable_static_ip ? 1 : 0
  domain_name = aws_lightsail_domain.wordpress[0].domain_name
  name   = ""  # Root domain (@)
  type   = "A"
  target = aws_lightsail_static_ip.wordpress[0].ip_address

  depends_on = [
    aws_lightsail_domain.wordpress,
    aws_lightsail_static_ip.wordpress
  ]
}

# CNAME record for www subdomain
resource "aws_lightsail_domain_entry" "wordpress_www" {
  count  = var.custom_domain != "" && var.create_dns_zone ? 1 : 0
  domain_name = aws_lightsail_domain.wordpress[0].domain_name
  name   = "www"
  type   = "CNAME"
  target = var.custom_domain

  depends_on = [aws_lightsail_domain.wordpress]
}

# Optional: Create instance snapshot for backup
resource "aws_lightsail_instance_snapshot" "wordpress_initial" {
  count         = var.enable_automatic_backups ? 1 : 0
  name          = "${local.resource_prefix}-initial-snapshot"
  instance_name = aws_lightsail_instance.wordpress.name

  tags = merge(local.common_tags, {
    Type        = "Initial Snapshot"
    Description = "Initial snapshot after WordPress installation"
  })

  # Create snapshot after instance is fully configured
  depends_on = [
    aws_lightsail_instance.wordpress,
    aws_lightsail_instance_public_ports.wordpress
  ]
}

# Data source to get instance metadata after creation
data "aws_lightsail_instance" "wordpress" {
  name = aws_lightsail_instance.wordpress.name

  depends_on = [aws_lightsail_instance.wordpress]
}

# Optional: CloudWatch Log Group for instance monitoring
# Note: Lightsail instances send logs to CloudWatch automatically
resource "aws_cloudwatch_log_group" "wordpress" {
  count             = var.enable_monitoring ? 1 : 0
  name              = "/aws/lightsail/${local.resource_prefix}"
  retention_in_days = 30

  tags = local.common_tags
}