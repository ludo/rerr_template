# RERR TEMPLATE
#
# Run: rails app_name -d mysql -m rerr_template.rb

template_root = File.expand_path(File.dirname(template), File.join(root,'..'))
app_name = @root.split('/').last

# Load configuration
# =============================================================================
require "yaml"
@config = YAML.load_file(File.join(template_root, "config.yml"))

# Helpers quick'n'dirty
# =============================================================================
require File.join(template_root, 'lib', 'erb_to_haml')

# require File.join(File.expand_path(File.dirname(template), File.join(root,'..')), "lib/rails_ext/template_runner")
def replace_migration(name, from)
  inside ("db/migrate") do
    run "cat #{from}/#{name}.rb > temp.rb"
    run "find *_#{name}.rb | xargs mv temp.rb"
  end
end

def yes_unless_in_config?(question)
  type = question.match(/\[(.*)\]/)[1].pluralize
  name = question.match(/Add (.*)\?/)[1]
  
  if @config[type].include?(name)
    true
  else
    yes?(question)
  end
end

# 
# =============================================================================
installed_gems = []
installed_plugins = []

# Delete files
# =============================================================================
run "rm README"
run "rm public/index.html"
run "rm public/favicon.ico"

# Set-up git repository
# =============================================================================
git :init

run "touch tmp/.gitignore log/.gitignore vendor/.gitignore"
run %{find . -type d -empty | grep -v "vendor" | grep -v ".git" | grep -v "tmp" | xargs -I xxx touch xxx/.gitignore}
file '.gitignore', <<-ENDEND
.DS_Store
log/*.log
tmp/**/*
config/database.yml
db/*.sqlite3
ENDEND

# Freeze Rails gems
# =============================================================================
rake "rails:freeze:gems"


# RSpec (test)
# -----------------------------------------------------------------------------
gem "rspec", :lib => false, :version => "~> 1.2", :env => "test"
gem "rspec-rails", :lib => false, :version => "~> 1.2", :env => "test"
rake "gems:install"

generate("rspec")

installed_gems << "rspec-rails"
installed_gems << "rspec"

# Cucumber (test)
# -----------------------------------------------------------------------------
gem "webrat", :lib => false, :version => "~> 0.5", :env => "test"
gem "cucumber", :lib => false, :version => "~> 0.4", :env => "test"
rake "gems:install" , :env => "test"   

generate("cucumber")

installed_gems << "cucumber"
installed_gems << "webrat"

# factory-girl (test)
# -----------------------------------------------------------------------------
gem "factory_girl", :lib => "factory_girl", :source => "http://gemcutter.org", :version => "~> 1.2", :env => "test"
rake "gems:install", :env => "test"

installed_gems << "factory-girl"

# Remarkable (test)
# -----------------------------------------------------------------------------
gem "remarkable_rails", :lib => false, :source => "http://gemcutter.org", :version => "~> 3.1", :env => "test"
rake "gems:install" , :env => "test"   

installed_gems << "remarkable_rails" 


# Mocha (mocking)
# -----------------------------------------------------------------------------
gem "mocha", :lib => false, :source => "http://gemcutter.org", :version => "~> 0.9.8", :env => "test"
rake "gems:install" , :env => "test"   

installed_gems << "mocha"


# Footnotes (development)
# -----------------------------------------------------------------------------
gem "rails-footnotes", :lib => false, :version => "~> 3.6", :source => "http://gemcutter.org", :env => "development"
rake "gems:install" , :env => "development"   

installed_gems << "rails-footnotes"

# Authlogic
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add authlogic?")
  gem "authlogic", :lib => false, :version => "~> 2.1", :source => "http://gemcutter.org"
  rake "gems:install"

  # UserSession
  generate("session", "user_session")
  gsub_file("app/models/user_session.rb", /(Authlogic::Session::Base)/mi) do |match|
    "#{match}\n  generalize_credentials_error_messages(true)"
  end
  
  # User
  generate("rspec_model", "user")
  replace_migration("create_users", template_root + "/templates/gems/authlogic/db/migrate")
  gsub_file("app/models/user.rb", /(ActiveRecord::Base)/mi) do |match|
    "#{match}\n  acts_as_authentic"
  end

  # UserSessionsController
  generate("rspec_controller", "user_sessions")
  run "cp #{template_root}/templates/gems/authlogic/app/controllers/user_sessions_controller.rb app/controllers/"
  run "cp #{template_root}/templates/gems/authlogic/app/views/user_sessions/* app/views/user_sessions/"
  route("map.resource :user_session")
  route("map.login '/login', :controller => 'user_sessions', :action => 'new'")
  route("map.logout '/logout', :controller => 'user_sessions', :action => 'destroy'")

  # UsersController
  generate("rspec_controller", "users")
  run "cp #{template_root}/templates/gems/authlogic/app/controllers/users_controller.rb app/controllers/"
  run "cp #{template_root}/templates/gems/authlogic/app/views/users/* app/views/users/"
  route('map.resource :account, :controller => "users"')
  route('map.resources :users')

  # ApplicationController
  run "cp #{template_root}/templates/gems/authlogic/app/controllers/application_controller.rb app/controllers/"

  installed_gems << "authlogic"
end

# Lockdown
# -----------------------------------------------------------------------------
if installed_gems.include?("authlogic") && yes_unless_in_config?("[gem] Add lockdown?")
  gem "lockdown", :lib => false, :version => "~> 1.3", :source => "http://gemcutter.org"
  rake "gems:install"

  generate("lockdown")

  # Bootstrap data
  email = "admin@example.com" # ask("[gem] Lockdown: Please enter email address for initial administrator user: ")
  password = "password" # ask("[gem] Lockdown: Please enter email address for initial administrator user: ")

  append_file("db/seeds.rb", <<-SEED

# Setup initial user and make this user an administrator
user = User.create(
  :login => "admin",
  :email => "#{email}",
  :password => "#{password}",
  :password_confirmation => "#{password}"
)

Lockdown::System.make_user_administrator(user)
SEED
  )

  run "cp #{template_root}/templates/gems/lockdown/app/controllers/application_controller.rb app/controllers/"
  run "cp #{template_root}/templates/gems/lockdown/app/controllers/user_sessions_controller.rb app/controllers/"
  run "cp #{template_root}/templates/gems/lockdown/lib/lockdown/init.rb lib/lockdown/"

  gsub_file("app/controllers/users_controller.rb", /"Account registered!"/mi) do |match|
    "#{match}\n      add_lockdown_session_values"
  end

  gsub_file("app/models/user.rb", /(ActiveRecord::Base)/mi) do |match|
    "#{match}\n has_and_belongs_to_many :user_groups"
  end

  installed_gems << "lockdown"
end

# Searchlogic
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add searchlogic?")
  gem "searchlogic", :lib => false, :version => "~> 2.3", :source => "http://gemcutter.org"
  rake "gems:install"

  installed_gems << "searchlogic"
end

# Formtastic
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add formtastic?")
  gem "formtastic", :lib => false, :version => "~> 0.9", :source => "http://gemcutter.org"
  rake "gems:install"

  generate("formtastic")
  
  installed_gems << "formtastic"
end

# Formtastic
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add inherited_resources?")
  gem "inherited_resources", :lib => false, :version => "~> 0.9", :source => "http://gemcutter.org"
  rake "gems:install"

  installed_gems << "inherited_resources"
end

# Paperclip
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add paperclip?")
  gem "paperclip", :lib => false, :version => "~> 2.3", :source => "http://gemcutter.org"
  rake "gems:install"

  installed_gems << "paperclip"
end

# Prawn
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add prawn?")
  gem "prawn", :lib => false, :version => "~> 0.5", :source => "http://gemcutter.org"
  rake "gems:install"

  installed_gems << "prawn"
end

# WillPaginate
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add will_paginate?")
  gem "will_paginate", :lib => "will_paginate", :version => "~> 2.3", :source => "http://gemcutter.org"
  rake "gems:install"

  installed_gems << "will_paginate"
end

# Geokit
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add geokit?")
  #plugin "geokit-rails", :git => "git://github.com/andre/geokit-rails.git"
  
  gem "geokit", :lib => false, :version => "~> 1.5", :source => "http://gemcutter.org"
  rake "gems:install"

  installed_gems << "geokit"
  #installed_plugins << "geokit-rails"
end

# Rest-client
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add rest-client?")
  gem "rest-client", :lib => false, :version => "~> 1.0", :source => "http://gemcutter.org"
  rake "gems:install"

  installed_gems << "rest-client"
end

# Haml
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add haml?")
  gem "haml", :lib => false, :version => "~> 2.2", :source => "http://gemcutter.org"
  rake "gems:install"

  installed_gems << "haml"
end

# Googlecharts
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add googlecharts?")
  gem "googlecharts", :lib => false, :version => "~> 1.3", :source => "http://gemcutter.org"
  rake "gems:install"

  installed_gems << "googlecharts"
end   

# Settingslogic
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add settingslogic?")
  gem "settingslogic", :lib => false, :version => "~> 2.0.3", :source => "http://gemcutter.org"
  rake "gems:install"
                                    

  run "cp #{template_root}/templates/gems/settingslogic/app/models/settings.rb app/models/"
  run "cp #{template_root}/templates/gems/settingslogic/config/application.yml config/"
  
  gsub_file("config/application.yml", /rails_app/) do |match|
    "#{app_name.gsub("_","")}"
  end  

  installed_gems << "settingslogic"
end

# Settingslogic
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[gem] Add michel-dry_scaffold?")
  gem "michel-dry_scaffold", :lib => false, :version => "~> 0.3.5", :source => "http://gemcutter.org"
  rake "gems:install"
end

# Configure plugins
# =============================================================================

# Eschaton
#
# Need to look into this plugin, using it fails with "no such file to load -- google/google"
# -----------------------------------------------------------------------------
# if yes?("[plugin] Add eschaton (helps writing google map mashups)?")
#   plugin "eschaton", :git => "git://github.com/yawningman/eschaton.git"
# end

# General
# =============================================================================

# jQuery
# -----------------------------------------------------------------------------
if yes_unless_in_config?("[javascript] Add jquery?")
  inside("public/javascripts") do
    run "rm *" # Remove prototype
    run "touch application.js"
    run "cp #{template_root}/templates/public/javascripts/* ./"
  end
end

# Post-processing
# =============================================================================
erb_to_haml("app/views") if installed_gems.include?("haml")

# Database
# =============================================================================
rake "db:drop:all" if yes?("[db] Drop existing databases?")
rake "db:create:all"

# ActiveRecordSessionStore
# -----------------------------------------------------------------------------
if yes?("[config] Use ActiveRecord for sessions?")
  rake "db:sessions:create"
  append_file("config/initializers/session_store.rb", "ActionController::Base.session_store = :active_record_store")
end 

# Migrate and prepare databases
# -----------------------------------------------------------------------------
rake "db:migrate"
rake "db:seed"
rake "db:test:prepare"  


#Commit rails app to git?
# -----------------------------------------------------------------------------
if yes?("[git] Make initial git commit?")
  git :add => "."
  git :commit => "-a -m 'Initial commit'"                          
end

log("", "Installed the following gems: #{installed_gems.join(", ")}")
log("", "Installed the following plugins: #{installed_plugins.join(", ")}")
log("done", "Go go go!")