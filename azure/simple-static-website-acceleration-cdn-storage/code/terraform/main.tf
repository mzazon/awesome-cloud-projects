# Static Website Acceleration with CDN and Storage
# This Terraform configuration creates a globally distributed static website
# using Azure Storage Account static hosting and Azure CDN for content delivery

# Generate random suffix for unique resource names
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
  numeric = true
}

# Data source to get current client configuration
data "azurerm_client_config" "current" {}

# Create Resource Group for all resources
resource "azurerm_resource_group" "main" {
  name     = "${var.resource_group_name}-${random_string.suffix.result}"
  location = var.location
  tags     = var.tags
}

# Create Storage Account with static website hosting capabilities
resource "azurerm_storage_account" "main" {
  name                     = "${var.storage_account_name_prefix}${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_account_replication_type
  account_kind             = "StorageV2"
  access_tier              = var.storage_account_access_tier

  # Enable static website hosting
  static_website {
    index_document     = var.index_document
    error_404_document = var.error_404_document
  }

  # Security configurations
  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = true
  shared_access_key_enabled        = true

  # Cross-Origin Resource Sharing (CORS) rules for web applications
  cors_rule {
    allowed_headers    = ["*"]
    allowed_methods    = ["GET", "HEAD", "OPTIONS"]
    allowed_origins    = ["*"]
    exposed_headers    = ["*"]
    max_age_in_seconds = 3600
  }

  tags = var.tags
}

# Create sample website content if enabled
resource "azurerm_storage_blob" "index_html" {
  count                  = var.create_sample_content ? 1 : 0
  name                   = var.index_document
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"

  source_content = templatefile("${path.module}/templates/index.html", {
    title       = "Global Product Catalog - Accelerated by Azure CDN"
    description = "Lightning-fast delivery worldwide via Azure CDN"
  })

  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_storage_blob" "styles_css" {
  count                  = var.create_sample_content ? 1 : 0
  name                   = "styles.css"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/css"

  source_content = file("${path.module}/templates/styles.css")

  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_storage_blob" "app_js" {
  count                  = var.create_sample_content ? 1 : 0
  name                   = "app.js"
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "application/javascript"

  source_content = file("${path.module}/templates/app.js")

  depends_on = [azurerm_storage_account.main]
}

resource "azurerm_storage_blob" "error_404_html" {
  count                  = var.create_sample_content ? 1 : 0
  name                   = var.error_404_document
  storage_account_name   = azurerm_storage_account.main.name
  storage_container_name = "$web"
  type                   = "Block"
  content_type           = "text/html"

  source_content = templatefile("${path.module}/templates/404.html", {
    title = "Page Not Found - Global Store"
  })

  depends_on = [azurerm_storage_account.main]
}

# Create CDN Profile for global content delivery
resource "azurerm_cdn_profile" "main" {
  name                = "${var.cdn_profile_name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = var.cdn_sku
  tags                = var.tags
}

# Create CDN Endpoint pointing to the static website
resource "azurerm_cdn_endpoint" "main" {
  name                = "${var.cdn_endpoint_name_prefix}-${random_string.suffix.result}"
  profile_name        = azurerm_cdn_profile.main.name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Configure origin pointing to storage account static website
  origin {
    name      = "storage-origin"
    host_name = replace(replace(azurerm_storage_account.main.primary_web_endpoint, "https://", ""), "/", "")
  }

  # Enable compression for better performance
  is_compression_enabled = var.enable_cdn_compression
  content_types_to_compress = [
    "text/plain",
    "text/html",
    "text/css",
    "application/x-javascript",
    "text/javascript",
    "application/javascript",
    "application/json",
    "application/xml",
    "text/xml",
    "image/svg+xml"
  ]

  # Configure caching behavior
  query_string_caching_behaviour = var.query_string_caching_behavior
  optimization_type             = var.optimization_type

  # Configure origin host header to match storage account
  origin_host_header = replace(replace(azurerm_storage_account.main.primary_web_endpoint, "https://", ""), "/", "")

  # Delivery rules for enhanced caching
  delivery_rule {
    name  = "CacheStaticAssets"
    order = 1

    # Match CSS, JS, and image files
    conditions {
      url_file_extension_condition {
        operator      = "Equal"
        match_values  = ["css", "js", "png", "jpg", "jpeg", "gif", "svg", "ico", "woff", "woff2", "ttf", "eot"]
        transforms    = ["Lowercase"]
      }
    }

    # Cache for 30 days
    actions {
      cache_expiration_action {
        behavior = "Override"
        duration = "30.00:00:00"
      }
    }
  }

  delivery_rule {
    name  = "CacheHTMLFiles"
    order = 2

    # Match HTML files
    conditions {
      url_file_extension_condition {
        operator     = "Equal"
        match_values = ["html", "htm"]
        transforms   = ["Lowercase"]
      }
    }

    # Cache for 1 hour
    actions {
      cache_expiration_action {
        behavior = "Override"
        duration = "01:00:00"
      }
    }
  }

  tags = var.tags

  depends_on = [azurerm_storage_account.main]
}

