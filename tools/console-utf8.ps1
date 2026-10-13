# Configura a saída do console do PowerShell em UTF-8 SOMENTE na sessão atual.
#
# Uso (dot-source, para as variáveis valerem na sessão que chamou):
#   . .\tools\console-utf8.ps1
#
# Por que existe:
#   - No Windows PowerShell 5.1 o console usa a página de código OEM (ex.: 850), então a saída
#     UTF-8 de CLIs nativas (Trivy com bordas Unicode, docker, terraform) aparece como "Ôö£ÔöÇ".
#   - CLIs Python como o aws cli usam a codificação do sistema ao imprimir e falham com
#     "UnicodeEncodeError: 'charmap' codec can't encode character" quando a saída tem acento ou seta.
#
# Não altera o perfil do usuário ($PROFILE), o registro nem variáveis de máquina/usuário.
# Tudo some quando a sessão fecha. Este arquivo é salvo em UTF-8 com BOM para o PowerShell 5.1
# ler os acentos dos comentários corretamente.

$utf8SemBom = New-Object System.Text.UTF8Encoding($false)

try {
    [Console]::OutputEncoding = $utf8SemBom
    [Console]::InputEncoding = $utf8SemBom
}
catch {
    # Hosts sem console real (saída redirecionada, alguns CIs) não aceitam a troca; segue sem ela.
    Write-Warning "Não foi possível ajustar a codificação do console: $($_.Exception.Message)"
}

# Codificação usada pelo PowerShell ao enviar texto para programas nativos por pipe.
$OutputEncoding = $utf8SemBom

# Modo UTF-8 do Python 3.7+ (PEP 540): stdout/stderr passam a usar UTF-8 em vez da página de código.
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
