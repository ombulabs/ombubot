# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

server 'ec2-54-81-195-220.compute-1.amazonaws.com',
  user: 'deployer',
  roles: %w{app db web},
  ssh_options: {
    forward_agent: true
  }

# server 'example.com', user: 'deploy', roles: %w{app web}, other_property: :other_value
# server 'db.example.com', user: 'deploy', roles: %w{db}

set :db_host, "localhost"

# Git
set :branch, `git rev-parse --abbrev-ref HEAD`.chomp

# role-based syntax
# ==================

# Defines a role with one or multiple servers. The primary server in each
# group is considered to be the first unless any  hosts have the primary
# property set. Specify the username and a domain or IP for the server.
# Don't use `:all`, it's a meta role.

# role :app, %w{deploy@example.com}, my_property: :my_value
# role :web, %w{user1@primary.com user2@additional.com}, other_property: :other_value
# role :db,  %w{deploy@example.com}



# Configuration
# =============
# You can set any configuration variable like in config/deploy.rb
# These variables are then only loaded and set in this stage.
# For available Capistrano configuration variables see the documentation page.
# http://capistranorb.com/documentation/getting-started/configuration/
# Feel free to add new variables to customise your setup.



# Custom SSH Options
# ==================
# You may pass any option but keep in mind that net/ssh understands a
# limited set of options, consult the Net::SSH documentation.
# http://net-ssh.github.io/net-ssh/classes/Net/SSH.html#method-c-start
#
# Global options
# --------------
# set :ssh_options, {
#   forward_agent: true
# }
#
# The server-based syntax can be used to override options:
# ------------------------------------
# server 'example.com',
#   user: 'user_name',
#   roles: %w{web app},
#   ssh_options: {
#     user: 'user_name', # overrides user setting above
#     keys: %w(/home/user_name/.ssh/id_rsa),
#     forward_agent: false,
#     auth_methods: %w(publickey password)
#     # password: 'please use keys'
#   }

namespace :monit do
  task :copy_configuration do
    on roles(:app, :db) do
      execute "source #{shared_path}/config/.env; sed -i \"s/user_placeholder/$MONIT_EMAIL_USERNAME/g\" #{release_path}/config/monit/monitrc"
      execute "source #{shared_path}/config/.env; sed -i \"s/pass_placeholder/$MONIT_EMAIL_PASSWORD/g\" #{release_path}/config/monit/monitrc"
      sudo "cp #{release_path}/config/monit/monitrc /etc/monitrc"
      sudo "cp #{release_path}/config/monit/staging.conf /etc/monit.d/staging.conf"
      sudo "monit reload"
    end
  end
end
