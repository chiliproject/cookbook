define :chiliproject_deploy_key, :name => "default", :instance => {}, :deploy_to => nil, :deploy_key => nil do
  inst = chiliproject_instance(params[:instance])

  deploy_to = params[:deploy_to] || inst['deploy_to']

  if params[:deploy_key] || inst["deploy_key"]
    file "#{deploy_to}/id_deploy" do
      owner inst['user']
      group inst['group']
      mode '0400'
      content params[:deploy_key] || inst["deploy_key"]
      backup false
    end

    template "#{deploy_to}/deploy-ssh-wrapper" do
      source "deploy-ssh-wrapper.erb"
      owner inst['user']
      group inst['group']
      mode "0755"
      variables :deploy_to => deploy_to
    end
  end
end
