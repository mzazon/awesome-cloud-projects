"""
Setup configuration for AWS IoT Device Defender CDK Python application.

This setup.py file configures the Python package for the IoT Device Defender
security implementation using AWS CDK.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip() 
            for line in f 
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.34.0"
    ]

setuptools.setup(
    name="iot-device-defender-cdk",
    version="1.0.0",
    
    description="AWS IoT Device Defender Security Implementation using CDK Python",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Architect",
    author_email="solutions@example.com",
    
    python_requires=">=3.8",
    
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Intended Audience :: System Administrators",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Security",
        "Topic :: Internet of Things",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "iot",
        "device-defender",
        "security",
        "monitoring",
        "threat-detection",
        "infrastructure-as-code"
    ],
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    install_requires=requirements,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.7.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
        ],
        "testing": [
            "moto>=4.2.0",
            "pytest-mock>=3.11.0",
        ]
    },
    
    entry_points={
        "console_scripts": [
            "deploy-iot-defender=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/iot/latest/developerguide/device-defender.html",
        "Source": "https://github.com/aws-samples/iot-device-defender-cdk",
        "Bug Tracker": "https://github.com/aws-samples/iot-device-defender-cdk/issues",
        "AWS CDK": "https://aws.amazon.com/cdk/",
        "AWS IoT Device Defender": "https://aws.amazon.com/iot-device-defender/",
    },
    
    package_data={
        "": ["*.md", "*.txt", "*.yaml", "*.yml", "*.json"],
    },
    
    include_package_data=True,
    zip_safe=False,
    
    # Metadata for package distribution
    license="MIT",
    platforms=["any"],
    
    # Security and compliance
    options={
        "bdist_wheel": {
            "universal": False,
        }
    },
)