define :chiliproject_deploy_key, :name => "default", :instance => {} do
  inst = chiliproject_instance(params[:instance])

  if inst.has_key?("deploy_key")
    file "#{inst['deploy_to']}/id_deploy" do
      owner inst['user']
      group inst['group']
      mode '0400'
      content inst["deploy_key"]
      backup false
    end

    template "#{inst['deploy_to']}/deploy-ssh-wrapper" do
      source "deploy-ssh-wrapper.erb"
      owner inst['user']
      group inst['group']
      mode "0755"
      variables :deploy_to => inst['deploy_to']
    end
  end

  if inst.has_key?('netrc')
    template "#{inst['deploy_to']}/.netrc" do
      source "netrc.erb"
      owner inst['user']
      group inst['group']
      mode '0400'
      variables ({
        :hostname => inst['netrc']['hostname'],
        :username => inst['netrc']['username'],
        :password => inst['netrc']['password']
      })
    end
  end
end
