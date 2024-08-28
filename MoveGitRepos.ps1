param (
    [string]$personalAccessToken
)

# Set the necessary variables
$organizationName = "yourorg" #Update the name of your Azure Devops Org
$projectNameFrom = "ProjectA" #Update the name of the Source Project
$projectNameTo = "ProjectB" #Update the name of the Destination Project
$scriptLocation = $PSScriptRoot
# Function to create the base64 authentication string
function Get-AuthHeader {
    param (
        [string]$token
    )
    return [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($token)"))
}

# Function to get repositories from Azure DevOps
function Get-Repositories {
    param (
        [string]$organization,
        [string]$project,
        [string]$authHeader
    )
    $repoUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/?api-version=7.1-preview.1"
    return Invoke-RestMethod -Uri $repoUrl -Method Get -Headers @{Authorization = "Basic $authHeader"}
}

# Function to enable a disabled repository
function Enable-Repository {
    param (
        [string]$organization,
        [string]$project,
        [string]$repoId,
        [string]$authHeader
    )
    $updateRepoUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/$repoId?api-version=7.1-preview.1"
    $updateRepoBody = @{ isDisabled = $false } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $updateRepoUrl -Method Patch -Body $updateRepoBody -Headers @{Authorization = "Basic $authHeader"} -ContentType "application/json"
        Write-Host "Repository '$repoId' has been enabled."
    } catch {
        Write-Host "Failed to enable repository '$repoId': $_"
    }
}

# Function to check if a repository exists in the destination project
function Test-RepositoryExists {
    param (
        [string]$organization,
        [string]$project,
        [string]$repoName,
        [string]$authHeader
    )
    $reposResponse = Get-Repositories -organization $organization -project $project -authHeader $authHeader
    $repositoriesList = $reposResponse.value

    # Check if the repository name exists in the list
    return ($repositoriesList | Where-Object { $_.name -eq $repoName }).Count -ne 0
}

# Function to delete a repository
function Delete-Repository {
    param (
        [string]$organization,
        [string]$project,
        [string]$repoId,
        [string]$authHeader
    )
   
    $baseUrl = "https://dev.azure.com/$organization/$project/_apis/git/repositories/"
    $baseUrl+=$repoId    
    $deleteRepoUrl = $baseUrl+"?api-version=7.1-preview.1"

    try {
        Invoke-RestMethod -Uri $deleteRepoUrl -Method Delete -Headers @{Authorization = "Basic $authHeader"}
        Write-Host "Repository '$repoId' has been deleted from '$project'."
    } catch {
        Write-Host "Failed to delete repository '$repoId': $_"
    }
}

# Function to clone and move deprecated repositories
function Move-DeprecatedRepository {
    param (
        [string]$organization,
        [string]$projectFrom,
        [string]$projectTo,
        [string]$repoId,      
        [string]$repoName,
        [string]$repoSshUrl,
        [string]$authHeader
    )

    if (Test-RepositoryExists -organization $organization -project $projectTo -repoName $repoName -authHeader $authHeader) {
        Write-Host "Repository '$repoName' already exists in '$projectTo'. Skipping move."
        return $false
    }

    # Create the new repository in the destination project
    $repoToUrl = "https://dev.azure.com/$organization/$projectTo/_apis/git/repositories?api-version=7.1-preview.1"
    $repoToBody = @{ name = $repoName } | ConvertTo-Json

    try {
        $repoToResponse = Invoke-RestMethod -Uri $repoToUrl -Method Post -Body $repoToBody -Headers @{Authorization = "Basic $authHeader"} -ContentType "application/json"
        $newRepoUrl = $repoToResponse.sshUrl
        Write-Host "Repository creation successful for '$repoName'."

        # Clone the repository
        $localClonePath = "$scriptLocation\$repoName"
        git clone --mirror $repoSshUrl $localClonePath
        Write-Host "Clone successful for '$repoName'."

        # Add the new remote repository and push
        Set-Location -Path $localClonePath
        git remote add new-origin $newRepoUrl
        git push new-origin --all
        git push new-origin --tags

        # Clean up
        Set-Location -Path ..
        Remove-Item -Recurse -Force $localClonePath
        Write-Host "Repository '$repoName' moved from '$projectFrom' to '$projectTo' successfully."

        # Delete the original repository using its ID
        Delete-Repository -organization $organization -project $projectFrom -repoId $repoId -authHeader $authHeader
        return $true
    } catch {
        Write-Host "Error moving repository '$repoName': $_"
        return $false
    }
}

# Main script execution
try {
    $authHeader = Get-AuthHeader -token $personalAccessToken
    $FromRepoResponse = Get-Repositories -organization $organizationName -project $projectNameFrom -authHeader $authHeader
    $repositoriesList = $FromRepoResponse.value

    # Enable disabled repositories
    $disabledRepositories = $repositoriesList | Where-Object { $_.IsDisabled -eq $true }
    foreach ($repo in $disabledRepositories) {
        Enable-Repository -organization $organizationName -project $projectNameFrom -repoId $repo.id -authHeader $authHeader
    }

    # Move deprecated repositories
    $deprecatedRepositories = $repositoriesList | Where-Object { $_.name -like "*Deprecated*" }
    $failedRepositories = @()
    foreach ($repo in $deprecatedRepositories) {  
        if (-not (Move-DeprecatedRepository -organization $organizationName -projectFrom $projectNameFrom -projectTo $projectNameTo -repoId $repo.id -repoName $repo.name -repoSshUrl $repo.sshUrl -authHeader $authHeader)) {
            $failedRepositories += $repo.name
        }
    }

    # Display the list of failed repositories
    if ($failedRepositories.Count -gt 0) {
        Write-Host "`nRepositories that failed to move:"
        $failedRepositories | ForEach-Object { Write-Host $_ }
    }
} catch {
    Write-Host "An error occurred: $_"
} finally {
    # Ensure the script returns to the original directory
    Set-Location -Path $scriptLocation
}