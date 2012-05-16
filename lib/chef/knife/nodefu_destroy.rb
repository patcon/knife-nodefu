require_relative 'nodefu_base'

class NodefuDestroy < Chef::Knife

  deps do
    require 'fileutils'
    require 'chef/api_client'
    require 'chef/node'
    require 'chef/json_compat'
    require 'thread'
    Chef::Knife::Ec2ServerDelete.load_deps
  end

  include NodefuBase

  banner "knife nodefu destroy <name>|<name>[range]"

  option :yes,
         :short => "-y",
         :long => "--yes",
         :description => "ignores prompts, just say YES!",
         :default => nil

  option :skip_clients,
         :short => "-c",
         :long => "--skip-clients",
         :description => "Do not delete clients",
         :default => nil

  option :skip_nodes,
         :short => "-n",
         :long => "--skip-nodes",
         :description => "Do not delete nodes",
         :default => nil

   option :skip_instances,
          :short => "-i",
          :long => "--skip-instances",
          :description => "Do not terminate instances",
          :default => nil

  def run
    check_args(1)
    matcher = /#{name_args[0]}/  

    all_clients = Chef::ApiClient.list(true) 
    all_nodes = Chef::Node.list

    nodes_to_delete = all_nodes.inject({}) { |nodes, (k,v)| nodes[k] = Chef::Node.load(k) if k =~ matcher; nodes } 
    clients_to_delete = all_clients.inject({}) { |clients, (k, v)| clients[k] = v if k =~ matcher; clients }   

    #Display all the items that will be removed   
    if config[:skip_clients]
      ui.msg("#{ui.color('Skipping clients...',:cyan)}")   
    else
      ui.msg("#{ui.color('Clients to be deleted:',:red)}")
      pretty_print_hash clients_to_delete
    end

    if config[:skip_nodes]
      ui.msg("#{ui.color('Skipping nodes...',:cyan)}")    
    else
      ui.msg("#{ui.color('Nodes to be deleted:',:red)}")
      pretty_print_hash nodes_to_delete
    end

    if config[:skip_instances]
      ui.msg("#{ui.color('Skipping instances...',:cyan)}")    
    else
      ui.msg("#{ui.color('EC2 instances to be terminated:',:red)}") 
      nodes_to_delete.each do |node|
        instance_id = node[1]['ec2']['instance_id']
        ui.msg("#{ui.color(node[0],:magenta)}: #{instance_id}")
      end
    end
    
    config[:yes] ? user_response = 'yes' : user_response = ui.ask_question("Does this seem right to you? [y/n]").downcase
    abort("See ya!") unless (['yes','y',].include?(user_response))

    unless config[:skip_instances]
      threads = []
      #Delete the ec2 server
      for i in nodes_to_delete
        threads << Thread.new(i) do |node|      
         ec2_delete = Ec2ServerDelete.new 
         instance_id = node[1]['ec2']['instance_id']
         ec2_delete.name_args[0] = instance_id
         ec2_delete.config[:yes] = true
         ec2_delete.run
        end
      end 
      threads.each(&:join)
    end

    unless config[:skip_nodes]
      nodes_to_delete.each_pair do |node_name,node_object|
        ui.msg("#{ui.color('destroying node:',:red)} #{node_name}")
        node_object.destroy
      end
    end

    unless config[:skip_clients]
      clients_to_delete.each_pair do |client_name,client_object|         
        ui.msg("#{ui.color('destroying client:',:red)} #{client_name}")
        client_object.destroy
      end
    end
  end
end