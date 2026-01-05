# 1. Get the latest Ubuntu Image
data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# 2. Bastion (Public)
resource "yandex_compute_instance" "bastion" {
  name        = "bastion"
  hostname    = "bastion"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20 # Saves money for lab/dev
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.bastion_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = var.vm_preemptible
  }

}

# 3. Two Private Webservers
resource "yandex_compute_instance" "web" {
  count       = 2
  name        = "web-${count.index + 1}"
  hostname    = "web-${count.index + 1}"
  # We spread them across zones A and B for high availability
  zone        = count.index == 0 ? "ru-central1-a" : "ru-central1-b"
  platform_id = "standard-v3"

  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    # Reference the specific private subnet based on the zone
    subnet_id          = count.index == 0 ? yandex_vpc_subnet.private-1.id : yandex_vpc_subnet.private-2.id
    security_group_ids = [yandex_vpc_security_group.web_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = var.vm_preemptible
  }
}

# 4. Monitoring: Zabbix and Kibana (Public)
resource "yandex_compute_instance" "monitoring" {
  for_each    = toset(["zabbix", "kibana"])
  name        = each.key
  hostname    = each.key
  zone        = "ru-central1-a"
  platform_id = "standard-v3"

  resources {
    cores  = 2
    memory = 4 # UI and Zabbix need slightly more RAM
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.monitoring_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = var.vm_preemptible
  }

}

# 5. Elasticsearch (Private)
resource "yandex_compute_instance" "elasticsearch" {
  name        = "elasticsearch"
  hostname    = "elasticsearch"
  zone        = "ru-central1-a"
  platform_id = "standard-v3"

  resources {
    cores  = 4 # Elastic is heavy
    memory = 8
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.private-1.id
    security_group_ids = [yandex_vpc_security_group.elastic_sg.id]
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  scheduling_policy {
    preemptible = var.vm_preemptible
  }
}

resource "yandex_alb_target_group" "web_targets" {
  name = "web-target-group"

  dynamic "target" {
    for_each = yandex_compute_instance.web
    content {
      subnet_id  = target.value.network_interface.0.subnet_id
      ip_address = target.value.network_interface.0.ip_address
    }
  }
}

resource "yandex_alb_backend_group" "web_backends" {
  name = "web-backend-group"

  http_backend {
    name             = "http-backend"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_alb_target_group.web_targets.id]
    
    load_balancing_config {
      panic_threshold = 50
    }    
    healthcheck {
      timeout             = "1s"
      interval            = "1s"
      http_healthcheck {
        path = "/"
      }
    }
  }
}

resource "yandex_alb_http_router" "web_router" {
  name = "web-http-router"
}

resource "yandex_alb_virtual_host" "web_vhost" {
  name           = "web-virtual-host"
  http_router_id = yandex_alb_http_router.web_router.id
  route {
    name = "root-route"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.web_backends.id
        timeout          = "3s"
      }
    }
  }
}

resource "yandex_alb_load_balancer" "main_alb" {
  name               = "main-load-balancer"
  network_id         = yandex_vpc_network.main.id
  security_group_ids = [yandex_vpc_security_group.alb_sg.id]

  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.public.id
    }
  }

  listener {
    name = "web-listener"
    endpoint {
      address {
        external_ipv4_address {
          # This will provide a public IP automatically
        }
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.web_router.id
      }
    }
  }
}

resource "local_file" "ansible_inventory" {
  content = templatefile("hosts.tftpl",
    {
      bastion_ip     = yandex_compute_instance.bastion.network_interface.0.nat_ip_address
      web_nodes      = yandex_compute_instance.web[*]
      monitor_nodes  = yandex_compute_instance.monitoring
      elastic_fqdn   = yandex_compute_instance.elasticsearch.fqdn
    }
  )
  filename = "ansible/hosts.ini" 
}

output "bastion_public_ip" {
  description = "Connect to this IP for SSH/Ansible management"
  value       = yandex_compute_instance.bastion.network_interface.0.nat_ip_address
}

output "web_site_url" {
  description = "Visit this IP in your browser to see your website"
  value       = "http://${yandex_alb_load_balancer.main_alb.listener.0.endpoint.0.address.0.external_ipv4_address.0.address}"
}

output "monitoring_ips" {
  description = "Public IPs for Zabbix and Kibana"
  value = {
    for k, v in yandex_compute_instance.monitoring : k => v.network_interface.0.nat_ip_address
  }
}