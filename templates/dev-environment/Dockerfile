# Docker Sandbox Template — DevOps Toolkit
#
# Extends the official claude-code-docker base template with:
#   - kubectl    (Kubernetes CLI)
#   - helm       (Kubernetes package manager)
#   - kustomize  (Kubernetes configuration management)
#   - azure-cli  (Azure resource management)
#
# Architecture: linux/arm64 (Apple Silicon) and linux/amd64 (Intel/AMD)
# Base OS: Ubuntu (from docker/sandbox-templates:claude-code-docker)
#
# Build:
#   docker build -t <your-registry>/sbx-devops-toolkit:v1.0.0 .
#
# Push:
#   docker push <your-registry>/sbx-devops-toolkit:v1.0.0
#
# Run:
#   sbx run claude --template <your-registry>/sbx-devops-toolkit:v1.0.0 --name 05-devops-workloads

FROM docker/sandbox-templates:claude-code-docker

# Pin versions for reproducibility
# Update these ARGs when upgrading tools
ARG KUBECTL_VERSION=v1.31.4
ARG HELM_VERSION=v3.16.4
ARG KUSTOMIZE_VERSION=5.4.3

LABEL org.opencontainers.image.title="sbx-devops-toolkit"
LABEL org.opencontainers.image.description="Docker Sandbox template with DevOps toolchain: kubectl, helm, kustomize, azure-cli"
LABEL org.opencontainers.image.source="https://github.com/opscart/docker-sandbox-devops"
LABEL org.opencontainers.image.version="1.0.0"

USER root

# System dependencies needed by install scripts
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# kubectl — detect arch at build time so image works on both arm64 and amd64
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    kubectl version --client

# helm — official install script handles arch detection internally
RUN curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | \
    DESIRED_VERSION=${HELM_VERSION} bash && \
    helm version --short

# kustomize — direct GitHub release download (install script unreliable on ARM64)
RUN ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    curl -fsSL "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_${ARCH}.tar.gz" \
    -o kustomize.tar.gz && \
    tar xzf kustomize.tar.gz && \
    mv kustomize /usr/local/bin/kustomize && \
    rm kustomize.tar.gz && \
    kustomize version

# azure-cli — Microsoft's official Debian/Ubuntu install script
RUN curl -fsSL https://aka.ms/InstallAzureCLIDeb | bash && \
    az version --output table

# Drop back to non-root agent user
USER agent

# Smoke test — all tools on PATH
RUN kubectl version --client --output=yaml | grep gitVersion && \
    helm version --short && \
    kustomize version && \
    az version --output table