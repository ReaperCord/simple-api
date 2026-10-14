#!/usr/bin/env bash
# Varredura de recursos residuais após terraform destroy (SOMENTE LEITURA).
# Recursos do root bootstrap (Track=bootstrap: bucket de state, OIDC, roles, budget, ECR) são esperados e ignorados;
# apague-os à mão ao fim da avaliação.
# Uso: tools/residual-check.sh [regiao]   (padrão: us-east-1)
# Códigos de saída:
#   0 = nada encontrado
#   1 = há recursos que podem continuar cobrando (revise a lista)
#   2 = alguma consulta falhou (credencial, permissão, rede) — o resultado NÃO é confiável
# Exceção: serviços opcionais que podem nem existir na conta (GuardDuty não está disponível em conta aberta
# pelo cadastro novo da AWS sem os recursos avançados) só geram AVISO quando a consulta falha.
set -uo pipefail
REGION="${1:-us-east-1}"
PROJECT="simple-api"
FOUND=0
ERRORS=0
WARNINGS=0

if ! command -v aws >/dev/null 2>&1; then
  echo "ERRO: AWS CLI não encontrada." >&2; exit 2
fi
if ! IDENTITY=$(aws sts get-caller-identity --query Arn --output text 2>&1); then
  echo "ERRO: não foi possível autenticar na AWS: $IDENTITY" >&2; exit 2
fi
echo "Conta/identidade: $IDENTITY | região: $REGION"

# check <título> <comando...>: roda o comando; saída não vazia = resíduo; código != 0 = erro de consulta
check() {
  local title="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  printf '\n== %s ==\n' "$title"
  if [ $rc -ne 0 ]; then
    echo "ERRO na consulta (rc=$rc): $out"; ERRORS=1
  elif [ -n "$out" ] && [ "$out" != "None" ]; then
    echo "$out"; FOUND=1
  else
    echo "ok: nada encontrado"
  fi
}

# check_soft <título> <comando...>: igual ao check, mas erro de consulta vira AVISO (serviço opcional)
check_soft() {
  local title="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  printf '\n== %s ==\n' "$title"
  if [ $rc -ne 0 ]; then
    echo "AVISO: a consulta falhou (rc=$rc); o serviço pode não estar disponível nesta conta: $out"; WARNINGS=1
  elif [ -n "$out" ] && [ "$out" != "None" ]; then
    echo "$out"; FOUND=1
  else
    echo "ok: nada encontrado"
  fi
}

# Recursos do root bootstrap (bucket de state, OIDC, roles do pipeline, budget, ECR) levam Track=bootstrap e são esperados.
# A consulta GERAL por tag não lista ECS cluster, service e task definition: a AWS nunca remove esses artefatos (cluster e
# service apagados ficam INACTIVE e visíveis; task definition desregistrada fica INACTIVE para sempre; as ACTIVE vêm de
# skip_destroy = true). Eles NÃO são ignorados: a seção seguinte classifica cada ARN de ECS achado por tag pelo STATUS REAL
# (describe-clusters / describe-services). Cluster ou service ativo, ou que não dá para classificar, é resíduo (exit 1);
# INACTIVE ou já inexistente é ignorado. Task definition ACTIVE só é informada (não cobra; não altera o código de saída).
# O índice de tags é eventualmente consistente: itens de outros tipos (ex.: regras de security group) podem aparecer por
# algumas horas depois do destroy; confirme no serviço de origem.
# shellcheck disable=SC2016  # crases são literal JMESPath, não expansão do shell
check "Recursos com tag Project=${PROJECT} (exceto Track=bootstrap)" \
  aws resourcegroupstaggingapi get-resources --region "$REGION" \
    --tag-filters "Key=Project,Values=${PROJECT}" \
    --query 'ResourceTagMappingList[?length(Tags[?Key==`Track` && Value==`bootstrap`]) == `0` && !(starts_with(ResourceARN, `arn:aws:ecs:`) && (contains(ResourceARN, `:task-definition/`) || contains(ResourceARN, `:cluster/`) || contains(ResourceARN, `:service/`)))].ResourceARN' --output text
# ARNs de ECS (cluster, service, task definition) com tag Project, exceto bootstrap.
ecs_tagged_arns() {
  aws resourcegroupstaggingapi get-resources --region "$REGION"     --tag-filters "Key=Project,Values=${PROJECT}"     --resource-type-filters ecs:cluster ecs:service ecs:task-definition     --query 'ResourceTagMappingList[?length(Tags[?Key==`Track` && Value==`bootstrap`]) == `0`].ResourceARN' --output text
}

# Resíduo = cluster/service ECS marcado por tag cujo status real NÃO é INACTIVE (ou que não dá para classificar).
# Imprime uma linha por resíduo; código != 0 = erro de consulta.
ecs_tagged_active() {
  local arns arn st path cluster svc
  arns=$(ecs_tagged_arns) || { echo "$arns"; return 1; }
  for arn in $arns; do
    case "$arn" in
      None|"") ;;
      *:cluster/*)
        st=$(aws ecs describe-clusters --region "$REGION" --clusters "$arn" --query 'clusters[0].status' --output text 2>&1)           || { echo "$st"; return 1; }
        case "$st" in INACTIVE|None|"") ;; *) echo "$arn (cluster ECS, status $st)" ;; esac ;;
      *:service/*)
        path="${arn#*:service/}"
        if [[ "$path" != */* ]]; then echo "$arn (service ECS em formato antigo, sem cluster no ARN: não classificável)"; continue; fi
        cluster="${path%%/*}"; svc="${path#*/}"
        st=$(aws ecs describe-services --region "$REGION" --cluster "$cluster" --services "$svc" --query 'services[0].status' --output text 2>&1)           || { echo "$st"; return 1; }
        case "$st" in INACTIVE|None|"") ;; *) echo "$arn (service ECS, status $st)" ;; esac ;;
      *) ;;
    esac
  done
}

