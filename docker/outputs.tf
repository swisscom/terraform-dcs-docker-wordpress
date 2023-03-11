output "wordpress_url" {
  value = format("https://%s", var.dns_hostname)
}
