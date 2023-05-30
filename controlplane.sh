#!/bin/bash

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    echo "Installing curl..."
    sudo apt-get update
    sudo apt-get install -y curl
    echo "curl installed successfully."
else
    echo "curl is already installed. Skipping installation."
fi

# Check if Docker is already installed
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    sudo usermod -aG docker $USER
    echo "Docker installed successfully."
else
    echo "Docker is already installed. Skipping installation."
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    # Install kubeadm, kubelet, and kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/

    curl -sSL -o /usr/local/bin/kubeadm https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubeadm
    chmod +x /usr/local/bin/kubeadm

    curl -sSL -o /usr/local/bin/kubelet https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubelet
    chmod +x /usr/local/bin/kubelet

    echo "Kubernetes components (kubectl, kubeadm, kubelet) installed successfully."
else
    echo "kubectl is already installed. Skipping installation."
fi

echo "Installation and container setup complete"


# Initialize Kubernetes cluster with kubeadm
echo "Initializing Kubernetes cluster with kubeadm..."
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Set up kubeconfig for the current user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install a network plugin (Calico)
echo "Installing network plugin (Calico)..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

echo "Kubernetes cluster initialized successfully"


# Install ArgoCD CLI
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Install ArgoCD Server
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD Server to be ready
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# Get ArgoCD Server URL
ARGOCD_SERVER_URL=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Set ArgoCD admin password
ARGOCD_ADMIN_PASSWORD="ourfamily789654"  # Update with your desired password

kubectl -n argocd patch secret argocd-secret \
  -p '{"stringData": {
    "admin.password": "'"$ARGOCD_ADMIN_PASSWORD"'"
  }}'

# ArgoCD setup
echo "ArgoCD Server URL: $ARGOCD_SERVER_URL"

# Create ArgoCD application manifest
cat > argocd-application.yaml <<EOL
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-containers
spec:
  destination:
    server: $ARGOCD_SERVER_URL
    namespace: default
  source:
    path: argocd-application
  project: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOL

# Create argocd-application directory
mkdir -p argocd-application

# Create Artemis YAML manifest
cat > argocd-application/artemis.yaml <<EOL
apiVersion: v1
kind: Pod
metadata:
  name: artemis
  labels:
    app: artemis
spec:
  containers:
    - name: artemis
      image: ghcr.io/secretkeeper/artemis:latest
EOL

# Create Whisper YAML manifest
cat > argocd-application/whisper.yaml <<EOL
apiVersion: v1
kind: Pod
metadata:
  name: whisper
  labels:
    app: whisper
spec:
  containers:
    - name: whisper
      image: ghcr.io/secretkeeper/whisper:latest
EOL

# Login to ArgoCD server
argocd login --username admin --password "$ARGOCD_ADMIN_PASSWORD" --insecure $ARGOCD_SERVER_URL

# Create ArgoCD application
argocd app create my-containers --file argocd-application.yaml

echo "ArgoCD application created successfully"

echo "Setup complete!"
