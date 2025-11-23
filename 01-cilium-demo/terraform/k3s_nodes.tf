resource "aws_instance" "controlplane" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"

  key_name = aws_key_pair.this.key_name

  primary_network_interface {
    network_interface_id = aws_network_interface.controlplane.id
  }

  tags = {
    Name = "${local.common_name}-controlplane"
  }
}

resource "aws_network_interface" "controlplane" {
  subnet_id   = module.vpc.subnets_private_raw["cilium-private-k8s"].id
  private_ips = ["10.10.11.10"]

  security_groups = [
    aws_security_group.k8s.id
  ]

  tags = {
    Name = "${local.common_name}-controlplane-private-ip"
  }
}

resource "aws_instance" "k8s_node_01" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"

  key_name = aws_key_pair.this.key_name

  primary_network_interface {
    network_interface_id = aws_network_interface.k8s_node_01.id
  }

  tags = {
    Name = "${local.common_name}-k8s-node-01"
  }
}

resource "aws_network_interface" "k8s_node_01" {
  subnet_id   = module.vpc.subnets_private_raw["cilium-private-k8s"].id
  private_ips = ["10.10.11.20"]

  security_groups = [
    aws_security_group.k8s.id
  ]

  tags = {
    Name = "${local.common_name}-k8s-node-01-private-ip"
  }
}

resource "aws_instance" "k8s_node_02" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.small"

  key_name = aws_key_pair.this.key_name

  primary_network_interface {
    network_interface_id = aws_network_interface.k8s_node_02.id
  }

  tags = {
    Name = "${local.common_name}-k8s-node-02"
  }
}

resource "aws_network_interface" "k8s_node_02" {
  subnet_id   = module.vpc.subnets_private_raw["cilium-private-k8s"].id
  private_ips = ["10.10.11.21"]

  security_groups = [
    aws_security_group.k8s.id
  ]

  tags = {
    Name = "${local.common_name}-k8s-node-02-private-ip"
  }
}

resource "aws_security_group" "k8s" {
  name        = "${local.common_name}-k8s-sg"
  description = "Security group for k8s hosts"
  vpc_id      = module.vpc.vpc_raw.id

  ingress {
    description = "SSH from local public IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    security_groups = [
      aws_security_group.bastion_sg.id
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cilium-demo-k8s-sg"
  }
}

resource "aws_security_group_rule" "allow_internal" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  source_security_group_id = aws_security_group.k8s.id
  security_group_id        = aws_security_group.k8s.id
  description              = "Allow all internal traffic within the security group"
}

output "controlplane_connection_string" {
  value = "ssh -o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' -o 'ProxyCommand=ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} -W %h:%p ubuntu@${aws_eip.bastion.public_ip}' -i ${local_file.private_key.filename} ubuntu@${aws_network_interface.controlplane.private_ip}"
}

output "node01_connection_string" {
  value = "ssh -o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' -o 'ProxyCommand=ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} -W %h:%p ubuntu@${aws_eip.bastion.public_ip}' -i ${local_file.private_key.filename} ubuntu@${aws_network_interface.k8s_node_01.private_ip}"
}

output "node02_connection_string" {
  value = "ssh -o 'UserKnownHostsFile=/dev/null' -o 'StrictHostKeyChecking=no' -o 'ProxyCommand=ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} -W %h:%p ubuntu@${aws_eip.bastion.public_ip}' -i ${local_file.private_key.filename} ubuntu@${aws_network_interface.k8s_node_02.private_ip}"
}
