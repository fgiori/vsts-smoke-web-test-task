$ErrorActionPreference = 'Stop'

try {
    # 1. Importa l'SDK ufficiale di Azure DevOps
    Import-Module -Name VstsTaskSdk -ErrorAction Stop

    # 2. Recupera gli input mappati nel tuo task.json
    $url = Get-VstsInput -Name "url" -Require
    $expectedReturnCode = [int](Get-VstsInput -Name "expectedReturnCode" -Require)
    $timeout = [int](Get-VstsInput -Name "timeout" -Require)

    Write-Host "Executing web test for $url"

    # 3. Configurazione policy SSL/TLS (Inclusa la retrocompatibilità TLS 1.3 se supportata dall'agente)
    $CertificatePolicyCode = @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
    
    # Evita errori di compilazione tipo duplicato se eseguito più volte sullo stesso agente
    if (-not ([System.Management.Automation.PSTypeName]'TrustAllCertsPolicy').Type) {
        Add-Type -TypeDefinition $CertificatePolicyCode
    }

    $AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
    [System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

    $HTTP_Status_Timeout = 0
    $HTTP_Request = [System.Net.WebRequest]::Create($url)

    # 4. Esecuzione della richiesta HTTP
    try {
        $HTTP_Request.Timeout = $timeout * 1000
        $HTTP_Response = $HTTP_Request.GetResponse()
        $HTTP_Status = [int]$HTTP_Response.StatusCode
        $HTTP_Response.Close()
    }
    catch [System.Net.WebException] {
        $res = $_.Exception.Response
        if ($res) {
            $HTTP_Status = [int]$res.StatusCode
        } else {
            $HTTP_Status = $HTTP_Status_Timeout
        }
    }

    # 5. Valutazione del risultato tramite funzioni VstsTaskSdk
    if ($HTTP_Status -eq $expectedReturnCode) {
        Set-VstsTaskResult -Result Succeeded -Message "Web test success with HTTP $HTTP_Status"
    }
    elseif ($HTTP_Status -eq $HTTP_Status_Timeout) {
        Set-VstsTaskResult -Result Failed -Message "Request failed due to timeout after $timeout seconds."
    }
    else {
        Set-VstsTaskResult -Result Failed -Message "Web test failed, received HTTP $HTTP_Status but expected HTTP $expectedReturnCode."
    }

}
catch {
    # 6. Fallimento sicuro in caso di eccezioni impreviste nello script
    if (Get-Command Set-VstsTaskResult -ErrorAction SilentlyContinue) {
        Set-VstsTaskResult -Result Failed -Message $_.Exception.Message
    } else {
        Write-Error $_.Exception.Message
        exit 1
    }
}
