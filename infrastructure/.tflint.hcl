# Configuracao do TFLint (B-7). Uso:
#   tflint --init --config infrastructure/.tflint.hcl
#   tflint --recursive --chdir infrastructure --config <caminho absoluto deste arquivo> --minimum-failure-severity=error
# Alertas (warning) dos modulos fora da trilha (alb, target-group, listener, nat-gateway) sao aceitos
# e listados no relatorio; nos demais modulos a meta e zero.

config {
  # Modulos locais sao analisados pelo --recursive; nao baixa modulos remotos.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Decisao 4 (decisoes-design.md): modulos declaram apenas 'source' do provider aws, sem 'version' e sem
# required_version; a versao (~> 6.68) e o required_version (>= 1.11) vivem so nos roots (bootstrap e
# infrastructure), que cumprem as duas regras. Sem esta excecao as regras geram 1 warning por modulo
# (46 no total), todos desta mesma natureza.
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}

# Versao FIXADA (release v0.49.0 de terraform-linters/tflint-ruleset-aws, publicada em 2026-09-19).
plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
