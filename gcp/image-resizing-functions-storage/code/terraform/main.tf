# Main Terraform configuration for GCP image resizing solution
# This creates a serverless image processing pipeline using Cloud Functions and Cloud Storage

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Data source to get current project information
data "google_project" "current" {
  project_id = var.project_id
}

# Data source to get the default compute service account
data "google_compute_default_service_account" "default" {
  depends_on = [google_project_service.required_apis]
}

# Enable required Google Cloud APIs
resource "google_project_service" "required_apis" {
  for_each = var.enable_apis ? toset([
    "cloudfunctions.googleapis.com",
    "storage.googleapis.com",
    "eventarc.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com"
  ]) : toset([])

  project = var.project_id
  service = each.key

  # Prevent automatic disabling of the API when the resource is destroyed
  disable_on_destroy = false
}

# Local values for computed configurations
locals {
  # Generate bucket names with random suffix if not provided
  original_bucket_name = var.bucket_names.original != null ? var.bucket_names.original : "original-images-${random_id.suffix.hex}"
  resized_bucket_name  = var.bucket_names.resized != null ? var.bucket_names.resized : "resized-images-${random_id.suffix.hex}"
  
  # Service account email for the function
  function_service_account = data.google_compute_default_service_account.default.email
  
  # Labels with additional computed values
  common_labels = merge(var.labels, {
    environment = var.environment
    region      = var.region
  })
}

