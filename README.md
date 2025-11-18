# cilium-demo

Demo repository for cilium installation

Reuqirenments:

- Terraform
- AWS Cloud
- k3s
- cilium

1. Create S3 bucket that being used for storing terraform state.

2. Configure backend configuration.

```hcl
terraform {
  backend "s3" {
    bucket       = "cilium-demo-s3-bucket"
    region       = "eu-north-1"
    key          = "cilium-demo-01/terraform.tfstate"
    use_lockfile = true
  }
}
```

3. Configure AWS credentials and Region.

4. Apply terraform condifuration by entering terraform directory and running `terraform apply`.

5. For the convinience you might add aliases to quickly connect from one host to another one. This can be taken from terraform apply outputs.

```sh
alias bastion="${terraform output bastion_connection_string}"
alias cp="${terraform output controlplane_connection_string}"
alias node1="${terraform output node01_connection_string}"
alias node2="${terraform output node02_connection_string}
```

Following commands `bastion`, `cp`, `node1`, `node2` you can easily connect to the node.

6. Install k3s on controlplane node joining the node using ssh command:

[k3s | Quick start](https://docs.k3s.io/quick-start)
[k3s | Configuration options](https://docs.k3s.io/installation/configuration)
[k3s | Server configuration options](https://docs.k3s.io/cli/server)

We have to disable flannel-backend as we are going to use cilium.

```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--flannel-backend=none --disable-network-policy --disable-kube-proxy --disable servicelb --disable traefik --write-kubeconfig-mode "0644"' sh -
```

Check the status of the nodes:

```sh
$ kubectl get node
NAME             STATUS     ROLES                  AGE   VERSION
ip-10-10-11-10   NotReady   control-plane,master   67s   v1.33.5+k3s1
```

7. Here we have to configure Cilium. This can be done in a few different ways:
   1. Proxying kubernetes API to you local machine and run command from here.

      SSH port forwarding:

      ```sh
      ssh -p 6443:10.10.11.10:6443 ubuntu@bastion-ip
      ```

   2. Install helm and cilium to the bastion/controlplane node and configure everything from here.
      1. Install helm (Source: https://helm.sh/docs/intro/install/ )

        ```sh
        curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
        chmod 700 get_helm.sh
        ./get_helm.sh

        # Verify installation:
        helm version
        ```

      2. Install cilium cli (source: https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/):

        ```sh
        CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
        CLI_ARCH=amd64
        if [ "$(uname -m)" = "aarch64" ]; then CLI_ARCH=arm64; fi
        curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}
        sha256sum --check cilium-linux-${CLI_ARCH}.tar.gz.sha256sum
        sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
        rm cilium-linux-${CLI_ARCH}.tar.gz{,.sha256sum}

        # Validating cilium:
        cilium version
        ```

8. The next step is to install cilium. We have to start from preparing helm values that being used during the installation.

```yaml
# cilium install -f ./values.yml
cluster:
  name: cilium-demo

ipam:
  mode: kubernetes

kubeProxyReplacement: true # This option we have to specify as we are using 
k8sServiceHost: 10.10.11.10 # This is controlplane IP, it's needed when we have kube-proxy replacement
k8sServicePort: 6443

# Use native routing (no tunneling)
routingMode: native
autoDirectNodeRoutes: true

# Enable L2 neighbor discovery - This is needed to be able to work Load Balancer concept
l2NeighDiscovery:
  enabled: true

# Enable Cilium Ingress Controller
ingressController:
  enabled: true
  loadbalancerMode: shared
  default: true

# Enable external IPs support
externalIPs:
  enabled: true
```

```sh
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
cilium install -f values.yml
```
