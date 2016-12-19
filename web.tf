provider "aws" {
  region = "${var.region}"
}

# Modules are a way of constructing reusable bundles of resources.
# The source tells Terraform where to find the module’s source code
module "vpc" {
  source        = "github.com/jason-azze/tf_vpc.git?ref=v0.0.1"
  name          = "web"
  cidr          = "10.0.0.0/16"
  public_subnet = "10.0.1.0/24"
}

resource "aws_instance" "web" {
  ami                         = "${lookup(var.ami, var.region)}"
  instance_type               = "${var.instance_type}"
  key_name                    = "${var.key_name}"
  subnet_id                   = "${module.vpc.public_subnet_id}"
  private_ip                  = "${var.instance_ips[count.index]}"
  user_data                   = "${file("files/web_bootstrap.sh")}"
  associate_public_ip_address = true

  vpc_security_group_ids = [
    "${aws_security_group.web_host_sg.id}",
  ]

  tags {
    # Name our instances by referencing the count.index.
    # The format function here turns our count index into a 3-digit number 
    # We add 1 so we don't get a name with 000.
    Name = "web-${format("%03d", count.index + 1)}"

    Owner = "${element(var.owner_tag, count.index)}"
  }

  # The length function lets us count the num of elements in the
  # instance_ips variable.
  count = "${length(var.instance_ips)}"
}

# We’ve specified a module output for the value of the subnets attribute
resource "aws_elb" "web" {
  name = "web-elb"

  subnets         = ["${module.vpc.public_subnet_id}"]
  security_groups = ["${aws_security_group.web_inbound_sg.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  # The instances are registered automatically
  # Using splat syntax here
  instances = ["${aws_instance.web.*.id}"]
}

resource "aws_security_group" "web_inbound_sg" {
  name        = "web_inbound"
  description = "Allow HTTP from Anywhere"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web_host_sg" {
  name        = "web_host"
  description = "Allow SSH & HTTP to web hosts"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${module.vpc.cidr}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8
    to_port     = 0
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
