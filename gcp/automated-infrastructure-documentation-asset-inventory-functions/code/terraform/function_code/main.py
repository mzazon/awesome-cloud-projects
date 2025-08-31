import json
import os
from datetime import datetime
from google.cloud import asset_v1
from google.cloud import storage
import functions_framework

@functions_framework.cloud_event
def generate_asset_documentation(cloud_event):
    """
    Triggered by Pub/Sub to generate infrastructure documentation
    from Cloud Asset Inventory data
    """
    
    project_id = os.environ.get('GCP_PROJECT', '${project_id}')
    bucket_name = os.environ.get('STORAGE_BUCKET', '${bucket_name}')
    
    # Initialize clients
    asset_client = asset_v1.AssetServiceClient()
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket_name)
    
    try:
        # Query all assets in the project
        parent = f"projects/{project_id}"
        request = asset_v1.ListAssetsRequest(
            parent=parent,
            content_type=asset_v1.ContentType.RESOURCE,
            page_size=1000
        )
        assets = asset_client.list_assets(request=request)
        
        # Process and categorize assets
        asset_summary = categorize_assets(assets)
        
        # Generate HTML report
        html_content = generate_html_report(asset_summary)
        upload_to_storage(bucket, 'reports/infrastructure-report.html', html_content)
        
        # Generate markdown documentation
        markdown_content = generate_markdown_docs(asset_summary)
        upload_to_storage(bucket, 'reports/infrastructure-docs.md', markdown_content)
        
        # Export raw JSON data
        json_content = json.dumps(asset_summary, indent=2, default=str)
        upload_to_storage(bucket, 'exports/asset-inventory.json', json_content)
        
        print(f"✅ Documentation generated successfully at {datetime.now()}")
        return {'status': 'success', 'timestamp': datetime.now().isoformat()}
        
    except Exception as e:
        print(f"❌ Error generating documentation: {str(e)}")
        return {'status': 'error', 'message': str(e)}

def categorize_assets(assets):
    """Categorize assets by type and extract key information"""
    categories = {
        'compute': [],
        'storage': [],
        'networking': [],
        'databases': [],
        'security': [],
        'other': []
    }
    
    for asset in assets:
        asset_info = {
            'name': asset.name,
            'asset_type': asset.asset_type,
            'create_time': asset.resource.discovery_document_uri if asset.resource else None,
            'location': asset.resource.location if asset.resource else 'global'
        }
        
        # Categorize by asset type
        if 'compute' in asset.asset_type.lower():
            categories['compute'].append(asset_info)
        elif 'storage' in asset.asset_type.lower():
            categories['storage'].append(asset_info)
        elif any(net in asset.asset_type.lower() for net in ['network', 'firewall', 'subnet']):
            categories['networking'].append(asset_info)
        elif any(db in asset.asset_type.lower() for db in ['sql', 'database', 'datastore']):
            categories['databases'].append(asset_info)
        elif any(sec in asset.asset_type.lower() for sec in ['iam', 'security', 'kms']):
            categories['security'].append(asset_info)
        else:
            categories['other'].append(asset_info)
    
    return categories

def generate_html_report(asset_summary):
    """Generate HTML infrastructure report"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <title>Infrastructure Documentation Report</title>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; }}
            .header {{ background-color: #4285F4; color: white; padding: 20px; border-radius: 5px; }}
            .category {{ margin: 20px 0; }}
            .category h2 {{ color: #34A853; border-bottom: 2px solid #34A853; }}
            table {{ border-collapse: collapse; width: 100%; margin: 10px 0; }}
            th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
            th {{ background-color: #f2f2f2; }}
            .timestamp {{ color: #666; font-size: 0.9em; }}
        </style>
    </head>
    <body>
        <div class="header">
            <h1>Google Cloud Infrastructure Documentation</h1>
            <p class="timestamp">Generated: {timestamp}</p>
        </div>
    """
    
    for category, assets in asset_summary.items():
        if assets:
            html += f"""
            <div class="category">
                <h2>{category.title()} Resources ({len(assets)})</h2>
                <table>
                    <tr>
                        <th>Resource Name</th>
                        <th>Asset Type</th>
                        <th>Location</th>
                    </tr>
            """
            for asset in assets:
                html += f"""
                    <tr>
                        <td>{asset['name'].split('/')[-1]}</td>
                        <td>{asset['asset_type']}</td>
                        <td>{asset['location']}</td>
                    </tr>
                """
            html += "</table></div>"
    
    html += "</body></html>"
    return html

def generate_markdown_docs(asset_summary):
    """Generate markdown documentation"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S UTC')
    
    markdown = f"""# Google Cloud Infrastructure Documentation

Generated: {timestamp}

## Overview

This document provides an automated inventory of all Google Cloud resources in the current project.

"""
    
    for category, assets in asset_summary.items():
        if assets:
            markdown += f"""## {category.title()} Resources ({len(assets)})

| Resource Name | Asset Type | Location |
|---------------|------------|----------|
"""
            for asset in assets:
                name = asset['name'].split('/')[-1]
                markdown += f"| {name} | {asset['asset_type']} | {asset['location']} |\n"
            
            markdown += "\n"
    
    return markdown

def upload_to_storage(bucket, filename, content):
    """Upload content to Cloud Storage"""
    blob = bucket.blob(filename)
    blob.upload_from_string(content)
    print(f"Uploaded {filename} to bucket")