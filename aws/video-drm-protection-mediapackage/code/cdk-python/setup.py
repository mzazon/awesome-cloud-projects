"""
Setup configuration for DRM-Protected Video Streaming CDK Application

This package creates a comprehensive DRM-protected video streaming solution using:
- AWS Elemental MediaLive for video ingestion and encoding
- AWS Elemental MediaPackage for content packaging and DRM integration
- AWS Lambda for SPEKE (Secure Packager and Encoder Key Exchange) API
- Amazon CloudFront for global content delivery with geographic restrictions
- AWS Secrets Manager and KMS for secure key management

Author: AWS CDK Generator
Version: 1.0
License: MIT
"""

from setuptools import setup, find_packages

# Read the README file for long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "DRM-Protected Video Streaming Infrastructure using AWS CDK"

# Read requirements from requirements.txt
def parse_requirements(filename):
    """Parse requirements from requirements.txt file."""
    with open(filename, 'r') as f:
        requirements = []
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if line and not line.startswith('#'):
                # Handle version specifiers
                if '>=' in line or '==' in line or '<=' in line or '~=' in line:
                    requirements.append(line)
                else:
                    requirements.append(line)
        return requirements

# Package metadata
setup(
    name="drm-protected-video-streaming-cdk",
    version="1.0.0",
    author="AWS CDK Generator",
    author_email="aws-cdk@example.com",
    description="DRM-Protected Video Streaming Infrastructure using AWS CDK",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/aws-samples/drm-protected-video-streaming",
    
    # Package discovery
    packages=find_packages(),
    
    # Include non-Python files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Dependencies
    install_requires=parse_requirements("requirements.txt"),
    
    # Python version requirement
    python_requires=">=3.8",
    
    # Package classification
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
        "Topic :: Multimedia :: Video",
        "Topic :: Security :: Cryptography",
    ],
    
    # Keywords for discoverability
    keywords=[
        "aws",
        "cdk",
        "cloud",
        "infrastructure",
        "video",
        "streaming",
        "drm",
        "mediapackage",
        "medialive",
        "cloudfront",
        "security",
        "encryption",
        "speke",
        "widevine",
        "playready",
        "fairplay",
        "content-protection"
    ],
    
    # Entry points for CLI commands
    entry_points={
        "console_scripts": [
            "deploy-drm-streaming=app:main",
        ],
    },
    
    # Additional metadata
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/drm-protected-video-streaming/issues",
        "Source": "https://github.com/aws-samples/drm-protected-video-streaming",
        "Documentation": "https://docs.aws.amazon.com/mediapackage/",
        "AWS CDK": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Development dependencies (extras)
    extras_require={
        "dev": [
            "pytest>=8.3.0",
            "pytest-cov>=5.0.0",
            "pytest-mock>=3.14.0",
            "black>=24.8.0",
            "flake8>=7.1.0",
            "isort>=5.13.0",
            "mypy>=1.11.0",
            "sphinx>=8.0.0",
            "sphinx-rtd-theme>=2.0.0",
        ],
        "testing": [
            "pytest>=8.3.0",
            "pytest-cov>=5.0.0",
            "pytest-mock>=3.14.0",
            "moto>=5.0.0",
            "boto3-stubs[essential]>=1.35.0",
        ],
        "docs": [
            "sphinx>=8.0.0",
            "sphinx-rtd-theme>=2.0.0",
            "sphinx-autodoc-typehints>=2.2.0",
        ],
    },
    
    # Zip safety
    zip_safe=False,
    
    # Platform compatibility
    platforms=["any"],
    
    # License
    license="MIT",
    
    # Maintainer information
    maintainer="AWS CDK Generator",
    maintainer_email="aws-cdk@example.com",
)