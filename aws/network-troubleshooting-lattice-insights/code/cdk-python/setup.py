"""
Setup configuration for Network Troubleshooting VPC Lattice CDK Python Application
"""

import setuptools

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setuptools.setup(
    name="network-troubleshooting-lattice-insights",
    version="1.0.0",
    author="AWS CDK Recipe Generator",
    author_email="your-email@example.com",
    description="CDK Python application for Network Troubleshooting VPC Lattice with Network Insights",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/your-username/network-troubleshooting-lattice-insights",
    packages=setuptools.find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Networking :: Monitoring",
        "Topic :: System :: Systems Administration",
    ],
    python_requires=">=3.9",
    install_requires=[
        "aws-cdk-lib>=2.100.0,<3.0.0",
        "constructs>=10.0.0,<11.0.0",
        "boto3>=1.26.0,<2.0.0",
        "typing-extensions>=4.0.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.0.0",
            "black>=22.0.0",
            "flake8>=5.0.0",
            "mypy>=1.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "network-troubleshooting=app:main",
        ],
    },
    project_urls={
        "Bug Reports": "https://github.com/your-username/network-troubleshooting-lattice-insights/issues",
        "Source": "https://github.com/your-username/network-troubleshooting-lattice-insights",
        "Documentation": "https://docs.aws.amazon.com/cdk/",
    },
)