# Lab 02 · Cilium on Amazon EKS with enablement of Gateway API

This lab runs Kubernetes 1.37 on EKS with one Spot worker. Cilium 1.20.4 provides pod networking and replaces kube-proxy. The EKS CoreDNS add-on provides service discovery.

You need Terraform 1.10 or later, the AWS CLI, Helm 3.10 or later, and kubectl. Configure AWS credentials for `eu-north-1` and use the same IAM identity for Terraform and kubectl. EKS grants that identity cluster admin access when it creates the cluster.

Set up the S3 backend using the [repository instructions](../README.md). Use `cilium-demo-02/terraform.tfstate` as the state key for this lab.

## 1. Create the control plane

From `02-cilium-demo/terraform`, run the initial targeted apply. This leaves the worker out of the first apply so you can install Cilium before the worker needs it.

```sh
terraform init
terraform apply -target=aws_eks_cluster.this
```


## 2. Prepare kubectl config

```sh
aws eks update-kubeconfig --region eu-north-1 --name cilium-demo-02
kubectl cluster-info
```

As we don't have any CNI configured yet, we don't need to add any node groups. If we do that on the current stage, nodes come to the cluster as `Not Ready`.

## 3. Installing cilium. We might proceed with 2 options, install cilium cli or we can use helm (Check 1st demo). In that one we are going to use helm.

Add cilium repo:

```sh
export CILIUM_VERSION="1.20.4"

helm install cilium oci://quay.io/cilium/charts/cilium \
  --version ${CILIUM_VERSION} \
  --namespace kube-system \
  --set eni.enabled=true \ 
  --set ipam.mode=eni \
  --set egressMasqueradeInterfaces=eth+ \
  --set routingMode=native\
  --set kubeProxyReplacement=true\
  --set k8sServiceHost=$(terraform output -raw  cluster_endpoint_for_cilium) \
  --set k8sServicePort=443
```

Helm values used above:

| Option | Description |
|--------|-------------|
| `--set eni.enabled=true` | Enables ENI mode, which is specific to AWS. Cilium uses Elastic Network Interfaces to give pods VPC-native IPs. |
| `--set ipam.mode=eni` | Sets IPAM to ENI. Cilium allocates pod IPs from the ENIs attached to the node instead of from a cluster-pool CIDR. |
| `--set egressMasqueradeInterfaces=eth+` | Sets the interfaces on which egress masquerading (NAT) is done. `eth+` is a wildcard that matches `eth0`, `eth1`, and so on, which covers the secondary ENIs. |
| `--set routingMode=native` | Uses native routing instead of encapsulation (VXLAN or Geneve). Traffic is routed directly through the VPC. |
| `--set kubeProxyReplacement=true` | Replaces kube-proxy. Cilium handles service load balancing with eBPF. |
| `--set k8sServiceHost=<EKS_API_ENDPOINT>` | Sets the host of the Kubernetes API server. This is the EKS endpoint hostname without `https://`. Cilium needs it to reach the API server when kube-proxy is absent. |
| `--set k8sServicePort=443` | Sets the port of the Kubernetes API server. EKS serves it on `443`. |

https://cilium.io/blog/2025/06/19/eks-eni-install/
https://docs.cilium.io/en/stable/installation/k8s-install-helm/

## 4. Create the worker node

With Cilium installed, run the full apply from `02-cilium-demo/terraform`. This creates the managed node group and the EKS add-ons.

```sh
# is_eks_initialized set to true
terraform apply
```

### IAM policies on the node role

Terraform creates two IAM roles. The cluster role is used by the EKS control plane. The node role is assumed by the worker EC2 instance, and every pod that uses the node credentials gets its permissions. That includes `cilium-operator`.

| Role | Managed policy | Why it is needed |
|------|----------------|------------------|
| Cluster | `AmazonEKSClusterPolicy` | Lets the EKS control plane manage AWS resources on your behalf, such as networking and load balancers. |
| Node | `AmazonEKSWorkerNodePolicy` | Lets the kubelet register the node with the cluster and read EC2 metadata about itself. |
| Node | `AmazonEC2ContainerRegistryReadOnly` | Lets the node pull images from ECR. The EKS add-ons (CoreDNS, metrics-server, node monitoring agent) are stored there. |
| Node | `AmazonEKS_CNI_Policy` | Lets the node manage ENIs and secondary IPs. Cilium needs it in ENI mode even though the AWS VPC CNI is not installed. |

