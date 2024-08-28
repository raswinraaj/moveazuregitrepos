# Move Azure Git Repos
Script to move Azure Git Repos from one project to another

# Prerequisites
1. Create a new Personal Access Token from Azure Devops with Full Access as instructed in https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=Windows
2. Create a new SSH key as instructed in https://learn.microsoft.com/en-us/azure/devops/repos/git/use-ssh-keys-to-authenticate?view=azure-devops
3. Use the latest Azure Repos API version - https://learn.microsoft.com/en-us/rest/api/azure/devops/git/repositories?view=azure-devops-rest-7.1

# Execute the script
.\MoveGitRepos.ps1 -personalAccessToken "YOUR_PERSONAL_ACCESS_TOKEN"

# Medium post describing the script available at
https://link.medium.com/7EUuVHQ6qMb
