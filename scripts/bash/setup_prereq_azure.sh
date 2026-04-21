
region="$1"

resourceGroup="arc_tfstate_rg"
storageAccount="arcstorageacct"
storageContainer="arc-tfstate-container"

echo "Creating Resource Group.."
az group create --name "$resourceGroup" --location "$region"

echo "Create Storage Account.."
az storage account create --name "$storageAccount" --resource-group "$resourceGroup" --location "$region" --sku Standard_LRS --kind StorageV2

echo "Create container on the Storage Account.."
az storage container create --name "$storageContainer" --account-name "$storageAccount" --auth-mode login