# Task definitions ACTIVE marcadas por tag (informativo).
ecs_taskdefs_active() {
  local arns arn st
  arns=$(ecs_tagged_arns) || { echo "$arns"; return 1; }
  for arn in $arns; do
    case "$arn" in
      *:task-definition/*)
        st=$(aws ecs describe-task-definition --region "$REGION" --task-definition "$arn" --query 'taskDefinition.status' --output text 2>&1)           || { echo "$st"; return 1; }
        [ "$st" = "ACTIVE" ] && echo "$arn" ;;
    esac
  done
  return 0
}

check "ECS marcado por tag e ainda ativo (cluster ou service com status diferente de INACTIVE)" ecs_tagged_active

printf '
== Task definitions ECS ACTIVE com tag Project=%s (informativo: não cobram; skip_destroy mantém a revisão; não altera o código de saída) ==
' "$PROJECT"
td_out=$(ecs_taskdefs_active); td_rc=$?
if [ $td_rc -ne 0 ]; then echo "ERRO na consulta (rc=$td_rc): $td_out"; ERRORS=1
elif [ -n "$td_out" ]; then echo "$td_out"
else echo "ok: nenhuma"; fi

check "Instâncias EC2 (nós do EKS, gerador de carga)" \
  aws ec2 describe-instances --region "$REGION" --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' --output text
check "VPCs com tag Project=${PROJECT}" \
  aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Project,Values=${PROJECT}" --query 'Vpcs[].VpcId' --output text
check "Elastic IPs sem associação" \
  aws ec2 describe-addresses --region "$REGION" --query 'Addresses[?AssociationId==null].[PublicIp,AllocationId]' --output text
check "NAT Gateways ativos" \
  aws ec2 describe-nat-gateways --region "$REGION" --filter Name=state,Values=available,pending --query 'NatGateways[].NatGatewayId' --output text
check "Interfaces de rede soltas (ENIs disponíveis)" \
  aws ec2 describe-network-interfaces --region "$REGION" --filters Name=status,Values=available --query 'NetworkInterfaces[].[NetworkInterfaceId,Description]' --output text
check "Volumes EBS soltos" \
  aws ec2 describe-volumes --region "$REGION" --filters Name=status,Values=available --query 'Volumes[].[VolumeId,Size]' --output text
check "Snapshots EBS da conta" \
  aws ec2 describe-snapshots --region "$REGION" --owner-ids self --query 'Snapshots[].[SnapshotId,VolumeSize,StartTime]' --output text
check "Load balancers" \
  aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerArn' --output text
check "Clusters EKS" \
  aws eks list-clusters --region "$REGION" --query 'clusters' --output text
check "Clusters ECS" \
  aws ecs list-clusters --region "$REGION" --query 'clusterArns' --output text
check "APIs HTTP do API Gateway" \
  aws apigatewayv2 get-apis --region "$REGION" --query 'Items[].[ApiId,Name]' --output text
check "VPC Links do API Gateway" \
  aws apigatewayv2 get-vpc-links --region "$REGION" --query 'Items[].[VpcLinkId,Name]' --output text
check "Namespaces do Cloud Map" \
  aws servicediscovery list-namespaces --region "$REGION" --query 'Namespaces[].[Id,Name,Type]' --output text
# shellcheck disable=SC2016  # crases são literal JMESPath, não expansão do shell
check "Zonas hospedadas privadas do Route 53 (US\$ 0,50/mês cada)" \
  aws route53 list-hosted-zones --query 'HostedZones[?Config.PrivateZone==`true`].[Id,Name]' --output text
check "Instâncias RDS" \
  aws rds describe-db-instances --region "$REGION" --query 'DBInstances[].DBInstanceIdentifier' --output text
check "Snapshots manuais do RDS" \
  aws rds describe-db-snapshots --region "$REGION" --snapshot-type manual --query 'DBSnapshots[].DBSnapshotIdentifier' --output text
check "Log groups do projeto e do EKS (os do EKS não levam as tags do projeto)" \
  aws logs describe-log-groups --region "$REGION" \
    --query "logGroups[?contains(logGroupName, '${PROJECT}') || starts_with(logGroupName, '/aws/eks/')].logGroupName" --output text
check "Segredos ativos do RDS ou do projeto" \
  aws secretsmanager list-secrets --region "$REGION" \
    --query "SecretList[?contains(Name, 'rds!') || contains(Name, '${PROJECT}')].Name" --output text
check "Alarmes do CloudWatch do projeto" \
  aws cloudwatch describe-alarms --region "$REGION" --query "MetricAlarms[?contains(AlarmName, '${PROJECT}')].AlarmName" --output text
check_soft "Detector do GuardDuty (cobra após o trial de 30 dias)" \
  aws guardduty list-detectors --region "$REGION" --query 'DetectorIds' --output text

echo
if [ $ERRORS -ne 0 ]; then
  echo "RESULTADO: houve ERRO em pelo menos uma consulta. O resultado não é confiável."; exit 2
elif [ $FOUND -ne 0 ]; then
  echo "RESULTADO: há recursos listados acima. Avalie antes de encerrar."; exit 1
elif [ $WARNINGS -ne 0 ]; then
  echo "RESULTADO: nenhum resíduo encontrado, mas há AVISOS acima (serviço opcional que não pôde ser consultado)."; exit 0
else
  echo "RESULTADO: nenhum resíduo encontrado."; exit 0
fi
