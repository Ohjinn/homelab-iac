#!/bin/bash
# Run this script once after creating the GitHub Runner LXC (github-runner-01)
#
# Usage:
#   bash bootstrap.sh                                  # packages only
#   bash bootstrap.sh <REPO_URL> <REG_TOKEN> [NAME]    # packages + register a runner
#
# Example:
#   bash bootstrap.sh https://github.com/Ohjinn/homelab-iac ABCD...
#
# The registration token is short-lived (about 1 hour) so it cannot be committed.
# Get one from: repo -> Settings -> Actions -> Runners -> New self-hosted runner.
# Run the script again with a different REPO_URL to add a second runner; each repo
# gets its own directory and its own systemd service.

set -e

RUNNER_VERSION="2.336.0"
RUNNER_USER="github-runner"

REPO_URL="${1:-}"
REG_TOKEN="${2:-}"
RUNNER_NAME="${3:-$(hostname)}"

echo "=== Installing base packages ==="
apt-get update -y
apt-get install -y unzip nodejs curl wget git

# Terraform is deliberately not installed here. The workflow provisions its own
# pinned version through hashicorp/setup-terraform, so a system-wide copy would
# only be a second place to keep the version in sync.

# Workflows on this runner build container images, so Docker is part of the
# runner's baseline. buildx is separate on Ubuntu 24.04 and `docker build`
# needs it, so install both.
echo "=== Installing Docker ==="
apt-get install -y docker.io docker-buildx
systemctl enable --now docker
docker --version
docker buildx version

echo "=== Preparing runner user (${RUNNER_USER}) ==="
if ! id "${RUNNER_USER}" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "${RUNNER_USER}"
fi
usermod -aG docker,sudo "${RUNNER_USER}"

if [ -z "${REPO_URL}" ] || [ -z "${REG_TOKEN}" ]; then
  echo
  echo "=== Bootstrap complete (packages only) ==="
  echo "To register a runner, re-run with a repo URL and a registration token:"
  echo "  bash bootstrap.sh https://github.com/Ohjinn/<repo> <TOKEN>"
  exit 0
fi

# One directory (and therefore one systemd service) per repo, so the same
# script can register runners for several repos on this single LXC.
REPO_SLUG="$(basename "${REPO_URL}")"
RUNNER_DIR="/home/${RUNNER_USER}/actions-runner-${REPO_SLUG}"

echo "=== Installing GitHub Actions runner ${RUNNER_VERSION} for ${REPO_URL} ==="
if [ -d "${RUNNER_DIR}" ]; then
  echo "${RUNNER_DIR} already exists - skipping download."
else
  mkdir -p "${RUNNER_DIR}"
  curl -fsSL -o /tmp/actions-runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
  tar xzf /tmp/actions-runner.tar.gz -C "${RUNNER_DIR}"
  rm /tmp/actions-runner.tar.gz
  chown -R "${RUNNER_USER}:${RUNNER_USER}" "${RUNNER_DIR}"
fi

# config.sh refuses to run as root; svc.sh must run as root.
if [ -f "${RUNNER_DIR}/.runner" ]; then
  echo "Runner already configured - skipping registration."
else
  sudo -u "${RUNNER_USER}" "${RUNNER_DIR}/config.sh" \
    --unattended \
    --url "${REPO_URL}" \
    --token "${REG_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels self-hosted,linux,x64 \
    --work _work
fi

cd "${RUNNER_DIR}"
./svc.sh install "${RUNNER_USER}"
./svc.sh start
./svc.sh status || true

echo
echo "=== Bootstrap complete ==="
