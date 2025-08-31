"""
Setup configuration for Security Compliance Auditing CDK Application

This setup.py file configures the Python package for the Security Compliance
Auditing solution that monitors VPC Lattice access logs and integrates with
GuardDuty for comprehensive threat detection and compliance reporting.
"""

import setuptools
from pathlib import Path

# Read the README file for the long description
readme_path = Path(__file__).parent / "README.md"
long_description = readme_path.read_text(encoding="utf-8") if readme_path.exists() else ""

# Read requirements from requirements.txt
requirements_path = Path(__file__).parent / "requirements.txt"
install_requires = []
if requirements_path.exists():
    with open(requirements_path, "r", encoding="utf-8") as f:
        install_requires = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]

setuptools.setup(
    name="security-compliance-auditing-cdk",
    version="1.0.0",
    
    description="CDK application for Security Compliance Auditing with VPC Lattice and GuardDuty",
    long_description=long_description,
    long_description_content_type="text/markdown",
    
    author="AWS Solutions Team",
    author_email="aws-solutions@amazon.com",
    
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
        "Topic :: System :: Security",
        "Topic :: System :: Monitoring",
    ],
    
    keywords=[
        "aws",
        "cdk",
        "security",
        "compliance",
        "vpc-lattice",
        "guardduty",
        "monitoring",
        "threat-detection",
        "infrastructure-as-code"
    ],
    
    packages=setuptools.find_packages(exclude=["tests*"]),
    
    install_requires=install_requires,
    
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "moto>=4.2.0",
            "black>=23.0.0",
            "flake8>=6.0.0",
            "mypy>=1.5.0",
        ]
    },
    
    entry_points={
        "console_scripts": [
            "security-compliance-cdk=app:main",
        ],
    },
    
    project_urls={
        "Documentation": "https://docs.aws.amazon.com/cdk/",
        "Source": "https://github.com/aws-samples/security-compliance-auditing",
        "Bug Reports": "https://github.com/aws-samples/security-compliance-auditing/issues",
    },
    
    # CDK-specific metadata
    package_data={
        "": ["*.md", "*.txt", "*.json", "*.yaml", "*.yml"],
    },
    
    include_package_data=True,
    zip_safe=False,
)