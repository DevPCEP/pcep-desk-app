# PCEP: assina com Authenticode os .exe/.dll de uma pasta (ou um arquivo só).
#
# Uso:   pwsh pcep/assinar-windows.ps1 -Caminho <pasta ou arquivo> [-Teste]
# Lê do ambiente PCEP_ASSINATURA_PFX (PFX em base64) e PCEP_ASSINATURA_SENHA.
# Sem os dois, não assina e sai com 0. Qualquer falha de assinatura sai com 1.
# -Teste: ignora os segredos e assina com um certificado autoassinado criado na
# hora (só para validar a mecânica no CI; o resultado não é confiável).
# Nunca imprime a senha nem o conteúdo do PFX.
param(
    [Parameter(Mandatory)][string]$Caminho,
    [switch]$Teste
)
$ErrorActionPreference = 'Stop'

$pfxB64 = $env:PCEP_ASSINATURA_PFX
$senha = $env:PCEP_ASSINATURA_SENHA
if (-not $Teste) {
    $temPfx = -not [string]::IsNullOrWhiteSpace($pfxB64)
    $temSenha = -not [string]::IsNullOrWhiteSpace($senha)
    if (-not $temPfx -and -not $temSenha) {
        Write-Host 'Assinatura: sem certificado, executável não assinado.'
        exit 0
    }
    if ($temPfx -ne $temSenha) {
        throw 'Assinatura: PCEP_ASSINATURA_PFX e PCEP_ASSINATURA_SENHA precisam estar os dois definidos (ou nenhum).'
    }
}

# signtool: pasta mais nova do Windows SDK instalada no runner.
$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Directory.Parent.Name } -Descending | Select-Object -First 1
if (-not $signtool) { throw 'signtool.exe não encontrado em "Windows Kits\10\bin\*\x64".' }

if (-not (Test-Path -LiteralPath $Caminho)) { throw "Caminho não existe: $Caminho" }
$item = Get-Item -LiteralPath $Caminho
if ($item.PSIsContainer) {
    # Ignora drivers\ e usbmmidd_v2\ (drivers de terceiros, com assinatura própria).
    $arquivos = @(Get-ChildItem -LiteralPath $item.FullName -Recurse -File -Include *.exe, *.dll |
        Where-Object { $_.FullName -notmatch '[\\/](drivers|usbmmidd_v2)[\\/]' })
} else {
    $arquivos = @($item)
}
# Pula o que já tem assinatura válida (por exemplo DLLs de terceiros).
$arquivos = @($arquivos | Where-Object { (Get-AuthenticodeSignature -LiteralPath $_.FullName).Status -ne 'Valid' })
if ($arquivos.Count -eq 0) {
    Write-Host 'Assinatura: nenhum arquivo para assinar.'
    exit 0
}

$base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$pfx = Join-Path $base ("pcep-assinatura-$([guid]::NewGuid()).pfx")
$thumb = $null
try {
    if ($Teste) {
        $senha = -join ([Security.Cryptography.RandomNumberGenerator]::GetBytes(24) | ForEach-Object { $_.ToString('x2') })
        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=PCEP Teste de Assinatura' -CertStoreLocation Cert:\CurrentUser\My
        $thumb = $cert.Thumbprint
        Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$thumb" -FilePath $pfx -Password (ConvertTo-SecureString $senha -AsPlainText -Force) | Out-Null
    } else {
        [IO.File]::WriteAllBytes($pfx, [Convert]::FromBase64String($pfxB64))
    }

    foreach ($arq in $arquivos) {
        # Até 3 tentativas: o servidor de carimbo de tempo às vezes falha.
        for ($i = 1; $i -le 3; $i++) {
            # A saída é capturada para não registrar a linha de comando; só aparece se falhar.
            $saida = & $signtool.FullName sign /fd sha256 /td sha256 /tr http://timestamp.digicert.com /f $pfx /p $senha $arq.FullName 2>&1
            if ($LASTEXITCODE -eq 0) { break }
            if ($i -eq 3) {
                $saida | ForEach-Object { Write-Host $_ }
                throw "Falha ao assinar $($arq.FullName) (signtool saiu com $LASTEXITCODE)."
            }
            Start-Sleep -Seconds 5
        }
    }

    # Confere que todos os arquivos assinados carregam um certificado.
    foreach ($arq in $arquivos) {
        if (-not (Get-AuthenticodeSignature -LiteralPath $arq.FullName).SignerCertificate) {
            throw "Sem assinatura após signtool: $($arq.FullName)"
        }
    }
    $raiz = if ($item.PSIsContainer) { $item.FullName } else { $item.DirectoryName }
    foreach ($arq in $arquivos) {
        Write-Host "  assinado: $([IO.Path]::GetRelativePath($raiz, $arq.FullName))"
    }
    Write-Host "Assinatura: $($arquivos.Count) arquivo(s) assinado(s)."
} finally {
    Remove-Item -LiteralPath $pfx -Force -ErrorAction SilentlyContinue
    if ($thumb) { Remove-Item "Cert:\CurrentUser\My\$thumb" -Force -ErrorAction SilentlyContinue }
}
