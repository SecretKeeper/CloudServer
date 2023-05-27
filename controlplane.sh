#!/bin/bash

# Get current VM IP address
IP_ADDRESS=95.215.173.110

# Install Docker if not already installed
if ! [ -x "$(command -v docker)" ]; then
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
fi

# Install Kubernetes if not already installed
if ! [ -x "$(command -v kubectl)" ]; then
  curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
fi

# Install Istio if not already installed
if ! [ -x "$(command -v istioctl)" ]; then
  curl -L https://istio.io/downloadIstio | sh -
  cd istio-*/ && export PATH=$PWD/bin:$PATH
  cd ..
fi

# Create a Kubernetes cluster if not already created
if ! [ -x "$(command -v kubectl)" ] || ! kubectl get nodes &>/dev/null; then
  # Install kubeadm, kubelet, and kubectl
  sudo apt update
  sudo apt install -y docker.io
  sudo apt install -y kubeadm kubelet kubectl

  # Initialize the cluster
  sudo kubeadm init

  # Set up kubectl configuration for the current user
  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
fi


# Install Istio on the Kubernetes cluster if not already installed
if ! kubectl get namespaces istio-system &>/dev/null; then
  istioctl install
fi

# Verify Istio installation
kubectl get svc -n istio-system

# Configure Istio Gateway if not already configured
if ! kubectl get gateway mygateway &>/dev/null; then
  cat <<EOF > gateway.yaml
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: mygateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - hosts:
      - $IP_ADDRESS
    port:
      number: 80
      name: http
      protocol: HTTP
EOF
  kubectl apply -f gateway.yaml
fi

# Configure Istio VirtualService for auth service if not already configured
if ! kubectl get virtualservice auth &>/dev/null; then
  cat <<EOF > auth-virtualservice.yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: auth
spec:
  hosts:
  - $IP_ADDRESS
  gateways:
  - mygateway
  http:
  - match:
    - uri:
        prefix: /auth
    route:
    - destination:
        host: artemis.opensecret.ir
        port:
          number: 80
EOF
  kubectl apply -f auth-virtualservice.yaml
fi

# Configure Istio VirtualService for WebSocket service if not already configured
if ! kubectl get virtualservice websocket &>/dev/null; then
  cat <<EOF > websocket-virtualservice.yaml
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: websocket
spec:
  hosts:
  - $IP_ADDRESS
  gateways:
  - mygateway
  http:
  - match:
    - uri:
        prefix: /ws
    route:
    - destination:
        host: pheme.opensecret.ir
        port:
          number: 80
EOF
  kubectl apply -f websocket-virtualservice.yaml
fi

# Configure Istio AuthorizationPolicy for WebSocket JWT verification if not already configured
if ! kubectl get authorizationpolicy websocket-authz &>/dev/null; then
  cat <<EOF > websocket-authorizationpolicy.yaml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: websocket-authz
spec:
  selector:
    matchLabels:
      app: websocket
  action: ALLOW
  rules:
  - from:
    - source:
        requestPrincipals: ["*"]
    to:
    - operation:
        methods: ["POST"]
        paths: ["/verify-token"]
    when:
    - key: request.headers[jwt-token]
      values:
      - "*"
EOF
  kubectl apply -f websocket-authorizationpolicy.yaml
fi

echo "Istio setup complete!"
