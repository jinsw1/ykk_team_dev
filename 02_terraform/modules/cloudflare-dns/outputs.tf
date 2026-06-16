# output "fqdn" {
#   value = cloudflare_dns_record.this.hostname
# }

output "fqdn" {
  value = cloudflare_dns_record.this.name
}