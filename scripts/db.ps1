param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "start-tools", "stop", "logs", "status", "test", "shell", "reset")]
    [string]$Action = "status"   # a chaque fois $Action va prendre l'une des valeurs suivantes : start, start-tools, stop, logs, status, test, shell, reset
)

$ErrorActionPreference = "Stop"  # on va arreter le script si il y a une erreur
$ProjectRoot = Split-Path -Parent $PSScriptRoot  # cest le fichier parent du fichier db.ps1
Set-Location -LiteralPath $ProjectRoot  # cest  comme "cd" dans le terminal 



function Enable-DockerCommand {
    if (Get-Command docker -ErrorAction SilentlyContinue) {  # si le docker est deja installé et lancé on passe a l'etape suivante
        return
    }

    $dockerCandidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\DockerDesktop\resources\bin\docker.exe"), # deux listes de chemins du docker pour les ajouter au PATH
        "C:\Program Files\Docker\Docker\resources\bin\docker.exe" # on va chercher le docker dans ces deux chemins 
    )

    foreach ($dockerExecutable in $dockerCandidates) { # pour chaque chemin dans $dockerCandidates on va faire les verification suivantes 
        if (Test-Path -LiteralPath $dockerExecutable) {   # teste si le chemin du docker existe 
            $dockerBinDirectory = Split-Path -Parent $dockerExecutable # on va separer le chemin du docker en deux parties 
            $env:PATH = "$dockerBinDirectory;$env:PATH" # on va ajouter le chemin du docker au PATH
            return
        }
    }

    throw "Docker est introuvable. Installez et demarrez Docker Desktop avant d'utiliser ce script."
}

Enable-DockerCommand

switch ($Action) {
    "start" {
        docker compose up -d postgres        # Démarre uniquement le conteneur PostgreSQL en arrière-plan
    }
    "start-tools" {
        docker compose --profile tools up -d         # Démarre les services définis dans le profil "tools" en arrière-plan
    }
    "stop" {
        docker compose down            # Arrête et supprime les conteneurs du projet Docker Compose
    }
    "logs" {
        docker compose logs -f postgres           # Affiche les logs du conteneur PostgreSQL en temps réel
    }
    "status" {
        docker compose ps            # Affiche l'état actuel des conteneurs du projet
    }
            # Exécute le fichier validate.sql dans PostgreSQL pour tester/valider la base de données
    "test" {
        docker compose exec -T postgres sh -lc 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /workspace-tests/validate.sql'
    }
    "shell" {
        docker compose exec postgres sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"'  # Ouvre un terminal PostgreSQL (psql) connecté à la base de données du projet
    }
    "reset" {
        $confirmation = Read-Host "Cette action supprime toutes les donnees locales ShopPulse. Tapez RESET pour continuer"
        if ($confirmation -ne "RESET") {
            Write-Host "Reinitialisation annulee."
            exit 0
        }
        docker compose down --volumes
        docker compose up -d postgres
    }
}
