output "external_ip" {
  value = data.vcd_edgegateway.edge_gateway.default_external_network_ip
}

output "wordpress_url" {
  value = format("https://%s", var.dns_hostname)
}