# Create template files for sample content
resource "local_file" "index_html_template" {
  count    = var.create_sample_content ? 1 : 0
  filename = "${path.module}/templates/index.html"
  content = templatefile("${path.module}/sample-content/index.html.tpl", {})

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/templates"
  }
}

resource "local_file" "styles_css_template" {
  count    = var.create_sample_content ? 1 : 0
  filename = "${path.module}/templates/styles.css"
  content  = file("${path.module}/sample-content/styles.css")

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/templates"
  }
}

resource "local_file" "app_js_template" {
  count    = var.create_sample_content ? 1 : 0
  filename = "${path.module}/templates/app.js"
  content  = file("${path.module}/sample-content/app.js")

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/templates"
  }
}

resource "local_file" "error_404_html_template" {
  count    = var.create_sample_content ? 1 : 0
  filename = "${path.module}/templates/404.html"
  content = templatefile("${path.module}/sample-content/404.html.tpl", {})

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/templates"
  }
}

# Create sample content directory and files
resource "local_file" "sample_index_html" {
  count    = var.create_sample_content ? 1 : 0
  filename = "${path.module}/sample-content/index.html.tpl"
  content  = <<-EOT
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header>
        <h1>Welcome to Our Global Store</h1>
        <p>${description}</p>
    </header>
    <main>
        <section class="hero">
            <h2>Experience Global Performance</h2>
            <p>This website is delivered from Azure's global edge network, 
               ensuring fast loading times regardless of your location.</p>
        </section>
        <section class="products">
            <h3>Featured Products</h3>
            <div class="product-grid">
                <div class="product">Premium Headphones - $299</div>
                <div class="product">Smart Watch - $399</div>
                <div class="product">Wireless Speaker - $199</div>
            </div>
        </section>
    </main>
    <script src="app.js"></script>
</body>
</html>
EOT

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/sample-content"
  }
}

resource "local_file" "sample_styles_css" {
  count    = var.create_sample_content ? 1 : 0
  filename = "${path.module}/sample-content/styles.css"
  content  = <<-EOT
* { margin: 0; padding: 0; box-sizing: border-box; }
body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
header { background: #0078D4; color: white; padding: 2rem; text-align: center; }
.hero { padding: 3rem 2rem; background: #f4f4f4; text-align: center; }
.products { padding: 2rem; }
.product-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-top: 1rem; }
.product { background: white; padding: 1rem; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
EOT

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/sample-content"
  }
}

resource "local_file" "sample_app_js" {
  count    = var.create_sample_content ? 1 : 0
  filename = "${path.module}/sample-content/app.js"
  content  = <<-EOT
document.addEventListener('DOMContentLoaded', function() {
    console.log('Static website loaded via Azure CDN');
    
    // Add performance timing
    window.addEventListener('load', function() {
        const loadTime = performance.timing.loadEventEnd - performance.timing.navigationStart;
        console.log('Page load time: ' + loadTime + 'ms');
    });
});
EOT

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/sample-content"
  }
}

resource "local_file" "sample_404_html" {
  count    = var.create_sample_content ? 1 : 0
  filename = "${path.module}/sample-content/404.html.tpl"
  content  = <<-EOT
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${title}</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <header><h1>Page Not Found</h1></header>
    <main style="padding: 2rem; text-align: center;">
        <h2>404 - Content Not Available</h2>
        <p>The requested page could not be found.</p>
        <a href="/" style="color: #0078D4;">Return to Home</a>
    </main>
</body>
</html>
EOT

  provisioner "local-exec" {
    command = "mkdir -p ${path.module}/sample-content"
  }
}