Why `AmazonEKS_CNI_Policy` is required here:

- With `ipam.mode=eni`, `cilium-operator` talks to the EC2 API. It creates ENIs, attaches them to the instance and assigns private IPs to them. Those IPs become the pod IPs.
- The operator uses the node role credentials, so the node role must allow `ec2:DescribeNetworkInterfaces`, `CreateNetworkInterface`, `AttachNetworkInterface`, `AssignPrivateIpAddresses` and related actions.
- Without it the operator exits with `UnauthorizedOperation` and never publishes an IP pool. The cilium agent then waits with `Waiting for cidr pool to become available`, the node keeps the `node.cilium.io/agent-not-ready` taint, and CoreDNS and metrics-server stay `Pending`.

This is the simplest setup for a demo, but it gives every pod on the node the ENI permissions. In production, give the operator its own role through EKS Pod Identity or IRSA and keep the node role minimal.

### Verify

```sh
kubectl -n kube-system get pods
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status --brief
```

Optionally, we might check status with the details:

```sh
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status
```

Some important notes in the output:

```txt
Kubernetes:              Ok         1.37 (v1.37.1-eks-577a51e) [linux/amd64]
...
KubeProxyReplacement:    True
...
Cilium:                  Ok   1.20.4 (v1.20.4-beb276d2)
...
Routing:                 Network: Native   Host: BPF
...
Controller Status:       34/34 healthy
```

### 5. Enable cilium gateway api

References:
- https://gateway-api.sigs.k8s.io/guides/getting-started/introduction/
- https://docs.cilium.io/en/latest/network/servicemesh/gateway-api/gateway-api/

Install required CRD first. According to cilium documentation, we have to install v1.6.3 version at the moment when this article is written.

```sh
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.7.0/standard-install.yaml
```

Enabling gateway api support from cilium side:

```sh
export CILIUM_VERSION="1.20.4"

helm upgrade cilium oci://quay.io/cilium/charts/cilium \
  --version ${CILIUM_VERSION} \
  --namespace kube-system \
  --reuse-values \
  --set gatewayAPI.enabled=true
```

Restart cilium and cilium operator:

```sh
kubectl rollout restart -n kube-system deploy/cilium-operator
kubectl rollout restart -n kube-system ds/cilium
```

Verify, that cilium gateway api is enabled:

```sh
kubectl get gatewayclasses.gateway.networking.k8s.io 
NAME     CONTROLLER                     ACCEPTED   AGE
cilium   io.cilium/gateway-controller   True       2m34s
```

## North-South traffic: how do we get traffic from the internet to our pods?

Now, to continue working with Cilium, we have to understand and decide how to handle North-South traffic (from the internet to our pods). We have a few options here.

### 1. Nodes in public subnets, Gateway exposed via NodePort

The nodes are placed in the public subnets, and Cilium (Envoy) is exposed through a `NodePort` service. This port (30000-32767 by default) is opened to the internet on the node security group. There is no load balancer to create or maintain.

### 2. Nodes in public subnets, Envoy listens on the host network

The nodes are again in the public subnets, but Cilium (Envoy) listens directly on the node's ports, for example 80 and 443. This is Gateway API host network mode. There is no `LoadBalancer` service at all. Traffic from outside the cluster reaches the node's public IP, Envoy intercepts it and routes it to the right backend.

Options 1 and 2 only make sense in specific scenarios, mostly small setups with limited budgets:

- personal labs, demos and learning clusters like this one
- hobby and side projects
- dev, test and short-lived preview environments
- single-node or edge clusters (small on-premises setups, IoT gateways)
- early MVPs where every fixed monthly cost matters

The trade-offs are the same for both options:

