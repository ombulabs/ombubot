require "slack-notify"

# config valid only for current version of Capistrano
lock '3.4.0'

set :use_sudo, false
set :user, "deployer"
set :application, "27shops.com"
set :repo_url,  "git@github.com:ombulabs/ombushop.git"
set :deploy_to,	"/home/deployer/#{fetch(:application)}"
set :keep_releases, 3
set :log_level, :info

# RVM
set :rvm_ruby_version, "2.1.2@ombushop" # use the same ruby as used locally for deployment
set :rvm_type, :system
# set :rvm_autolibs_flag, "read-only"    # more info: rvm help autolibs
# set :rvm_install_with_sudo, true

set :default_shell, :bash

# Bundler
set :bundle_without, %w{development test cucumber}.join(' ')             # this is default
set :bundle_flags, '--deployment --quiet'

# Sidekiq
set :sidekiq_pid, File.join(shared_path, 'pids', 'sidekiq.pid')
set :sidekiq_log,  File.join(shared_path, 'log', 'sidekiq.log')
set :sidekiq_cmd, "#{fetch(:bundle_cmd, "bundle")} exec sidekiq"
set :sidekiqctl_cmd, "#{fetch(:bundle_cmd, "bundle")} exec sidekiqctl"
set :sidekiq_role, :db

set :pty, true # instead of default_run_options[:pty] = true

# Git
set :scm, :git
set :git_enable_submodules, 1

# Default value for :linked_files is []
# set :linked_files, fetch(:linked_files, []).push('config/database.yml', 'config/secrets.yml')

# Default value for linked_dirs is []
set :linked_dirs, fetch(:linked_dirs, []).push('log', 'tmp/pids', 'tmp/cache', 'tmp/sockets', 'vendor/bundle')

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

## Methods
BRANCH_NAME = %x[git rev-parse --abbrev-ref HEAD].strip
USERNAME = %x[whoami].strip
GIT_TAG = %x[git describe --tags].strip

def notify_slack(msg)
  client = SlackNotify::Client.new(channel: "#ombushop",
                                   webhook_url: "https://hooks.slack.com/services/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",
                                   username: USERNAME,
                                   icon_url: "http://pbs.twimg.com/profile_images/460757695755087872/OUy1gBe4_400x400.png",
                                   icon_emoji: ":shipit:")

  client.notify(msg, "#ombushop") if client
end

namespace :init do
  desc "create database.yml"
  task :database_yml do
    on roles(:app, :db) do
      ask(:db_user, "ombushop")
      ask(:db_pass, nil, echo: false)
      ask(:db_name, "ombu_store_production")

      mysql_database_configuration = %(
production: &production
  adapter: mysql2
  encoding: utf8
  database: #{fetch(:db_name)}
  host: #{fetch(:db_host)}
  username: #{fetch(:db_user)}
  password: #{fetch(:db_pass)}
  reconnect: true

staging:
  <<: *production

)
      execute "mkdir -p #{shared_path}/config"
      string_io_mysql_database = StringIO.new(mysql_database_configuration)
      upload! string_io_mysql_database, "#{shared_path}/config/database.yml"

      pg_database_configuration = %(
development:
  host: #{fetch(:db_host)}
  adapter: postgres
  database: faqtly_production
  username: postgres

test: &test
  adapter: postgres
  encoding: utf8
  reconnect: false
  database: faqtly_test
  pool: 5
  username: postgres
  password: postgres

production: &production
  host: #{fetch(:db_host)}
  adapter: postgres
  encoding: utf8
  reconnect: false
  database: faqtly_production
  pool: 5
  user: postgres

staging:
  <<: *production

)

      ["#{shared_path}/config/ayuda_database.yml", "#{shared_path}/config/api_database.yml"].each do |file|
        string_io_pg_database = StringIO.new(pg_database_configuration)
        upload! string_io_pg_database, file
      end
    end
  end

  desc "creates database & database user"
  task :create_database do
    on roles(:app, :db) do
      ask(:root_password, nil, echo: false)
      ask(:app_db_user, "ombushop")
      ask(:app_db_pass, nil, echo: false)
      ask(:db_name, "ombu_store_production")

      execute "mysql --user=root --password=#{fetch(:root_password)} -e \"CREATE DATABASE IF NOT EXISTS #{fetch(:db_name)}\""
      execute "mysql --user=root --password=#{fetch(:root_password)} -e \"GRANT ALL PRIVILEGES ON #{fetch(:db_name)}.* TO '#{fetch(:app_db_user)}'@'localhost' IDENTIFIED BY '#{fetch(:app_db_pass)}' WITH GRANT OPTION\""
    end
  end

  task :default do
    invoke "init:create_database"
    invoke "init:database_yml"
  end
end

task init: "init:default"

namespace :notify do
  task :start do
    on roles(:app) do
      msg = "#{USERNAME} started deploying ombushop (#{BRANCH_NAME} #{GIT_TAG}) to #{fetch(:stage)}"
      notify_slack(msg)
    end
  end

  task :done do
    on roles(:app) do
      msg = "#{USERNAME} just deployed ombushop (#{BRANCH_NAME} #{GIT_TAG}) to #{fetch(:stage)}"
      notify_slack(msg)
    end
  end
end

