# AGENTS.md — Contrato de trabalho para agentes de IA (KXC simple-api)

Vale para QUALQUER agente (Kiro, Claude, Codex, Copilot). É curto de propósito; o detalhe está em `.kiro/steering/`.

## Ordem de autoridade

1. Pedido explícito do Leandro na conversa atual
2. Decisões e regras de `.kiro/steering/` (arquitetura, FinOps, segurança, padrões)
3. Estado ATUAL do código no repositório (fatos sobre o que existe hoje)
4. Seu conhecimento prévio — o MENOS confiável (preços, APIs e versões mudam)

Fatos e decisões são coisas diferentes:
- **Fato sobre o código** (porta, arquivo, variável): o código atual é a verdade. `00-fonte-da-verdade.md` descreve o repo BASE (commit `25337f2`); se o código atual divergir, provavelmente já foi corrigido — aponte a divergência e nunca "desconserte" o código para bater com a steering.
- **Decisão de arquitetura** (ALB, NAT, tamanho de task, região): vale a steering, mesmo que o README original de `infrastructure/` descreva outra coisa (ALB + NAT). A divergência é consciente e vai documentada em ADR.

## As 12 regras anti-alucinação

1. **Leia antes de afirmar.** Nunca descreva arquivo, porta, variável, recurso ou módulo sem abri-lo nesta sessão. Cite `caminho:linha`.
2. **Rotule.** Toda afirmação técnica relevante leva `[FATO: arquivo:linha | comando | URL]`, `[HIPÓTESE]` ou `[PROPOSTA]`.
3. **Não invente números.** Preço AWS, limite de serviço, latência, RPS ou versão só com fonte (URL oficial aberta, saída de comando ou medição). Sem fonte: "a verificar" + como verificar.
4. **Não invente APIs.** Argumentos Terraform, campos de task definition, flags de CLI, inputs de Actions e ações IAM precisam existir na versão fixada. Em dúvida: `terraform validate`, schema do provider, `<cli> --help`, `action.yml`.
5. **Rode e mostre.** "Os testes passam" só com a saída do comando no turno. Nada de "deve funcionar".
6. **Escopo é lei.** Mude só o que a tarefa pede. Fora do escopo: pergunte. Nada de "aproveitar para refatorar".
7. **Nada que gere custo sem aprovação.** `terraform apply/destroy`, `aws ... create/put/update/delete`, `kubectl apply` em cluster remoto: só com aprovação explícita do Leandro NO TURNO, depois de mostrar plano e custo estimado.
8. **Segredo nunca entra no repo, no log, no chat nem no contexto.** Não leia credenciais, tfstate ou variáveis de ambiente com segredos. Placeholders: `<DB_PASSWORD>`, `<AWS_ACCOUNT_ID>`.
9. **Diga "não sei".** Se a informação não está no repo, na steering ou numa fonte verificável, pare e pergunte.
10. **Feche com evidência.** Toda entrega termina com: arquivos alterados, comandos + resultado, o que NÃO foi verificado, próximo passo.
11. **Números locais não são números da AWS.** Benchmark feito na máquina local é sempre rotulado LOCAL.
12. **Credenciais do agente são somente leitura por padrão** (perfil AWS de leitura, ex.: `kxc-readonly`). Escrita na AWS só acontece pelo pipeline com aprovação ou quando o Leandro ativa um perfil de escrita naquele momento e aprova o comando. Nunca peça, crie ou guarde credencial de escrita.

## Decisões travadas (não reabrir sem pedido explícito)

Ver `.kiro/steering/01-arquitetura-e-restricoes.md`. Resumo: API Gateway HTTP API → VPC Link → Cloud Map → ECS Fargate ARM64 0,5 vCPU / 1 GB → RDS PostgreSQL privado. Sem ALB e sem NAT na trilha ECS. EKS só como laboratório efêmero. Região `us-east-1`.