# Cloud Storage bucket for original images
resource "google_storage_bucket" "original_images" {
  name          = local.original_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for consistent security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Lifecycle configuration to manage costs
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Apply labels for resource management
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Cloud Storage bucket for resized images
resource "google_storage_bucket" "resized_images" {
  name          = local.resized_bucket_name
  location      = var.region
  storage_class = var.storage_class
  
  # Enable uniform bucket-level access for consistent security
  uniform_bucket_level_access = var.enable_uniform_bucket_level_access
  
  # Lifecycle configuration for cost optimization
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = 180
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  # Enable versioning for data protection
  versioning {
    enabled = true
  }
  
  # Apply labels for resource management
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Create function source code directory structure
resource "local_file" "function_requirements" {
  filename = "${path.module}/function-source/requirements.txt"
  content = <<-EOF
    Pillow>=10.0.0
    google-cloud-storage>=2.10.0
    functions-framework>=3.4.0
  EOF
}

# Create the main function code
resource "local_file" "function_main" {
  filename = "${path.module}/function-source/main.py"
  content = templatefile("${path.module}/function-template.py.tpl", {
    thumbnail_sizes = var.thumbnail_sizes
    supported_formats = var.supported_image_formats
  })
}

# Template file for the function code (referenced above)
resource "local_file" "function_template" {
  filename = "${path.module}/function-template.py.tpl"
  content = <<-'EOF'
import os
import tempfile
from PIL import Image
from google.cloud import storage
import functions_framework

# Initialize Cloud Storage client
storage_client = storage.Client()

# Define thumbnail sizes (width, height) from Terraform variables
THUMBNAIL_SIZES = [
%{ for size in thumbnail_sizes ~}
    (${size.width}, ${size.height}),
%{ endfor ~}
]

# Supported image formats from Terraform variables
SUPPORTED_FORMATS = {
%{ for format in supported_formats ~}
    '.${format}',
%{ endfor ~}
}

@functions_framework.cloud_event
def resize_image(cloud_event):
    """
    Triggered by Cloud Storage object finalization.
    Resizes uploaded images and saves thumbnails to the resized bucket.
    
    Args:
        cloud_event: The CloudEvent that triggered this function
    """
    # Parse event data
    data = cloud_event.data
    bucket_name = data['bucket']
    file_name = data['name']
    
    print(f"Processing image: {file_name} from bucket: {bucket_name}")
    
    # Skip if file is not an image
    file_extension = os.path.splitext(file_name.lower())[1]
    if file_extension not in SUPPORTED_FORMATS:
        print(f"Skipping non-image file: {file_name} (extension: {file_extension})")
        return
    
    # Skip if already a resized image (prevent recursion)
    if 'resized' in file_name.lower():
        print(f"Skipping already resized image: {file_name}")
        return
    
    try:
        # Download image from source bucket
        source_bucket = storage_client.bucket(bucket_name)
        source_blob = source_bucket.blob(file_name)
        
        # Create temporary file for download
        with tempfile.NamedTemporaryFile() as temp_file:
            source_blob.download_to_filename(temp_file.name)
            
            # Open and process image
            with Image.open(temp_file.name) as image:
                # Convert to RGB if necessary (for PNG with transparency)
                if image.mode in ('RGBA', 'LA', 'P'):
                    rgb_image = Image.new('RGB', image.size, (255, 255, 255))
                    if image.mode == 'P':
                        image = image.convert('RGBA')
                    rgb_image.paste(image, mask=image.split()[-1] if image.mode == 'RGBA' else None)
                    image = rgb_image
                
                # Get resized images bucket name from environment variable
                resized_bucket_name = os.environ.get('RESIZED_BUCKET')
                if not resized_bucket_name:
                    print("Error: RESIZED_BUCKET environment variable not set")
                    return
                
                resized_bucket = storage_client.bucket(resized_bucket_name)
                
                # Create thumbnails in different sizes
                for width, height in THUMBNAIL_SIZES:
                    try:
                        # Calculate resize dimensions maintaining aspect ratio
                        image_ratio = image.width / image.height
                        target_ratio = width / height
                        
                        if image_ratio > target_ratio:
                            # Image is wider, fit to width
                            new_width = width
                            new_height = int(width / image_ratio)
                        else:
                            # Image is taller, fit to height
                            new_height = height
                            new_width = int(height * image_ratio)
                        
                        # Resize image with high-quality resampling
                        resized_image = image.resize(
                            (new_width, new_height), 
                            Image.Resampling.LANCZOS
                        )
                        
                        # Generate output filename
                        name_parts = os.path.splitext(file_name)
                        output_name = f"{name_parts[0]}_resized_{width}x{height}.jpg"
                        
                        # Save to temporary file
                        with tempfile.NamedTemporaryFile(suffix='.jpg') as output_temp:
                            resized_image.save(
                                output_temp.name, 
                                'JPEG', 
                                quality=85, 
                                optimize=True
                            )
                            
                            # Upload to resized bucket
                            output_blob = resized_bucket.blob(output_name)
                            output_blob.upload_from_filename(
                                output_temp.name,
                                content_type='image/jpeg'
                            )
                            
                            print(f"Created thumbnail: {output_name} ({new_width}x{new_height})")
                    
                    except Exception as thumbnail_error:
                        print(f"Error creating {width}x{height} thumbnail: {str(thumbnail_error)}")
                        continue
                
                print(f"Successfully processed {file_name}")
    
    except Exception as e:
        print(f"Error processing {file_name}: {str(e)}")
        # Re-raise the exception to trigger function failure
        raise
    
    return "Processing completed"
EOF
}

# Create ZIP archive of function source code
data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = "${path.module}/function-source"
  output_path = "${path.module}/function-source.zip"
  
  depends_on = [
    local_file.function_main,
    local_file.function_requirements
  ]
}

# Cloud Storage bucket for function source code
resource "google_storage_bucket" "function_source" {
  name          = "${local.original_bucket_name}-function-source"
  location      = var.region
  storage_class = "STANDARD"
  
  # Apply labels
  labels = local.common_labels
  
  depends_on = [google_project_service.required_apis]
}

# Upload function source code to Cloud Storage
resource "google_storage_bucket_object" "function_source" {
  name   = "function-source-${random_id.suffix.hex}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
  
  # Ensure we redeploy if the source changes
  source_checksum = data.archive_file.function_source.output_base64sha256
}

# Cloud Function for image resizing
resource "google_cloudfunctions2_function" "resize_function" {
  name        = var.function_name
  location    = var.region
  description = "Serverless image resizing function triggered by Cloud Storage uploads"
  
  build_config {
    runtime     = var.function_config.runtime
    entry_point = var.function_config.entry_point
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }
  
  service_config {
    max_instance_count = var.function_config.max_instances
    min_instance_count = var.function_config.min_instances
    available_memory   = "${var.function_config.memory_mb}M"
    timeout_seconds    = var.function_config.timeout_seconds
    
    # Environment variables for the function
    environment_variables = {
      RESIZED_BUCKET = google_storage_bucket.resized_images.name
    }
    
    # Use the default compute service account
    service_account_email = local.function_service_account
  }
  
  # Event trigger configuration
  event_trigger {
    trigger_region        = var.region
    event_type           = "google.cloud.storage.object.v1.finalized"
    retry_policy         = "RETRY_POLICY_RETRY"
    service_account_email = local.function_service_account
    
    event_filters {
      attribute = "bucket"
      value     = google_storage_bucket.original_images.name
    }
  }
  
  # Labels for resource management
  labels = local.common_labels
  
  depends_on = [
    google_project_service.required_apis,
    google_storage_bucket.original_images,
    google_storage_bucket.resized_images
  ]
}

# IAM binding for function to read from original bucket
resource "google_storage_bucket_iam_member" "function_original_bucket_reader" {
  bucket = google_storage_bucket.original_images.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.function_service_account}"
  
  depends_on = [google_cloudfunctions2_function.resize_function]
}

# IAM binding for function to write to resized bucket
resource "google_storage_bucket_iam_member" "function_resized_bucket_writer" {
  bucket = google_storage_bucket.resized_images.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${local.function_service_account}"
  
  depends_on = [google_cloudfunctions2_function.resize_function]
}

# IAM binding for Eventarc service account (required for Cloud Functions Gen2)
resource "google_project_iam_member" "eventarc_service_account" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${local.function_service_account}"
  
  depends_on = [google_project_service.required_apis]
}