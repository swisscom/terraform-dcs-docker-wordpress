output "external_ip" {
  value = data.vcd_edgegateway.edge_gateway.default_external_network_ip
}
