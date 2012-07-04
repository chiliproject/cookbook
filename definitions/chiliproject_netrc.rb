define :chiliproject_netrc, :name => "default", :instance => {} do
  inst = chiliproject_instance(params[:instance])

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
