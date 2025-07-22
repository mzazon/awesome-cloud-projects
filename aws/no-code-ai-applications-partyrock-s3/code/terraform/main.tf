# Main Terraform configuration for PartyRock AI Applications with S3 and CloudFront
# This configuration creates the complete infrastructure for hosting a static website
# that showcases PartyRock AI applications with global content delivery

# Generate random ID for unique resource naming
resource "random_id" "bucket_suffix" {
  byte_length = var.random_id_length / 2
  
  keepers = {
    # Recreate random ID if bucket name prefix changes
    bucket_name_prefix = var.bucket_name_prefix
  }
}

# Get current AWS caller identity for account information
data "aws_caller_identity" "current" {}

# Get current AWS region information
data "aws_region" "current" {}

# Create S3 bucket for static website hosting
resource "aws_s3_bucket" "website" {
  # Generate unique bucket name using prefix and random suffix
  bucket = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"

  # Force destroy bucket even if it contains objects (for development/testing)
  # Set to false for production environments
  force_destroy = var.environment != "prod"

  tags = merge(var.resource_tags, {
    Name        = "${var.project_name}-website-bucket"
    Purpose     = "Static Website Hosting"
    ContentType = "PartyRock AI Application Showcase"
  })
}

# Configure S3 bucket versioning for data protection
resource "aws_s3_bucket_versioning" "website" {
  count  = var.enable_versioning ? 1 : 0
  bucket = aws_s3_bucket.website.id
  
  versioning_configuration {
    status = "Enabled"
  }

  depends_on = [aws_s3_bucket.website]
}

# Configure S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  count  = var.enable_encryption ? 1 : 0
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.encryption_algorithm
    }
    
    # Enable bucket key to reduce encryption costs for KMS
    bucket_key_enabled = var.encryption_algorithm == "aws:kms"
  }

  depends_on = [aws_s3_bucket.website]
}

# Configure S3 bucket for static website hosting
resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = var.index_document
  }

  error_document {
    key = var.error_document
  }

  depends_on = [aws_s3_bucket.website]
}

# Configure S3 bucket CORS for web application access
resource "aws_s3_bucket_cors_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  cors_rule {
    allowed_headers = var.allowed_headers
    allowed_methods = var.allowed_methods
    allowed_origins = var.allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }

  depends_on = [aws_s3_bucket.website]
}

# Remove S3 bucket public access block to enable public website hosting
resource "aws_s3_bucket_public_access_block" "website" {
  count  = var.enable_public_access ? 1 : 0
  bucket = aws_s3_bucket.website.id

  # Allow public access for static website hosting
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false

  depends_on = [aws_s3_bucket.website]
}

# Create S3 bucket policy for public read access
resource "aws_s3_bucket_policy" "website" {
  count  = var.enable_public_access ? 1 : 0
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })

  depends_on = [
    aws_s3_bucket.website,
    aws_s3_bucket_public_access_block.website
  ]
}

# Upload sample index.html file to S3 bucket
resource "aws_s3_object" "index_html" {
  count = var.upload_sample_website ? 1 : 0
  
  bucket       = aws_s3_bucket.website.id
  key          = var.index_document
  content_type = "text/html"
  
  # Sample HTML content for PartyRock AI application showcase
  content = templatefile("${path.module}/templates/index.html.tpl", {
    partyrock_app_url = var.partyrock_app_url
    project_name      = var.project_name
    cloudfront_url    = var.enable_cloudfront ? "https://${aws_cloudfront_distribution.website[0].domain_name}" : ""
    s3_website_url    = "http://${aws_s3_bucket.website.bucket}.s3-website.${data.aws_region.current.name}.amazonaws.com"
  })

  tags = merge(var.resource_tags, {
    Name        = "Index Document"
    ContentType = "Website Landing Page"
  })

  depends_on = [
    aws_s3_bucket.website,
    aws_s3_bucket_website_configuration.website
  ]
}

# Upload sample error.html file to S3 bucket
resource "aws_s3_object" "error_html" {
  count = var.upload_sample_website ? 1 : 0
  
  bucket       = aws_s3_bucket.website.id
  key          = var.error_document
  content_type = "text/html"
  
  # Sample error page content
  content = templatefile("${path.module}/templates/error.html.tpl", {
    project_name   = var.project_name
    s3_website_url = "http://${aws_s3_bucket.website.bucket}.s3-website.${data.aws_region.current.name}.amazonaws.com"
  })

  tags = merge(var.resource_tags, {
    Name        = "Error Document"
    ContentType = "Website Error Page"
  })

  depends_on = [
    aws_s3_bucket.website,
    aws_s3_bucket_website_configuration.website
  ]
}

