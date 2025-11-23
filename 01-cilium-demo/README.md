# cilium-demo

Lab environment:

![scheme](./images/cilium-demo-01.png)

1. Apply terraform condifuration by entering terraform directory and running `terraform apply`.

2. For the convinience you might add aliases to quickly connect from one host to another one. This can be taken from terraform apply outputs.

```sh
alias bastion="$(terraform output -raw bastion_connection_string)"
alias controlplane="$(terraform output -raw controlplane_connection_string)"
alias node1="$(terraform output -raw node01_connection_string)"
alias node2="$(terraform output -raw node02_connection_string)"
```

Following commands `bastion`, `cp`, `node1`, `node2` you can easily connect to the proper insatnce.

3. Install k3s on controlplane node joining the node using ssh command:

[k3s | Quick start](https://docs.k3s.io/quick-start)
[k3s | Configuration options](https://docs.k3s.io/installation/configuration)
[k3s | Server configuration options](https://docs.k3s.io/cli/server)

Connect to the controlplane via alias:

```sh
cp
```

Installing k3s. We have to disable flannel-backend as we are going to use cilium.

```sh
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--flannel-backend=none --disable-network-policy --disable-kube-proxy --disable servicelb --disable traefik --write-kubeconfig-mode "0644"' sh -
```

Exporting kubeconfig to be able to use kubectl:

```sh
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
```

Check the status of the nodes:

```sh
$ kubectl get node
NAME             STATUS     ROLES                  AGE   VERSION
ip-10-10-11-10   NotReady   control-plane,master   67s   v1.33.5+k3s1
```

1. Here we have to configure Cilium. This can be done in a few different ways:
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

2. The next step is to install cilium. We have to start from preparing helm values that being used during the installation.

Installing cilium to the cluster:

```sh
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
cilium install --set cluster.name=cilium-demo-01  --set kubeProxyReplacement=true --set k8sServiceHost=10.10.11.10 --set k8sServicePort=6443

# Check cilium installation by executing:
cilium status --wait
```

We should see all the options are healthy:

![cilium-status](./images/cilium-demo-01-cilium-status.png)

3. Install k3s on the worker nodes and join the cluster.

On the controlplane we could take node-token or :

```sh
cat /var/lib/rancher/k3s/server/node-token
```

This token should be stored as this being used for the nodes registration.

Join the first worker node and register this node as worker node:

```sh
node1

export K3S_CP_TOKEN="...." # Token is taken from the previous command

# Installing k3s agent
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="agent --server https://10.10.11.10:6443 --token $K3S_CP_TOKEN sh -s -
```

Do the same for the second node.
After that exiting from the worker node and join back controlplane and verify that nodes were added to the cluster:

```sh
$ kubectl get nodes
NAME             STATUS   ROLES                  AGE   VERSION
ip-10-10-11-10   Ready    control-plane,master   61m   v1.33.5+k3s1
ip-10-10-11-20   Ready    <none>                 96s   v1.33.5+k3s1
ip-10-10-11-21   Ready    <none>                 73s   v1.33.5+k3s1
```

(Optional) To verify the cilium installation, we might run the test preapred by the cilium team. This operation might take some time:

```sh
cilium connectivity test
```

-----

```yaml
cluster:
  name: cilium-demo-01

ipam:
  mode: kubernetes

kubeProxyReplacement: true # This option we have to specify as we are using 
k8sServiceHost: 10.10.11.10 # This is controlplane IP, it's needed when we have kube-proxy replacement
k8sServicePort: 6443

# Use native routing (no tunneling)
# routingMode: native
# autoDirectNodeRoutes: true

# Set native routing CIDR to only include pod CIDR
# ipv4NativeRoutingCIDR: 10.42.0.0/16

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
cilium status --wait

kubectl rollout restart -n kube-system deploy/cilium-operator
kubectl rollout restart -n kube-system ds/cilium
```
