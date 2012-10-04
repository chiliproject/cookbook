# If you use this definition by yourself, make sure to pass a properly setup
# instance. You can create one using the chiliproject_instance helper from a
# databag item
#
# extend ChiliProject::Helpers
# inst = chiliproject_instance "my_instance"

define :chiliproject_netrc, :name => "default", :instance => {} do
  inst = params[:instance]

  hosts = [inst['netrc']]
  hosts += inst['plugins'].collect{|name, plugin| plugin['netrc']}
  hosts = hosts.compact.uniq

  unless hosts.empty?
    template "#{inst['deploy_to']}/.netrc" do
      source "netrc.erb"
      owner inst['user']
      group inst['group']
      mode '0400'
      variables :hosts => hosts
    end
  end
end