# Create CloudFront Origin Access Control for secure S3 access
resource "aws_cloudfront_origin_access_control" "website" {
  count = var.enable_cloudfront ? 1 : 0
  
  name                              = "${var.project_name}-oac-${random_id.bucket_suffix.hex}"
  description                       = "Origin Access Control for ${var.project_name} S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Create CloudFront distribution for global content delivery
resource "aws_cloudfront_distribution" "website" {
  count = var.enable_cloudfront ? 1 : 0
  
  # S3 origin configuration
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.website.bucket}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website[0].id
  }

  # Enable the distribution
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${var.project_name} PartyRock AI application"
  default_root_object = var.index_document
  price_class         = var.cloudfront_price_class

  # Default cache behavior
  default_cache_behavior {
    target_origin_id       = "S3-${aws_s3_bucket.website.bucket}"
    viewer_protocol_policy = "redirect-to-https"
    compress               = var.enable_compression

    # Allowed methods for web application functionality
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    # Cache and origin request policies
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"  # Managed-CachingDisabled
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"  # Managed-CORS-S3Origin

    # TTL configuration
    min_ttl     = 0
    default_ttl = var.cloudfront_default_ttl
    max_ttl     = var.cloudfront_max_ttl
  }

  # Custom error pages configuration
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/${var.error_document}"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/${var.error_document}"
  }

  # Geographic restrictions (none by default)
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # SSL/TLS configuration
  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  # Web Application Firewall (WAF) integration
  web_acl_id = null  # Can be configured separately for enhanced security

  tags = merge(var.resource_tags, {
    Name        = "${var.project_name}-cloudfront-distribution"
    Purpose     = "Global Content Delivery"
    ContentType = "PartyRock AI Application CDN"
  })

  depends_on = [
    aws_s3_bucket.website,
    aws_cloudfront_origin_access_control.website
  ]
}

# Update S3 bucket policy to allow CloudFront access if CloudFront is enabled
resource "aws_s3_bucket_policy" "cloudfront_access" {
  count  = var.enable_cloudfront && var.enable_public_access ? 1 : 0
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      },
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website[0].arn
          }
        }
      }
    ]
  })

  depends_on = [
    aws_s3_bucket.website,
    aws_s3_bucket_public_access_block.website,
    aws_cloudfront_distribution.website
  ]
}

