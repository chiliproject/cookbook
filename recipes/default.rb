extend ChiliProject::Helpers

# First create the required databases if configured
include_recipe "chiliproject::database"

# Then deploy the ChiliProject instances
include_recipe "git"

data_bag(node["chiliproject"]["databag"]).each do |name|
  inst = chiliproject_instance(name)
  chiliproject name do
    instance inst
  end
end
