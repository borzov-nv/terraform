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