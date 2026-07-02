{ pkgs, ... }:

{
  packages = with pkgs; [
    # Kubernetes
    kubectl
    kubernetes-helm
    kustomize
    skaffold
    k9s

    # Cloud
    flyctl

    # DevPod
    devpod
  ];
}
