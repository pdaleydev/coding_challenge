# ---------------------------------------------------------------------------
# Variables (bonus-specific)
# ---------------------------------------------------------------------------

variable "ssh_source_cidr" {
  description = "Your public IP (CIDR) that is allowed to SSH into the VM."
  type        = string
}

variable "vm_admin_username" {
  description = "Admin username for the bonus VM."
  type        = string
  default     = "azureadmin"
}

variable "vm_ssh_public_key" {
  description = "SSH public key for VM access, injected via GitHub Actions secret."
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# VNet
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "bonus_vnet" {
  name                = "vnet-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.10.0.0/16"]

  tags = var.tags
}

# Subnet for the VM
resource "azurerm_subnet" "vm_subnet" {
  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.bonus_vnet.name
  address_prefixes     = ["10.10.1.0/24"]
}

# Subnet for Private Endpoints
# private_endpoint_network_policies must be Disabled to allow PE traffic routing
resource "azurerm_subnet" "pe_subnet" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.bonus_vnet.name
  address_prefixes     = ["10.10.2.0/24"]

  private_endpoint_network_policies = "Disabled"
}

# ---------------------------------------------------------------------------
# Network Security Group — VM subnet
# ---------------------------------------------------------------------------

resource "azurerm_network_security_group" "vm_nsg" {
  name                = "nsg-vm-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  security_rule {
    name                       = "allow-ssh-inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ssh_source_cidr
    destination_address_prefix = "*"
  }

  # Deny all other inbound traffic explicitly
  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_subnet_network_security_group_association" "vm_nsg_assoc" {
  subnet_id                 = azurerm_subnet.vm_subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# ---------------------------------------------------------------------------
# Public IP + NIC for the VM
# ---------------------------------------------------------------------------

resource "azurerm_public_ip" "vm_pip" {
  name                = "pip-vm-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.tags
}

resource "azurerm_network_interface" "vm_nic" {
  name                = "nic-vm-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  ip_configuration {
    name                          = "ipconfig-vm"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Linux VM (Standard_B1s — smallest burstable SKU, free-tier eligible)
# SSH key auth only; password auth disabled
# ---------------------------------------------------------------------------

resource "azurerm_linux_virtual_machine" "bonus_vm" {
  name                = "vm-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  #size                = "Standard_B1s" B series is "retiring"
  size           = "Standard_D2as_v5"
  admin_username = var.vm_admin_username

  disable_password_authentication = true

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = var.vm_ssh_public_key
  }

  network_interface_ids = [azurerm_network_interface.vm_nic.id]

  os_disk {
    name                 = "osdisk-vm-${var.project}-${var.environment}-${var.location_short}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Private Endpoint — Function App (data-plane: "sites")
# ---------------------------------------------------------------------------

resource "azurerm_private_endpoint" "func_pe" {
  name                = "pe-func-${var.project}-${var.environment}-${var.location_short}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  subnet_id           = azurerm_subnet.pe_subnet.id

  private_service_connection {
    name                           = "psc-func-${var.project}"
    private_connection_resource_id = azurerm_windows_function_app.func.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  # Attach the private DNS zone so the PE NIC gets a DNS record automatically
  private_dns_zone_group {
    name                 = "dnsgroup-func"
    private_dns_zone_ids = [azurerm_private_dns_zone.func_dns.id]
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Private DNS Zone — privatelink.azurewebsites.net
# ---------------------------------------------------------------------------

resource "azurerm_private_dns_zone" "func_dns" {
  name                = "privatelink.azurewebsites.net"
  resource_group_name = azurerm_resource_group.rg.name

  tags = var.tags
}

# Link the DNS zone to the VNet so VMs in the VNet resolve the private IP
resource "azurerm_private_dns_zone_virtual_network_link" "func_dns_link" {
  name                  = "dnslink-${var.project}-${var.environment}"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.func_dns.name
  virtual_network_id    = azurerm_virtual_network.bonus_vnet.id
  registration_enabled  = false

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Outputs (bonus)
# ---------------------------------------------------------------------------

output "bonus_vm_public_ip" {
  description = "Public IP address to SSH into the bonus VM."
  value       = azurerm_public_ip.vm_pip.ip_address
}

output "bonus_vm_ssh_command" {
  description = "Ready-to-run SSH command for the bonus VM."
  value       = "ssh ${var.vm_admin_username}@${azurerm_public_ip.vm_pip.ip_address}"
}

output "bonus_private_endpoint_ip" {
  description = "Private IP assigned to the Function App private endpoint."
  value       = azurerm_private_endpoint.func_pe.private_service_connection[0].private_ip_address
}

output "bonus_curl_command" {
  description = "curl command to run from inside the VM to hit the Function App via its private endpoint."
  value       = "curl -i \"https://func-${var.project}-${var.environment}-${var.location_short}.azurewebsites.net/api/HttpExample?name=World\""
}
