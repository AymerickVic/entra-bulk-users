<#
.SYNOPSIS
    Création en masse d'utilisateurs Microsoft Entra ID depuis un fichier CSV,
    via Microsoft Graph, avec gestion d'erreur et rapport des échecs.

.DESCRIPTION
    Le script lit un CSV, tente de créer chaque utilisateur avec New-MgUser,
    et continue même si une ligne échoue (doublon, champ manquant, etc.).
    Chaque échec est collecté (UPN + nom + raison) puis exporté dans un CSV
    de rapport, lisible dans Excel.

.PARAMETER CsvPath
    Chemin du CSV source. Colonnes attendues :
    DisplayName, MailNickname, UserPrincipalName, Department, JobTitle

.PARAMETER TenantId
    Domaine ou ID du tenant Entra cible (ex. contoso.onmicrosoft.com).
    Obligatoire : épingle explicitement le tenant pour éviter qu'un compte
    invité/MSA ne se connecte dans son contexte personnel (erreur 405).

.PARAMETER ReportPath
    Chemin du rapport CSV des échecs. Défaut : ./echecs_creation.csv

.EXAMPLE
    ./New-BulkEntraUsers.ps1 -CsvPath ./users.csv -TenantId contoso.onmicrosoft.com

.NOTES
    Prérequis : PowerShell 7+ et le module Microsoft.Graph.
    Permission Graph requise : User.ReadWrite.All
#>

param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [string]$ReportPath = "./echecs_creation.csv"
)

# --- Connexion Graph ---
# -TenantId épingle le bon tenant (sinon un compte invité/MSA se connecte
# dans son contexte personnel -> erreur 405 sur New-MgUser).
Connect-MgGraph -TenantId $TenantId -Scopes "User.ReadWrite.All" -NoWelcome

# --- Lecture du CSV ---
$users = Import-Csv -Path $CsvPath

# Panier qui collectera tous les échecs (vide au départ)
$echecs = @()

foreach ($u in $users) {

    # Mot de passe temporaire (forcé au 1er login)
    $passwordProfile = @{
        Password                      = "TempP@ss-$(Get-Random -Minimum 1000 -Maximum 9999)!"
        ForceChangePasswordNextSignIn = $true
    }

    try {
        New-MgUser `
            -DisplayName       $u.DisplayName `
            -MailNickname      $u.MailNickname `
            -UserPrincipalName $u.UserPrincipalName `
            -Department        $u.Department `
            -JobTitle          $u.JobTitle `
            -AccountEnabled `
            -PasswordProfile   $passwordProfile `
            -ErrorAction Stop
    }
    catch {
        Write-Host "Echec : $($u.UserPrincipalName) - $($_.Exception.Message)"

        # On logue l'UPN AUSSI : si DisplayName est vide, l'UPN reste exploitable
        $echecs += [PSCustomObject]@{
            UserPrincipalName = $u.UserPrincipalName
            Nom               = $u.DisplayName
            Raison            = $_.Exception.Message
        }
    }
}

# --- Bilan de fin ---
Write-Host "Termine. Nombre d'echecs : $($echecs.Count)"

# On ne génère le rapport QUE s'il y a eu des échecs
if ($echecs.Count -gt 0) {
    $echecs | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    Write-Host "Rapport des echecs : $ReportPath"
}

Disconnect-MgGraph | Out-Null
