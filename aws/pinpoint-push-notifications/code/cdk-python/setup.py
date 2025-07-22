"""
Setup configuration for Mobile Push Notifications CDK Python Application
Recipe: Pinpoint Mobile Push Notifications

This setup.py file configures the Python package for the CDK application
that creates mobile push notification infrastructure using AWS Pinpoint.
"""

import setuptools
from pathlib import Path

# Read the README file for long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        requirements = [
            line.strip()
            for line in f.readlines()
            if line.strip() and not line.startswith("#")
        ]
else:
    requirements = [
        "aws-cdk-lib>=2.150.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "typing-extensions>=4.0.0",
    ]

setuptools.setup(
    name="mobile-push-notifications-pinpoint-cdk",
    version="1.0.0",
    description="AWS CDK Python application for mobile push notifications with Pinpoint",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="AWS Recipe Generator",
    author_email="recipes@aws.example.com",
    url="https://github.com/aws-samples/cloud-recipes",
    project_urls={
        "Bug Reports": "https://github.com/aws-samples/cloud-recipes/issues",
        "Source": "https://github.com/aws-samples/cloud-recipes",
        "Documentation": "https://docs.aws.amazon.com/pinpoint/",
    },
    packages=setuptools.find_packages(exclude=["tests", "tests.*"]),
    py_modules=["app"],
    classifiers=[
        "Development Status :: 4 - Beta",
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
        "Topic :: Internet :: WWW/HTTP",
        "Topic :: Communications",
        "Typing :: Typed",
    ],
    keywords=[
        "aws",
        "cdk",
        "pinpoint",
        "push-notifications",
        "mobile",
        "ios",
        "android",
        "apns",
        "fcm",
        "messaging",
        "engagement",
        "marketing",
        "analytics",
        "infrastructure-as-code",
        "cloud",
    ],
    python_requires=">=3.8",
    install_requires=requirements,
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "pytest-cov>=4.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
        "docs": [
            "sphinx>=5.0.0",
            "sphinx-rtd-theme>=1.0.0",
        ],
        "aws": [
            "boto3>=1.35.0",
            "awscli>=1.33.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "deploy-mobile-push=app:main",
        ],
    },
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    include_package_data=True,
    zip_safe=False,
    platforms=["any"],
    license="MIT",
    license_files=["LICENSE"],
)