# Local file for the index.html template if not using embedded content
resource "local_file" "index_template" {
  count = var.upload_sample_website ? 1 : 0
  
  filename = "${path.module}/templates/index.html.tpl"
  content = <<-EOT
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Business Name Generator - ${project_name}</title>
    <meta name="description" content="Experience the power of generative AI with our no-code application built using Amazon PartyRock and hosted on AWS.">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            line-height: 1.6;
            color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        
        .container { 
            max-width: 900px; 
            margin: 0 auto; 
            padding: 40px 20px;
            background: white;
            border-radius: 10px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.1);
            margin-top: 40px;
        }
        
        h1 {
            color: #2c3e50;
            margin-bottom: 20px;
            font-size: 2.5em;
            text-align: center;
        }
        
        .subtitle {
            text-align: center;
            color: #7f8c8d;
            margin-bottom: 40px;
            font-size: 1.2em;
        }
        
        .partyrock-embed { 
            border: 2px solid #e74c3c;
            padding: 30px; 
            border-radius: 10px;
            margin: 30px 0;
            background: #fdf2f2;
            text-align: center;
        }
        
        .partyrock-embed h2 {
            color: #e74c3c;
            margin-bottom: 15px;
        }
        
        .btn { 
            background: linear-gradient(45deg, #ff6b6b, #ee5a24);
            color: white; 
            padding: 15px 30px; 
            text-decoration: none; 
            border-radius: 25px;
            display: inline-block;
            margin: 20px 0;
            transition: all 0.3s ease;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 1px;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(238, 90, 36, 0.4);
        }
        
        .features {
            margin: 40px 0;
        }
        
        .features h2 {
            color: #2c3e50;
            margin-bottom: 20px;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        
        .features ul {
            list-style: none;
        }
        
        .features li {
            padding: 10px 0;
            padding-left: 30px;
            position: relative;
        }
        
        .features li::before {
            content: "✨";
            position: absolute;
            left: 0;
            top: 10px;
        }
        
        .tech-stack {
            background: #ecf0f1;
            padding: 20px;
            border-radius: 10px;
            margin: 30px 0;
        }
        
        .tech-stack h3 {
            color: #2c3e50;
            margin-bottom: 15px;
        }
        
        .tech-badges {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
        }
        
        .badge {
            background: #3498db;
            color: white;
            padding: 5px 12px;
            border-radius: 15px;
            font-size: 0.9em;
        }
        
        .aws-badge { background: #ff9900; }
        .ai-badge { background: #9b59b6; }
        .web-badge { background: #27ae60; }
        
        footer {
            text-align: center;
            margin-top: 40px;
            padding-top: 20px;
            border-top: 1px solid #ecf0f1;
            color: #7f8c8d;
        }
        
        @media (max-width: 768px) {
            .container {
                margin: 20px;
                padding: 20px;
            }
            
            h1 {
                font-size: 2em;
            }
            
            .tech-badges {
                justify-content: center;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🤖 AI-Powered Business Name Generator</h1>
        <p class="subtitle">Experience the power of generative AI with our no-code application built using Amazon PartyRock and hosted on AWS.</p>
        
        <div class="partyrock-embed">
            <h2>🚀 Try the Application</h2>
            <p>Click the button below to access our AI business name generator powered by Amazon Bedrock:</p>
            <a href="${partyrock_app_url}" class="btn" target="_blank">
                Launch AI App
            </a>
            %{ if partyrock_app_url == "YOUR_PARTYROCK_APP_URL" }
            <p><em>Note: Replace the PartyRock app URL in your Terraform variables to link to your actual application.</em></p>
            %{ endif }
        </div>
        
        <div class="features">
            <h2>✨ Features</h2>
            <ul>
                <li>AI-powered name generation using Amazon Bedrock foundation models</li>
                <li>Industry-specific suggestions tailored to your business sector</li>
                <li>Target audience consideration for maximum impact</li>
                <li>Logo concept generation with visual branding ideas</li>
                <li>No-code development with instant deployment</li>
                <li>Global content delivery through CloudFront CDN</li>
            </ul>
        </div>
        
        <div class="tech-stack">
            <h3>🛠️ Technology Stack</h3>
            <div class="tech-badges">
                <span class="badge aws-badge">Amazon PartyRock</span>
                <span class="badge ai-badge">Amazon Bedrock</span>
                <span class="badge aws-badge">Amazon S3</span>
                <span class="badge aws-badge">CloudFront CDN</span>
                <span class="badge web-badge">Static Website</span>
                <span class="badge">Terraform</span>
            </div>
        </div>
        
        <footer>
            <p>Deployed with ❤️ using AWS infrastructure | Managed by Terraform</p>
            %{ if cloudfront_url != "" }
            <p>CDN URL: <a href="${cloudfront_url}">${cloudfront_url}</a></p>
            %{ endif }
            <p>S3 Website: <a href="${s3_website_url}">${s3_website_url}</a></p>
        </footer>
    </div>
</body>
</html>
EOT

  depends_on = [aws_s3_bucket.website]
}

# Local file for the error.html template
resource "local_file" "error_template" {
  count = var.upload_sample_website ? 1 : 0
  
  filename = "${path.module}/templates/error.html.tpl"
  content = <<-EOT
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - ${project_name}</title>
    <style>
        body { 
            font-family: Arial, sans-serif; 
            margin: 0;
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        
        .container { 
            max-width: 600px; 
            text-align: center;
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.1);
        }
        
        h1 {
            color: #e74c3c;
            font-size: 4em;
            margin-bottom: 20px;
        }
        
        h2 {
            color: #2c3e50;
            margin-bottom: 20px;
        }
        
        p {
            color: #7f8c8d;
            margin-bottom: 30px;
            line-height: 1.6;
        }
        
        .btn {
            background: linear-gradient(45deg, #3498db, #2980b9);
            color: white;
            padding: 15px 30px;
            text-decoration: none;
            border-radius: 25px;
            display: inline-block;
            transition: all 0.3s ease;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(52, 152, 219, 0.4);
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>404</h1>
        <h2>Oops! Page Not Found</h2>
        <p>The page you're looking for doesn't exist. It might have been moved, deleted, or you entered the wrong URL.</p>
        <a href="${s3_website_url}" class="btn">Return to Home</a>
    </div>
</body>
</html>
EOT

  depends_on = [aws_s3_bucket.website]
}