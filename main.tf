variable "account" {
  type        = string
  description = "Brightbox account identifier for api authentication by terraform"
}
variable "username" {
  type        = string
  description = "brightbox username for api authentication by terraform"
}
variable "password" {
  type        = string
  description = "brightbox password for api authentication by terraform"
}

variable "cluster_name" {
  type        = string
  description = "Name to identify the cluster. Used in resource names"
  default     = "test"
}
variable "server_type" {
  type        = string
  description = "type of server to create to run jitsi"
  default     = "4gb.ssd"
}
variable "acme_email" {
  type        = string
  description = "email address to register with Let's Encrypt"
}
variable "jitsi_fqdn" {
  type        = string
  description = "allow overriding fqdn used to access jitsi. lets encrypt certificate will be generated for this. Defaults to Cloud IP fqdn"
  default     = ""
}

locals {
  jitsi_fqdn = coalesce(var.jitsi_fqdn, brightbox_cloudip.jitsi.fqdn)
}

provider "brightbox" {
  version   = "~> 1.2"
  apiurl    = "https://api.gb1.brightbox.com"
  account   = var.account
  username  = var.username
  password  = var.password
}

data "brightbox_image" "bionic" {
  name        = "^ubuntu-bionic.*server$"
  arch        = "x86_64"
  official    = true
  most_recent = true
}

resource "brightbox_server_group" "jitsi" {
  name = "jitsi.${var.cluster_name}"
}

resource "brightbox_firewall_policy" "jitsi" {
  name         = brightbox_server_group.jitsi.name
  server_group = brightbox_server_group.jitsi.id
  depends_on   = [brightbox_server_group.jitsi]
}

resource "brightbox_firewall_rule" "jitsi-tcp" {
  destination_port = "80,443,4445,4443,22"
  protocol         = "tcp"
  source           = "any"
  description      = "jitsi services"
  firewall_policy  = brightbox_firewall_policy.jitsi.id
}
resource "brightbox_firewall_rule" "jitsi-udp" {
  destination_port = "10000"
  protocol         = "udp"
  source           = "any"
  description      = "jitsi services"
  firewall_policy  = brightbox_firewall_policy.jitsi.id
}
resource "brightbox_firewall_rule" "jitsi-out" {
  destination      = "any"
  description      = "jitsi outgoing"
  firewall_policy  = brightbox_firewall_policy.jitsi.id
}

resource "brightbox_cloudip" "jitsi" {
  name   = "jitsi.${var.cluster_name}"
  target = brightbox_server.jitsi.interface

  provisioner "local-exec" {
    when    = destroy
    command = "ssh-keygen -R ${self.fqdn}; ssh-keygen -R ${self.public_ip}"
  }
}

resource "brightbox_server" "jitsi" {
  name      = "jitsi.${var.cluster_name}"
  image     = data.brightbox_image.bionic.id
  type      = var.server_type
  server_groups = [brightbox_server_group.jitsi.id]
  depends_on    = [brightbox_server_group.jitsi]
}

resource "null_resource" "configure-jitsi" {

  triggers  = {
    server = brightbox_server.jitsi.id
    cloudip = brightbox_cloudip.jitsi.public_ip
    jitsi_fqdn = local.jitsi_fqdn
  }

  depends_on = [brightbox_server.jitsi, brightbox_cloudip.jitsi]

  connection {
    user = "ubuntu"
    host = brightbox_cloudip.jitsi.fqdn
  }

  provisioner "file" {
    content     = file("scripts/configure-jitsi.sh")
    destination = "configure-jitsi.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo sh /home/ubuntu/configure-jitsi.sh ${local.jitsi_fqdn} ${brightbox_cloudip.jitsi.fqdn} ${var.acme_email}"
    ]
  }
}

output "jitsi_url" {
  value = "https://${local.jitsi_fqdn}"
}
