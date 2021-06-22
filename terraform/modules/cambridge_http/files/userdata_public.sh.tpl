#! /usr/bin/env bash
set -e

echo "Updating system packages..."
yum update -y

amazon-linux-extras enable nginx1.18
amazon-linux-extras install nginx1 -y

${authorized_keys}

echo "Done."
