#!/bin/bash
# Run this script once after creating the GitHub Runner LXC (github-runner-01)
# Usage: bash bootstrap.sh

set -e

TERRAFORM_VERSION="1.13.0"

echo "=== Installing base packages ==="
apt-get update -y
apt-get install -y unzip nodejs curl wget git

echo "=== Installing Terraform ${TERRAFORM_VERSION} ==="
wget -q "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -O /tmp/terraform.zip
unzip /tmp/terraform.zip -d /usr/local/bin/
rm /tmp/terraform.zip
chmod +x /usr/local/bin/terraform
terraform version

echo "=== Bootstrap complete ==="
