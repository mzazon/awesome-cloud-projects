"""
Setup configuration for Weather Alert Notifications CDK Python application

This setup.py file configures the Python package for the CDK application,
including dependencies, metadata, and development requirements.
"""

import setuptools

# Read the README file for the long description
try:
    with open("README.md", "r", encoding="utf-8") as fh:
        long_description = fh.read()
except FileNotFoundError:
    long_description = "Weather Alert Notifications CDK Python Application"

# Read requirements from requirements.txt
def read_requirements():
    """Read requirements from requirements.txt file"""
    try:
        with open("requirements.txt", "r", encoding="utf-8") as fh:
            return [line.strip() for line in fh if line.strip() and not line.startswith("#")]
    except FileNotFoundError:
        # Fallback requirements if file not found
        return [
            "aws-cdk-lib==2.154.0",
            "constructs>=10.0.0,<11.0.0",
            "typing-extensions>=4.0.0",
        ]

setuptools.setup(
    name="weather-alert-notifications-cdk",
    version="1.0.0",
    description="AWS CDK Python application for weather alert notifications system",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS CDK Developer",
    author_email="developer@example.com",
    url="https://github.com/aws-samples/weather-alert-notifications-cdk",
    
    # Package configuration
    packages=setuptools.find_packages(),
    python_requires=">=3.8",
    install_requires=read_requirements(),
    
    # Development dependencies
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.0.0",
        ],
        "test": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "moto>=4.0.0",  # For mocking AWS services in tests
        ],
    },
    
    # Package classification
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
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
    ],
    
    # Keywords for discovery
    keywords="aws cdk python weather alerts notifications serverless lambda sns eventbridge",
    
    # Project URLs
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/weather-alert-notifications-cdk/issues",
        "Source": "https://github.com/aws-samples/weather-alert-notifications-cdk",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
    
    # Entry points for CLI commands (if needed)
    entry_points={
        "console_scripts": [
            # Example: "weather-cdk=weather_alert_notifications.cli:main",
        ],
    },
    
    # Include additional files
    include_package_data=True,
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    # Zip safe configuration
    zip_safe=False,
)