- Nodes are directly exposed to the internet, so the attack surface is larger.
- The entry point is the node's public IP. If a node is replaced (Spot interruption, upgrade, scaling), the IP changes and DNS has to follow.
- There are no managed health checks and no multi-AZ entry point. Several nodes mean several entry points.
- In option 2, the ports must be free on the node, so only one Gateway can use a given port per node.

### 3. Load balancer in front of the cluster (our choice)

A load balancer handles the traffic from the internet and forwards it to the nodes. From there Cilium's eBPF datapath takes over, passes the traffic to Envoy, and Envoy routes it to the pods. The nodes stay in the private subnets and are not reachable from the internet.

The same setup also works with an internal NLB. It is reachable only inside the private network, for cases where the Gateway should not be exposed publicly.

This is the most common and most reliable setup. We get a stable, static entry point to the infrastructure, while the nodes can be as dynamic as we want. They can be replaced or scaled without us worrying about public IPs, DNS or exposed nodes.

The price is a load balancer to run and pay for, plus one more controller in the cluster (the AWS Load Balancer Controller).

That is the direction we take in this lab:

    Internet -> AWS NLB -> Node (NodePort) -> Cilium (eBPF) -> Envoy -> Pod

Next we install the AWS Load Balancer Controller, so the Cilium Gateway can get its NLB.

### 6. Installing AWS NLB Controller

https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/deploy/installation/ 

0. Check that aws_iam_openid_connect_provider is enabled in terraform - that's required for enabling AWS NLB Controller.

1. Re-run terraform apply with the installation of the required resources for controller

Enable local enable_nlb_iam_permissions. I did it so to be able to show, what are the resources needed to be created:

```txt
enable_nlb_iam_permissions = true # Check and set it in local
```

```sh
terraform apply # to create required resources
```

2. Precreate service account required for the operator.

```sh
ROLE_ARN=$(terraform output -raw nlb_controller_role_arn)
kubectl -n kube-system create serviceaccount aws-load-balancer-controller
kubectl -n kube-system annotate serviceaccount aws-load-balancer-controller \
  "eks.amazonaws.com/role-arn=${ROLE_ARN}" --overwrite
```

#### How pods get access to AWS resources (for EKS beginners)

A pod sometimes needs to call AWS APIs, for example to read from an S3 bucket or, in our case, to let a controller create load balancers. By default, a pod has no AWS permissions, so we have to grant them. There are two common ways.

**1. IAM roles for service accounts (IRSA, or EKS Pod Identity)** - recommended

Each workload gets its own IAM role with only the permissions it needs:

1. Create an IAM policy that describes the allowed actions (for example, read one S3 bucket).
2. Attach the policy to an IAM role. The role's trust policy defines who may assume it: a specific Kubernetes service account in a specific namespace.
3. Link the role to the Kubernetes service account.
   - With IRSA, we annotate the service account with the role ARN (`eks.amazonaws.com/role-arn`). This needs an IAM OIDC provider for the cluster (`eksctl utils associate-iam-oidc-provider`), so that IAM trusts the cluster's tokens.
   - With EKS Pod Identity, we create an association between the role and the service account using the EKS API. This needs the `eks-pod-identity-agent` add-on, but no OIDC provider and no annotation.
4. Set that service account in the pod (`serviceAccountName`). The pod now receives temporary credentials for that role, and only that pod.

Only the pods that use this service account get the permissions, which follows the principle of least privilege.

**2. Attach the policy to the node IAM role** - simple, but less secure

The policy is attached to the IAM role of the worker node (EC2 instance). Every pod running on the node can use these permissions, even ones that don't need them. This is acceptable for quick demos, but not recommended for production. Access to the node credentials can be restricted from pods (for example, via the instance metadata hop limit), but then pods can't use this approach at all.

In this lab, the Cilium operator uses the node role (approach 2) because it needs the ENI permissions on every node. For the AWS Load Balancer Controller we use approach 1.


2. Installing it using helm:

```sh
helm repo add eks https://aws.github.io/eks-charts
helm install -n kube-system aws-load-balancer-controller \
    eks/aws-load-balancer-controller \
    --set clusterName=$(terraform output -raw cluster_name) \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller
```


References:

- https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/
- https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html
- https://kubernetes-sigs.github.io/aws-load-balancer-controller/