# Configuration Tasks
namespace :config do
  desc "copy shared configurations to current"
  task :copy_shared_configurations do
    on roles(:app, :db) do
      %w[database.yml].each do |file|
        execute "ln -nsf #{shared_path}/config/#{file} #{release_path}/config/#{file}"
        execute "ln -nsf #{shared_path}/config/ayuda_database.yml #{release_path}/lib/ayuda/config/database.yml"
        execute "ln -nsf #{shared_path}/config/#{file} #{release_path}/lib/api/config/database.yml"

        execute "ln -nsf #{shared_path}/config/.env #{release_path}/.env"
      end
    end
  end
end

namespace :clean do
  task :tmp do
    on roles(:app) do
      sudo "rm -rf /tmp/RackMultipart2013*"
      sudo "rm -rf /tmp/*.jpg"
      sudo "rm -rf /tmp/*.png"
      sudo "rm -rf /tmp/IMG*"
      sudo "rm -rf /tmp/DSC*"
      sudo "rm -rf /tmp/*2013*"
    end
  end

  task :check_payments do
    on roles(:db) do
      execute "cd #{release_path}; RAILS_ENV=#{fetch(:stage)} bundle exec rake jobs:check_payments", shell: fetch(:rvm_shell)
    end
  end
end

namespace :sidekiq do
  task :start do
    on roles(:db) do
      sudo "monit start sidekiq"
    end
  end

  task :stop do
    on roles(:db) do
      sudo "monit stop sidekiq"
    end
  end

  task :restart do
    on roles(:db) do
      sudo "monit restart sidekiq"
    end
  end
end

namespace :git do
  desc 'Copy repo to releases'
  task create_release: :'git:update' do
    on roles(:app, :db) do
      with fetch(:git_environmental_variables) do
        within repo_path do
          execute :git, :clone, '-b', fetch(:branch), '--recursive', '.', release_path
        end
      end
    end
  end
end

namespace :deploy do

  namespace :nginx do
    task :setup do
      on roles(:app) do
        sudo "mkdir -p /etc/nginx/conf.d"
        within release_path do
          sudo "cp #{release_path}/config/nginx/nginx.conf /etc/nginx/nginx.conf"
          sudo "cp #{release_path}/config/nginx/#{fetch(:stage)}/conf.d/* /etc/nginx/conf.d/"
        end
      end
    end

    task :restart do
      invoke 'deploy:nginx:start'
    end

    task :stop do
      on roles(:app) do
        sudo "mkdir -p /etc/nginx/conf.d"

        execute "sudo nginx -s stop"
      end
    end

    task :start do
      on roles(:app) do
        sudo "mkdir -p /etc/nginx/conf.d"

        if remote_file_exists?("/tmp/nginx.pid")
          execute "sudo nginx -s reload"
        else
          execute "sudo nginx"
        end
      end
    end

  end

  namespace :assets do
    task :precompile do
      on roles(:app) do
        within release_path do
          with rails_env: fetch(:stage) do
            execute :rake, "assets:precompile:primary"
          end
        end
      end
    end

    task :symlink_public do
      on roles(:app, :db) do
        execute "mkdir -p #{shared_path}/assets"
        execute "mkdir -p #{shared_path}/assets/sitemaps"
        execute "rm -rf #{release_path}/public/assets"
        execute "ln -s #{shared_path}/assets #{release_path}/public/assets"
      end
    end
  end

  task :stop do
    on roles(:app) do
      if remote_file_exists? "#{shared_path}/pids/unicorn.pid"
        execute "kill -QUIT `cat #{shared_path}/pids/unicorn.pid`"
        execute "rm #{shared_path}/pids/unicorn.pid"
      end
    end
  end

  task :start do
    on roles(:app) do
      execute "cd #{release_path}; bundle exec unicorn_rails -E #{fetch(:stage)} -D -c config/unicorn.rb"
    end
  end

  def remote_file_exists?(full_path)
    capture("if [ -e #{full_path} ]; then echo 'true'; fi").strip.include? "true"
  end

  task :restart do
    on roles(:app) do
      if remote_file_exists?("#{shared_path}/pids/unicorn.pid")
        execute "kill -s USR2 `cat #{shared_path}/pids/unicorn.pid`"
      else
        invoke "deploy:start"
      end
    end
  end

  desc "Update ruby version file"
  task :ruby_version do
    on roles(:app, :db) do
      execute "cp #{release_path}/.ruby-version.production #{release_path}/.ruby-version"
      # execute "mkdir -p #{shared_path}/gems"
      # execute "gem install bundler --no-ri --no-rdoc"
      # execute "cd #{current_path}; bundle install --path=#{shared_path}/gems --without=development test cucumber"
    end
  end

  before :deploy, "notify:start"
  after "deploy:updating", "deploy:ruby_version"
  before :restart, "deploy:ruby_version"
  before "deploy:updated", "config:copy_shared_configurations"
  before :restart, "config:copy_shared_configurations"
  # before "deploy:updated", "sidekiq:stop"
  # before :restart, "sidekiq:stop"
  before "deploy:updated", "monit:copy_configuration"
  before :restart, "monit:copy_configuration"
  before "deploy:updated", "deploy:nginx:setup"
  before "deploy:updated", "deploy:nginx:restart"
  before "deploy:restart", "deploy:nginx:restart"
  before "deploy:restart", "deploy:assets:symlink_public"
  before "deploy:updated", "deploy:assets:symlink_public"
  before "deploy:finished", "deploy:restart"

  after 'deploy:updated', 'deploy:assets:precompile'
  after "deploy:finished", "notify:done"
  after :restart, "sidekiq:restart"
  after "deploy:stop", "sidekiq:stop"
  after "deploy:stop", "deploy:nginx:stop"
  after "deploy:start", "sidekiq:start"
  after "deploy:start", "deploy:nginx:start"
end
