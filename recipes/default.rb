self.class.send(:include, ChiliProject::Helpers)

# First create the required databases if configured
include_recipe "chiliproject::database"

# Then deploy the ChiliProject instances
include_recipe "git"

instances = Chef::DataBag.load("chiliproject").values
instances.each do |inst|
  chiliproject inst['id'] do
    instance inst
  end
end
