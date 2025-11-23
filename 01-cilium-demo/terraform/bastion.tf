resource "aws_instance" "bastion" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  subnet_id       = module.vpc.subnets_public_raw["cilium-public-bastion"].id
  security_groups = [aws_security_group.bastion_sg.id]
  key_name        = aws_key_pair.this.key_name

  user_data = <<-EOF
              #!/bin/bash
              hostnamectl set-hostname ${local.common_name}-bastion
              EOF

  tags = {
    Name = "${local.common_name}-bastion"
  }
}

resource "aws_eip" "bastion" {
  instance = aws_instance.bastion.id
  domain   = "vpc"
}

resource "aws_security_group" "bastion_sg" {
  name        = "${local.common_name}-bastion-sg"
  description = "Security group for bastion host"
  vpc_id      = module.vpc.vpc_raw.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "bastion_ssh_inbound" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  security_group_id = aws_security_group.bastion_sg.id
  # cidr_blocks       = ["${chomp(data.http.myip.response_body)}/32"]
  cidr_blocks = ["0.0.0.0/0"]
}

data "http" "myip" {
  url = "https://ifconfig.me"

  request_headers = {
    Accept = "application/json"
  }
}

output "bastion_connection_string" {
  value = "ssh -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} ubuntu@${aws_eip.bastion.public_ip}"
}
